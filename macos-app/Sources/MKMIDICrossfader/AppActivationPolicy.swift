import AppKit
import Foundation

@MainActor
enum AppActivationPolicy {
    static let showDockIconDefaultsKey = "showDockIcon"

    static func shouldShowDockIcon(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: showDockIconDefaultsKey) as? Bool ?? true
    }

    static func policy(
        showDockIcon: Bool
    ) -> NSApplication.ActivationPolicy {
        showDockIcon ? .regular : .accessory
    }

    @discardableResult
    static func apply(showDockIcon: Bool) -> Bool {
        let target = policy(showDockIcon: showDockIcon)
        guard NSApp.activationPolicy() != target else {
            return true
        }
        return NSApp.setActivationPolicy(target)
    }
}
