import Foundation

actor JSONProfileStore: ProfileStore {
    private struct StoredConfiguration: Codable {
        let schemaVersion: Int
        let profiles: [SyncProfile]
    }

    private let fileURL: URL
    private let backupURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.backupURL = fileURL.appendingPathExtension("backup")
        self.fileManager = fileManager
    }

    static func live() -> JSONProfileStore {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = applicationSupport.appendingPathComponent("dev.obssync.app", isDirectory: true)
        return JSONProfileStore(fileURL: directory.appendingPathComponent("configuration.json"))
    }

    func loadProfiles() async throws -> [SyncProfile] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            return try decodeConfiguration(at: fileURL).profiles
        } catch {
            guard fileManager.fileExists(atPath: backupURL.path) else { throw error }
            return try decodeConfiguration(at: backupURL).profiles
        }
    }

    func saveProfiles(_ profiles: [SyncProfile]) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: fileURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }

        let configuration = StoredConfiguration(schemaVersion: 1, profiles: profiles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }

    private func decodeConfiguration(at url: URL) throws -> StoredConfiguration {
        let data = try Data(contentsOf: url)
        let configuration = try JSONDecoder().decode(StoredConfiguration.self, from: data)
        guard configuration.schemaVersion == 1 else {
            throw ProfileStoreError.unsupportedSchema(configuration.schemaVersion)
        }
        return configuration
    }
}

enum ProfileStoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            L10n.format("error.unsupportedSchema", table: .errors, version)
        }
    }
}
