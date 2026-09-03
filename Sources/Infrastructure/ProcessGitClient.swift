import Foundation
import Darwin

struct ProcessGitClient: GitClient, Sendable {
    private let gitExecutable: String
    private let timeout: TimeInterval

    init(gitExecutable: String? = nil, timeout: TimeInterval = 120) {
        self.gitExecutable = gitExecutable ?? Self.discoverGitExecutable()
        self.timeout = timeout
    }

    func validateRepository(_ profile: SyncProfile) async throws -> RepositoryInfo {
        guard FileManager.default.isExecutableFile(atPath: gitExecutable) else {
            throw SyncFailure.gitUnavailable(
                L10n.format("error.gitUnavailable", table: .errors, gitExecutable)
            )
        }

        let root: String
        do {
            root = try await run(arguments: ["-C", profile.localPath, "rev-parse", "--show-toplevel"])
                .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncFailure.invalidRepository(
                L10n.string("error.invalidRepository", table: .errors)
            )
        }

        let gitDirectory = try await run(
            arguments: ["-C", root, "rev-parse", "--absolute-git-dir"]
        ).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.hasOperationInProgress(gitDirectory: gitDirectory) {
            throw SyncFailure.conflict(
                L10n.string("error.operationInProgress", table: .errors)
            )
        }

        let branch: String
        do {
            branch = try await run(arguments: ["-C", root, "symbolic-ref", "--short", "HEAD"])
                .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncFailure.detachedHead
        }

        let remoteURL: String
        do {
            remoteURL = try await run(arguments: ["-C", root, "remote", "get-url", profile.remoteName])
                .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncFailure.remoteMissing(
                L10n.format("error.remoteMissing", table: .errors, profile.remoteName)
            )
        }

        return RepositoryInfo(
            rootPath: root,
            currentBranch: branch,
            remoteURL: remoteURL,
            gitDirectory: gitDirectory
        )
    }

    func workingTreeStatus(at path: String) async throws -> GitWorkingTreeStatus {
        let result = try await run(arguments: ["-C", path, "status", "--porcelain=v2", "-z"])
        let records = result.standardOutput.split(separator: "\0", omittingEmptySubsequences: true)
        let hasUnmergedPaths = records.contains(where: { $0.hasPrefix("u ") })
        let gitDirectory = try await run(
            arguments: ["-C", path, "rev-parse", "--absolute-git-dir"]
        ).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOperationInProgress = Self.hasOperationInProgress(gitDirectory: gitDirectory)
        return GitWorkingTreeStatus(
            hasChanges: !records.isEmpty,
            hasUnmergedPaths: hasUnmergedPaths,
            hasOperationInProgress: hasOperationInProgress
        )
    }

    func currentRevision(at path: String) async throws -> String {
        try await run(arguments: ["-C", path, "rev-parse", "--verify", "HEAD"])
            .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func synchronizationState(
        at path: String,
        remote: String,
        branch: String
    ) async throws -> RepositorySynchronizationState {
        let status = try await workingTreeStatus(at: path)
        if status.hasChanges || status.hasUnmergedPaths || status.hasOperationInProgress {
            return .outOfSync
        }

        let localHead = try await run(
            arguments: ["-C", path, "rev-parse", "HEAD"]
        ).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        let remoteOutput = try await run(
            arguments: ["-C", path, "ls-remote", "--heads", remote, "refs/heads/\(branch)"]
        ).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remoteHead = remoteOutput.split(whereSeparator: { $0.isWhitespace }).first else {
            return .outOfSync
        }
        return localHead == String(remoteHead) ? .upToDate : .outOfSync
    }

    func checkRemoteAccess(at path: String, remote: String) async throws {
        _ = try await run(
            arguments: ["-C", path, "ls-remote", "--heads", remote],
            step: .validation
        )
    }

    func stageAll(at path: String) async throws {
        _ = try await run(arguments: ["-C", path, "add", "--all"], step: .staging)
    }

    func commitIdentity(at path: String) async throws -> GitCommitIdentity {
        async let name = configuredValue("user.name", at: path)
        async let email = configuredValue("user.email", at: path)
        return try await GitCommitIdentity(name: name, email: email)
    }

    func commit(at path: String, message: String) async throws {
        _ = try await run(arguments: ["-C", path, "commit", "-m", message], step: .committing)
    }

    func commit(
        at path: String,
        message: String,
        identity: GitCommitIdentity
    ) async throws {
        guard let name = identity.name, let email = identity.email else {
            throw SyncFailure.configuration(
                L10n.string("error.commitIdentityMissing", table: .errors)
            )
        }
        _ = try await run(
            arguments: [
                "-c", "user.name=\(name)",
                "-c", "user.email=\(email)",
                "-C", path,
                "commit", "-m", message
            ],
            step: .committing
        )
    }

    func integrateRemote(
        at path: String,
        remote: String,
        branch: String,
        strategy: SyncIntegrationStrategy
    ) async throws {
        let strategyArguments: [String]
        switch strategy {
        case .rebase:
            strategyArguments = ["--rebase"]
        case .merge:
            strategyArguments = ["--no-rebase", "--no-edit"]
        }
        _ = try await run(
            arguments: ["-C", path, "pull"] + strategyArguments + [remote, branch],
            step: .pulling
        )
    }

    func push(at path: String, remote: String, branch: String) async throws {
        _ = try await run(
            arguments: ["-C", path, "push", remote, "HEAD:\(branch)"],
            step: .pushing
        )
    }

    private func configuredValue(_ key: String, at path: String) async throws -> String? {
        let result: CommandResult
        do {
            result = try await run(arguments: ["-C", path, "config", "--get", key])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        let value = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func run(arguments: [String], step: SyncStep = .validation) async throws -> CommandResult {
        let executable = gitExecutable
        let commandTimeout = timeout
        let result: CommandResult

        let worker = Task.detached(priority: .utility) {
            try Self.runSynchronously(
                executable: executable,
                arguments: arguments,
                timeout: commandTimeout,
                isCancelled: { Task<Never, Never>.isCancelled }
            )
        }

        do {
            result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as SyncFailure {
            throw failure
        } catch {
            throw SyncFailure.commandFailed(step: step, message: error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            throw classifyFailure(result: result, step: step)
        }
        return result
    }

    private func classifyFailure(result: CommandResult, step: SyncStep) -> SyncFailure {
        let combinedOutput = [result.standardError, result.standardOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let message = Self.sanitized(combinedOutput)
        let lowercased = message.lowercased()

        if lowercased.contains("authentication failed") ||
            lowercased.contains("permission denied") ||
            lowercased.contains("could not read username") ||
            lowercased.contains("repository not found") {
            return .authentication(message)
        }
        if lowercased.contains("conflict") ||
            lowercased.contains("could not apply") ||
            lowercased.contains("resolve all conflicts manually") {
            return .conflict(message)
        }
        if lowercased.contains("could not resolve host") ||
            lowercased.contains("network is unreachable") ||
            lowercased.contains("connection timed out") ||
            lowercased.contains("connection refused") {
            return .network(message)
        }
        return .commandFailed(step: step, message: message)
    }

    private static func runSynchronously(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        isCancelled: @Sendable () -> Bool
    ) throws -> CommandResult {
        if isCancelled() {
            throw CancellationError()
        }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FloderSync-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment

        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while process.isRunning {
            if isCancelled() {
                stop(process)
                throw CancellationError()
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                stop(process)
                throw SyncFailure.timedOut
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()

        let standardOutput = String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
        let standardError = String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }

        process.terminate()
        waitForExit(process, timeout: 0.25)

        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            waitForExit(process, timeout: 1)
        }
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private static func discoverGitExecutable() -> String {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? "/usr/bin/git"
    }

    private static func hasOperationInProgress(gitDirectory: String) -> Bool {
        let operationMarkers = [
            "rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD"
        ]
        return operationMarkers.contains { marker in
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: gitDirectory).appendingPathComponent(marker).path
            )
        }
    }

    private static func sanitized(_ message: String) -> String {
        var result = message
        let pattern = #"(https?://)[^/@\s]+@"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1***@"
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CommandResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}
