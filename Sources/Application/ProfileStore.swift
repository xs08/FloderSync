import Foundation

protocol ProfileStore: Sendable {
    func loadProfiles() async throws -> [SyncProfile]
    func saveProfiles(_ profiles: [SyncProfile]) async throws
}
