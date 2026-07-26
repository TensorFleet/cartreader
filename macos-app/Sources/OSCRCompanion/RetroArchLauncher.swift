import AppKit
import Foundation

enum ROMSystem: String, CaseIterable, Equatable {
    case gameBoy
    case gameBoyAdvance
    case nes
    case snes
    case nintendo64
    case genesis
    case masterSystem
    case gameGear
    case sg1000
    case pcEngine
    case wonderSwan
    case neoGeoPocket
    case intellivision
    case colecoVision
    case virtualBoy
    case supervision
    case atari2600
    case odyssey2
    case msx
    case pokemonMini
    case commodore64
    case atari5200
    case atari7800
    case atariJaguar
    case atariLynx
    case vectrex
    case atari8Bit

    var displayName: String {
        switch self {
        case .gameBoy: return "Game Boy / Game Boy Color"
        case .gameBoyAdvance: return "Game Boy Advance"
        case .nes: return "NES / Famicom"
        case .snes: return "Super Nintendo / Super Famicom"
        case .nintendo64: return "Nintendo 64"
        case .genesis: return "Mega Drive / Genesis"
        case .masterSystem: return "Master System / Mark III"
        case .gameGear: return "Game Gear"
        case .sg1000: return "SG-1000"
        case .pcEngine: return "PC Engine / TurboGrafx-16"
        case .wonderSwan: return "WonderSwan"
        case .neoGeoPocket: return "Neo Geo Pocket"
        case .intellivision: return "Intellivision"
        case .colecoVision: return "ColecoVision"
        case .virtualBoy: return "Virtual Boy"
        case .supervision: return "Watara Supervision"
        case .atari2600: return "Atari 2600"
        case .odyssey2: return "Magnavox Odyssey 2"
        case .msx: return "MSX"
        case .pokemonMini: return "Pokémon Mini"
        case .commodore64: return "Commodore 64"
        case .atari5200: return "Atari 5200"
        case .atari7800: return "Atari 7800"
        case .atariJaguar: return "Atari Jaguar"
        case .atariLynx: return "Atari Lynx"
        case .vectrex: return "Vectrex"
        case .atari8Bit: return "Atari 8-bit"
        }
    }

    var fileExtensions: Set<String> {
        switch self {
        case .gameBoy: return ["gb", "gbc"]
        case .gameBoyAdvance: return ["gba"]
        case .nes: return ["nes", "unf", "unif", "bin"]
        case .snes: return ["sfc", "smc", "bs"]
        case .nintendo64: return ["z64", "n64", "v64"]
        case .genesis: return ["md", "gen", "bin"]
        case .masterSystem: return ["sms"]
        case .gameGear: return ["gg"]
        case .sg1000: return ["sg"]
        case .pcEngine: return ["pce"]
        case .wonderSwan: return ["ws", "wsc"]
        case .neoGeoPocket: return ["ngp", "ngc"]
        case .intellivision: return ["int", "rom", "bin"]
        case .colecoVision: return ["col", "rom", "bin"]
        case .virtualBoy: return ["vb"]
        case .supervision: return ["sv"]
        case .atari2600: return ["a26", "bin"]
        case .odyssey2: return ["bin"]
        case .msx: return ["rom", "mx1", "mx2", "bin"]
        case .pokemonMini: return ["min"]
        case .commodore64: return ["crt", "bin"]
        case .atari5200: return ["a52", "bin"]
        case .atari7800: return ["a78"]
        case .atariJaguar: return ["j64", "jag"]
        case .atariLynx: return ["lnx"]
        case .vectrex: return ["vec", "bin"]
        case .atari8Bit: return ["xex", "atr", "car", "bin"]
        }
    }

    /// Preferred cores come first. A fallback is used only when it is explicitly
    /// compatible with the same system and already installed.
    var coreNames: [String] {
        switch self {
        case .gameBoy: return ["gambatte_libretro", "sameboy_libretro", "mgba_libretro"]
        case .gameBoyAdvance: return ["mgba_libretro", "vbam_libretro"]
        case .nes: return ["mesen_libretro", "nestopia_libretro", "fceumm_libretro"]
        case .snes: return ["snes9x_libretro"]
        case .nintendo64: return ["mupen64plus_next_libretro", "parallel_n64_libretro"]
        case .genesis: return ["genesis_plus_gx_libretro", "picodrive_libretro"]
        case .masterSystem, .gameGear, .sg1000:
            return ["genesis_plus_gx_libretro", "gearsystem_libretro", "smsplus_libretro"]
        case .pcEngine: return ["mednafen_pce_fast_libretro", "mednafen_supergrafx_libretro"]
        case .wonderSwan: return ["mednafen_wswan_libretro"]
        case .neoGeoPocket: return ["mednafen_ngp_libretro", "race_libretro"]
        case .intellivision: return ["freeintv_libretro"]
        case .colecoVision: return ["gearcoleco_libretro", "bluemsx_libretro"]
        case .virtualBoy: return ["mednafen_vb_libretro"]
        case .supervision: return ["potator_libretro"]
        case .atari2600: return ["stella_libretro"]
        case .odyssey2: return ["o2em_libretro"]
        case .msx: return ["bluemsx_libretro", "fmsx_libretro"]
        case .pokemonMini: return ["pokemini_libretro"]
        case .commodore64: return ["vice_x64_libretro", "vice_x64sc_libretro"]
        case .atari5200: return ["a5200_libretro", "atari800_libretro"]
        case .atari7800: return ["prosystem_libretro"]
        case .atariJaguar: return ["virtualjaguar_libretro"]
        case .atariLynx: return ["mednafen_lynx_libretro", "handy_libretro"]
        case .vectrex: return ["vecx_libretro"]
        case .atari8Bit: return ["atari800_libretro"]
        }
    }

    static func from(menuTitle: String) -> ROMSystem? {
        let title = menuTitle.lowercased()
        if title.contains("game boy advance") { return .gameBoyAdvance }
        if title.contains("game boy (color)") || title.hasSuffix("game boy") { return .gameBoy }
        if title.contains("nes/famicom") { return .nes }
        if title.contains("super nintendo") || title.contains("sfc") { return .snes }
        if title.contains("nintendo 64") { return .nintendo64 }
        if title.contains("mega drive") || title.contains("genesis") { return .genesis }
        if title.contains("sms/gg") || title.contains("master system") || title.contains("mark iii") { return .masterSystem }
        if title.contains("game gear") { return .gameGear }
        if title.contains("sg-1000") { return .sg1000 }
        if title.contains("pc engine") || title.contains("tg16") { return .pcEngine }
        if title.contains("wonderswan") { return .wonderSwan }
        if title.contains("neogeo pocket") || title.contains("neo geo pocket") { return .neoGeoPocket }
        if title.contains("intellivision") { return .intellivision }
        if title.contains("colecovision") { return .colecoVision }
        if title.contains("virtual boy") { return .virtualBoy }
        if title.contains("watara supervision") { return .supervision }
        if title.contains("atari 2600") { return .atari2600 }
        if title.contains("odyssey 2") { return .odyssey2 }
        if title.contains("pokemon mini") { return .pokemonMini }
        if title.contains("commodore 64") { return .commodore64 }
        if title.contains("atari 5200") { return .atari5200 }
        if title.contains("atari 7800") { return .atari7800 }
        if title.contains("atari jaguar") { return .atariJaguar }
        if title.contains("atari lynx") { return .atariLynx }
        if title.contains("vectrex") { return .vectrex }
        if title.contains("atari 8-bit") { return .atari8Bit }
        if title.contains("msx") { return .msx }
        return nil
    }

    static func resolve(for romURL: URL, preferred: ROMSystem?) throws -> ROMSystem {
        let ext = romURL.pathExtension.lowercased()
        let matches = allCases.filter { $0.fileExtensions.contains(ext) }
        if let preferred, matches.contains(preferred) {
            return preferred
        }
        if matches.count == 1, let match = matches.first {
            return match
        }
        if matches.isEmpty {
            throw RetroArchLaunchError.unsupportedROM(ext.isEmpty ? romURL.lastPathComponent : ".\(ext)")
        }
        throw RetroArchLaunchError.ambiguousROM(ext, matches.map(\.displayName))
    }
}

struct ROMReadTracker {
    private(set) var selectedSystem: ROMSystem?
    private(set) var isReadPending = false
    private(set) var isReadReady = false
    private(set) var relativeDumpFolder: String?
    private var streamBuffer = ""

    mutating func select(_ action: QuickAction) {
        if let system = ROMSystem.from(menuTitle: action.title) {
            selectedSystem = system
        }
        let title = action.title.lowercased()
        guard title.contains("read rom") || title.contains("dump rom") else { return }
        isReadPending = true
        isReadReady = false
        relativeDumpFolder = nil
        streamBuffer = ""
    }

    mutating func consume(_ text: String) {
        guard isReadPending else { return }
        streamBuffer.append(text)
        if streamBuffer.count > 12_000 {
            streamBuffer = String(streamBuffer.suffix(8_000))
        }

        if let range = streamBuffer.range(
            of: #"Saving to\s+/?([^\r\n]+?)/\.\.\."#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            var path = String(streamBuffer[range])
            path = path.replacingOccurrences(
                of: #"^Saving to\s+/?"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            path = path.replacingOccurrences(of: #"/\.\.\.$"#, with: "", options: .regularExpression)
            relativeDumpFolder = path
        }

        let lowercased = streamBuffer.lowercased()
        let completionMarkers = ["press button", "press any button", "finished successfully", "finished reading", " -> ok"]
        if completionMarkers.contains(where: lowercased.contains) {
            isReadPending = false
            isReadReady = true
        }
    }
}

enum RetroArchLaunchError: LocalizedError, Equatable {
    case retroArchNotInstalled
    case unsupportedROM(String)
    case ambiguousROM(String, [String])
    case wrongROM(expected: String, actual: String)
    case coreNotInstalled(system: String, preferredCore: String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .retroArchNotInstalled:
            return "RetroArch is not installed in /Applications or your Applications folder."
        case .unsupportedROM(let ext):
            return "No safe RetroArch core mapping is configured for \(ext)."
        case .ambiguousROM(let ext, let systems):
            return "The .\(ext) extension is used by several systems (\(systems.joined(separator: ", "))). Select the console in OSCR before opening this dump."
        case .wrongROM(let expected, let actual):
            return "This read was for \(expected), but the selected file is \(actual)."
        case .coreNotInstalled(let system, let preferredCore):
            return "The correct core for \(system) is not installed. In RetroArch, use Online Updater → Core Downloader and install \(preferredCore)."
        case .launchFailed(let message):
            return "RetroArch could not be launched: \(message)"
        }
    }
}

struct RetroArchLauncher {
    let fileManager: FileManager
    let homeDirectory: URL

    init(fileManager: FileManager = .default, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func launch(romURL: URL, preferredSystem: ROMSystem?) throws -> ROMSystem {
        let system = try ROMSystem.resolve(for: romURL, preferred: preferredSystem)
        if let preferredSystem, system != preferredSystem {
            throw RetroArchLaunchError.wrongROM(expected: preferredSystem.displayName, actual: system.displayName)
        }
        guard let executable = retroArchExecutable() else {
            throw RetroArchLaunchError.retroArchNotInstalled
        }
        guard let core = coreURL(for: system, in: coreDirectories()) else {
            let preferred = system.coreNames.first?.replacingOccurrences(of: "_libretro", with: "") ?? "a compatible core"
            throw RetroArchLaunchError.coreNotInstalled(system: system.displayName, preferredCore: preferred)
        }

        do {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["-L", core.path, romURL.path]
            try process.run()
            return system
        } catch {
            throw RetroArchLaunchError.launchFailed(error.localizedDescription)
        }
    }

    func coreURL(for system: ROMSystem, in directories: [URL]) -> URL? {
        for name in system.coreNames {
            for directory in directories {
                for suffix in ["dylib", "so"] {
                    let candidate = directory.appendingPathComponent("\(name).\(suffix)")
                    if fileManager.isReadableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    func newestDump(relativeFolder: String?, system: ROMSystem?) -> URL? {
        guard let relativeFolder, !relativeFolder.isEmpty else { return nil }
        let volumes = (try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes", isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var matches: [URL] = []
        for volume in volumes where volume.path != "/Volumes/Macintosh HD" {
            let folder = volume.appendingPathComponent(relativeFolder, isDirectory: true)
            let files = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            matches.append(contentsOf: files.filter { url in
                guard let system else { return !url.pathExtension.isEmpty }
                return system.fileExtensions.contains(url.pathExtension.lowercased())
            })
        }
        return matches.max { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }
    }

    private func retroArchExecutable() -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/RetroArch.app/Contents/MacOS/RetroArch"),
            homeDirectory.appendingPathComponent("Applications/RetroArch.app/Contents/MacOS/RetroArch")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func coreDirectories() -> [URL] {
        var directories = [
            homeDirectory.appendingPathComponent("Library/Application Support/RetroArch/cores", isDirectory: true),
            homeDirectory.appendingPathComponent(".config/retroarch/cores", isDirectory: true),
            homeDirectory.appendingPathComponent(".retroarch/cores", isDirectory: true)
        ]

        let configURLs = [
            homeDirectory.appendingPathComponent("Library/Application Support/RetroArch/config/retroarch.cfg"),
            homeDirectory.appendingPathComponent(".config/retroarch/retroarch.cfg"),
            homeDirectory.appendingPathComponent(".retroarch.cfg")
        ]
        for configURL in configURLs {
            guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n") {
                guard line.trimmingCharacters(in: .whitespaces).hasPrefix("libretro_directory") else { continue }
                guard let rawValue = line.split(separator: "=", maxSplits: 1).last else { continue }
                var path = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if path.hasPrefix("~/") {
                    path = homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
                }
                directories.insert(URL(fileURLWithPath: path, isDirectory: true), at: 0)
            }
        }
        return Array(NSOrderedSet(array: directories.map(\.standardizedFileURL))) as? [URL] ?? directories
    }
}
