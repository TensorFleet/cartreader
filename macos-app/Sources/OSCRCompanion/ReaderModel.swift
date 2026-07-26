import AppKit
import Foundation
import UniformTypeIdentifiers

struct SerialPortDescriptor: Identifiable, Hashable {
    let path: String
    let displayName: String
    var id: String { path }
}

@MainActor
final class ReaderModel: ObservableObject {
    static let baudRates = [9_600, 19_200, 38_400, 57_600, 115_200, 230_400, 250_000, 500_000]
    private static let maximumTerminalCharacters = 100_000

    @Published var ports: [SerialPortDescriptor] = []
    @Published var selectedPortPath = ""
    @Published var baudRate = 115_200
    @Published var isConnected = false
    @Published var status = "Disconnected — plug in the cart reader and connect"
    @Published var terminalText = ""
    @Published var terminalRevision = 0
    @Published var quickActions: [QuickAction] = []
    @Published var command = ""
    @Published var isCapturing = false
    @Published var captureBytes: UInt64 = 0
    @Published var captureName: String?
    @Published var isGuidePresented = false
    @Published var isROMReadyForRetroArch = false
    @Published var romReadMessage: String?
    @Published var alertMessage: String?
    @Published var isDownloadingROM = false
    @Published var romDownloadProgress = 0.0

    let emulatorSettings = EmulatorSettingsStore()

    private let serialClient = SerialPortClient()
    private let retroArchLauncher = RetroArchLauncher()
    private var parser = MenuParser()
    private var romReadTracker = ROMReadTracker()
    private var romTransferReceiver: SerialROMTransferReceiver?
    private var launchAfterDownload = false
    private var captureHandle: FileHandle?

    init() {
        serialClient.onData = { [weak self] data in self?.receive(data) }
        serialClient.onDisconnect = { [weak self] reason in
            self?.appendTerminal("\n[connection lost: \(reason)]\n")
            self?.disconnect()
        }
        refreshPorts()
    }

    var selectedPort: SerialPortDescriptor? {
        ports.first { $0.path == selectedPortPath }
    }

    var captureStatus: String? {
        guard let captureName, isCapturing else { return nil }
        return "Recording to \(captureName) — \(captureBytes.formatted()) bytes"
    }

    func refreshPorts() {
        let deviceNames = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let detected = deviceNames
            .filter(Self.isSupportedSerialDevice)
            .map { name in
                SerialPortDescriptor(path: "/dev/\(name)", displayName: Self.friendlyName(for: name))
            }
            .sorted { left, right in
                let leftPreferred = Self.isPreferredUSBPort(left.path)
                let rightPreferred = Self.isPreferredUSBPort(right.path)
                return leftPreferred == rightPreferred
                    ? left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
                    : leftPreferred
            }

        ports = detected
        if !detected.contains(where: { $0.path == selectedPortPath }) {
            selectedPortPath = detected.first(where: { Self.isPreferredUSBPort($0.path) })?.path
                ?? detected.first?.path
                ?? ""
        }
        if detected.isEmpty && !isConnected {
            status = "No USB serial device found"
        }
    }

    func toggleConnection() {
        isConnected ? disconnect() : connect()
    }

    func connect() {
        guard !selectedPortPath.isEmpty else {
            status = "Select a USB serial device first"
            return
        }
        do {
            try serialClient.connect(path: selectedPortPath, baudRate: baudRate)
            isConnected = true
            status = "Connected: \(selectedPort?.displayName ?? selectedPortPath) @ \(baudRate) baud"
            appendTerminal("[connected to \(selectedPortPath) at \(baudRate) baud]\n")
        } catch {
            status = error.localizedDescription
            appendTerminal("[connection failed: \(error.localizedDescription)]\n")
        }
    }

    func disconnect() {
        romTransferReceiver?.cancel()
        romTransferReceiver = nil
        isDownloadingROM = false
        serialClient.disconnect()
        isConnected = false
        status = "Disconnected — plug in the cart reader and connect"
    }

    func sendCommand() {
        guard !command.isEmpty else { return }
        if send(command) {
            command = ""
        }
    }

    func perform(_ action: QuickAction) {
        romReadTracker.select(action)
        if romReadTracker.isReadPending {
            isROMReadyForRetroArch = false
            romReadMessage = "Reading ROM to the OSCR SD card…"
        }
        _ = send(action.value)
    }

    @discardableResult
    func send(_ value: String) -> Bool {
        do {
            try serialClient.send(value)
            appendTerminal("> \(value)\n")
            return true
        } catch {
            status = error.localizedDescription
            appendTerminal("\n[write failed: \(error.localizedDescription)]\n")
            if serialClient.isConnected == false {
                disconnect()
            }
            return false
        }
    }

    func clearTerminal() {
        terminalText = ""
        terminalRevision += 1
    }

    func toggleCapture() {
        isCapturing ? stopCapture() : startCapture()
    }

    func revealCaptureFolder() {
        NSWorkspace.shared.open(Self.captureDirectory)
    }

    func openROMInRetroArch() {
        let preferredSystem = romReadTracker.selectedSystem
        if let exactDump = retroArchLauncher.newestDump(
            relativeFolder: romReadTracker.relativeDumpFolder,
            system: preferredSystem
        ) {
            launchROM(exactDump, preferredSystem: preferredSystem)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Open OSCR ROM"
        panel.prompt = "Open ROM"
        panel.message = "Insert the OSCR SD card, then select the ROM dump. The app will use the emulator configured for its cartridge type."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if FileManager.default.fileExists(atPath: "/Volumes") {
            panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        }
        guard panel.runModal() == .OK, let romURL = panel.url else { return }
        launchROM(romURL, preferredSystem: preferredSystem)
    }

    func downloadROM() {
        startROMDownload(launchWhenFinished: false)
    }

    func downloadAndOpenROM() {
        startROMDownload(launchWhenFinished: true)
    }

    func chooseCustomEmulator(for system: ROMSystem) {
        let panel = NSOpenPanel()
        panel.title = "Choose emulator for \(system.displayName)"
        panel.prompt = "Choose Emulator"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        emulatorSettings.setApplication(url, for: system)
    }

    private func startROMDownload(launchWhenFinished: Bool) {
        guard isConnected else {
            alertMessage = "Connect to the OSCR before requesting the ROM transfer."
            return
        }
        let receiver = SerialROMTransferReceiver(destinationDirectory: Self.romDownloadDirectory)
        romTransferReceiver = receiver
        launchAfterDownload = launchWhenFinished
        isDownloadingROM = true
        romDownloadProgress = 0
        romReadMessage = "Requesting ROM from the reader…"
        if !send("T") {
            receiver.cancel()
            romTransferReceiver = nil
            isDownloadingROM = false
        }
    }

    private func receive(_ data: Data) {
        if let romTransferReceiver {
            let result = romTransferReceiver.consume(data)
            handleTransferEvents(result.events)
            if !result.passthrough.isEmpty {
                receiveTextData(result.passthrough)
            }
            return
        }
        receiveTextData(data)
    }

    private func receiveTextData(_ data: Data) {
        if let captureHandle {
            do {
                try captureHandle.write(contentsOf: data)
                captureBytes += UInt64(data.count)
            } catch {
                appendTerminal("\n[capture write failed: \(error.localizedDescription)]\n")
                stopCapture(report: false)
            }
        }

        // Firmware pads the legacy checksum footer with NUL bytes so Android
        // USB hosts release their final bulk read. Preserve those bytes in a
        // raw capture, but keep them out of the terminal and menu parser.
        let terminalBytes = data.filter { $0 != 0 }
        guard !terminalBytes.isEmpty else { return }
        let text = String(bytes: terminalBytes, encoding: .isoLatin1) ?? ""
        appendTerminal(text)
        parser.consume(text)
        quickActions = parser.actions
        romReadTracker.consume(text)
        if romReadTracker.isReadReady, !isROMReadyForRetroArch {
            isROMReadyForRetroArch = true
            let system = romReadTracker.selectedSystem?.displayName ?? "ROM"
            romReadMessage = "\(system) dump finished — choose Download or Download & Play."
        }
    }

    private func handleTransferEvents(_ events: [ROMTransferConsumeResult.Event]) {
        for event in events {
            switch event {
            case .started(let name, let size):
                romReadMessage = "Downloading \(name) — \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
            case .progress(let received, let size):
                romDownloadProgress = size == 0 ? 0 : Double(received) / Double(size)
                romReadMessage = "Downloading ROM — \(Int(romDownloadProgress * 100))%"
            case .completed(let url, let crc32):
                romTransferReceiver = nil
                isDownloadingROM = false
                romDownloadProgress = 1
                romReadMessage = String(format: "Downloaded and verified %@ — CRC32 %08X", url.lastPathComponent, crc32)
                appendTerminal(String(format: "\n[ROM downloaded: %@ — CRC32 %08X]\n", url.path, crc32))
                if launchAfterDownload {
                    launchROM(url, preferredSystem: romReadTracker.selectedSystem)
                } else {
                    status = "Downloaded \(url.lastPathComponent)"
                }
            case .failed(let message):
                romTransferReceiver?.cancel()
                romTransferReceiver = nil
                isDownloadingROM = false
                romDownloadProgress = 0
                romReadMessage = "ROM transfer failed"
                alertMessage = message
            }
        }
    }

    private func launchROM(_ romURL: URL, preferredSystem: ROMSystem?) {
        do {
            let system = try ROMSystem.resolve(for: romURL, preferred: preferredSystem)
            if let preferredSystem, system != preferredSystem {
                throw RetroArchLaunchError.wrongROM(expected: preferredSystem.displayName, actual: system.displayName)
            }
            let preference = emulatorSettings.preference(for: system)
            switch preference.mode {
            case .retroArch:
                _ = try retroArchLauncher.launch(romURL: romURL, preferredSystem: system)
                status = "Opened \(romURL.lastPathComponent) in RetroArch using the correct \(system.displayName) core"
                appendTerminal("\n[RetroArch: opened \(romURL.lastPathComponent) as \(system.displayName)]\n")
            case .systemDefault:
                guard NSWorkspace.shared.open(romURL) else {
                    throw RetroArchLaunchError.launchFailed("macOS has no application registered for .\(romURL.pathExtension)")
                }
                status = "Opened \(romURL.lastPathComponent) with the macOS default application"
                appendTerminal("\n[opened with macOS default: \(romURL.lastPathComponent)]\n")
            case .customApplication:
                guard let path = preference.applicationPath else {
                    throw RetroArchLaunchError.launchFailed("Choose an application for \(system.displayName) in Settings first.")
                }
                let applicationURL = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: applicationURL.path) else {
                    throw RetroArchLaunchError.launchFailed("The configured application is no longer installed: \(path)")
                }
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(
                    [romURL],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { [weak self] _, error in
                    Task { @MainActor in
                        if let error {
                            self?.alertMessage = "Could not open \(romURL.lastPathComponent): \(error.localizedDescription)"
                        }
                    }
                }
                status = "Opened \(romURL.lastPathComponent) with \(applicationURL.deletingPathExtension().lastPathComponent)"
                appendTerminal("\n[opened with \(applicationURL.lastPathComponent): \(romURL.lastPathComponent)]\n")
            }
        } catch {
            alertMessage = error.localizedDescription
            status = "Could not open ROM"
        }
    }

    private func startCapture() {
        do {
            try FileManager.default.createDirectory(
                at: Self.captureDirectory,
                withIntermediateDirectories: true
            )
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let name = "oscr_capture_\(formatter.string(from: Date())).log"
            let url = Self.captureDirectory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            captureHandle = try FileHandle(forWritingTo: url)
            captureName = name
            captureBytes = 0
            isCapturing = true
            appendTerminal("[capture started: ~/Downloads/CartReader/\(name)]\n")
        } catch {
            status = "Capture failed: \(error.localizedDescription)"
        }
    }

    private func stopCapture(report: Bool = true) {
        let name = captureName
        try? captureHandle?.synchronize()
        try? captureHandle?.close()
        captureHandle = nil
        captureName = nil
        isCapturing = false
        if report, let name {
            appendTerminal("[capture saved: ~/Downloads/CartReader/\(name), \(captureBytes) bytes]\n")
            status = "Saved \(name)"
        }
    }

    private func appendTerminal(_ text: String) {
        terminalText.append(text)
        if terminalText.count > Self.maximumTerminalCharacters {
            terminalText = String(terminalText.suffix(Self.maximumTerminalCharacters / 2))
        }
        terminalRevision += 1
    }

    private static var captureDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CartReader", isDirectory: true)
    }

    private static var romDownloadDirectory: URL {
        captureDirectory.appendingPathComponent("ROMs", isDirectory: true)
    }

    private static func isSupportedSerialDevice(_ name: String) -> Bool {
        guard name.hasPrefix("cu.") else { return false }
        let lowercased = name.lowercased()
        return lowercased.contains("usbserial")
            || lowercased.contains("usbmodem")
            || lowercased.contains("wchusbserial")
            || lowercased.contains("slab_usb")
            || lowercased.contains("serial")
    }

    private static func isPreferredUSBPort(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.contains("usbserial")
            || lowercased.contains("usbmodem")
            || lowercased.contains("wch")
            || lowercased.contains("slab")
    }

    private static func friendlyName(for deviceName: String) -> String {
        let lowercased = deviceName.lowercased()
        if lowercased.contains("wch") { return "WCH CH340/CH341 — \(deviceName)" }
        if lowercased.contains("slab") { return "Silicon Labs CP210x — \(deviceName)" }
        if lowercased.contains("usbmodem") { return "Arduino / USB Modem — \(deviceName)" }
        if lowercased.contains("usbserial") { return "USB Serial — \(deviceName)" }
        return deviceName
    }
}
