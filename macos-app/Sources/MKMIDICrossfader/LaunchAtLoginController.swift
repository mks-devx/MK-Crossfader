import Combine
import ServiceManagement

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LaunchAtLoginServicing {}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isAvailable = true
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusMessage: String?

    private let service: any LaunchAtLoginServicing

    init(service: any LaunchAtLoginServicing = SMAppService.mainApp) {
        self.service = service
        updateStatus()
    }

    func refresh() {
        statusMessage = nil
        updateStatus()
    }

    func setEnabled(_ shouldEnable: Bool) {
        statusMessage = nil

        do {
            if shouldEnable {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            statusMessage = shouldEnable
                ? "Launch at Login could not be enabled."
                : "Launch at Login could not be disabled."
        }

        updateStatus(preserveMessage: true)
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func updateStatus(preserveMessage: Bool = false) {
        let currentStatus = service.status
        isEnabled = currentStatus == .enabled
        isAvailable = currentStatus != .notFound
        requiresApproval = currentStatus == .requiresApproval

        guard !preserveMessage || statusMessage == nil else {
            return
        }

        switch currentStatus {
        case .requiresApproval:
            statusMessage = "Launch at Login needs approval in System Settings."
        case .notFound:
            statusMessage = "Launch at Login is unavailable for this app copy."
        case .enabled, .notRegistered:
            statusMessage = nil
        @unknown default:
            statusMessage = "Launch at Login status is unavailable."
        }
    }
}
