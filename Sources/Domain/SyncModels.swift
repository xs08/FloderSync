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
}

enum SyncPolicy: Codable, Hashable, Sendable {
    case daily(times: [DailyTime])
    case interval(seconds: TimeInterval)
    case fileChanges
}

struct SyncProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var localPath: String
    var remoteName: String
    var commitMessageTemplate: String
    var policies: [SyncPolicy]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        localPath: String,
        remoteName: String = "origin",
        commitMessageTemplate: String = "FloderSync: automatic sync at {timestamp}",
        policies: [SyncPolicy] = [.fileChanges],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.remoteName = remoteName
        self.commitMessageTemplate = commitMessageTemplate
        self.policies = policies
        self.isEnabled = isEnabled
    }

    func commitMessage(at date: Date) -> String {
        commitMessageTemplate.replacingOccurrences(
            of: "{timestamp}",
            with: date.formatted(.iso8601)
        )
    }

    var watchesFileChanges: Bool {
        policies.contains(.fileChanges)
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
}

enum SyncTrigger: String, Codable, Sendable {
    case manual
    case scheduled
    case interval
    case fileChanges
    case wakeCatchUp
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
}

struct RepositoryInfo: Equatable, Sendable {
    let rootPath: String
    let currentBranch: String
    let remoteURL: String
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
        case .commandFailed: .commandFailed
        }
    }

    var requiresUserAction: Bool {
        switch self {
        case .invalidRepository, .remoteMissing, .detachedHead, .authentication, .conflict:
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
