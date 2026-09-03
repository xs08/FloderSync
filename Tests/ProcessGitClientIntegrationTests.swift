import Foundation
import Darwin
import XCTest
@testable import floderSync

final class ProcessGitClientIntegrationTests: XCTestCase {
    func testCurrentRevisionReturnsRepositoryHead() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()

        let revision = try await ProcessGitClient(timeout: 10)
            .currentRevision(at: fixture.workURL.path)

        XCTAssertEqual(
            revision,
            try fixture.git(["-C", fixture.workURL.path, "rev-parse", "HEAD"])
        )
    }

    func testSynchronizationStateDetectsCleanMatchingRepository() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()

        let state = try await ProcessGitClient(timeout: 10).synchronizationState(
            at: fixture.workURL.path,
            remote: "origin",
            branch: "main"
        )

        XCTAssertEqual(state, .upToDate)
    }

    func testSynchronizationStateDetectsDirtyWorkingTree() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()
        try fixture.write("local update\n", to: fixture.workURL.appendingPathComponent("Notes.md"))

        let state = try await ProcessGitClient(timeout: 10).synchronizationState(
            at: fixture.workURL.path,
            remote: "origin",
            branch: "main"
        )

        XCTAssertEqual(state, .outOfSync)
    }

    func testSynchronizationStateDetectsRemoteCommit() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()
        try fixture.pushRemoteChange("remote update\n")

        let state = try await ProcessGitClient(timeout: 10).synchronizationState(
            at: fixture.workURL.path,
            remote: "origin",
            branch: "main"
        )

        XCTAssertEqual(state, .outOfSync)
    }

    func testValidationRejectsNonGitFolder() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let profile = SyncProfile(name: "Not Git", localPath: fixture.rootURL.path)

        do {
            _ = try await ProcessGitClient(timeout: 10).validateRepository(profile)
            XCTFail("A non-Git folder must be rejected.")
        } catch let failure as SyncFailure {
            guard case .invalidRepository = failure else {
                return XCTFail("Expected invalidRepository, got \(failure)")
            }
        }
    }

    func testLocalChangeIsCommittedAndPushedToBareRemote() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()
        try fixture.write("local update\n", to: fixture.workURL.appendingPathComponent("Notes.md"))

        let profile = SyncProfile(name: "Notes", localPath: fixture.workURL.path)
        let record = await SyncEngine(git: ProcessGitClient(timeout: 10))
            .synchronize(profile: profile, trigger: .manual)

        XCTAssertEqual(record.result, .succeeded, record.failureMessage ?? "")
        XCTAssertTrue(record.hadLocalChanges)
        XCTAssertEqual(try fixture.git(["-C", fixture.workURL.path, "status", "--porcelain"]), "")
        let localHead = try fixture.git(["-C", fixture.workURL.path, "rev-parse", "HEAD"])
        let remoteHead = try fixture.git([
            "--git-dir", fixture.remoteURL.path, "rev-parse", "refs/heads/main"
        ])
        XCTAssertEqual(localHead, remoteHead)
    }

    func testCommitUsesConfiguredIdentityWithoutChangingRepositoryConfiguration() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()
        try fixture.write("identity update\n", to: fixture.workURL.appendingPathComponent("Notes.md"))
        let client = ProcessGitClient(timeout: 10)

        try await client.stageAll(at: fixture.workURL.path)
        try await client.commit(
            at: fixture.workURL.path,
            message: "Configured message",
            identity: GitCommitIdentity(name: "Floder User", email: "floder@example.com")
        )

        let metadata = try fixture.git([
            "-C", fixture.workURL.path, "log", "-1", "--format=%an%n%ae%n%s"
        ]).split(separator: "\n").map(String.init)
        XCTAssertEqual(metadata, ["Floder User", "floder@example.com", "Configured message"])
        XCTAssertEqual(
            try fixture.git(["-C", fixture.workURL.path, "config", "user.name"]),
            "floderSync Tests"
        )
        XCTAssertEqual(
            try fixture.git(["-C", fixture.workURL.path, "config", "user.email"]),
            "tests@flodersync.dev"
        )
    }

    func testCommitIdentityReadsEffectiveGitConfiguration() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()

        let identity = try await ProcessGitClient(timeout: 10)
            .commitIdentity(at: fixture.workURL.path)

        XCTAssertEqual(
            identity,
            GitCommitIdentity(name: "floderSync Tests", email: "tests@flodersync.dev")
        )
    }

    func testRemoteChangeIsPulledIntoCleanWorkingTree() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()
        try fixture.pushRemoteChange("remote update\n")

        let profile = SyncProfile(name: "Notes", localPath: fixture.workURL.path)
        let record = await SyncEngine(git: ProcessGitClient(timeout: 10))
            .synchronize(profile: profile, trigger: .scheduled)

        XCTAssertEqual(record.result, .succeeded, record.failureMessage ?? "")
        let contents = try String(
            contentsOf: fixture.workURL.appendingPathComponent("Notes.md"),
            encoding: .utf8
        )
        XCTAssertEqual(contents, "remote update\n")
    }

    func testMergeStrategyCreatesMergeCommitForDivergedHistory() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()
        try fixture.pushRemoteChange("remote update\n")
        try fixture.write("local file\n", to: fixture.workURL.appendingPathComponent("Local.md"))

        let profile = SyncProfile(
            name: "Notes",
            localPath: fixture.workURL.path,
            integrationStrategy: .merge
        )
        let record = await SyncEngine(git: ProcessGitClient(timeout: 10))
            .synchronize(profile: profile, trigger: .manual)

        XCTAssertEqual(record.result, .succeeded, record.failureMessage ?? "")
        XCTAssertEqual(record.integrationStrategy, .merge)
        let parents = try fixture.git([
            "-C", fixture.workURL.path, "show", "-s", "--format=%P", "HEAD"
        ]).split(separator: " ")
        XCTAssertEqual(parents.count, 2)
    }

    func testConflictingChangesStopBeforePush() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.createInitialRepository()
        try fixture.pushRemoteChange("remote change\n")
        try fixture.write("local change\n", to: fixture.workURL.appendingPathComponent("Notes.md"))
        let remoteHeadBeforeSync = try fixture.git([
            "--git-dir", fixture.remoteURL.path, "rev-parse", "refs/heads/main"
        ])

        let profile = SyncProfile(name: "Notes", localPath: fixture.workURL.path)
        let record = await SyncEngine(git: ProcessGitClient(timeout: 10))
            .synchronize(profile: profile, trigger: .manual)

        XCTAssertEqual(record.result, .needsUserAction, record.failureMessage ?? "")
        XCTAssertEqual(record.failureCategory, .conflict)
        XCTAssertFalse(record.steps.contains(where: { $0.step == .pushing }))
        let remoteHeadAfterSync = try fixture.git([
            "--git-dir", fixture.remoteURL.path, "rev-parse", "refs/heads/main"
        ])
        XCTAssertEqual(remoteHeadAfterSync, remoteHeadBeforeSync)

        let retry = await SyncEngine(git: ProcessGitClient(timeout: 10))
            .synchronize(profile: profile, trigger: .newCommit)
        XCTAssertEqual(retry.result, .needsUserAction)
        XCTAssertEqual(retry.failureCategory, .conflict)
        XCTAssertTrue(retry.steps.isEmpty, "A conflicted repository must stop before any write step.")
    }

    func testTimeoutForceKillsCommandThatIgnoresTermination() async throws {
        let fixture = try HangingCommandFixture()
        defer { fixture.remove() }
        let client = ProcessGitClient(
            gitExecutable: fixture.executableURL.path,
            timeout: 1
        )
        let startedAt = ProcessInfo.processInfo.systemUptime

        do {
            try await client.checkRemoteAccess(at: "/", remote: "origin")
            XCTFail("A hanging command must time out.")
        } catch let failure as SyncFailure {
            XCTAssertEqual(failure, .timedOut)
        }

        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, 3)
        let pid = try await fixture.waitForPID()
        let processDidExit = await fixture.waitUntilProcessExits(pid: pid)
        XCTAssertTrue(processDidExit)
    }

    func testTaskCancellationForceKillsCommandThatIgnoresTermination() async throws {
        let fixture = try HangingCommandFixture()
        defer { fixture.remove() }
        let client = ProcessGitClient(
            gitExecutable: fixture.executableURL.path,
            timeout: 10
        )
        let task = Task {
            try await client.checkRemoteAccess(at: "/", remote: "origin")
        }
        let pid = try await fixture.waitForPID()
        let cancelledAt = ProcessInfo.processInfo.systemUptime

        task.cancel()

        do {
            try await task.value
            XCTFail("A cancelled command must throw CancellationError.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - cancelledAt, 2)
        let processDidExit = await fixture.waitUntilProcessExits(pid: pid)
        XCTAssertTrue(processDidExit)
    }
}

private final class HangingCommandFixture {
    let executableURL: URL
    private let rootURL: URL
    private let pidURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloderSync-Lifecycle-\(UUID().uuidString)", isDirectory: true)
        executableURL = rootURL.appendingPathComponent("hang.sh")
        pidURL = rootURL.appendingPathComponent("pid")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        trap '' TERM
        printf '%s' "$$" > '\(pidURL.path)'
        while :; do
            sleep 1
        done
        """
        try Data(script.utf8).write(to: executableURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func waitForPID(timeout: TimeInterval = 2) async throws -> pid_t {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let contents = try? String(contentsOf: pidURL, encoding: .utf8),
               let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HangingCommandFixtureError.pidWasNotWritten
    }

    func waitUntilProcessExits(pid: pid_t, timeout: TimeInterval = 2) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if Darwin.kill(pid, 0) == -1 && errno == ESRCH {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return Darwin.kill(pid, 0) == -1 && errno == ESRCH
    }
}

private enum HangingCommandFixtureError: Error {
    case pidWasNotWritten
}

private final class GitFixture {
    let rootURL: URL
    let workURL: URL
    let remoteURL: URL
    private let peerURL: URL
    private let gitExecutable = "/usr/bin/git"

    init() throws {
        guard FileManager.default.isExecutableFile(atPath: gitExecutable) else {
            throw XCTSkip("System Git is unavailable")
        }
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("floderSync Git ✓ \(UUID().uuidString)", isDirectory: true)
        workURL = rootURL.appendingPathComponent("Working Copy", isDirectory: true)
        remoteURL = rootURL.appendingPathComponent("Remote.git", isDirectory: true)
        peerURL = rootURL.appendingPathComponent("Remote Peer", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func createInitialRepository() throws {
        _ = try git(["init", "--bare", remoteURL.path])
        _ = try git(["init", "--initial-branch=main", workURL.path])
        try configureIdentity(at: workURL)
        try write("initial\n", to: workURL.appendingPathComponent("Notes.md"))
        _ = try git(["-C", workURL.path, "add", "--all"])
        _ = try git(["-C", workURL.path, "commit", "-m", "Initial"])
        _ = try git(["-C", workURL.path, "remote", "add", "origin", remoteURL.path])
        _ = try git(["-C", workURL.path, "push", "--set-upstream", "origin", "main"])
        _ = try git(["--git-dir", remoteURL.path, "symbolic-ref", "HEAD", "refs/heads/main"])
    }

    func pushRemoteChange(_ contents: String) throws {
        _ = try git(["clone", remoteURL.path, peerURL.path])
        try configureIdentity(at: peerURL)
        try write(contents, to: peerURL.appendingPathComponent("Notes.md"))
        _ = try git(["-C", peerURL.path, "add", "--all"])
        _ = try git(["-C", peerURL.path, "commit", "-m", "Remote change"])
        _ = try git(["-C", peerURL.path, "push", "origin", "main"])
    }

    func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: gitExecutable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitFixtureError.commandFailed(arguments: arguments, output: error + output)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func configureIdentity(at repositoryURL: URL) throws {
        _ = try git(["-C", repositoryURL.path, "config", "user.name", "floderSync Tests"])
        _ = try git(["-C", repositoryURL.path, "config", "user.email", "tests@flodersync.dev"])
    }
}

private enum GitFixtureError: LocalizedError {
    case commandFailed(arguments: [String], output: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, output):
            "git \(arguments.joined(separator: " ")) failed: \(output)"
        }
    }
}
