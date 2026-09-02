import Foundation

protocol GitClient: Sendable {
    func validateRepository(_ profile: SyncProfile) async throws -> RepositoryInfo
    func checkRemoteAccess(at path: String, remote: String) async throws
    func workingTreeStatus(at path: String) async throws -> GitWorkingTreeStatus
    func stageAll(at path: String) async throws
    func commit(at path: String, message: String) async throws
    func pullRebase(at path: String, remote: String, branch: String) async throws
    func push(at path: String, remote: String, branch: String) async throws
}
