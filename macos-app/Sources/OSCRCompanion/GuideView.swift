import SwiftUI

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("How to dump a cartridge")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    guideStep(1, "Flash serial firmware", "Build the OSCR serial-transfer firmware with SERIAL_MONITOR enabled. It runs the menu and CRC-verified ROM downloads over USB at 115,200 baud.")
                    guideStep(2, "Connect", "Remove cartridges while flashing. For normal use, insert a cartridge, power on the OSCR, choose its USB serial port here, leave 115,200 baud selected, and click Connect.")
                    guideStep(3, "Navigate", "The options printed by the OSCR appear as buttons. Click an option, use the page buttons, or type one character and press Send.")
                    guideStep(4, "Read", "Choose the console, then Read ROM or Read Save. Progress, detected metadata, and checksums appear in the terminal.")
                    guideStep(5, "Capture if useful", "Capture stores the raw serial output in ~/Downloads/CartReader. It does not transfer the ROM itself.")
                    guideStep(6, "Download and play", "When the ROM finishes, choose Download & Play. The Mac verifies the serial copy against the reader's CRC32, saves it under Downloads/CartReader/ROMs, and opens the correct RetroArch core.")

                    Label("Commands are sent byte-for-byte with no newline appended.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(22)
            }
        }
        .frame(width: 620, height: 560)
    }

    private func guideStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
