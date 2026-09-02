import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    struct InitialSyncPrompt: Identifiable, Equatable {
        let profileID: UUID
        let profileName: String

        var id: UUID { profileID }
    }

    enum SettingsSection: String, CaseIterable, Identifiable {
        case repositories
        case automation
        case diagnostics
        case general

        var id: Self { self }
    }

    enum OverallState {
        case ready
        case syncing
        case problems
    }

    enum ConnectionCheckState: Equatable {
        case checking
        case succeeded
        case failed
    }

    @Published private(set) var profiles: [SyncProfile] = []
    @Published private(set) var recentRuns: [SyncRunRecord] = []
    @Published private(set) var syncingProfileIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var launchAtLoginStatus: LoginItemStatus = .disabled
    @Published private(set) var notifyOnFailure: Bool
    @Published private(set) var appLanguage: AppLanguage
    @Published private(set) var connectionChecks: [UUID: ConnectionCheckState] = [:]
    @Published var selectedSettingsSection: SettingsSection = .repositories
    @Published var selectedProfileID: UUID?
    @Published var initialSyncPrompt: InitialSyncPrompt?
    @Published var presentedError: String?

    private let engine: SyncEngine
    private let coordinator: SyncCoordinator
    private let git: any GitClient
    private let profileStore: any ProfileStore
    private let historyStore: any RunHistoryStore
    private let loginItemService: any LoginItemManaging
    private let notificationService: any FailureNotificationSending
    private let automationScheduler = AutomationScheduler()
    private let fileChangeScheduler = FileChangeScheduler()
    private let wakeMonitor = SystemWakeMonitor()
    private var hasStarted = false
    private var configurationSaveTask: Task<Void, Never>?

    init(
        git: any GitClient = ProcessGitClient(),
        profileStore: any ProfileStore = JSONProfileStore.live(),
        historyStore: any RunHistoryStore = JSONRunHistoryStore.live(),
        loginItemService: any LoginItemManaging = LoginItemService(),
        notificationService: any FailureNotificationSending = UserNotificationService()
    ) {
        self.git = git
        self.engine = SyncEngine(git: git)
        self.coordinator = SyncCoordinator(engine: self.engine)
        self.profileStore = profileStore
        self.historyStore = historyStore
        self.loginItemService = loginItemService
        self.notificationService = notificationService
        self.notifyOnFailure = UserDefaults.standard.object(forKey: "notifyOnFailure") as? Bool ?? true
        self.appLanguage = AppLanguage.selected
    }

    var overallState: OverallState {
        if !syncingProfileIDs.isEmpty { return .syncing }
        if profiles.contains(where: { profile in
            guard let result = latestRun(for: profile)?.result else { return false }
            return result == .failed || result == .needsUserAction
        }) {
            return .problems
        }
        return .ready
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        wakeMonitor.start { [weak self] in self?.runCatchUpIfNeeded() }
        Task {
            listenForSyncEvents()
            do {
                profiles = try await profileStore.loadProfiles()
                configureAutomation()
            } catch {
                presentedError = error.localizedDescription
            }
            do {
                recentRuns = try await historyStore.loadRuns()
                runCatchUpIfNeeded()
            } catch {
                presentedError = error.localizedDescription
            }
            launchAtLoginStatus = await loginItemService.status()
            if notifyOnFailure, !profiles.isEmpty {
                _ = try? await notificationService.requestAuthorization()
            }
            isLoading = false
        }
    }

    func addRepository(at url: URL) async -> Bool {
        var profile = SyncProfile(name: url.lastPathComponent, localPath: url.path)
        do {
            let repository = try await git.validateRepository(profile)
            guard !profiles.contains(where: { $0.localPath == repository.rootPath }) else {
                presentedError = L10n.string("error.repositoryAlreadyAdded", table: .settings)
                return false
            }
            profile.localPath = repository.rootPath
            profile.name = URL(fileURLWithPath: repository.rootPath).lastPathComponent

            let synchronizationState: RepositorySynchronizationState?
            do {
                synchronizationState = try await git.synchronizationState(
                    at: repository.rootPath,
                    remote: profile.remoteName,
                    branch: repository.currentBranch
                )
            } catch let failure as SyncFailure {
                synchronizationState = nil
                presentedError = failure.displayMessage
            } catch {
                synchronizationState = nil
                presentedError = error.localizedDescription
            }

            profiles.append(profile)
            profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            selectedSettingsSection = .repositories
            selectedProfileID = profile.id
            try await persistProfiles()
            configureAutomation()
            if synchronizationState == .outOfSync {
                initialSyncPrompt = InitialSyncPrompt(
                    profileID: profile.id,
                    profileName: profile.name
                )
            }
            return true
        } catch let failure as SyncFailure {
            presentedError = failure.displayMessage
        } catch {
            presentedError = error.localizedDescription
        }
        return false
    }

    func removeProfile(id: UUID) {
        profiles.removeAll(where: { $0.id == id })
        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }
        persistProfilesInBackground()
    }

    func setProfileEnabled(id: UUID, enabled: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].isEnabled = enabled
        persistProfilesInBackground()
        configureAutomation()
    }

    func setProfileName(id: UUID, name: String) {
        updateProfile(id: id) { profile in
            profile.name = name
        }
    }

    func setRemoteName(id: UUID, remoteName: String) {
        updateProfile(id: id) { profile in
            profile.remoteName = remoteName
        }
        connectionChecks[id] = nil
    }

    func setCommitMessageTemplate(id: UUID, template: String) {
        updateProfile(id: id) { profile in
            profile.commitMessageTemplate = template
        }
    }

    func checkConnection(for profile: SyncProfile) {
        connectionChecks[profile.id] = .checking
        Task {
            do {
                try await git.checkRemoteAccess(at: profile.localPath, remote: profile.remoteName)
                connectionChecks[profile.id] = .succeeded
            } catch {
                connectionChecks[profile.id] = .failed
                if let failure = error as? SyncFailure {
                    presentedError = failure.displayMessage
                } else {
                    presentedError = error.localizedDescription
                }
            }
        }
    }

    func setFileChangeSync(id: UUID, enabled: Bool) {
        updatePolicies(id: id) { policies in
            policies.removeAll(where: { $0 == .fileChanges })
            if enabled { policies.append(.fileChanges) }
        }
    }

    func setIntervalSync(id: UUID, seconds: TimeInterval?) {
        updatePolicies(id: id) { policies in
            policies.removeAll { policy in
                if case .interval = policy { return true }
                return false
            }
            if let seconds { policies.append(.interval(seconds: seconds)) }
        }
    }

    func setDailyTimes(id: UUID, times: [DailyTime]) {
        updatePolicies(id: id) { policies in
            policies.removeAll { policy in
                if case .daily = policy { return true }
                return false
            }
            if !times.isEmpty { policies.append(.daily(times: times.sorted())) }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        Task {
            do {
                try await loginItemService.setEnabled(enabled)
                launchAtLoginStatus = await loginItemService.status()
            } catch {
                launchAtLoginStatus = await loginItemService.status()
                presentedError = error.localizedDescription
            }
        }
    }

    func openLoginItemsSettings() {
        Task { await loginItemService.openSystemSettings() }
    }

    func setNotifyOnFailure(_ enabled: Bool) {
        notifyOnFailure = enabled
        UserDefaults.standard.set(enabled, forKey: "notifyOnFailure")
        if enabled {
            Task {
                do {
                    let granted = try await notificationService.requestAuthorization()
                    if !granted {
                        notifyOnFailure = false
                        UserDefaults.standard.set(false, forKey: "notifyOnFailure")
                    }
                } catch {
                    notifyOnFailure = false
                    UserDefaults.standard.set(false, forKey: "notifyOnFailure")
                    presentedError = error.localizedDescription
                }
            }
        }
    }

    func setAppLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.defaultsKey)
        appLanguage = language
    }

    func syncAll() {
        for profile in profiles {
            sync(profile)
        }
    }

    func sync(_ profile: SyncProfile) {
        requestSync(profile, trigger: .manual)
    }

    func respondToInitialSync(syncNow: Bool) {
        guard let prompt = initialSyncPrompt else { return }
        initialSyncPrompt = nil
        guard syncNow,
              let profile = profiles.first(where: { $0.id == prompt.profileID }) else { return }
        sync(profile)
    }

    func latestRun(for profile: SyncProfile) -> SyncRunRecord? {
        recentRuns.first(where: { $0.profileID == profile.id })
    }

    func needsUserAttention(_ profile: SyncProfile) -> Bool {
        guard let result = latestRun(for: profile)?.result else { return false }
        return result == .failed || result == .needsUserAction
    }

    private func persistProfiles() async throws {
        try await profileStore.saveProfiles(profiles)
    }

    private func persistProfilesInBackground() {
        let snapshot = profiles
        configurationSaveTask?.cancel()
        configurationSaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await profileStore.saveProfiles(snapshot)
                configureAutomation()
            } catch is CancellationError {
                return
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func updateProfile(id: UUID, change: (inout SyncProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&profiles[index])
        persistProfilesInBackground()
    }

    private func updatePolicies(id: UUID, change: (inout [SyncPolicy]) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&profiles[index].policies)
        persistProfilesInBackground()
        configureAutomation()
    }

    private func configureAutomation() {
        let snapshot = profiles
        Task {
            await automationScheduler.configure(profiles: snapshot) { [weak self] profile, trigger in
                guard let self else { return }
                await self.enqueueAndWait(profile: profile, trigger: trigger)
            }
            let watcherFailures = await fileChangeScheduler.configure(profiles: snapshot) { [weak self] profile, trigger in
                guard let self else { return }
                await self.enqueueAndWait(profile: profile, trigger: trigger)
            }
            if let failure = watcherFailures.values.first {
                presentedError = failure
            }
        }
    }

    private func enqueueAndWait(profile: SyncProfile, trigger: SyncTrigger) async {
        await coordinator.enqueue(profile: profile, trigger: trigger)
        await coordinator.waitUntilIdle(profileID: profile.id)
    }

    private func requestSync(_ profile: SyncProfile, trigger: SyncTrigger) {
        Task { await coordinator.enqueue(profile: profile, trigger: trigger) }
    }

    private func listenForSyncEvents() {
        Task {
            for await event in coordinator.events {
                switch event {
                case let .started(profileID):
                    syncingProfileIDs.insert(profileID)
                case let .finished(record):
                    recentRuns.insert(record, at: 0)
                    recentRuns = Array(recentRuns.prefix(100))
                    Task {
                        do {
                            try await historyStore.append(record, limit: 100)
                        } catch {
                            presentedError = error.localizedDescription
                        }
                    }
                    if notifyOnFailure &&
                        (record.result == .failed || record.result == .needsUserAction) {
                        let profileName = profiles.first(where: { $0.id == record.profileID })?.name
                            ?? L10n.string("history.unknownRepository", table: .history)
                        Task {
                            try? await notificationService.sendFailure(
                                for: record,
                                profileName: profileName
                            )
                        }
                    }
                case let .becameIdle(profileID):
                    syncingProfileIDs.remove(profileID)
                }
            }
        }
    }

    private func runCatchUpIfNeeded() {
        let now = Date()
        for profile in profiles where profile.isEnabled {
            let lastRunAt = recentRuns.first(where: { $0.profileID == profile.id })?.finishedAt
            if CatchUpCalculator.shouldRunCatchUp(profile: profile, lastRunAt: lastRunAt, now: now) {
                requestSync(profile, trigger: .wakeCatchUp)
            }
        }
    }
}
