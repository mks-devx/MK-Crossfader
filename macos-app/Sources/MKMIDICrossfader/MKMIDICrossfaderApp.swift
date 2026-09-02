import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppActivationPolicy.apply(
            showDockIcon: AppActivationPolicy.shouldShowDockIcon()
        )
    }
}

@main
@MainActor
struct MKMIDICrossfaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            MenuBarRouteMark(isActive: model.isEnabled)
        }
        .menuBarExtraStyle(.menu)
    }
}
