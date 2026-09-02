import XCTest
@testable import obsSync

final class SyncEngineTests: XCTestCase {
    func testLocalChangesAreCommittedBeforePullAndPush() async throws {
        let git = FakeGitClient(hasChanges: true)
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .manual)
        let calls = await git.calls

        XCTAssertEqual(record.result, .succeeded)
        XCTAssertTrue(record.hadLocalChanges)
        XCTAssertEqual(calls, ["validate", "status", "stage", "commit", "pull:rebase", "push"])
        XCTAssertEqual(record.steps.map(\.step), SyncStep.allCases)
    }

    func testCleanTreeSkipsStageAndCommit() async throws {
        let git = FakeGitClient(hasChanges: false)
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .scheduled)
        let calls = await git.calls

        XCTAssertEqual(record.result, .succeeded)
        XCTAssertFalse(record.hadLocalChanges)
        XCTAssertEqual(calls, ["validate", "status", "pull:rebase", "push"])
        XCTAssertEqual(record.steps.map(\.step), [.validation, .status, .pulling, .pushing])
    }

    func testMergeStrategyIsForwardedAndRecorded() async throws {
        let git = FakeGitClient(hasChanges: false)
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/notes",
            integrationStrategy: .merge
        )

        let record = await engine.synchronize(
            profile: profile,
            trigger: .interval,
            automationRuleName: "Rule 1"
        )
        let calls = await git.calls

        XCTAssertEqual(calls, ["validate", "status", "pull:merge", "push"])
        XCTAssertEqual(record.integrationStrategy, .merge)
        XCTAssertEqual(record.automationRuleName, "Rule 1")
    }

    func testConflictStopsBeforePushAndRequiresUserAction() async throws {
        let git = FakeGitClient(hasChanges: true, pullFailure: .conflict("CONFLICT in Notes.md"))
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .fileChanges)
        let calls = await git.calls

        XCTAssertEqual(record.result, .needsUserAction)
        XCTAssertEqual(record.failureCategory, .conflict)
        XCTAssertEqual(calls, ["validate", "status", "stage", "commit", "pull:rebase"])
        XCTAssertFalse(calls.contains("push"))
    }

    func testFileChangeTriggerWithCleanTreeAvoidsNetworkOperations() async throws {
        let git = FakeGitClient(hasChanges: false)
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .fileChanges)
        let calls = await git.calls

        XCTAssertEqual(record.result, .succeeded)
        XCTAssertEqual(calls, ["validate", "status"])
    }

    func testExistingConflictStopsBeforeStaging() async throws {
        let git = FakeGitClient(
            hasChanges: true,
            status: GitWorkingTreeStatus(
                hasChanges: true,
                hasUnmergedPaths: true,
                hasOperationInProgress: true
            )
        )
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .fileChanges)
        let calls = await git.calls

        XCTAssertEqual(record.result, .needsUserAction)
        XCTAssertEqual(record.failureCategory, .conflict)
        XCTAssertEqual(calls, ["validate", "status"])
    }

    func testDailyTimeRejectsInvalidValues() {
        XCTAssertThrowsError(try DailyTime(hour: 24, minute: 0))
        XCTAssertThrowsError(try DailyTime(hour: 12, minute: 60))
        XCTAssertNoThrow(try DailyTime(hour: 23, minute: 59))
    }
}

private actor FakeGitClient: GitClient {
    private(set) var calls: [String] = []
    private let hasChanges: Bool
    private let status: GitWorkingTreeStatus?
    private let pullFailure: SyncFailure?

    init(
        hasChanges: Bool,
        pullFailure: SyncFailure? = nil,
        status: GitWorkingTreeStatus? = nil
    ) {
        self.hasChanges = hasChanges
        self.pullFailure = pullFailure
        self.status = status
    }

    func validateRepository(_ profile: SyncProfile) async throws -> RepositoryInfo {
        calls.append("validate")
        return RepositoryInfo(rootPath: profile.localPath, currentBranch: "main", remoteURL: "local")
    }

    func workingTreeStatus(at path: String) async throws -> GitWorkingTreeStatus {
        calls.append("status")
        return status ?? GitWorkingTreeStatus(hasChanges: hasChanges)
    }

    func checkRemoteAccess(at path: String, remote: String) async throws { }

    func stageAll(at path: String) async throws {
        calls.append("stage")
    }

    func commit(at path: String, message: String) async throws {
        calls.append("commit")
    }

    func integrateRemote(
        at path: String,
        remote: String,
        branch: String,
        strategy: SyncIntegrationStrategy
    ) async throws {
        calls.append("pull:\(strategy.rawValue)")
        if let pullFailure { throw pullFailure }
    }

    func push(at path: String, remote: String, branch: String) async throws {
        calls.append("push")
    }
}
