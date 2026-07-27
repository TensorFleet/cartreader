import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ReaderModel
    @FocusState private var commandFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            terminal
            Divider()
            actionArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.toggleCapture()
                } label: {
                    Label(model.isCapturing ? "Stop Capture" : "Capture", systemImage: model.isCapturing ? "stop.circle.fill" : "record.circle")
                }
                .tint(model.isCapturing ? .red : nil)

                Button {
                    model.clearTerminal()
                } label: {
                    Label("Clear", systemImage: "trash")
                }

                Button {
                    model.isGuidePresented = true
                } label: {
                    Label("Guide", systemImage: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $model.isGuidePresented) {
            GuideView()
        }
        .alert("OSCR Companion", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.status)
                    .font(.headline)
                    .lineLimit(1)
                if let captureStatus = model.captureStatus {
                    Text(captureStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                model.refreshPorts()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh serial devices")
            .disabled(model.isConnected)

            Picker("Port", selection: $model.selectedPortPath) {
                if model.ports.isEmpty {
                    Text("No USB serial devices").tag("")
                }
                ForEach(model.ports) { port in
                    Text(port.displayName).tag(port.path)
                }
            }
            .labelsHidden()
            .frame(width: 280)
            .disabled(model.isConnected)

            Picker("Baud", selection: $model.baudRate) {
                ForEach(ReaderModel.baudRates, id: \.self) { rate in
                    Text("\(rate) baud").tag(rate)
                }
            }
            .labelsHidden()
            .frame(width: 145)
            .disabled(model.isConnected)

            Button(model.isConnected ? "Disconnect" : "Connect") {
                model.toggleConnection()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private var terminal: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.terminalText.isEmpty ? "Connect to an OSCR running SERIAL_MONITOR firmware to begin." : model.terminalText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(model.terminalText.isEmpty ? Color.secondary : Color(red: 0.76, green: 0.95, blue: 0.72))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                Color.clear.frame(height: 1).id("terminal-bottom")
            }
            .background(Color(red: 0.045, green: 0.055, blue: 0.05))
            .onChange(of: model.terminalRevision) { _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            if !model.quickActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.quickActions) { action in
                            Button(action.title) {
                                model.perform(action)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(!model.isConnected)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            HStack(spacing: 10) {
                TextField("Menu number or letter — sent exactly as typed, without a newline", text: $model.command)
                    .textFieldStyle(.roundedBorder)
                    .focused($commandFocused)
                    .onSubmit { model.sendCommand() }
                Button("Send") {
                    model.sendCommand()
                    commandFocused = true
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!model.isConnected || model.command.isEmpty)
            }
            .padding(.horizontal, 12)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROM and save files remain on the OSCR SD card; Capture records serial output only.")
                    if let romReadMessage = model.romReadMessage {
                        Text(romReadMessage)
                            .foregroundStyle(model.isROMReadyForRetroArch ? Color.green : Color.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if model.isROMReadyForRetroArch {
                    if model.isDownloadingROM {
                        ProgressView(value: model.romDownloadProgress)
                            .frame(width: 130)
                    }
                    Button {
                        model.downloadROM()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .disabled(!model.isConnected || model.isDownloadingROM)

                    Button {
                        model.downloadAndOpenROM()
                    } label: {
                        Label("Download & Play", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(!model.isConnected || model.isDownloadingROM)

                    Button("Open from SD…") {
                        model.openROMInRetroArch()
                    }
                    .disabled(model.isDownloadingROM)
                }
                Button("Show Captures") { model.revealCaptureFolder() }
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: ReaderModel

    var body: some View {
        Form {
            Section("Reader") {
                Picker("Default baud rate", selection: $model.baudRate) {
                    ForEach(ReaderModel.baudRates, id: \.self) { rate in
                        Text("\(rate)").tag(rate)
                    }
                }
                Text("OSCR serial-transfer firmware uses 115,200 baud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            EmulatorSettingsRows(store: model.emulatorSettings) { system in
                model.chooseCustomEmulator(for: system)
            }
        }
    }
}

private struct EmulatorSettingsRows: View {
    @ObservedObject var store: EmulatorSettingsStore
    let chooseApplication: (ROMSystem) -> Void

    var body: some View {
        Section("Emulators by cartridge type") {
            Text("RetroArch uses the compatible core mapped for each system. Choose macOS Default or a specific application to override it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ROMSystem.allCases, id: \.rawValue) { system in
                HStack {
                    Text(system.displayName)
                        .frame(width: 210, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { store.preference(for: system).mode },
                        set: { store.setMode($0, for: system) }
                    )) {
                        ForEach(EmulatorMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()

                    if store.preference(for: system).mode == .customApplication {
                        Button(applicationName(for: system)) {
                            chooseApplication(system)
                        }
                    }
                }
            }
        }
    }

    private func applicationName(for system: ROMSystem) -> String {
        guard let path = store.preference(for: system).applicationPath else { return "Choose…" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
