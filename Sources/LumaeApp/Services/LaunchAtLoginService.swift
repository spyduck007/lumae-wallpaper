import Foundation
import ServiceManagement

@MainActor
struct LaunchAtLoginService {
    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        }
    }
    var statusDescription: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status { case .enabled: return "Enabled"; case .requiresApproval: return "Requires approval in System Settings"; case .notRegistered: return "Disabled"; case .notFound: return "Unavailable"; @unknown default: return "Unknown" }
        }
        return "Unavailable"
    }
}
