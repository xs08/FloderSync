import Foundation

struct ConfigurationArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    var profiles: [SyncProfile]
    var automationRules: [AutomationRule]
    let settings: ArchivedAppSettings

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        profiles: [SyncProfile],
        automationRules: [AutomationRule],
        settings: ArchivedAppSettings
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.profiles = profiles
        self.automationRules = automationRules
        self.settings = settings
    }

    func validated() throws -> ConfigurationArchive {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationArchiveError.unsupportedSchema(schemaVersion)
        }
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(automationRules.map(\.id)).count == automationRules.count else {
            throw ConfigurationArchiveError.duplicateIdentifier
        }

        var normalizedRuleNames = Set<String>()
        var normalizedRules: [AutomationRule] = []
        for var rule in automationRules {
            let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw ConfigurationArchiveError.missingRequiredValue }
            let comparableName = name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard normalizedRuleNames.insert(comparableName).inserted else {
                throw ConfigurationArchiveError.duplicateRuleName
            }
            guard !rule.configuration.policies.isEmpty else {
                throw ConfigurationArchiveError.invalidAutomation
            }
            rule.name = name
            rule.configuration = try validate(rule.configuration)
            normalizedRules.append(rule)
        }

        let ruleIDs = Set(normalizedRules.map(\.id))
        var normalizedPaths = Set<String>()
        var normalizedProfiles: [SyncProfile] = []
        for var profile in profiles {
            profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.localPath = profile.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.remoteName = profile.remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profile.name.isEmpty, !profile.localPath.isEmpty, !profile.remoteName.isEmpty else {
                throw ConfigurationArchiveError.missingRequiredValue
            }
            guard normalizedPaths.insert(profile.localPath).inserted else {
                throw ConfigurationArchiveError.duplicateRepositoryPath
            }
            if let ruleID = profile.automationRuleID, !ruleIDs.contains(ruleID) {
                throw ConfigurationArchiveError.missingAutomationRule
            }
            profile.customAutomationConfiguration = try validate(
                profile.customAutomationConfiguration
            )
            normalizedProfiles.append(profile)
        }

        var normalized = self
        normalized.profiles = normalizedProfiles.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        normalized.automationRules = normalizedRules.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return normalized
    }

    private func validate(_ configuration: AutomationConfiguration) throws -> AutomationConfiguration {
        var dailyCount = 0
        var intervalCount = 0
        var commitCount = 0
        for policy in configuration.policies {
            switch policy {
            case let .daily(times):
                dailyCount += 1
                guard !times.isEmpty,
                      Set(times).count == times.count,
                      times.allSatisfy({
                          (0..<24).contains($0.hour) && (0..<60).contains($0.minute)
                      }) else {
                    throw ConfigurationArchiveError.invalidAutomation
                }
            case let .interval(seconds):
                intervalCount += 1
                guard seconds.isFinite, (60...86_400).contains(seconds) else {
                    throw ConfigurationArchiveError.invalidAutomation
                }
            case .newCommits:
                commitCount += 1
            }
        }
        guard dailyCount <= 1, intervalCount <= 1, commitCount <= 1 else {
            throw ConfigurationArchiveError.invalidAutomation
        }
        if configuration.automaticCommit.isEnabled,
           configuration.automaticCommit.messageTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigurationArchiveError.invalidAutomation
        }
        do {
            return try configuration.normalizedForSaving()
        } catch {
            throw ConfigurationArchiveError.invalidAutomation
        }
    }
}

struct ArchivedAppSettings: Codable, Equatable, Sendable {
    let launchAtLogin: Bool
    let notifyOnFailure: Bool
    let language: AppLanguage
    let theme: AppTheme
}

protocol ConfigurationArchiveCoding: Sendable {
    func read(from url: URL) async throws -> ConfigurationArchive
    func write(_ archive: ConfigurationArchive, to url: URL) async throws
}

enum ConfigurationArchiveError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidFile
    case fileTooLarge
    case duplicateIdentifier
    case duplicateRuleName
    case duplicateRepositoryPath
    case missingAutomationRule
    case missingRequiredValue
    case invalidAutomation

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            L10n.format("configuration.error.unsupportedSchema", table: .errors, version)
        case .invalidFile:
            L10n.string("configuration.error.invalidFile", table: .errors)
        case .fileTooLarge:
            L10n.string("configuration.error.fileTooLarge", table: .errors)
        case .duplicateIdentifier:
            L10n.string("configuration.error.duplicateIdentifier", table: .errors)
        case .duplicateRuleName:
            L10n.string("configuration.error.duplicateRuleName", table: .errors)
        case .duplicateRepositoryPath:
            L10n.string("configuration.error.duplicateRepositoryPath", table: .errors)
        case .missingAutomationRule:
            L10n.string("configuration.error.missingAutomationRule", table: .errors)
        case .missingRequiredValue:
            L10n.string("configuration.error.missingRequiredValue", table: .errors)
        case .invalidAutomation:
            L10n.string("configuration.error.invalidAutomation", table: .errors)
        }
    }
}
