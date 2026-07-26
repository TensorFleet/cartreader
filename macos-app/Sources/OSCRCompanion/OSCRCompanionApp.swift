import SwiftUI

@main
struct OSCRCompanionApp: App {
    @StateObject private var model = ReaderModel()

    var body: some Scene {
        WindowGroup("OSCR Companion") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 620)
        }
        .defaultSize(width: 980, height: 720)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 720, height: 680)
                .padding()
        }
    }
}
