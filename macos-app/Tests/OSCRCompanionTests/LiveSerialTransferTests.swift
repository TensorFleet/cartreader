import Foundation
import XCTest
@testable import OSCRCompanion

final class LiveSerialTransferTests: XCTestCase {
    func testLiveSerialROMTransferWhenConfigured() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let portPath = environment["OSCR_LIVE_PORT"] else {
            throw XCTSkip("Set OSCR_LIVE_PORT to run the hardware integration test.")
        }

        let baudRate = Int(environment["OSCR_LIVE_BAUD"] ?? "115200") ?? 115_200
        let expectedCRC = environment["OSCR_LIVE_EXPECTED_CRC"]
            .flatMap { UInt32($0, radix: 16) }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("oscr-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        enum Phase { case boot, cartridgeType, snesMenu, dump, transfer }
        var phase = Phase.boot
        var terminal = ""
        var receiver: SerialROMTransferReceiver?
        var completedURL: URL?
        var completedCRC: UInt32?
        var finished = false
        let completion = expectation(description: "CRC-verified ROM transfer")
        let client = SerialPortClient()

        func finish(with error: String? = nil) {
            guard !finished else { return }
            finished = true
            if let error { XCTFail(error) }
            completion.fulfill()
        }

        client.onDisconnect = { message in
            finish(with: "Reader disconnected: \(message)")
        }
        client.onData = { data in
            if let activeReceiver = receiver {
                let result = activeReceiver.consume(data)
                for event in result.events {
                    switch event {
                    case let .completed(url, crc32):
                        completedURL = url
                        completedCRC = crc32
                        finish()
                    case let .failed(message):
                        finish(with: message)
                    default:
                        break
                    }
                }
                return
            }

            terminal += String(decoding: data, as: UTF8.self)
            do {
                switch phase {
                case .boot where terminal.contains("0)Game Boy"):
                    terminal.removeAll(keepingCapacity: true)
                    phase = .cartridgeType
                    try client.send("2")
                case .cartridgeType where terminal.contains("Select Cart Type"):
                    terminal.removeAll(keepingCapacity: true)
                    phase = .snesMenu
                    try client.send("0")
                case .snesMenu where terminal.contains("SNES Cart Reader"):
                    terminal.removeAll(keepingCapacity: true)
                    phase = .dump
                    try client.send("0")
                case .dump where terminal.contains("Press Button"):
                    terminal.removeAll(keepingCapacity: true)
                    phase = .transfer
                    receiver = SerialROMTransferReceiver(destinationDirectory: destination)
                    try client.send("T")
                default:
                    break
                }
            } catch {
                finish(with: "Serial command failed: \(error.localizedDescription)")
            }
        }

        try client.connect(path: portPath, baudRate: baudRate)
        wait(for: [completion], timeout: 480)
        client.disconnect()

        let url = try XCTUnwrap(completedURL)
        let crc = try XCTUnwrap(completedCRC)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
        if let expectedCRC { XCTAssertEqual(crc, expectedCRC) }
    }
}
