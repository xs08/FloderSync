import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    private let configuresWindow: Bool

    init(model: AppModel, configuresWindow: Bool = true) {
        self.model = model
        self.configuresWindow = configuresWindow
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            HStack(spacing: 0) {
                SettingsSidebar(model: model)
                    .frame(width: 220)
                    .padding(12)
                SettingsDetail(model: model)
            }
        }
        .frame(minWidth: 900, idealWidth: 960, minHeight: 560, idealHeight: 640)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background {
            if configuresWindow {
                SettingsWindowConfigurator()
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .task { model.start() }
        .onDisappear { RepositoryPicker.shared.cancel() }
        .alert(L10n.string("error.title", table: .settings), isPresented: errorIsPresented) {
            Button(L10n.string("action.ok", table: .settings), role: .cancel) {
                model.presentedError = nil
            }
        } message: {
            Text(model.presentedError ?? "")
        }
        .confirmationDialog(
            initialSyncTitle,
            isPresented: initialSyncIsPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.string("repository.initialSync.now", table: .repositoryActions)) {
                model.respondToInitialSync(syncNow: true)
            }
            Button(
                L10n.string("repository.initialSync.later", table: .repositoryActions),
                role: .cancel
            ) {
                model.respondToInitialSync(syncNow: false)
            }
        } message: {
            Text(L10n.string("repository.initialSync.message", table: .repositoryActions))
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )
    }

    private var initialSyncIsPresented: Binding<Bool> {
        Binding(
            get: { model.initialSyncPrompt != nil },
            set: { if !$0 { model.respondToInitialSync(syncNow: false) } }
        )
    }

    private var initialSyncTitle: String {
        L10n.format(
            "repository.initialSync.title",
            table: .repositoryActions,
            model.initialSyncPrompt?.profileName ?? ""
        )
    }
}

private struct SettingsSidebar: View {
    @ObservedObject var model: AppModel
    @FocusState private var focusedSection: AppModel.SettingsSection?

    private let primarySections: [AppModel.SettingsSection] = [
        .repositories,
        .automation,
        .diagnostics
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(primarySections) { section in
                    Button {
                        navigate(to: section)
                    } label: {
                        SettingsSidebarLabel(
                            section: section,
                            isSelected: model.selectedSettingsSection == section
                        )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedSection, equals: section)
                    .focusEffectDisabled()
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 72)

            Spacer(minLength: 24)

            HStack {
                Button {
                    navigate(to: .general)
                } label: {
                    Image(systemName: AppModel.SettingsSection.general.symbolName)
                        .font(.title3)
                }
                .foregroundStyle(
                    model.selectedSettingsSection == .general ? Color.accentColor : .secondary
                )
                .help(L10n.string("settings.general"))
                .accessibilityLabel(L10n.string("settings.general"))
                .focused($focusedSection, equals: .general)
                .focusEffectDisabled()

                Spacer()

                Button {
                    RepositoryPicker.shared.cancel()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.title3)
                }
                .foregroundStyle(.secondary)
                .help(L10n.string("app.quit"))
                .accessibilityLabel(L10n.string("app.quit"))
                .focusEffectDisabled()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .onChange(of: focusedSection) { _, section in
            guard let section, section != model.selectedSettingsSection else { return }
            navigate(to: section)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
    }

    private func navigate(to section: AppModel.SettingsSection) {
        RepositoryPicker.shared.cancel()
        model.selectedSettingsSection = section
    }
}

private struct SettingsSidebarLabel: View {
    let section: AppModel.SettingsSection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .frame(width: 20)
            Text(L10n.string(section.titleKey))
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            isSelected ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingsDetail: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string(model.selectedSettingsSection.titleKey))
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Group {
                switch model.selectedSettingsSection {
                case .repositories:
                    RepositorySettingsView(model: model)
                case .automation:
                    AutomationSettingsView(model: model)
                case .diagnostics:
                    HistorySettingsView(model: model)
                case .general:
                    GeneralSettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowConfigurationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}

private final class SettingsWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.configureWindow()
        }
    }

    private func configureWindow() {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }
}

private extension AppModel.SettingsSection {
    var titleKey: String {
        switch self {
        case .repositories: "settings.repositories"
        case .automation: "settings.automation"
        case .diagnostics: "settings.diagnostics"
        case .general: "settings.general"
        }
    }

    var symbolName: String {
        switch self {
        case .repositories: "externaldrive"
        case .automation: "clock"
        case .diagnostics: "waveform.path.ecg"
        case .general: "gearshape"
        }
    }
}

private struct RepositorySettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pendingRemoval: SyncProfile?

    @ViewBuilder
    var body: some View {
        if model.profiles.isEmpty {
            ContentUnavailableView {
                Label(
                    L10n.string("repositories.empty.title"),
                    systemImage: "externaldrive.badge.plus"
                )
            } description: {
                Text(L10n.string("repositories.settings.empty.message"))
            } actions: {
                Button(L10n.string("repository.add", table: .settings)) {
                    chooseRepository()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            repositoryEditor
        }
    }

    private var repositoryEditor: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.selectedProfileID) {
                    ForEach(model.profiles) { profile in
                        HStack(spacing: 8) {
                            Image(systemName: repositorySymbol(for: profile))
                                .foregroundStyle(repositoryColor(for: profile))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .lineLimit(1)
                                Text(repositorySubtitle(for: profile))
                                    .font(.caption)
                                    .foregroundStyle(
                                        model.needsUserAttention(profile) ? Color.orange : .secondary
                                    )
                                    .lineLimit(1)
                            }
                        }
                        .tag(profile.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 14) {
                    Button(action: chooseRepository) {
                        Image(systemName: "plus")
                    }
                    .help(L10n.string("repository.add", table: .settings))
                    .accessibilityLabel(L10n.string("repository.add", table: .settings))

                    Button(action: removeSelection) {
                        Image(systemName: "minus")
                    }
                    .help(L10n.string("repository.remove", table: .settings))
                    .disabled(selectedProfile == nil)
                    .accessibilityLabel(L10n.string("repository.remove", table: .settings))

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.bar)
            }
            .frame(width: 260)

            Divider()

            Group {
                if let profile = selectedProfile {
                    RepositoryDetailView(profile: profile, model: model)
                } else {
                    ContentUnavailableView {
                        Label(
                            L10n.string("repository.select.title", table: .settings),
                            systemImage: "externaldrive.badge.plus"
                        )
                    } description: {
                        Text(L10n.string("repository.select.message", table: .settings))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if model.selectedProfileID == nil {
                model.selectedProfileID = model.profiles.first?.id
            }
        }
        .alert(
            L10n.string("repository.remove.confirm.title", table: .repositoryActions),
            isPresented: removalIsPresented
        ) {
            Button(L10n.string("action.cancel", table: .repositoryActions), role: .cancel) {
                pendingRemoval = nil
            }
            Button(L10n.string("repository.remove", table: .settings), role: .destructive) {
                guard let pendingRemoval else { return }
                model.removeProfile(id: pendingRemoval.id)
                self.pendingRemoval = nil
            }
        } message: {
            Text(L10n.string("repository.remove.confirm.message", table: .repositoryActions))
        }
    }

    private var selectedProfile: SyncProfile? {
        guard let id = model.selectedProfileID else { return nil }
        return model.profiles.first(where: { $0.id == id })
    }

    private func chooseRepository() {
        Task {
            guard let url = await RepositoryPicker.shared.chooseRepository() else { return }
            _ = await model.addRepository(at: url)
        }
    }

    private func removeSelection() {
        pendingRemoval = selectedProfile
    }

    private var removalIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private func repositorySymbol(for profile: SyncProfile) -> String {
        if model.syncingProfileIDs.contains(profile.id) {
            return "arrow.triangle.2.circlepath"
        }
        if model.needsUserAttention(profile) {
            return "exclamationmark.triangle.fill"
        }
        return profile.isEnabled ? "externaldrive.fill" : "externaldrive"
    }

    private func repositoryColor(for profile: SyncProfile) -> Color {
        if model.needsUserAttention(profile) { return .orange }
        return profile.isEnabled ? .accentColor : .secondary
    }

    private func repositorySubtitle(for profile: SyncProfile) -> String {
        if model.needsUserAttention(profile) {
            return L10n.string("repository.status.needsAttention", table: .repositoryActions)
        }
        return profile.localPath
    }
}

private struct RepositoryDetailView: View {
    let profile: SyncProfile
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            if model.needsUserAttention(profile) {
                Section {
                    Label(
                        L10n.string("repository.failure.title", table: .repositoryActions),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)

                    if let failureMessage = model.latestRun(for: profile)?.failureMessage,
                       !failureMessage.isEmpty {
                        Text(failureMessage)
                            .textSelection(.enabled)
                    }

                    Text(L10n.string("repository.failure.instruction", table: .repositoryActions))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    TextField(
                        L10n.string("repository.name", table: .settings),
                        text: Binding(
                            get: { profile.name },
                            set: { model.setProfileName(id: profile.id, name: $0) }
                        )
                    )
                    .labelsHidden()
                } label: {
                    Text(L10n.string("repository.name", table: .settings))
                }

                LabeledContent {
                    Text(profile.localPath)
                        .textSelection(.enabled)
                        .lineLimit(2)
                } label: {
                    Text(L10n.string("repository.path", table: .settings))
                }

                LabeledContent {
                    TextField(
                        L10n.string("repository.remote", table: .settings),
                        text: Binding(
                            get: { profile.remoteName },
                            set: { model.setRemoteName(id: profile.id, remoteName: $0) }
                        )
                    )
                    .labelsHidden()
                } label: {
                    Text(L10n.string("repository.remote", table: .settings))
                }
            } header: {
                Text(L10n.string("repository.section.identity", table: .settings))
            }

            Section {
                Toggle(
                    L10n.string("repository.enabled", table: .settings),
                    isOn: Binding(
                        get: { profile.isEnabled },
                        set: { model.setProfileEnabled(id: profile.id, enabled: $0) }
                    )
                )

                LabeledContent(
                    L10n.string("repository.branchPolicy", table: .settings),
                    value: L10n.string("repository.currentBranch", table: .settings)
                )

                LabeledContent {
                    TextField(
                        L10n.string("repository.commitTemplate", table: .repositoryActions),
                        text: Binding(
                            get: { profile.commitMessageTemplate },
                            set: { model.setCommitMessageTemplate(id: profile.id, template: $0) }
                        )
                    )
                    .labelsHidden()
                } label: {
                    Text(L10n.string("repository.commitTemplate", table: .repositoryActions))
                }
            } header: {
                Text(L10n.string("repository.section.behavior", table: .settings))
            }

            Section {
                HStack(spacing: 12) {
                    Button(L10n.string("sync.repository")) { model.sync(profile) }
                        .disabled(model.syncingProfileIDs.contains(profile.id))
                    Button(L10n.string("repository.checkConnection", table: .repositoryActions)) {
                        model.checkConnection(for: profile)
                    }
                    .disabled(
                        profile.remoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        model.connectionChecks[profile.id] == .checking
                    )
                    if model.connectionChecks[profile.id] == .succeeded {
                        Label(
                            L10n.string("repository.connection.succeeded", table: .repositoryActions),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                        .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    L10n.string("general.launchAtLogin", table: .settings),
                    isOn: Binding(
                        get: { model.launchAtLoginStatus == .enabled },
                        set: { enabled in model.setLaunchAtLogin(enabled) }
                    )
                )
                if model.launchAtLoginStatus == .requiresApproval {
                    LabeledContent {
                        Button(L10n.string("general.openLoginItems", table: .settings)) {
                            model.openLoginItemsSettings()
                        }
                    } label: {
                        Label(
                            L10n.string("general.approvalRequired", table: .settings),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text(L10n.string("general.startup.section", table: .settings))
            }

            Section {
                Toggle(
                    L10n.string("general.notifyOnFailure", table: .notifications),
                    isOn: Binding(
                        get: { model.notifyOnFailure },
                        set: { enabled in model.setNotifyOnFailure(enabled) }
                    )
                )
            } header: {
                Text(L10n.string("general.notifications.section", table: .notifications))
            }

            Section {
                Picker(
                    L10n.string("general.language", table: .settings),
                    selection: Binding(
                        get: { model.appLanguage },
                        set: { model.setAppLanguage($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(languageTitle(language)).tag(language)
                    }
                }
            } header: {
                Text(L10n.string("general.language.section", table: .settings))
            }

            Section {
                Picker(
                    L10n.string("general.theme", table: .settings),
                    selection: Binding(
                        get: { model.appTheme },
                        set: { model.setAppTheme($0) }
                    )
                ) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(themeTitle(theme)).tag(theme)
                    }
                }
            } header: {
                Text(L10n.string("general.theme.section", table: .settings))
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            L10n.string("general.language.system", table: .settings)
        case .english:
            L10n.string("general.language.english", table: .settings)
        case .simplifiedChinese:
            L10n.string("general.language.simplifiedChinese", table: .settings)
        }
    }

    private func themeTitle(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            L10n.string("general.theme.system", table: .settings)
        case .light:
            L10n.string("general.theme.light", table: .settings)
        case .dark:
            L10n.string("general.theme.dark", table: .settings)
        }
    }
}

private struct AutomationSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.profiles.isEmpty {
            ContentUnavailableView {
                Label(
                    L10n.string("repositories.empty.title"),
                    systemImage: "clock.badge.exclamationmark"
                )
            } description: {
                Text(L10n.string("automation.empty.message", table: .automation))
            }
            .padding(24)
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(model.profiles) { profile in
                        AutomationProfileCard(profile: profile, model: model)
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct AutomationProfileCard: View {
    let profile: SyncProfile
    @ObservedObject var model: AppModel

    private let intervalOptions: [TimeInterval?] = [nil, 300, 900, 1_800, 3_600, 10_800, 21_600]

    var body: some View {
        GroupBox {
            Form {
                Toggle(
                    L10n.string("automation.fileChanges", table: .automation),
                    isOn: Binding(
                        get: { profile.watchesFileChanges },
                        set: { model.setFileChangeSync(id: profile.id, enabled: $0) }
                    )
                )

                Picker(
                    L10n.string("automation.interval", table: .automation),
                    selection: Binding(
                        get: { profile.intervalSeconds },
                        set: { model.setIntervalSync(id: profile.id, seconds: $0) }
                    )
                ) {
                    ForEach(intervalOptions, id: \.self) { interval in
                        Text(intervalLabel(interval)).tag(interval)
                    }
                }

                DailyTimesEditor(
                    times: profile.dailyTimes,
                    onChange: { model.setDailyTimes(id: profile.id, times: $0) }
                )
            }
            .formStyle(.grouped)
        } label: {
            HStack {
                Label(profile.name, systemImage: "externaldrive.fill")
                Spacer()
                if !profile.isEnabled {
                    Text(L10n.string("automation.repositoryDisabled", table: .automation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!profile.isEnabled)
    }

    private func intervalLabel(_ interval: TimeInterval?) -> String {
        guard let interval else {
            return L10n.string("automation.interval.off", table: .automation)
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return L10n.format("automation.interval.minutes", table: .automation, minutes)
        }
        return L10n.format("automation.interval.hours", table: .automation, minutes / 60)
    }
}

private struct DailyTimesEditor: View {
    let times: [DailyTime]
    let onChange: ([DailyTime]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("automation.daily", table: .automation))
                Spacer()
                Button {
                    addTime()
                } label: {
                    Label(
                        L10n.string("automation.daily.add", table: .automation),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.borderless)
            }

            if times.isEmpty {
                Text(L10n.string("automation.daily.off", table: .automation))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                    HStack {
                        DatePicker(
                            L10n.string("automation.daily.time", table: .automation),
                            selection: Binding(
                                get: { date(for: time) },
                                set: { replaceTime(at: index, with: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        Spacer()
                        Button {
                            removeTime(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(
                            L10n.string("automation.daily.remove", table: .automation)
                        )
                    }
                }
            }
        }
    }

    private func addTime() {
        let candidates = [(9, 0), (12, 0), (18, 0), (21, 0)]
        guard let candidate = candidates.first(where: { hour, minute in
            !times.contains(where: { $0.hour == hour && $0.minute == minute })
        }), let time = try? DailyTime(hour: candidate.0, minute: candidate.1) else { return }
        onChange((times + [time]).sorted())
    }

    private func removeTime(at index: Int) {
        var updated = times
        updated.remove(at: index)
        onChange(updated)
    }

    private func replaceTime(at index: Int, with date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour,
              let minute = components.minute,
              let replacement = try? DailyTime(hour: hour, minute: minute) else { return }
        var updated = times
        updated[index] = replacement
        onChange(Array(Set(updated)).sorted())
    }

    private func date(for time: DailyTime) -> Date {
        Calendar.current.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
    }
}

private struct HistorySettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: UUID?

    var body: some View {
        if model.recentRuns.isEmpty {
            ContentUnavailableView {
                Label(
                    L10n.string("history.empty.title", table: .history),
                    systemImage: "clock.arrow.circlepath"
                )
            } description: {
                Text(L10n.string("history.empty.message", table: .history))
            }
            .padding(24)
        } else {
            HSplitView {
                List(model.recentRuns, selection: $selection) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: resultSymbol(run.result))
                                .foregroundStyle(resultColor(run.result))
                            Text(profileName(for: run))
                                .lineLimit(1)
                        }
                        Text(run.finishedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(run.id)
                }
                .frame(minWidth: 240, idealWidth: 270, maxWidth: 320)

                Group {
                    if let run = selectedRun {
                        SyncRunDetailView(run: run, profileName: profileName(for: run))
                    } else {
                        ContentUnavailableView(
                            L10n.string("history.select.title", table: .history),
                            systemImage: "sidebar.left"
                        )
                    }
                }
                .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                if selection == nil { selection = model.recentRuns.first?.id }
            }
        }
    }

    private var selectedRun: SyncRunRecord? {
        guard let selection else { return nil }
        return model.recentRuns.first(where: { $0.id == selection })
    }

    private func profileName(for run: SyncRunRecord) -> String {
        model.profiles.first(where: { $0.id == run.profileID })?.name
            ?? L10n.string("history.unknownRepository", table: .history)
    }
}

private struct SyncRunDetailView: View {
    let run: SyncRunRecord
    let profileName: String

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.string("history.repository", table: .history), value: profileName)
                LabeledContent(L10n.string("history.result", table: .history), value: resultText(run.result))
                LabeledContent(L10n.string("history.trigger", table: .history), value: triggerText(run.trigger))
                LabeledContent(L10n.string("history.started", table: .history), value: run.startedAt.formatted())
                LabeledContent(L10n.string("history.duration", table: .history), value: durationText)
            } header: {
                Text(L10n.string("history.summary", table: .history))
            }

            Section {
                ForEach(run.steps, id: \.step) { record in
                    Label(stepText(record.step), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } header: {
                Text(L10n.string("history.steps", table: .history))
            }

            if let message = run.failureMessage {
                Section {
                    Text(message)
                        .textSelection(.enabled)
                } header: {
                    Text(L10n.string("history.error", table: .history))
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var durationText: String {
        let duration = run.finishedAt.timeIntervalSince(run.startedAt)
        return L10n.format("history.duration.seconds", table: .history, duration)
    }
}

private func resultSymbol(_ result: SyncRunResult) -> String {
    switch result {
    case .succeeded: "checkmark.circle.fill"
    case .failed: "xmark.circle.fill"
    case .needsUserAction: "exclamationmark.triangle.fill"
    case .cancelled: "stop.circle.fill"
    }
}

private func resultColor(_ result: SyncRunResult) -> Color {
    switch result {
    case .succeeded: .green
    case .failed: .red
    case .needsUserAction: .orange
    case .cancelled: .secondary
    }
}

private func resultText(_ result: SyncRunResult) -> String {
    switch result {
    case .succeeded: L10n.string("history.result.succeeded", table: .history)
    case .failed: L10n.string("history.result.failed", table: .history)
    case .needsUserAction: L10n.string("history.result.needsUserAction", table: .history)
    case .cancelled: L10n.string("history.result.cancelled", table: .history)
    }
}

private func triggerText(_ trigger: SyncTrigger) -> String {
    switch trigger {
    case .manual: L10n.string("history.trigger.manual", table: .history)
    case .scheduled: L10n.string("history.trigger.scheduled", table: .history)
    case .interval: L10n.string("history.trigger.interval", table: .history)
    case .fileChanges: L10n.string("history.trigger.fileChanges", table: .history)
    case .wakeCatchUp: L10n.string("history.trigger.wakeCatchUp", table: .history)
    }
}

private func stepText(_ step: SyncStep) -> String {
    switch step {
    case .validation: L10n.string("history.step.validation", table: .history)
    case .status: L10n.string("history.step.status", table: .history)
    case .staging: L10n.string("history.step.staging", table: .history)
    case .committing: L10n.string("history.step.committing", table: .history)
    case .pulling: L10n.string("history.step.pulling", table: .history)
    case .pushing: L10n.string("history.step.pushing", table: .history)
    }
}
