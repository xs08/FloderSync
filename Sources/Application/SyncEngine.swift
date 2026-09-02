import Foundation

struct SyncEngine: Sendable {
    private let git: any GitClient

    init(git: any GitClient) {
        self.git = git
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

            if trigger == .fileChanges, !status.hasChanges {
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
                    hadLocalChanges: false,
                    integrationStrategy: profile.integrationStrategy,
                    automationRuleName: automationRuleName
                )
            }

            if status.hasChanges {
                activeStep = .staging
                try Task.checkCancellation()
                try await git.stageAll(at: repository.rootPath)
                completedSteps.append(.init(step: .staging, completedAt: now()))

                activeStep = .committing
                try Task.checkCancellation()
                try await git.commit(
                    at: repository.rootPath,
                    message: profile.commitMessage(at: startedAt)
                )
                completedSteps.append(.init(step: .committing, completedAt: now()))
            }

            activeStep = .pulling
            try Task.checkCancellation()
            try await git.integrateRemote(
                at: repository.rootPath,
                remote: profile.remoteName,
                branch: repository.currentBranch,
                strategy: profile.integrationStrategy
            )
            completedSteps.append(.init(step: .pulling, completedAt: now()))

            activeStep = .pushing
            try Task.checkCancellation()
            try await git.push(
                at: repository.rootPath,
                remote: profile.remoteName,
                branch: repository.currentBranch
            )
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
