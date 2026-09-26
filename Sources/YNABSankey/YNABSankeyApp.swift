import AppKit
import SwiftUI

@main
struct YNABSankeyApp: App {
    @State private var model = AppModel()

    init() {
        // Launched as a bare executable (swift run), macOS won't give us a Dock icon or focus.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("YNAB Sankey") {
            ContentView().environment(model)
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { model.zoom(by: 1.25) }.keyboardShortcut("=")
                Button("Zoom Out") { model.zoom(by: 1 / 1.25) }.keyboardShortcut("-")
                Button("Actual Size") { model.zoom = 1 }.keyboardShortcut("0")
                Divider()
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}
