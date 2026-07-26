import XCTest
@testable import OSCRCompanion

final class EmulatorSettingsTests: XCTestCase {
    func testPersistsPerSystemPreferences() {
        let suite = "EmulatorSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = EmulatorSettingsStore(defaults: defaults)
        store.setMode(.systemDefault, for: .snes)
        store.setApplication(URL(fileURLWithPath: "/Applications/Test Emulator.app"), for: .gameBoy)

        let restored = EmulatorSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.preference(for: .snes).mode, .systemDefault)
        XCTAssertEqual(restored.preference(for: .gameBoy).mode, .customApplication)
        XCTAssertEqual(
            restored.preference(for: .gameBoy).applicationPath,
            "/Applications/Test Emulator.app"
        )
        XCTAssertEqual(restored.preference(for: .nes), EmulatorPreference())
    }
}
