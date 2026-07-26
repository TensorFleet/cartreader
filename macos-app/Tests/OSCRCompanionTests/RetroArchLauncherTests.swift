import XCTest
@testable import OSCRCompanion

final class RetroArchLauncherTests: XCTestCase {
    func testResolvesUnambiguousROMExtensionsToCorrectSystems() throws {
        XCTAssertEqual(try ROMSystem.resolve(for: URL(fileURLWithPath: "/tmp/game.sfc"), preferred: nil), .snes)
        XCTAssertEqual(try ROMSystem.resolve(for: URL(fileURLWithPath: "/tmp/game.gba"), preferred: nil), .gameBoyAdvance)
        XCTAssertEqual(try ROMSystem.resolve(for: URL(fileURLWithPath: "/tmp/game.z64"), preferred: nil), .nintendo64)
    }

    func testUsesSelectedConsoleToDisambiguateBinDump() throws {
        XCTAssertEqual(
            try ROMSystem.resolve(for: URL(fileURLWithPath: "/tmp/game.bin"), preferred: .genesis),
            .genesis
        )
        XCTAssertThrowsError(try ROMSystem.resolve(for: URL(fileURLWithPath: "/tmp/game.bin"), preferred: nil))
    }

    func testReadTrackerCapturesChunkedDumpPathAndCompletion() {
        var tracker = ROMReadTracker()
        tracker.select(QuickAction(id: "system", title: "2  Super Nintendo/SFC", value: "2", kind: .menu))
        tracker.select(QuickAction(id: "read", title: "0  Read ROM", value: "0", kind: .menu))

        tracker.consume("Saving to SNES/ROM/Super Ma")
        tracker.consume("rio World/7/...\r\nChecksum... 1234 -> OK\r\nPress Button")

        XCTAssertEqual(tracker.selectedSystem, .snes)
        XCTAssertEqual(tracker.relativeDumpFolder, "SNES/ROM/Super Mario World/7")
        XCTAssertFalse(tracker.isReadPending)
        XCTAssertTrue(tracker.isReadReady)
    }

    func testSelectsPreferredInstalledCore() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fallback = temporaryDirectory.appendingPathComponent("nestopia_libretro.dylib")
        XCTAssertTrue(FileManager.default.createFile(atPath: fallback.path, contents: Data()))

        let launcher = RetroArchLauncher()
        XCTAssertEqual(launcher.coreURL(for: .nes, in: [temporaryDirectory]), fallback)
    }
}

final class SerialROMTransferTests: XCTestCase {
    func testReceivesChunkedROMAndVerifiesCRC32() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let receiver = SerialROMTransferReceiver(destinationDirectory: destination)
        let packet = Data("OSCRXFER1\r\nNAME:test.sfc\r\nSIZE:9\r\nDATA\r\n123456789\r\nOSCRXFER1 END CBF43926\r\nNEXT MENU\r\n".utf8)
        var events: [ROMTransferConsumeResult.Event] = []
        var passthrough = Data()
        for chunk in packet.chunked(into: 7) {
            let result = receiver.consume(chunk)
            events.append(contentsOf: result.events)
            passthrough.append(result.passthrough)
        }

        guard case .completed(let url, let crc)? = events.first(where: {
            if case .completed = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected a completed transfer")
        }
        XCTAssertEqual(crc, 0xCBF43926)
        XCTAssertEqual(try Data(contentsOf: url), Data("123456789".utf8))
        XCTAssertEqual(String(data: passthrough, encoding: .utf8), "NEXT MENU\r\n")
    }

    func testRejectsBadTransferChecksumAndDeletesPartialFile() {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let receiver = SerialROMTransferReceiver(destinationDirectory: destination)
        let packet = Data("OSCRXFER1\r\nNAME:test.gb\r\nSIZE:3\r\nDATA\r\nabc\r\nOSCRXFER1 END 00000000\r\n".utf8)
        let result = receiver.consume(packet)

        XCTAssertTrue(result.events.contains { event in
            if case .failed(let message) = event { return message.contains("checksum mismatch") }
            return false
        })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        XCTAssertTrue(files.isEmpty)
    }
}

private extension Data {
    func chunked(into size: Int) -> [Data] {
        stride(from: 0, to: count, by: size).map { offset in
            subdata(in: offset..<Swift.min(offset + size, count))
        }
    }
}
