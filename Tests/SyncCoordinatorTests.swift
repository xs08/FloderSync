import XCTest
@testable import floderSync

final class SyncCoordinatorTests: XCTestCase {
    func testRepeatedTriggersForOneRepositoryAreCoalesced() async throws {
        let git = DelayedGitClient(delay: .milliseconds(80))
        let coordinator = SyncCoordinator(engine: SyncEngine(git: git))
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/Notes")

        await coordinator.enqueue(profile: profile, trigger: .newCommit)
        await coordinator.enqueue(profile: profile, trigger: .scheduled)
        await coordinator.enqueue(profile: profile, trigger: .manual)
        await coordinator.waitUntilIdle(profileID: profile.id)

        let validationCount = await git.validationCount
        XCTAssertEqual(validationCount, 2, "An event storm should produce the active run plus one coalesced run.")
    }

    func testCoordinatorNeverRunsSameRepositoryInParallel() async throws {
        let git = DelayedGitClient(delay: .milliseconds(60))
        let coordinator = SyncCoordinator(engine: SyncEngine(git: git))
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/Notes")

        await coordinator.enqueue(profile: profile, trigger: .manual)
        await coordinator.enqueue(profile: profile, trigger: .manual)
        await coordinator.waitUntilIdle(profileID: profile.id)

        let maximum = await git.maximumConcurrentValidations
        XCTAssertEqual(maximum, 1)
    }
}

private actor DelayedGitClient: GitClient {
    private let delay: Duration
    private(set) var validationCount = 0
    private(set) var maximumConcurrentValidations = 0
    private var concurrentValidations = 0

    init(delay: Duration) {
        self.delay = delay
    }

    func validateRepository(_ profile: SyncProfile) async throws -> RepositoryInfo {
        validationCount += 1
        concurrentValidations += 1
        maximumConcurrentValidations = max(maximumConcurrentValidations, concurrentValidations)
        try await Task.sleep(for: delay)
        concurrentValidations -= 1
        return RepositoryInfo(rootPath: profile.localPath, currentBranch: "main", remoteURL: "local")
    }

    func workingTreeStatus(at path: String) async throws -> GitWorkingTreeStatus {
        GitWorkingTreeStatus(hasChanges: false)
    }

    func currentRevision(at path: String) async throws -> String { "revision" }

    func checkRemoteAccess(at path: String, remote: String) async throws { }

    func stageAll(at path: String) async throws { }
    func commit(at path: String, message: String) async throws { }
    func fetchRemote(
        at path: String,
        remote: String,
        branch: String
    ) async throws -> GitRemoteSnapshot {
        GitRemoteSnapshot(revision: "remote")
    }

    func divergence(
        at path: String,
        remoteRevision: String
    ) async throws -> RepositoryDivergence {
        RepositoryDivergence(localCommitCount: 0, remoteCommitCount: 0)
    }

    func integrateFetchedRemote(
        at path: String,
        remoteRevision: String,
        strategy: SyncIntegrationStrategy
    ) async throws { }
    func push(at path: String, remote: String, branch: String) async throws { }
}
