import Foundation
import XCTest
@testable import obsSync

final class ProcessGitClientIntegrationTests: XCTestCase {
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
            .synchronize(profile: profile, trigger: .fileChanges)
        XCTAssertEqual(retry.result, .needsUserAction)
        XCTAssertEqual(retry.failureCategory, .conflict)
        XCTAssertTrue(retry.steps.isEmpty, "A conflicted repository must stop before any write step.")
    }
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
            .appendingPathComponent("obsSync Git ✓ \(UUID().uuidString)", isDirectory: true)
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
        _ = try git(["-C", repositoryURL.path, "config", "user.name", "obsSync Tests"])
        _ = try git(["-C", repositoryURL.path, "config", "user.email", "tests@obssync.dev"])
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
