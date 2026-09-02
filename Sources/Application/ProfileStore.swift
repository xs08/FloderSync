import Foundation

struct AppConfiguration: Equatable, Sendable {
    var profiles: [SyncProfile]
    var automationRules: [AutomationRule]

    static let empty = AppConfiguration(profiles: [], automationRules: [])
}

protocol ProfileStore: Sendable {
    func loadConfiguration() async throws -> AppConfiguration
    func saveConfiguration(_ configuration: AppConfiguration) async throws
}
