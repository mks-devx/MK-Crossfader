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
    @StateObject private var updateChecker = AppUpdateChecker()

    var body: some Scene {
        Window("MK MIDI Crossfader", id: "settings") {
            SettingsView(model: model, updateChecker: updateChecker)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(model: model, updateChecker: updateChecker)
        } label: {
            MenuBarRouteMark(isActive: model.isEnabled)
        }
        .menuBarExtraStyle(.menu)
    }
}
