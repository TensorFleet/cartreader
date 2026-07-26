import Foundation

enum EmulatorMode: String, CaseIterable, Codable {
    case retroArch
    case systemDefault
    case customApplication

    var displayName: String {
        switch self {
        case .retroArch: return "RetroArch (recommended)"
        case .systemDefault: return "macOS default application"
        case .customApplication: return "Chosen application"
        }
    }
}

struct EmulatorPreference: Codable, Equatable {
    var mode: EmulatorMode = .retroArch
    var applicationPath: String?
}

final class EmulatorSettingsStore: ObservableObject {
    private static let defaultsKey = "OSCREmulatorPreferencesV1"

    @Published private(set) var preferences: [String: EmulatorPreference]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: EmulatorPreference].self, from: data) {
            preferences = decoded
        } else {
            preferences = [:]
        }
    }

    func preference(for system: ROMSystem) -> EmulatorPreference {
        preferences[system.rawValue] ?? EmulatorPreference()
    }

    func setMode(_ mode: EmulatorMode, for system: ROMSystem) {
        var preference = preference(for: system)
        preference.mode = mode
        preferences[system.rawValue] = preference
        save()
    }

    func setApplication(_ url: URL, for system: ROMSystem) {
        preferences[system.rawValue] = EmulatorPreference(
            mode: .customApplication,
            applicationPath: url.path
        )
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
