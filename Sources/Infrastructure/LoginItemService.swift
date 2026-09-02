import ServiceManagement

enum LoginItemStatus: Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

protocol LoginItemManaging: Sendable {
    func status() async -> LoginItemStatus
    func setEnabled(_ enabled: Bool) async throws
    func openSystemSettings() async
}

struct LoginItemService: LoginItemManaging {
    func status() async -> LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() async {
        SMAppService.openSystemSettingsLoginItems()
    }
}
