import Foundation

struct CommitRevisionState: Equatable, Sendable {
    private(set) var baseline: String?
    private(set) var isSynchronizationActive = false

    init(baseline: String? = nil) {
        self.baseline = baseline
    }

    mutating func beginSynchronization() {
        isSynchronizationActive = true
    }

    mutating func endSynchronization(currentRevision: String?) {
        baseline = currentRevision
        isSynchronizationActive = false
    }

    mutating func observe(_ revision: String) -> Bool {
        guard !isSynchronizationActive else { return false }
        defer { baseline = revision }
        guard let baseline else { return false }
        return baseline != revision
    }
}

struct CommitEventFilter {
    static func hasPotentialRevisionChange(paths: [String], gitDirectory: String) -> Bool {
        let normalizedGitDirectory = URL(fileURLWithPath: gitDirectory).standardizedFileURL.path
        let exactPaths = [
            normalizedGitDirectory,
            normalizedGitDirectory + "/HEAD",
            normalizedGitDirectory + "/logs/HEAD"
        ]
        let directoryPrefixes = [
            normalizedGitDirectory + "/refs/heads/",
            normalizedGitDirectory + "/logs/refs/heads/"
        ]

        return paths.contains { rawPath in
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            return exactPaths.contains(path) || directoryPrefixes.contains(where: path.hasPrefix)
        }
    }
}

actor CommitChangeScheduler {
    typealias TriggerHandler = @Sendable (SyncProfile, SyncTrigger) async -> Void

    private let git: any GitClient
    private var watchers: [UUID: FSEventsDirectoryWatcher] = [:]
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private var states: [UUID: CommitRevisionState] = [:]
    private var triggerHandler: TriggerHandler?

    init(git: any GitClient) {
        self.git = git
    }

    deinit {
        debounceTasks.values.forEach { $0.cancel() }
        watchers.values.forEach { $0.stop() }
    }

    func configure(
        profiles: [SyncProfile],
        synchronizingProfileIDs: Set<UUID> = [],
        onTrigger: @escaping TriggerHandler
    ) async -> [UUID: String] {
        debounceTasks.values.forEach { $0.cancel() }
        debounceTasks.removeAll()
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
        states.removeAll()
        triggerHandler = onTrigger

        var failures: [UUID: String] = [:]
        for profile in profiles where profile.isEnabled && profile.watchesNewCommits {
            do {
                let repository = try await git.validateRepository(profile)
                let revision = try await git.currentRevision(at: repository.rootPath)
                let watcher = FSEventsDirectoryWatcher(path: repository.gitDirectory) { [weak self] paths in
                    Task {
                        await self?.receive(
                            paths: paths,
                            profile: profile,
                            gitDirectory: repository.gitDirectory
                        )
                    }
                }
                var state = CommitRevisionState(baseline: revision)
                if synchronizingProfileIDs.contains(profile.id) {
                    state.beginSynchronization()
                }
                states[profile.id] = state
                try watcher.start()
                watchers[profile.id] = watcher
            } catch {
                states[profile.id] = nil
                failures[profile.id] = (error as? SyncFailure)?.displayMessage
                    ?? error.localizedDescription
            }
        }
        return failures
    }

    func beginSynchronization(profileID: UUID) {
        debounceTasks[profileID]?.cancel()
        debounceTasks[profileID] = nil
        states[profileID]?.beginSynchronization()
    }

    func endSynchronization(profile: SyncProfile) async {
        guard states[profile.id] != nil else { return }
        let revision = try? await git.currentRevision(at: profile.localPath)
        states[profile.id]?.endSynchronization(currentRevision: revision)
    }

    private func receive(paths: [String], profile: SyncProfile, gitDirectory: String) {
        guard states[profile.id]?.isSynchronizationActive == false,
              CommitEventFilter.hasPotentialRevisionChange(
                paths: paths,
                gitDirectory: gitDirectory
              ) else {
            return
        }

        debounceTasks[profile.id]?.cancel()
        debounceTasks[profile.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                await self?.detectRevisionChange(for: profile)
            } catch {
                return
            }
        }
    }

    private func detectRevisionChange(for profile: SyncProfile) async {
        guard states[profile.id]?.isSynchronizationActive == false,
              let revision = try? await git.currentRevision(at: profile.localPath),
              states[profile.id]?.observe(revision) == true else {
            return
        }
        await triggerHandler?(profile, .newCommit)
    }
}
