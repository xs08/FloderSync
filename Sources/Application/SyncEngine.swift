import Foundation

struct SyncRetryPolicy: Sendable {
    let networkAttemptLimit: Int
    let pushRaceRetryLimit: Int
    let retryDelayNanoseconds: UInt64

    init(
        networkAttemptLimit: Int = 3,
        pushRaceRetryLimit: Int = 2,
        retryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.networkAttemptLimit = max(1, networkAttemptLimit)
        self.pushRaceRetryLimit = max(0, pushRaceRetryLimit)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }
}

struct SyncEngine: Sendable {
    private let git: any GitClient
    private let retryPolicy: SyncRetryPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void

    init(
        git: any GitClient,
        retryPolicy: SyncRetryPolicy = SyncRetryPolicy(),
        sleep: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        }
    ) {
        self.git = git
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func synchronize(
        profile: SyncProfile,
        trigger: SyncTrigger,
        automationRuleName: String? = nil,
        now: @Sendable () -> Date = Date.init
    ) async -> SyncRunRecord {
        let runID = UUID()
        let startedAt = now()
        var completedSteps: [SyncStepRecord] = []
        var hadLocalChanges = false
        var activeStep = SyncStep.validation

        do {
            try Task.checkCancellation()
            let repository = try await git.validateRepository(profile)
            completedSteps.append(.init(step: .validation, completedAt: now()))

            activeStep = .status
            try Task.checkCancellation()
            let status = try await git.workingTreeStatus(at: repository.rootPath)
            hadLocalChanges = status.hasChanges
            completedSteps.append(.init(step: .status, completedAt: now()))

            if status.hasUnmergedPaths || status.hasOperationInProgress {
                throw SyncFailure.conflict(
                    L10n.string("error.operationInProgress", table: .errors)
                )
            }

            if status.hasChanges && !profile.automaticCommit.isEnabled {
                throw SyncFailure.configuration(
                    L10n.string("error.autoCommitDisabled", table: .errors)
                )
            }

            activeStep = .pulling
            var remoteSnapshot = try await retryingNetworkOperation {
                try await git.fetchRemote(
                    at: repository.rootPath,
                    remote: profile.remoteName,
                    branch: repository.currentBranch
                )
            }

            if status.hasChanges {
                let configuredIdentity = GitCommitIdentity(
                    name: profile.automaticCommit.authorName,
                    email: profile.automaticCommit.authorEmail
                )
                let fallbackIdentity = configuredIdentity.isComplete
                    ? GitCommitIdentity()
                    : try await git.commitIdentity(at: repository.rootPath)
                let commitIdentity = profile.automaticCommit.resolvedIdentity(
                    fallingBackTo: fallbackIdentity
                )
                guard commitIdentity.isComplete else {
                    throw SyncFailure.configuration(
                        L10n.string("error.commitIdentityMissing", table: .errors)
                    )
                }
                let commitMessage = profile.automaticCommit
                    .resolvedMessage(identity: commitIdentity, at: startedAt)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !commitMessage.isEmpty else {
                    throw SyncFailure.configuration(
                        L10n.string("error.commitMessageMissing", table: .errors)
                    )
                }

                activeStep = .staging
                try Task.checkCancellation()
                try await git.stageAll(at: repository.rootPath)
                completedSteps.append(.init(step: .staging, completedAt: now()))

                activeStep = .committing
                try Task.checkCancellation()
                try await git.commit(
                    at: repository.rootPath,
                    message: commitMessage,
                    identity: commitIdentity
                )
                completedSteps.append(.init(step: .committing, completedAt: now()))
            }

            var remainingPushRaceRetries = retryPolicy.pushRaceRetryLimit
            while true {
                activeStep = .pulling
                try Task.checkCancellation()
                let divergence = try await git.divergence(
                    at: repository.rootPath,
                    remoteRevision: remoteSnapshot.revision
                )
                if divergence.requiresIntegration {
                    try await git.integrateFetchedRemote(
                        at: repository.rootPath,
                        remoteRevision: remoteSnapshot.revision,
                        strategy: profile.integrationStrategy
                    )
                }

                activeStep = .pushing
                do {
                    try Task.checkCancellation()
                    try await retryingNetworkOperation {
                        try await git.push(
                            at: repository.rootPath,
                            remote: profile.remoteName,
                            branch: repository.currentBranch
                        )
                    }
                    break
                } catch let failure as SyncFailure {
                    guard case .nonFastForward = failure,
                          remainingPushRaceRetries > 0 else {
                        throw failure
                    }
                    remainingPushRaceRetries -= 1
                    activeStep = .pulling
                    remoteSnapshot = try await retryingNetworkOperation {
                        try await git.fetchRemote(
                            at: repository.rootPath,
                            remote: profile.remoteName,
                            branch: repository.currentBranch
                        )
                    }
                }
            }

            completedSteps.append(.init(step: .pulling, completedAt: now()))
            completedSteps.append(.init(step: .pushing, completedAt: now()))

            return SyncRunRecord(
                id: runID,
                profileID: profile.id,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: now(),
                result: .succeeded,
                steps: completedSteps,
                failureCategory: nil,
                failureMessage: nil,
                hadLocalChanges: hadLocalChanges,
                integrationStrategy: profile.integrationStrategy,
                automationRuleName: automationRuleName
            )
        } catch is CancellationError {
            return failureRecord(
                id: runID,
                profile: profile,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: now(),
                steps: completedSteps,
                failure: .cancelled,
                hadLocalChanges: hadLocalChanges,
                automationRuleName: automationRuleName
            )
        } catch let failure as SyncFailure {
            return failureRecord(
                id: runID,
                profile: profile,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: now(),
                steps: completedSteps,
                failure: failure,
                hadLocalChanges: hadLocalChanges,
                automationRuleName: automationRuleName
            )
        } catch {
            return failureRecord(
                id: runID,
                profile: profile,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: now(),
                steps: completedSteps,
                failure: .commandFailed(step: activeStep, message: error.localizedDescription),
                hadLocalChanges: hadLocalChanges,
                automationRuleName: automationRuleName
            )
        }
    }

    private func retryingNetworkOperation<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let failure as SyncFailure {
                guard case .network = failure,
                      attempt < retryPolicy.networkAttemptLimit else {
                    throw failure
                }
                let multiplier = UInt64(attempt)
                let (delay, overflow) = retryPolicy.retryDelayNanoseconds
                    .multipliedReportingOverflow(by: multiplier)
                try await sleep(overflow ? UInt64.max : delay)
                attempt += 1
            }
        }
    }

    private func failureRecord(
        id: UUID,
        profile: SyncProfile,
        trigger: SyncTrigger,
        startedAt: Date,
        finishedAt: Date,
        steps: [SyncStepRecord],
        failure: SyncFailure,
        hadLocalChanges: Bool,
        automationRuleName: String?
    ) -> SyncRunRecord {
        let result: SyncRunResult
        if failure == .cancelled {
            result = .cancelled
        } else if failure.requiresUserAction {
            result = .needsUserAction
        } else {
            result = .failed
        }

        return SyncRunRecord(
            id: id,
            profileID: profile.id,
            trigger: trigger,
            startedAt: startedAt,
            finishedAt: finishedAt,
            result: result,
            steps: steps,
            failureCategory: failure.category,
            failureMessage: failure.displayMessage,
            hadLocalChanges: hadLocalChanges,
            integrationStrategy: profile.integrationStrategy,
            automationRuleName: automationRuleName
        )
    }
}
