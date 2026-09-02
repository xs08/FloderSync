import Foundation

protocol GitClient: Sendable {
    func validateRepository(_ profile: SyncProfile) async throws -> RepositoryInfo
    func synchronizationState(
        at path: String,
        remote: String,
        branch: String
    ) async throws -> RepositorySynchronizationState
    func checkRemoteAccess(at path: String, remote: String) async throws
    func workingTreeStatus(at path: String) async throws -> GitWorkingTreeStatus
    func stageAll(at path: String) async throws
    func commit(at path: String, message: String) async throws
    func integrateRemote(
        at path: String,
        remote: String,
        branch: String,
        strategy: SyncIntegrationStrategy
    ) async throws
    func push(at path: String, remote: String, branch: String) async throws
}

extension GitClient {
    func synchronizationState(
        at path: String,
        remote: String,
        branch: String
    ) async throws -> RepositorySynchronizationState {
        .upToDate
    }
}
