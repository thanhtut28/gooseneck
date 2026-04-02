import SwiftUI

struct PostureDeskCommands: Commands {
    let viewModel: PostureViewModel

    var body: some Commands {
        // Replace the default app menu "About" item
        CommandGroup(replacing: .appInfo) {
            Button("About PostureDesk") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    NSApplication.AboutPanelOptionKey.applicationName: "PostureDesk",
                    NSApplication.AboutPanelOptionKey.applicationVersion: "1.0.0",
                    NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                        string: "Real-time posture monitoring using your MacBook's built-in sensors.",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                ])
            }
        }

        // Monitoring menu
        CommandMenu("Monitoring") {
            Button(viewModel.isPaused ? "Resume Monitoring" : "Pause Monitoring") {
                if viewModel.isPaused {
                    viewModel.resumeMonitoring()
                } else {
                    viewModel.pauseMonitoring()
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Recalibrate Posture") {
                viewModel.calibrate()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Took a Break") {
                viewModel.recordBreak()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()

            // Surface submenu
            Picker("Surface", selection: Binding(
                get: { viewModel.selectedSurface },
                set: { viewModel.selectedSurface = $0 }
            )) {
                Text("Desk").tag(Surface.desk)
                Text("Lap").tag(Surface.lap)
                Text("Couch").tag(Surface.couch)
            }
        }

        // Appearance in View menu
        CommandGroup(after: .toolbar) {
            Divider()

            Picker("Appearance", selection: Binding(
                get: { viewModel.themeMode },
                set: { viewModel.themeMode = $0 }
            )) {
                Text("System").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }

            Toggle("Posture Island", isOn: Binding(
                get: { viewModel.dynamicIslandEnabled },
                set: { viewModel.dynamicIslandEnabled = $0 }
            ))
        }
    }
}
