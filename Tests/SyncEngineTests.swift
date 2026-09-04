import XCTest
@testable import floderSync

final class SyncEngineTests: XCTestCase {
    func testLocalChangesAreCommittedBeforeRemoteIntegrationAndPush() async throws {
        let git = FakeGitClient(hasChanges: true)
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .manual)
        let calls = await git.calls

        XCTAssertEqual(record.result, .succeeded)
        XCTAssertTrue(record.hadLocalChanges)
        XCTAssertEqual(
            calls,
            ["validate", "status", "fetch", "stage", "commit", "divergence", "integrate:rebase", "push"]
        )
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
        XCTAssertEqual(calls, ["validate", "status", "fetch", "divergence", "integrate:rebase", "push"])
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

        XCTAssertEqual(calls, ["validate", "status", "fetch", "divergence", "integrate:merge", "push"])
        XCTAssertEqual(record.integrationStrategy, .merge)
        XCTAssertEqual(record.automationRuleName, "Rule 1")
    }

    func testConflictStopsBeforePushAndRequiresUserAction() async throws {
        let git = FakeGitClient(
            hasChanges: true,
            integrationFailure: .conflict("CONFLICT in Notes.md")
        )
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .newCommit)
        let calls = await git.calls

        XCTAssertEqual(record.result, .needsUserAction)
        XCTAssertEqual(record.failureCategory, .conflict)
        XCTAssertEqual(
            calls,
            ["validate", "status", "fetch", "stage", "commit", "divergence", "integrate:rebase"]
        )
        XCTAssertFalse(calls.contains("push"))
    }

    func testNewCommitTriggerWithCleanTreeIntegratesAndPushes() async throws {
        let git = FakeGitClient(hasChanges: false)
        let engine = SyncEngine(git: git)
        let profile = SyncProfile(name: "Notes", localPath: "/tmp/notes")

        let record = await engine.synchronize(profile: profile, trigger: .newCommit)
        let calls = await git.calls

        XCTAssertEqual(record.result, .succeeded)
        XCTAssertEqual(calls, ["validate", "status", "fetch", "divergence", "integrate:rebase", "push"])
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

        let record = await engine.synchronize(profile: profile, trigger: .newCommit)
        let calls = await git.calls

        XCTAssertEqual(record.result, .needsUserAction)
        XCTAssertEqual(record.failureCategory, .conflict)
        XCTAssertEqual(calls, ["validate", "status"])
    }

    func testAutomaticCommitUsesConfiguredIdentityAndDynamicMessage() async throws {
        let git = FakeGitClient(
            hasChanges: true,
            commitIdentity: GitCommitIdentity(name: "Global User", email: "global@example.com")
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/notes",
            automaticCommit: AutomaticCommitConfiguration(
                authorName: "Repository User",
                messageTemplate: "Sync ${user} <${email}> at ${time}"
            )
        )

        let record = await SyncEngine(git: git).synchronize(
            profile: profile,
            trigger: .scheduled,
            now: { date }
        )

        XCTAssertEqual(record.result, .succeeded)
        let committedIdentity = await git.committedIdentity
        let committedMessage = await git.committedMessage
        XCTAssertEqual(
            committedIdentity,
            GitCommitIdentity(name: "Repository User", email: "global@example.com")
        )
        XCTAssertEqual(
            committedMessage,
            "Sync Repository User <global@example.com> at \(date.formatted(.iso8601))"
        )
    }

    func testDirtyTreeStopsBeforeWritesWhenAutomaticCommitIsDisabled() async throws {
        let git = FakeGitClient(hasChanges: true)
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/notes",
            automaticCommit: AutomaticCommitConfiguration(isEnabled: false)
        )

        let record = await SyncEngine(git: git).synchronize(
            profile: profile,
            trigger: .interval
        )

        XCTAssertEqual(record.result, .needsUserAction)
        XCTAssertEqual(record.failureCategory, .configuration)
        let calls = await git.calls
        XCTAssertEqual(calls, ["validate", "status"])
    }

    func testFetchRetriesTransientNetworkFailures() async throws {
        let git = FakeGitClient(
            hasChanges: false,
            fetchFailures: [.network("offline"), .network("offline")]
        )
        let engine = SyncEngine(
            git: git,
            retryPolicy: SyncRetryPolicy(
                networkAttemptLimit: 3,
                pushRaceRetryLimit: 0,
                retryDelayNanoseconds: 0
            ),
            sleep: { _ in }
        )

        let record = await engine.synchronize(
            profile: SyncProfile(name: "Notes", localPath: "/tmp/notes"),
            trigger: .scheduled
        )

        XCTAssertEqual(record.result, .succeeded)
        let calls = await git.calls
        XCTAssertEqual(calls.filter { $0 == "fetch" }.count, 3)
    }

    func testPushNonFastForwardRefetchesAndIntegratesBeforeRetrying() async throws {
        let git = FakeGitClient(
            hasChanges: false,
            divergences: [
                RepositoryDivergence(localCommitCount: 0, remoteCommitCount: 0),
                RepositoryDivergence(localCommitCount: 1, remoteCommitCount: 1)
            ],
            pushFailures: [.nonFastForward("fetch first")]
        )
        let engine = SyncEngine(
            git: git,
            retryPolicy: SyncRetryPolicy(
                networkAttemptLimit: 1,
                pushRaceRetryLimit: 1,
                retryDelayNanoseconds: 0
            ),
            sleep: { _ in }
        )

        let record = await engine.synchronize(
            profile: SyncProfile(name: "Notes", localPath: "/tmp/notes"),
            trigger: .scheduled
        )

        XCTAssertEqual(record.result, .succeeded, record.failureMessage ?? "")
        let calls = await git.calls
        XCTAssertEqual(
            calls,
            ["validate", "status", "fetch", "divergence", "push", "fetch", "divergence", "integrate:rebase", "push"]
        )
    }

    func testPushRetriesTransientNetworkFailures() async throws {
        let git = FakeGitClient(
            hasChanges: false,
            divergences: [RepositoryDivergence(localCommitCount: 0, remoteCommitCount: 0)],
            pushFailures: [.network("offline"), .network("offline")]
        )
        let engine = SyncEngine(
            git: git,
            retryPolicy: SyncRetryPolicy(
                networkAttemptLimit: 3,
                pushRaceRetryLimit: 0,
                retryDelayNanoseconds: 0
            ),
            sleep: { _ in }
        )

        let record = await engine.synchronize(
            profile: SyncProfile(name: "Notes", localPath: "/tmp/notes"),
            trigger: .scheduled
        )

        XCTAssertEqual(record.result, .succeeded)
        let calls = await git.calls
        XCTAssertEqual(calls.filter { $0 == "push" }.count, 3)
    }

    func testNonFastForwardStopsAfterRetryLimitWithoutForcePush() async throws {
        let git = FakeGitClient(
            hasChanges: false,
            divergences: [RepositoryDivergence(localCommitCount: 0, remoteCommitCount: 0)],
            pushFailures: [
                .nonFastForward("fetch first"),
                .nonFastForward("fetch first")
            ]
        )
        let engine = SyncEngine(
            git: git,
            retryPolicy: SyncRetryPolicy(
                networkAttemptLimit: 1,
                pushRaceRetryLimit: 1,
                retryDelayNanoseconds: 0
            ),
            sleep: { _ in }
        )

        let record = await engine.synchronize(
            profile: SyncProfile(name: "Notes", localPath: "/tmp/notes"),
            trigger: .scheduled
        )

        XCTAssertEqual(record.result, .needsUserAction)
        XCTAssertEqual(record.failureCategory, .nonFastForward)
        let calls = await git.calls
        XCTAssertEqual(calls.filter { $0 == "fetch" }.count, 2)
        XCTAssertEqual(calls.filter { $0 == "push" }.count, 2)
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
    private var fetchFailures: [SyncFailure]
    private var divergences: [RepositoryDivergence]
    private let integrationFailure: SyncFailure?
    private var pushFailures: [SyncFailure]
    private let availableCommitIdentity: GitCommitIdentity
    private(set) var committedIdentity: GitCommitIdentity?
    private(set) var committedMessage: String?

    init(
        hasChanges: Bool,
        fetchFailures: [SyncFailure] = [],
        divergences: [RepositoryDivergence] = [
            RepositoryDivergence(localCommitCount: 1, remoteCommitCount: 1)
        ],
        integrationFailure: SyncFailure? = nil,
        pushFailures: [SyncFailure] = [],
        status: GitWorkingTreeStatus? = nil,
        commitIdentity: GitCommitIdentity = GitCommitIdentity(
            name: "Test User",
            email: "test@example.com"
        )
    ) {
        self.hasChanges = hasChanges
        self.fetchFailures = fetchFailures
        self.divergences = divergences
        self.integrationFailure = integrationFailure
        self.pushFailures = pushFailures
        self.status = status
        self.availableCommitIdentity = commitIdentity
    }

    func validateRepository(_ profile: SyncProfile) async throws -> RepositoryInfo {
        calls.append("validate")
        return RepositoryInfo(rootPath: profile.localPath, currentBranch: "main", remoteURL: "local")
    }

    func workingTreeStatus(at path: String) async throws -> GitWorkingTreeStatus {
        calls.append("status")
        return status ?? GitWorkingTreeStatus(hasChanges: hasChanges)
    }

    func currentRevision(at path: String) async throws -> String { "revision" }

    func checkRemoteAccess(at path: String, remote: String) async throws { }

    func commitIdentity(at path: String) async throws -> GitCommitIdentity {
        availableCommitIdentity
    }

    func stageAll(at path: String) async throws {
        calls.append("stage")
    }

    func commit(at path: String, message: String) async throws {
        calls.append("commit")
    }

    func commit(
        at path: String,
        message: String,
        identity: GitCommitIdentity
    ) async throws {
        committedMessage = message
        committedIdentity = identity
        calls.append("commit")
    }

    func fetchRemote(
        at path: String,
        remote: String,
        branch: String
    ) async throws -> GitRemoteSnapshot {
        calls.append("fetch")
        if !fetchFailures.isEmpty {
            throw fetchFailures.removeFirst()
        }
        return GitRemoteSnapshot(revision: "remote-\(calls.count)")
    }

    func divergence(
        at path: String,
        remoteRevision: String
    ) async throws -> RepositoryDivergence {
        calls.append("divergence")
        if divergences.count > 1 {
            return divergences.removeFirst()
        }
        return divergences[0]
    }

    func integrateFetchedRemote(
        at path: String,
        remoteRevision: String,
        strategy: SyncIntegrationStrategy
    ) async throws {
        calls.append("integrate:\(strategy.rawValue)")
        if let integrationFailure { throw integrationFailure }
    }

    func push(at path: String, remote: String, branch: String) async throws {
        calls.append("push")
        if !pushFailures.isEmpty {
            throw pushFailures.removeFirst()
        }
    }
}
