import Foundation

struct DailyTime: Codable, Hashable, Sendable, Comparable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) throws {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else {
            throw SyncConfigurationError.invalidDailyTime
        }
        self.hour = hour
        self.minute = minute
    }

    static func < (lhs: DailyTime, rhs: DailyTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    static func suggestedAfter(_ previous: DailyTime?) throws -> DailyTime {
        let previousMinutes = previous.map { $0.hour * 60 + $0.minute } ?? -60
        let nextMinutes = min(previousMinutes + 60, 23 * 60)
        return try DailyTime(hour: nextMinutes / 60, minute: nextMinutes % 60)
    }
}

enum SyncPolicy: Codable, Hashable, Sendable {
    case daily(times: [DailyTime])
    case interval(seconds: TimeInterval)
    case newCommits

    private enum CodingKeys: String, CodingKey {
        case daily
        case interval
        case newCommits
        case fileChanges
    }

    private struct DailyPayload: Codable {
        let times: [DailyTime]
    }

    private struct IntervalPayload: Codable {
        let seconds: TimeInterval
    }

    private struct EmptyPayload: Codable { }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.daily) {
            self = .daily(times: try container.decode(DailyPayload.self, forKey: .daily).times)
        } else if container.contains(.interval) {
            self = .interval(
                seconds: try container.decode(IntervalPayload.self, forKey: .interval).seconds
            )
        } else if container.contains(.newCommits) {
            self = .newCommits
        } else if container.contains(.fileChanges) {
            // schema v1-v3 compatibility: the retired file-change trigger becomes commit detection.
            self = .newCommits
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown sync policy")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .daily(times):
            try container.encode(DailyPayload(times: times), forKey: .daily)
        case let .interval(seconds):
            try container.encode(IntervalPayload(seconds: seconds), forKey: .interval)
        case .newCommits:
            try container.encode(EmptyPayload(), forKey: .newCommits)
        }
    }
}

enum SyncIntegrationStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case rebase
    case merge

    var id: Self { self }
}

struct GitCommitIdentity: Codable, Hashable, Sendable {
    var name: String?
    var email: String?

    init(name: String? = nil, email: String? = nil) {
        self.name = Self.normalized(name)
        self.email = Self.normalized(email)
    }

    var isComplete: Bool {
        name != nil && email != nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

struct AutomaticCommitConfiguration: Codable, Hashable, Sendable {
    static let defaultMessageTemplate = "FloderSync: automatic sync at ${time}"

    var isEnabled: Bool
    var authorName: String?
    var authorEmail: String?
    var messageTemplate: String

    init(
        isEnabled: Bool = true,
        authorName: String? = nil,
        authorEmail: String? = nil,
        messageTemplate: String = Self.defaultMessageTemplate
    ) {
        self.isEnabled = isEnabled
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.messageTemplate = messageTemplate
    }

    func resolvedIdentity(fallingBackTo fallback: GitCommitIdentity) -> GitCommitIdentity {
        let configured = GitCommitIdentity(name: authorName, email: authorEmail)
        return GitCommitIdentity(
            name: configured.name ?? fallback.name,
            email: configured.email ?? fallback.email
        )
    }

    func resolvedMessage(identity: GitCommitIdentity, at date: Date) -> String {
        messageTemplate
            .replacingOccurrences(of: "${user}", with: identity.name ?? "")
            .replacingOccurrences(of: "${email}", with: identity.email ?? "")
            .replacingOccurrences(of: "${time}", with: date.formatted(.iso8601))
            .replacingOccurrences(of: "{timestamp}", with: date.formatted(.iso8601))
    }
}

struct AutomationConfiguration: Codable, Hashable, Sendable {
    var policies: [SyncPolicy]
    var integrationStrategy: SyncIntegrationStrategy
    var automaticCommit: AutomaticCommitConfiguration

    init(
        policies: [SyncPolicy] = [.newCommits],
        integrationStrategy: SyncIntegrationStrategy = .rebase,
        automaticCommit: AutomaticCommitConfiguration = AutomaticCommitConfiguration()
    ) {
        self.policies = policies
        self.integrationStrategy = integrationStrategy
        self.automaticCommit = automaticCommit
    }

    var watchesNewCommits: Bool {
        policies.contains(.newCommits)
    }

    var intervalSeconds: TimeInterval? {
        policies.compactMap { policy in
            if case let .interval(seconds) = policy { return seconds }
            return nil
        }.first
    }

    var dailyTimes: [DailyTime] {
        policies.compactMap { policy in
            if case let .daily(times) = policy { return times }
            return nil
        }.first ?? []
    }

    func normalizedForSaving() throws -> AutomationConfiguration {
        var normalized = self
        normalized.policies = try policies.map { policy in
            guard case let .daily(times) = policy else { return policy }
            let sortedTimes = times.sorted()
            guard Set(sortedTimes).count == sortedTimes.count else {
                throw SyncConfigurationError.duplicateDailyTime
            }
            return .daily(times: sortedTimes)
        }
        return normalized
    }
}

struct AutomationRule: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var configuration: AutomationConfiguration

    init(
        id: UUID = UUID(),
        name: String,
        configuration: AutomationConfiguration = AutomationConfiguration()
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}

struct SyncProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var localPath: String
    var remoteName: String
    var customAutomationConfiguration: AutomationConfiguration
    var automationRuleID: UUID?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        localPath: String,
        remoteName: String = "origin",
        commitMessageTemplate: String? = nil,
        policies: [SyncPolicy] = [.newCommits],
        integrationStrategy: SyncIntegrationStrategy = .rebase,
        automaticCommit: AutomaticCommitConfiguration = AutomaticCommitConfiguration(),
        automationRuleID: UUID? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.remoteName = remoteName
        var resolvedAutomaticCommit = automaticCommit
        if let commitMessageTemplate {
            resolvedAutomaticCommit.messageTemplate = commitMessageTemplate
        }
        self.customAutomationConfiguration = AutomationConfiguration(
            policies: policies,
            integrationStrategy: integrationStrategy,
            automaticCommit: resolvedAutomaticCommit
        )
        self.automationRuleID = automationRuleID
        self.isEnabled = isEnabled
    }

    var watchesNewCommits: Bool {
        customAutomationConfiguration.watchesNewCommits
    }

    var intervalSeconds: TimeInterval? {
        customAutomationConfiguration.intervalSeconds
    }

    var dailyTimes: [DailyTime] {
        customAutomationConfiguration.dailyTimes
    }

    var integrationStrategy: SyncIntegrationStrategy {
        customAutomationConfiguration.integrationStrategy
    }

    var automaticCommit: AutomaticCommitConfiguration {
        customAutomationConfiguration.automaticCommit
    }

    var policies: [SyncPolicy] {
        get { customAutomationConfiguration.policies }
        set { customAutomationConfiguration.policies = newValue }
    }

    func resolved(using rules: [AutomationRule]) -> SyncProfile? {
        guard let automationRuleID else { return self }
        guard let rule = rules.first(where: { $0.id == automationRuleID }) else { return nil }
        var resolved = self
        resolved.customAutomationConfiguration = rule.configuration
        return resolved
    }
}

enum SyncTrigger: String, Codable, Sendable {
    case manual
    case scheduled
    case interval
    case newCommit
    case wakeCatchUp

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "fileChanges" {
            self = .newCommit
        } else if let trigger = Self(rawValue: value) {
            self = trigger
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown sync trigger")
            )
        }
    }
}

enum SyncStep: String, Codable, CaseIterable, Sendable {
    case validation
    case status
    case staging
    case committing
    case pulling
    case pushing
}

enum SyncRunResult: String, Codable, Sendable {
    case succeeded
    case failed
    case needsUserAction
    case cancelled
}

enum SyncFailureCategory: String, Codable, Sendable {
    case gitUnavailable
    case invalidRepository
    case remoteMissing
    case detachedHead
    case authentication
    case conflict
    case network
    case timedOut
    case cancelled
    case configuration
    case commandFailed
}

struct SyncStepRecord: Codable, Hashable, Sendable {
    let step: SyncStep
    let completedAt: Date
}

struct SyncRunRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let profileID: UUID
    let trigger: SyncTrigger
    let startedAt: Date
    let finishedAt: Date
    let result: SyncRunResult
    let steps: [SyncStepRecord]
    let failureCategory: SyncFailureCategory?
    let failureMessage: String?
    let hadLocalChanges: Bool
    let integrationStrategy: SyncIntegrationStrategy?
    let automationRuleName: String?

    init(
        id: UUID,
        profileID: UUID,
        trigger: SyncTrigger,
        startedAt: Date,
        finishedAt: Date,
        result: SyncRunResult,
        steps: [SyncStepRecord],
        failureCategory: SyncFailureCategory?,
        failureMessage: String?,
        hadLocalChanges: Bool,
        integrationStrategy: SyncIntegrationStrategy? = nil,
        automationRuleName: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.trigger = trigger
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.result = result
        self.steps = steps
        self.failureCategory = failureCategory
        self.failureMessage = failureMessage
        self.hadLocalChanges = hadLocalChanges
        self.integrationStrategy = integrationStrategy
        self.automationRuleName = automationRuleName
    }
}

struct RepositoryInfo: Equatable, Sendable {
    let rootPath: String
    let currentBranch: String
    let remoteURL: String
    let gitDirectory: String

    init(rootPath: String, currentBranch: String, remoteURL: String, gitDirectory: String? = nil) {
        self.rootPath = rootPath
        self.currentBranch = currentBranch
        self.remoteURL = remoteURL
        self.gitDirectory = gitDirectory ?? rootPath + "/.git"
    }
}

enum RepositorySynchronizationState: Equatable, Sendable {
    case upToDate
    case outOfSync
}

struct GitWorkingTreeStatus: Equatable, Sendable {
    let hasChanges: Bool
    let hasUnmergedPaths: Bool
    let hasOperationInProgress: Bool

    init(
        hasChanges: Bool,
        hasUnmergedPaths: Bool = false,
        hasOperationInProgress: Bool = false
    ) {
        self.hasChanges = hasChanges
        self.hasUnmergedPaths = hasUnmergedPaths
        self.hasOperationInProgress = hasOperationInProgress
    }
}

enum SyncConfigurationError: Error, Equatable {
    case invalidDailyTime
    case duplicateDailyTime
}

enum SyncFailure: Error, Equatable, Sendable {
    case gitUnavailable(String)
    case invalidRepository(String)
    case remoteMissing(String)
    case detachedHead
    case authentication(String)
    case conflict(String)
    case network(String)
    case timedOut
    case cancelled
    case configuration(String)
    case commandFailed(step: SyncStep, message: String)

    var category: SyncFailureCategory {
        switch self {
        case .gitUnavailable: .gitUnavailable
        case .invalidRepository: .invalidRepository
        case .remoteMissing: .remoteMissing
        case .detachedHead: .detachedHead
        case .authentication: .authentication
        case .conflict: .conflict
        case .network: .network
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        case .configuration: .configuration
        case .commandFailed: .commandFailed
        }
    }

    var requiresUserAction: Bool {
        switch self {
        case .invalidRepository, .remoteMissing, .detachedHead, .authentication, .conflict,
             .configuration:
            true
        default:
            false
        }
    }

    var displayMessage: String {
        switch self {
        case let .gitUnavailable(message),
             let .invalidRepository(message),
             let .remoteMissing(message),
             let .authentication(message),
             let .conflict(message),
             let .network(message),
             let .configuration(message),
             let .commandFailed(_, message):
            message
        case .detachedHead:
            L10n.string("error.detachedHead", table: .errors)
        case .timedOut:
            L10n.string("error.timedOut", table: .errors)
        case .cancelled:
            L10n.string("error.cancelled", table: .errors)
        }
    }
}
