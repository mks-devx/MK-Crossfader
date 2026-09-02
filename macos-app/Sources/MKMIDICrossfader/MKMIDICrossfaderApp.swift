import SwiftUI

@main
@MainActor
struct MKMIDICrossfaderApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("MK MIDI Crossfader", id: "settings") {
            SettingsView(model: model)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(
                systemName: model.isEnabled
                    ? "arrow.left.arrow.right.circle.fill"
                    : "arrow.left.arrow.right.circle"
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
