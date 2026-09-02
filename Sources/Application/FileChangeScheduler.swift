import Foundation

struct FileEventFilter {
    static func hasRelevantChange(paths: [String], repositoryRoot: String) -> Bool {
        let normalizedRoot = URL(fileURLWithPath: repositoryRoot).standardizedFileURL.path
        let gitDirectory = normalizedRoot + "/.git"
        return paths.contains { rawPath in
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            return path != gitDirectory && !path.hasPrefix(gitDirectory + "/")
        }
    }
}

actor FileChangeScheduler {
    typealias TriggerHandler = @Sendable (SyncProfile, SyncTrigger) async -> Void

    private var watchers: [UUID: FSEventsDirectoryWatcher] = [:]
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private var triggerHandler: TriggerHandler?

    deinit {
        debounceTasks.values.forEach { $0.cancel() }
        watchers.values.forEach { $0.stop() }
    }

    func configure(
        profiles: [SyncProfile],
        onTrigger: @escaping TriggerHandler
    ) -> [UUID: String] {
        debounceTasks.values.forEach { $0.cancel() }
        debounceTasks.removeAll()
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
        triggerHandler = onTrigger

        var failures: [UUID: String] = [:]
        for profile in profiles where profile.isEnabled && profile.watchesFileChanges {
            let watcher = FSEventsDirectoryWatcher(path: profile.localPath) { [weak self] paths in
                Task { await self?.receive(paths: paths, for: profile) }
            }
            do {
                try watcher.start()
                watchers[profile.id] = watcher
            } catch {
                failures[profile.id] = error.localizedDescription
            }
        }
        return failures
    }

    private func receive(paths: [String], for profile: SyncProfile) {
        guard FileEventFilter.hasRelevantChange(paths: paths, repositoryRoot: profile.localPath) else {
            return
        }
        debounceTasks[profile.id]?.cancel()
        let handler = triggerHandler
        debounceTasks[profile.id] = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                try Task.checkCancellation()
                await handler?(profile, .fileChanges)
            } catch {
                return
            }
        }
    }
}
