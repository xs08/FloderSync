import Foundation

actor JSONProfileStore: ProfileStore {
    private struct StoredConfigurationV2: Codable {
        let schemaVersion: Int
        let profiles: [SyncProfile]
        let automationRules: [AutomationRule]
    }

    private struct ConfigurationHeader: Decodable {
        let schemaVersion: Int
    }

    private struct StoredConfigurationV1: Decodable {
        let profiles: [SyncProfileV1]
    }

    private struct SyncProfileV1: Decodable {
        let id: UUID
        let name: String
        let localPath: String
        let remoteName: String
        let commitMessageTemplate: String
        let policies: [SyncPolicyV1]
        let isEnabled: Bool

        func migrated() -> SyncProfile {
            SyncProfile(
                id: id,
                name: name,
                localPath: localPath,
                remoteName: remoteName,
                commitMessageTemplate: commitMessageTemplate,
                policies: policies.map(\.migrated),
                integrationStrategy: .rebase,
                isEnabled: isEnabled
            )
        }
    }

    private enum SyncPolicyV1: Decodable {
        case daily(times: [DailyTime])
        case interval(seconds: TimeInterval)
        case fileChanges

        private enum CodingKeys: String, CodingKey {
            case daily
            case interval
            case fileChanges
        }

        private struct DailyPayload: Decodable { let times: [DailyTime] }
        private struct IntervalPayload: Decodable { let seconds: TimeInterval }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.daily) {
                self = .daily(times: try container.decode(DailyPayload.self, forKey: .daily).times)
            } else if container.contains(.interval) {
                self = .interval(
                    seconds: try container.decode(IntervalPayload.self, forKey: .interval).seconds
                )
            } else if container.contains(.fileChanges) {
                self = .fileChanges
            } else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unknown sync policy")
                )
            }
        }

        var migrated: SyncPolicy {
            switch self {
            case let .daily(times): .daily(times: times)
            case let .interval(seconds): .interval(seconds: seconds)
            case .fileChanges: .fileChanges(debounceSeconds: 5)
            }
        }
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

    func loadConfiguration() async throws -> AppConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .empty }

        do {
            return try decodeConfiguration(at: fileURL)
        } catch {
            guard fileManager.fileExists(atPath: backupURL.path) else { throw error }
            return try decodeConfiguration(at: backupURL)
        }
    }

    func saveConfiguration(_ configuration: AppConfiguration) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: fileURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }

        let storedConfiguration = StoredConfigurationV2(
            schemaVersion: 2,
            profiles: configuration.profiles,
            automationRules: configuration.automationRules
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storedConfiguration)
        try data.write(to: fileURL, options: .atomic)
    }

    private func decodeConfiguration(at url: URL) throws -> AppConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let header = try decoder.decode(ConfigurationHeader.self, from: data)
        switch header.schemaVersion {
        case 1:
            let legacy = try decoder.decode(StoredConfigurationV1.self, from: data)
            return AppConfiguration(
                profiles: legacy.profiles.map { $0.migrated() },
                automationRules: []
            )
        case 2:
            let stored = try decoder.decode(StoredConfigurationV2.self, from: data)
            return AppConfiguration(
                profiles: stored.profiles,
                automationRules: stored.automationRules
            )
        default:
            throw ProfileStoreError.unsupportedSchema(header.schemaVersion)
        }
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
