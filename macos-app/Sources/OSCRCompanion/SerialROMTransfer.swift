import Foundation

struct ROMTransferConsumeResult {
    enum Event: Equatable {
        case started(name: String, size: UInt64)
        case progress(received: UInt64, size: UInt64)
        case completed(url: URL, crc32: UInt32)
        case failed(String)
    }

    var events: [Event] = []
    var passthrough = Data()
}

final class SerialROMTransferReceiver {
    private enum State {
        case header
        case data
        case footer
        case finished
    }

    private static let protocolMarker = Data("OSCRXFER1".utf8)
    private static let dataMarker = Data("\r\nDATA\r\n".utf8)

    private let fileManager: FileManager
    private let destinationDirectory: URL
    private var state = State.header
    private var buffer = Data()
    private var handle: FileHandle?
    private var temporaryURL: URL?
    private var finalURL: URL?
    private var expectedSize: UInt64 = 0
    private var receivedSize: UInt64 = 0
    private var crc = CRC32()

    init(destinationDirectory: URL, fileManager: FileManager = .default) {
        self.destinationDirectory = destinationDirectory
        self.fileManager = fileManager
    }

    deinit {
        try? handle?.close()
    }

    func consume(_ data: Data) -> ROMTransferConsumeResult {
        var result = ROMTransferConsumeResult()
        buffer.append(data)

        var madeProgress = true
        while madeProgress {
            madeProgress = false
            switch state {
            case .header:
                if let error = parseDeviceError() {
                    result.events.append(.failed(error))
                    finish(removingPartialFile: true)
                    result.passthrough = buffer
                    buffer.removeAll()
                    continue
                }
                guard let markerRange = buffer.range(of: Self.protocolMarker) else {
                    if buffer.count > 4_096 {
                        fail("The reader did not send a valid OSCRXFER1 header.", into: &result)
                    }
                    continue
                }
                if markerRange.lowerBound > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<markerRange.lowerBound)
                }
                guard let dataRange = buffer.range(of: Self.dataMarker) else { continue }
                let headerData = buffer[..<dataRange.lowerBound]
                guard let header = String(data: headerData, encoding: .utf8),
                      let name = value(named: "NAME", in: header),
                      let sizeText = value(named: "SIZE", in: header),
                      let size = UInt64(sizeText), size > 0 else {
                    fail("The reader sent an invalid transfer header.", into: &result)
                    continue
                }

                do {
                    try prepareFile(named: name)
                } catch {
                    fail("Could not create the ROM download: \(error.localizedDescription)", into: &result)
                    continue
                }
                expectedSize = size
                buffer.removeSubrange(buffer.startIndex..<dataRange.upperBound)
                state = .data
                result.events.append(.started(name: finalURL?.lastPathComponent ?? name, size: size))
                madeProgress = true

            case .data:
                let remaining = expectedSize - receivedSize
                guard remaining > 0 else {
                    closeHandle()
                    state = .footer
                    madeProgress = true
                    continue
                }
                guard !buffer.isEmpty else { continue }
                let count = min(Int(remaining), buffer.count)
                let chunk = Data(buffer.prefix(count))
                do {
                    try handle?.write(contentsOf: chunk)
                } catch {
                    fail("Writing the ROM download failed: \(error.localizedDescription)", into: &result)
                    continue
                }
                crc.update(chunk)
                receivedSize += UInt64(count)
                buffer.removeFirst(count)
                result.events.append(.progress(received: receivedSize, size: expectedSize))
                madeProgress = true

            case .footer:
                guard let lineRange = footerLineRange() else {
                    if buffer.count > 256 {
                        fail("The reader did not send a valid transfer checksum.", into: &result)
                    }
                    continue
                }
                let lineData = buffer[lineRange]
                let line = String(data: lineData, encoding: .utf8) ?? ""
                let components = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
                guard components.count >= 3,
                      components[0] == "OSCRXFER1",
                      components[1] == "END",
                      let deviceCRC = UInt32(components[2], radix: 16) else {
                    fail("The reader sent a malformed transfer checksum.", into: &result)
                    continue
                }
                let localCRC = crc.finalized
                guard deviceCRC == localCRC else {
                    fail(
                        String(format: "ROM transfer checksum mismatch (reader %08X, Mac %08X). Please retry.", deviceCRC, localCRC),
                        into: &result
                    )
                    continue
                }
                guard let temporaryURL, let finalURL else {
                    fail("The ROM download destination was lost.", into: &result)
                    continue
                }
                do {
                    try fileManager.moveItem(at: temporaryURL, to: finalURL)
                } catch {
                    fail("Could not finalize the ROM download: \(error.localizedDescription)", into: &result)
                    continue
                }
                buffer.removeSubrange(buffer.startIndex..<lineRange.upperBound)
                result.events.append(.completed(url: finalURL, crc32: localCRC))
                state = .finished
                result.passthrough = buffer
                buffer.removeAll()

            case .finished:
                result.passthrough.append(buffer)
                buffer.removeAll()
            }
        }
        return result
    }

    func cancel() {
        finish(removingPartialFile: true)
    }

    private func parseDeviceError() -> String? {
        guard let markerRange = buffer.range(of: Data("OSCRXFER1 ERR ".utf8)),
              let newline = buffer[markerRange.upperBound...].firstIndex(of: 10) else { return nil }
        let reasonData = buffer[markerRange.upperBound..<newline]
        let reason = String(data: reasonData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "UNKNOWN"
        switch reason {
        case "NO_ROM": return "No completed ROM is available. Read a ROM first, then request the transfer at the Press Button prompt."
        case "FILE_NOT_FOUND": return "The completed ROM could not be reopened on the OSCR SD card."
        default: return "The reader rejected the ROM transfer: \(reason)"
        }
    }

    private func value(named name: String, in header: String) -> String? {
        let prefix = "\(name):"
        return header.components(separatedBy: .newlines)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func prepareFile(named deviceName: String) throws {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var safeName = URL(fileURLWithPath: deviceName).lastPathComponent
        safeName = safeName.replacingOccurrences(of: ":", with: "-")
        if safeName.isEmpty || safeName == "." { safeName = "OSCR-ROM.bin" }

        let baseURL = destinationDirectory.appendingPathComponent(safeName)
        var candidate = baseURL
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) || fileManager.fileExists(atPath: candidate.path + ".part") {
            let stem = baseURL.deletingPathExtension().lastPathComponent
            let ext = baseURL.pathExtension
            let name = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            candidate = destinationDirectory.appendingPathComponent(name)
            suffix += 1
        }

        let partial = URL(fileURLWithPath: candidate.path + ".part")
        guard fileManager.createFile(atPath: partial.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: partial)
        temporaryURL = partial
        finalURL = candidate
    }

    private func footerLineRange() -> Range<Data.Index>? {
        guard let marker = buffer.range(of: Self.protocolMarker),
              let newline = buffer[marker.lowerBound...].firstIndex(of: 10) else { return nil }
        return marker.lowerBound..<(newline + 1)
    }

    private func fail(_ message: String, into result: inout ROMTransferConsumeResult) {
        result.events.append(.failed(message))
        finish(removingPartialFile: true)
        result.passthrough = buffer
        buffer.removeAll()
    }

    private func closeHandle() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
    }

    private func finish(removingPartialFile: Bool) {
        closeHandle()
        if removingPartialFile, let temporaryURL {
            try? fileManager.removeItem(at: temporaryURL)
        }
        state = .finished
    }
}

private struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    private var value: UInt32 = 0xFFFFFFFF

    mutating func update(_ data: Data) {
        for byte in data {
            let index = Int((value ^ UInt32(byte)) & 0xFF)
            value = Self.table[index] ^ (value >> 8)
        }
    }

    var finalized: UInt32 { ~value }
}
