import Foundation

actor JSONRunHistoryStore: RunHistoryStore {
    private struct StoredHistory: Codable {
        let schemaVersion: Int
        var runs: [SyncRunRecord]
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func live() -> JSONRunHistoryStore {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = applicationSupport.appendingPathComponent("dev.obssync.app", isDirectory: true)
        return JSONRunHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
    }

    func loadRuns() async throws -> [SyncRunRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let history = try JSONDecoder().decode(StoredHistory.self, from: data)
        guard history.schemaVersion == 1 else {
            throw ProfileStoreError.unsupportedSchema(history.schemaVersion)
        }
        return history.runs
    }

    func append(_ run: SyncRunRecord, limit: Int = 100) async throws {
        var runs = (try? await loadRuns()) ?? []
        runs.removeAll(where: { $0.id == run.id })
        runs.insert(run, at: 0)
        runs = Array(runs.prefix(max(1, limit)))

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let history = StoredHistory(schemaVersion: 1, runs: runs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}
