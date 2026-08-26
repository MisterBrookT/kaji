import Foundation
import ServiceManagement

enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    enum AuthorizationStatus: Equatable {
        case authorized, notAuthorized, needsReauthorization
    }

    static var authorizationStatus: AuthorizationStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .authorized
        case .requiresApproval: .needsReauthorization
        case .notRegistered, .notFound: .notAuthorized
        @unknown default: .notAuthorized
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[kaji.login-item] failed enabled=\(enabled) error=\(error)")
            return false
        }
    }
}
