import CSerialBridge
import Darwin
import Foundation

enum SerialPortError: LocalizedError {
    case open(path: String, code: Int32)
    case disconnected
    case encoding
    case write(expected: Int, actual: Int, code: Int32)

    var errorDescription: String? {
        switch self {
        case let .open(path, code):
            return "Could not open \(path): \(String(cString: strerror(code)))"
        case .disconnected:
            return "The cart reader is not connected."
        case .encoding:
            return "The command contains characters the reader cannot accept."
        case let .write(expected, actual, code):
            let detail = code == 0 ? "short write" : String(cString: strerror(code))
            return "Sent \(actual) of \(expected) bytes: \(detail)"
        }
    }
}

final class SerialPortClient {
    var onData: ((Data) -> Void)?
    var onDisconnect: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.oscr.companion.serial", qos: .userInitiated)
    private var descriptor: Int32 = -1
    private var readSource: DispatchSourceRead?

    var isConnected: Bool { descriptor >= 0 }

    func connect(path: String, baudRate: Int) throws {
        disconnect()
        let result = path.withCString { cr_serial_open($0, UInt32(baudRate)) }
        guard result >= 0 else {
            throw SerialPortError.open(path: path, code: -result)
        }

        descriptor = result
        let source = DispatchSource.makeReadSource(fileDescriptor: result, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        readSource = source
        source.resume()
    }

    func disconnect() {
        readSource?.setEventHandler {}
        readSource?.cancel()
        readSource = nil
        if descriptor >= 0 {
            _ = cr_serial_close(descriptor)
            descriptor = -1
        }
    }

    func send(_ text: String) throws {
        guard descriptor >= 0 else { throw SerialPortError.disconnected }
        guard let data = text.data(using: .isoLatin1) else { throw SerialPortError.encoding }

        let written = data.withUnsafeBytes { rawBuffer -> Int in
            guard let address = rawBuffer.baseAddress else { return 0 }
            return cr_serial_write_all(descriptor, address, rawBuffer.count, 2_000)
        }
        guard written == data.count else {
            throw SerialPortError.write(
                expected: data.count,
                actual: max(0, written),
                code: written < 0 ? errno : 0
            )
        }
    }

    private func readAvailable() {
        guard descriptor >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let count = cr_serial_read(descriptor, &buffer, buffer.count)
            if count > 0 {
                let data = Data(buffer.prefix(count))
                DispatchQueue.main.async { [weak self] in self?.onData?(data) }
                continue
            }
            // This descriptor is intentionally nonblocking with VMIN/VTIME set
            // to zero. A zero-byte read means the current burst is drained; it
            // does not mean that a serial/TTY device reached EOF or detached.
            if count == 0 {
                return
            }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                return
            }
            if count < 0 && errno == EINTR {
                continue
            }
            let message = String(cString: strerror(errno))
            DispatchQueue.main.async { [weak self] in self?.onDisconnect?(message) }
            return
        }
    }

    deinit {
        disconnect()
    }
}
