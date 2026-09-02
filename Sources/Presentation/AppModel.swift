import Combine
import Foundation

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let defaultsKey = "appTheme"

    var id: Self { self }

    static var selected: Self {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let theme = Self(rawValue: rawValue) else {
            return .system
        }
        return theme
    }
}

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
    @Published private(set) var automationRules: [AutomationRule] = []
    @Published private(set) var recentRuns: [SyncRunRecord] = []
    @Published private(set) var syncingProfileIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var launchAtLoginStatus: LoginItemStatus = .disabled
    @Published private(set) var notifyOnFailure: Bool
    @Published private(set) var appLanguage: AppLanguage
    @Published private(set) var appTheme: AppTheme
    @Published private(set) var connectionChecks: [UUID: ConnectionCheckState] = [:]
    @Published var selectedSettingsSection: SettingsSection = .repositories
    @Published var selectedProfileID: UUID?
    @Published var selectedAutomationRuleID: UUID?
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
        notificationService: any FailureNotificationSending = UserNotificationService(),
        initialConfiguration: AppConfiguration? = nil
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
        self.appTheme = AppTheme.selected
        if let initialConfiguration {
            self.profiles = initialConfiguration.profiles
            self.automationRules = initialConfiguration.automationRules
            self.selectedProfileID = initialConfiguration.profiles.first?.id
            self.selectedAutomationRuleID = initialConfiguration.automationRules.first?.id
        }
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
                let configuration = try await profileStore.loadConfiguration()
                profiles = configuration.profiles
                automationRules = configuration.automationRules
                selectedAutomationRuleID = automationRules.first?.id
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

    @discardableResult
    func addAutomationRule() -> UUID {
        let existingNames = Set(automationRules.map { $0.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ) })
        var number = automationRules.count + 1
        var name = L10n.format("automation.rule.defaultName", table: .automation, number)
        while existingNames.contains(name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )) {
            number += 1
            name = L10n.format("automation.rule.defaultName", table: .automation, number)
        }

        let rule = AutomationRule(name: name)
        automationRules.append(rule)
        automationRules.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selectedAutomationRuleID = rule.id
        persistProfilesInBackground()
        return rule.id
    }

    func saveAutomationRule(_ rule: AutomationRule) -> Bool {
        let trimmedName = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            presentedError = L10n.string("automation.rule.nameRequired", table: .automation)
            return false
        }
        let normalizedName = trimmedName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        guard !automationRules.contains(where: { candidate in
            candidate.id != rule.id && candidate.name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) == normalizedName
        }) else {
            presentedError = L10n.string("automation.rule.nameDuplicate", table: .automation)
            return false
        }
        guard !rule.configuration.policies.isEmpty else {
            presentedError = L10n.string("automation.rule.triggerRequired", table: .automation)
            return false
        }
        guard let index = automationRules.firstIndex(where: { $0.id == rule.id }) else { return false }
        var savedRule = rule
        savedRule.name = trimmedName
        automationRules[index] = savedRule
        automationRules.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistProfilesInBackground()
        return true
    }

    func removeAutomationRule(id: UUID, detachReferencedRepositories: Bool) -> Bool {
        guard let rule = automationRules.first(where: { $0.id == id }) else { return false }
        let referencedIndexes = profiles.indices.filter { profiles[$0].automationRuleID == id }
        if !referencedIndexes.isEmpty && !detachReferencedRepositories {
            presentedError = L10n.string("automation.rule.inUse", table: .automation)
            return false
        }
        for index in referencedIndexes {
            profiles[index].customAutomationConfiguration = rule.configuration
            profiles[index].automationRuleID = nil
        }
        automationRules.removeAll(where: { $0.id == id })
        selectedAutomationRuleID = automationRules.first?.id
        persistProfilesInBackground()
        return true
    }

    func repositories(using ruleID: UUID) -> [SyncProfile] {
        profiles.filter { $0.automationRuleID == ruleID }
    }

    func automationRule(id: UUID?) -> AutomationRule? {
        guard let id else { return nil }
        return automationRules.first(where: { $0.id == id })
    }

    func effectiveConfiguration(for profile: SyncProfile) -> AutomationConfiguration? {
        guard let ruleID = profile.automationRuleID else {
            return profile.customAutomationConfiguration
        }
        return automationRule(id: ruleID)?.configuration
    }

    func setRepositoryAutomationRule(profileID: UUID, ruleID: UUID?) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        if ruleID == nil,
           let effectiveConfiguration = effectiveConfiguration(for: profiles[index]) {
            profiles[index].customAutomationConfiguration = effectiveConfiguration
        }
        profiles[index].automationRuleID = ruleID
        persistProfilesInBackground()
    }

    func setCustomAutomationConfiguration(
        profileID: UUID,
        configuration: AutomationConfiguration
    ) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].customAutomationConfiguration = configuration
        profiles[index].automationRuleID = nil
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

    func setAppTheme(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.defaultsKey)
        appTheme = theme
    }

    func syncAll() {
        for profile in profiles {
            sync(profile)
        }
    }

    func sync(_ profile: SyncProfile) {
        let resolved = profile.resolved(using: automationRules) ?? profile
        requestSync(resolved, trigger: .manual)
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
        try await profileStore.saveConfiguration(
            AppConfiguration(profiles: profiles, automationRules: automationRules)
        )
    }

    private func persistProfilesInBackground() {
        let snapshot = AppConfiguration(profiles: profiles, automationRules: automationRules)
        configurationSaveTask?.cancel()
        configurationSaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await profileStore.saveConfiguration(snapshot)
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

    private func configureAutomation() {
        let rulesSnapshot = automationRules
        let snapshot = profiles.compactMap { $0.resolved(using: rulesSnapshot) }
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
        let ruleName = automationRule(id: profile.automationRuleID)?.name
        await coordinator.enqueue(
            profile: profile,
            trigger: trigger,
            automationRuleName: ruleName
        )
        await coordinator.waitUntilIdle(profileID: profile.id)
    }

    private func requestSync(_ profile: SyncProfile, trigger: SyncTrigger) {
        let ruleName = automationRule(id: profile.automationRuleID)?.name
        Task {
            await coordinator.enqueue(
                profile: profile,
                trigger: trigger,
                automationRuleName: ruleName
            )
        }
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
        let resolvedProfiles = profiles.compactMap { $0.resolved(using: automationRules) }
        for profile in resolvedProfiles where profile.isEnabled {
            let lastRunAt = recentRuns.first(where: { $0.profileID == profile.id })?.finishedAt
            if CatchUpCalculator.shouldRunCatchUp(profile: profile, lastRunAt: lastRunAt, now: now) {
                requestSync(profile, trigger: .wakeCatchUp)
            }
        }
    }
}
