import AppKit
import SwiftUI

struct SettingsPalette {
    let windowBackground: Color
    let contentBackground: Color
    let sidebarBackground: Color
    let elevatedBackground: Color
    let windowBorder: Color
    let sidebarBorder: Color
    let divider: Color
    let primaryText: Color
    let secondaryText: Color
    let mutedText: Color
    let navigationText: Color
    let selectionBackground: Color
    let selectionForeground: Color
    let shadow: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            // A cool charcoal ramp modeled after native macOS utility surfaces. Elevation is
            // expressed through lightness rather than heavy shadows or translucent overlays.
            windowBackground = Color(red: 0.129, green: 0.157, blue: 0.176)
            contentBackground = Color(red: 0.145, green: 0.173, blue: 0.192)
            sidebarBackground = Color(red: 0.102, green: 0.125, blue: 0.141)
            elevatedBackground = Color(red: 0.169, green: 0.200, blue: 0.220)
            windowBorder = Color(red: 0.310, green: 0.357, blue: 0.384)
            sidebarBorder = Color(red: 0.239, green: 0.286, blue: 0.314)
            divider = Color(red: 0.220, green: 0.259, blue: 0.282)
            primaryText = Color(red: 0.949, green: 0.961, blue: 0.969)
            secondaryText = Color(red: 0.714, green: 0.749, blue: 0.769)
            mutedText = Color(red: 0.541, green: 0.588, blue: 0.616)
            navigationText = Color(red: 0.894, green: 0.918, blue: 0.929)
            selectionBackground = Color(red: 0.090, green: 0.420, blue: 0.790)
            selectionForeground = .white
            shadow = .clear
        } else {
            windowBackground = Color(nsColor: .windowBackgroundColor)
            contentBackground = Color(nsColor: .windowBackgroundColor)
            sidebarBackground = Color(nsColor: .controlBackgroundColor)
            elevatedBackground = Color(nsColor: .textBackgroundColor)
            windowBorder = Color(nsColor: .separatorColor)
            sidebarBorder = Color(nsColor: .separatorColor)
            divider = Color(nsColor: .separatorColor)
            primaryText = Color(nsColor: .labelColor)
            secondaryText = Color(nsColor: .secondaryLabelColor)
            mutedText = Color(nsColor: .tertiaryLabelColor)
            navigationText = Color(nsColor: .labelColor)
            selectionBackground = .accentColor
            selectionForeground = .white
            shadow = .black.opacity(0.08)
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            palette.windowBackground

            HStack(spacing: 0) {
                SettingsSidebar(model: model)
                    .frame(width: 220)
                    .padding(12)
                SettingsDetail(model: model)
            }
        }
        .frame(minWidth: 900, idealWidth: 960, minHeight: 560, idealHeight: 640)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(palette.windowBorder, lineWidth: 1)
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
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedSection: AppModel.SettingsSection?

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

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
                            isSelected: model.selectedSettingsSection == section,
                            language: model.appLanguage
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
                    model.selectedSettingsSection == .general
                        ? palette.selectionBackground
                        : palette.secondaryText
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
                .foregroundStyle(palette.secondaryText)
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
                .fill(palette.sidebarBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.sidebarBorder, lineWidth: 1)
                }
                .shadow(color: palette.shadow, radius: 8, y: 3)
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
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .frame(width: 20)
            Text(L10n.string(section.titleKey, language: language))
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? palette.selectionForeground : palette.navigationText)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            isSelected ? palette.selectionBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingsDetail: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string(model.selectedSettingsSection.titleKey))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
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
        .background(palette.contentBackground)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingRemoval: SyncProfile?

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    @ViewBuilder
    var body: some View {
        if model.profiles.isEmpty {
            ContentUnavailableView {
                Label {
                    Text(L10n.string("repositories.empty.title"))
                        .foregroundStyle(palette.primaryText)
                } icon: {
                    Image(systemName: "externaldrive.badge.plus")
                        .foregroundStyle(palette.mutedText)
                }
            } description: {
                Text(L10n.string("repositories.settings.empty.message"))
                    .foregroundStyle(palette.secondaryText)
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
                .scrollContentBackground(.hidden)
                .background(palette.elevatedBackground)

                Divider().overlay(palette.divider)

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
                .background(palette.elevatedBackground)
            }
            .frame(width: 260)

            Divider().overlay(palette.divider)

            Group {
                if let profile = selectedProfile {
                    RepositoryDetailView(profile: profile, model: model)
                } else {
                    ContentUnavailableView {
                        Label {
                            Text(L10n.string("repository.select.title", table: .settings))
                                .foregroundStyle(palette.primaryText)
                        } icon: {
                            Image(systemName: "externaldrive.badge.plus")
                                .foregroundStyle(palette.mutedText)
                        }
                    } description: {
                        Text(L10n.string("repository.select.message", table: .settings))
                            .foregroundStyle(palette.secondaryText)
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
    @Environment(\.colorScheme) private var colorScheme

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

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

            } header: {
                Text(L10n.string("repository.section.behavior", table: .settings))
            }

            Section {
                Picker(
                    L10n.string("automation.source", table: .automation),
                    selection: Binding<UUID?>(
                        get: { profile.automationRuleID },
                        set: { model.setRepositoryAutomationRule(profileID: profile.id, ruleID: $0) }
                    )
                ) {
                    Text(L10n.string("automation.source.custom", table: .automation))
                        .tag(Optional<UUID>.none)
                    ForEach(model.automationRules) { rule in
                        Text(rule.name).tag(Optional(rule.id))
                    }
                }

                if let ruleID = profile.automationRuleID,
                   let rule = model.automationRule(id: ruleID) {
                    AutomationConfigurationSummary(configuration: rule.configuration)
                    LabeledContent {
                        Button(L10n.string("automation.rule.edit", table: .automation)) {
                            model.selectedAutomationRuleID = rule.id
                            model.selectedSettingsSection = .automation
                        }
                    } label: {
                        Text(L10n.string("automation.rule.shared", table: .automation))
                    }
                } else if profile.automationRuleID != nil {
                    Label(
                        L10n.string("automation.rule.missing", table: .automation),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button(L10n.string("automation.source.useCustom", table: .automation)) {
                        model.setRepositoryAutomationRule(profileID: profile.id, ruleID: nil)
                    }
                } else {
                    AutomationConfigurationEditor(
                        configuration: profile.customAutomationConfiguration,
                        onChange: { configuration in
                            model.setCustomAutomationConfiguration(
                                profileID: profile.id,
                                configuration: configuration
                            )
                        }
                    )
                }
            } header: {
                Text(L10n.string("automation.repository.section", table: .automation))
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
        .scrollContentBackground(.hidden)
        .background(palette.contentBackground)
        .padding(20)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

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
                        Text(language.pickerTitle(interfaceLanguage: model.appLanguage)).tag(language)
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
        .scrollContentBackground(.hidden)
        .background(palette.contentBackground)
        .padding(24)
        .task {
            await model.refreshLaunchAtLoginStatus()
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingRemoval: AutomationRule?

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    @ViewBuilder
    var body: some View {
        if model.automationRules.isEmpty {
            ContentUnavailableView {
                Label {
                    Text(L10n.string("automation.rules.empty.title", table: .automation))
                        .foregroundStyle(palette.primaryText)
                } icon: {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundStyle(palette.mutedText)
                }
            } description: {
                Text(L10n.string("automation.rules.empty.message", table: .automation))
                    .foregroundStyle(palette.secondaryText)
            } actions: {
                Button(L10n.string("automation.rule.add", table: .automation)) {
                    model.addAutomationRule()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        } else {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(selection: $model.selectedAutomationRuleID) {
                        ForEach(model.automationRules) { rule in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.name).lineLimit(1)
                                Text(ruleUsageLabel(rule))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(rule.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(palette.elevatedBackground)

                    Divider().overlay(palette.divider)

                    HStack(spacing: 14) {
                        Button { model.addAutomationRule() } label: {
                            Image(systemName: "plus")
                        }
                        .help(L10n.string("automation.rule.add", table: .automation))
                        .accessibilityLabel(L10n.string("automation.rule.add", table: .automation))

                        Button { pendingRemoval = selectedRule } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedRule == nil)
                        .help(L10n.string("automation.rule.remove", table: .automation))
                        .accessibilityLabel(L10n.string("automation.rule.remove", table: .automation))

                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(palette.elevatedBackground)
                }
                .frame(width: 260)

                Divider().overlay(palette.divider)

                Group {
                    if let rule = selectedRule {
                        AutomationRuleDetailView(rule: rule, model: model)
                            .id(rule.id)
                    } else {
                        ContentUnavailableView(
                            L10n.string("automation.rule.select", table: .automation),
                            systemImage: "clock.arrow.2.circlepath"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                if model.selectedAutomationRuleID == nil {
                    model.selectedAutomationRuleID = model.automationRules.first?.id
                }
            }
            .alert(
                L10n.string("automation.rule.remove.confirm.title", table: .automation),
                isPresented: removalIsPresented
            ) {
                Button(L10n.string("action.cancel", table: .repositoryActions), role: .cancel) {
                    pendingRemoval = nil
                }
                Button(L10n.string("automation.rule.remove", table: .automation), role: .destructive) {
                    guard let pendingRemoval else { return }
                    _ = model.removeAutomationRule(
                        id: pendingRemoval.id,
                        detachReferencedRepositories: true
                    )
                    self.pendingRemoval = nil
                }
            } message: {
                Text(removalMessage)
            }
        }
    }

    private var selectedRule: AutomationRule? {
        model.automationRule(id: model.selectedAutomationRuleID)
    }

    private func ruleUsageLabel(_ rule: AutomationRule) -> String {
        L10n.format(
            "automation.rule.usage",
            table: .automation,
            model.repositories(using: rule.id).count
        )
    }

    private var removalIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private var removalMessage: String {
        guard let rule = pendingRemoval else { return "" }
        let count = model.repositories(using: rule.id).count
        if count == 0 {
            return L10n.string("automation.rule.remove.confirm.unused", table: .automation)
        }
        return L10n.format(
            "automation.rule.remove.confirm.used",
            table: .automation,
            count
        )
    }
}

private struct AutomationRuleDetailView: View {
    let rule: AutomationRule
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: AutomationRule

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    init(rule: AutomationRule, model: AppModel) {
        self.rule = rule
        self.model = model
        _draft = State(initialValue: rule)
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    L10n.string("automation.rule.name", table: .automation),
                    text: $draft.name
                )
            } header: {
                Text(L10n.string("automation.rule.identity", table: .automation))
            }

            Section {
                AutomationConfigurationEditor(
                    configuration: draft.configuration,
                    onChange: { draft.configuration = $0 }
                )
            } header: {
                Text(L10n.string("automation.rule.configuration", table: .automation))
            }

            Section {
                let repositories = model.repositories(using: rule.id)
                if repositories.isEmpty {
                    Text(L10n.string("automation.rule.repositories.none", table: .automation))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(repositories) { profile in
                        Label(profile.name, systemImage: "externaldrive.fill")
                    }
                }
            } header: {
                Text(L10n.string("automation.rule.repositories", table: .automation))
            }

            Section {
                HStack {
                    if !model.repositories(using: rule.id).isEmpty {
                        Text(L10n.format(
                            "automation.rule.saveImpact",
                            table: .automation,
                            model.repositories(using: rule.id).count
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.string("automation.rule.save", table: .automation)) {
                        if model.saveAutomationRule(draft) {
                            draft = model.automationRule(id: draft.id) ?? draft
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == rule)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(palette.contentBackground)
        .padding(20)
    }
}

private struct AutomationConfigurationSummary: View {
    let configuration: AutomationConfiguration

    var body: some View {
        LabeledContent(
            L10n.string("automation.summary.triggers", table: .automation),
            value: triggerSummary
        )
        LabeledContent(
            L10n.string("automation.integration", table: .automation),
            value: integrationTitle(configuration.integrationStrategy)
        )
        LabeledContent(
            L10n.string("automation.autoCommit", table: .automation),
            value: L10n.string(
                configuration.automaticCommit.isEnabled
                    ? "automation.autoCommit.enabled"
                    : "automation.autoCommit.disabled",
                table: .automation
            )
        )
    }

    private var triggerSummary: String {
        var parts: [String] = []
        if let seconds = configuration.fileChangeDebounceSeconds {
            parts.append(L10n.format("automation.summary.fileChanges", table: .automation, Int(seconds)))
        }
        if let seconds = configuration.intervalSeconds {
            parts.append(L10n.format("automation.summary.interval", table: .automation, Int(seconds / 60)))
        }
        if !configuration.dailyTimes.isEmpty {
            let times = configuration.dailyTimes.map {
                String(format: "%02d:%02d", $0.hour, $0.minute)
            }.joined(separator: ", ")
            parts.append(times)
        }
        return parts.joined(separator: " · ")
    }
}

private struct AutomationConfigurationEditor: View {
    let configuration: AutomationConfiguration
    let onChange: (AutomationConfiguration) -> Void

    private enum FileDelayChoice: Int, CaseIterable, Identifiable {
        case fiveSeconds = 5
        case tenSeconds = 10
        case oneMinute = 60
        case custom = -1
        var id: Self { self }
    }

    private enum IntervalChoice: Int, CaseIterable, Identifiable {
        case fiveMinutes = 300
        case tenMinutes = 600
        case oneHour = 3_600
        case custom = -1
        var id: Self { self }
    }

    var body: some View {
        Toggle(
            L10n.string("automation.fileChanges", table: .automation),
            isOn: Binding(
                get: { configuration.watchesFileChanges },
                set: { setFileChangesEnabled($0) }
            )
        )

        if let seconds = configuration.fileChangeDebounceSeconds {
            Picker(
                L10n.string("automation.fileChanges.delay", table: .automation),
                selection: Binding(
                    get: { fileDelayChoice(seconds) },
                    set: { setFileDelayChoice($0) }
                )
            ) {
                ForEach(FileDelayChoice.allCases) { choice in
                    Text(fileDelayTitle(choice)).tag(choice)
                }
            }
            if fileDelayChoice(seconds) == .custom {
                Stepper(
                    L10n.format("automation.fileChanges.customSeconds", table: .automation, Int(seconds)),
                    value: Binding(
                        get: { Int(seconds) },
                        set: { setFileDelay(TimeInterval($0)) }
                    ),
                    in: 1...3_600
                )
            }
        }

        Toggle(
            L10n.string("automation.interval", table: .automation),
            isOn: Binding(
                get: { configuration.intervalSeconds != nil },
                set: { setIntervalEnabled($0) }
            )
        )

        if let seconds = configuration.intervalSeconds {
            Picker(
                L10n.string("automation.interval", table: .automation),
                selection: Binding(
                    get: { intervalChoice(seconds) },
                    set: { setIntervalChoice($0) }
                )
            ) {
                ForEach(IntervalChoice.allCases) { choice in
                    Text(intervalTitle(choice)).tag(choice)
                }
            }
            if intervalChoice(seconds) == .custom {
                Stepper(
                    L10n.format("automation.interval.customMinutes", table: .automation, Int(seconds / 60)),
                    value: Binding(
                        get: { max(1, Int(seconds / 60)) },
                        set: { setInterval(TimeInterval($0 * 60)) }
                    ),
                    in: 1...1_440
                )
            }
        }

        DailyTimesEditor(
            times: configuration.dailyTimes,
            onChange: setDailyTimes
        )

        Toggle(
            L10n.string("automation.autoCommit", table: .automation),
            isOn: Binding(
                get: { configuration.automaticCommit.isEnabled },
                set: { setAutomaticCommitEnabled($0) }
            )
        )

        if configuration.automaticCommit.isEnabled {
            LabeledContent {
                TextField(
                    L10n.string("automation.autoCommit.user.placeholder", table: .automation),
                    text: Binding(
                        get: { configuration.automaticCommit.authorName ?? "" },
                        set: { setAutomaticCommitAuthorName($0) }
                    )
                )
                .labelsHidden()
            } label: {
                Text(L10n.string("automation.autoCommit.user", table: .automation))
            }

            LabeledContent {
                TextField(
                    L10n.string("automation.autoCommit.email.placeholder", table: .automation),
                    text: Binding(
                        get: { configuration.automaticCommit.authorEmail ?? "" },
                        set: { setAutomaticCommitAuthorEmail($0) }
                    )
                )
                .labelsHidden()
            } label: {
                Text(L10n.string("automation.autoCommit.email", table: .automation))
            }

            Text(L10n.string("automation.autoCommit.identity.help", table: .automation))
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent {
                TextField(
                    L10n.string("automation.autoCommit.message.placeholder", table: .automation),
                    text: Binding(
                        get: { configuration.automaticCommit.messageTemplate },
                        set: { setAutomaticCommitMessageTemplate($0) }
                    )
                )
                .labelsHidden()
            } label: {
                Text(L10n.string("automation.autoCommit.message", table: .automation))
            }

            Text(L10n.string("automation.autoCommit.message.help", table: .automation))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        Picker(
            L10n.string("automation.integration", table: .automation),
            selection: Binding(
                get: { configuration.integrationStrategy },
                set: { strategy in
                    var updated = configuration
                    updated.integrationStrategy = strategy
                    onChange(updated)
                }
            )
        ) {
            ForEach(SyncIntegrationStrategy.allCases) { strategy in
                Text(integrationTitle(strategy)).tag(strategy)
            }
        }

        Text(integrationDescription(configuration.integrationStrategy))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func setFileChangesEnabled(_ enabled: Bool) {
        var updated = configuration
        updated.policies.removeAll { if case .fileChanges = $0 { true } else { false } }
        if enabled { updated.policies.append(.fileChanges(debounceSeconds: 5)) }
        onChange(updated)
    }

    private func setFileDelay(_ seconds: TimeInterval) {
        var updated = configuration
        updated.policies.removeAll { if case .fileChanges = $0 { true } else { false } }
        updated.policies.append(.fileChanges(debounceSeconds: min(max(seconds, 1), 3_600)))
        onChange(updated)
    }

    private func setIntervalEnabled(_ enabled: Bool) {
        var updated = configuration
        updated.policies.removeAll { if case .interval = $0 { true } else { false } }
        if enabled { updated.policies.append(.interval(seconds: 300)) }
        onChange(updated)
    }

    private func setInterval(_ seconds: TimeInterval) {
        var updated = configuration
        updated.policies.removeAll { if case .interval = $0 { true } else { false } }
        updated.policies.append(.interval(seconds: min(max(seconds, 60), 86_400)))
        onChange(updated)
    }

    private func setDailyTimes(_ times: [DailyTime]) {
        var updated = configuration
        updated.policies.removeAll { if case .daily = $0 { true } else { false } }
        if !times.isEmpty { updated.policies.append(.daily(times: times.sorted())) }
        onChange(updated)
    }

    private func setAutomaticCommitEnabled(_ enabled: Bool) {
        var updated = configuration
        updated.automaticCommit.isEnabled = enabled
        onChange(updated)
    }

    private func setAutomaticCommitAuthorName(_ name: String) {
        var updated = configuration
        updated.automaticCommit.authorName = name
        onChange(updated)
    }

    private func setAutomaticCommitAuthorEmail(_ email: String) {
        var updated = configuration
        updated.automaticCommit.authorEmail = email
        onChange(updated)
    }

    private func setAutomaticCommitMessageTemplate(_ template: String) {
        var updated = configuration
        updated.automaticCommit.messageTemplate = template
        onChange(updated)
    }

    private func fileDelayChoice(_ seconds: TimeInterval) -> FileDelayChoice {
        FileDelayChoice(rawValue: Int(seconds)) ?? .custom
    }

    private func setFileDelayChoice(_ choice: FileDelayChoice) {
        setFileDelay(TimeInterval(choice == .custom ? 30 : choice.rawValue))
    }

    private func fileDelayTitle(_ choice: FileDelayChoice) -> String {
        switch choice {
        case .fiveSeconds: L10n.string("automation.delay.5seconds", table: .automation)
        case .tenSeconds: L10n.string("automation.delay.10seconds", table: .automation)
        case .oneMinute: L10n.string("automation.delay.1minute", table: .automation)
        case .custom: L10n.string("automation.duration.custom", table: .automation)
        }
    }

    private func intervalChoice(_ seconds: TimeInterval) -> IntervalChoice {
        IntervalChoice(rawValue: Int(seconds)) ?? .custom
    }

    private func setIntervalChoice(_ choice: IntervalChoice) {
        setInterval(TimeInterval(choice == .custom ? 1_800 : choice.rawValue))
    }

    private func intervalTitle(_ choice: IntervalChoice) -> String {
        switch choice {
        case .fiveMinutes: L10n.string("automation.interval.5minutes", table: .automation)
        case .tenMinutes: L10n.string("automation.interval.10minutes", table: .automation)
        case .oneHour: L10n.string("automation.interval.1hour", table: .automation)
        case .custom: L10n.string("automation.duration.custom", table: .automation)
        }
    }
}

private func integrationTitle(_ strategy: SyncIntegrationStrategy) -> String {
    switch strategy {
    case .rebase: L10n.string("automation.integration.rebase", table: .automation)
    case .merge: L10n.string("automation.integration.merge", table: .automation)
    }
}

private func integrationDescription(_ strategy: SyncIntegrationStrategy) -> String {
    switch strategy {
    case .rebase: L10n.string("automation.integration.rebase.description", table: .automation)
    case .merge: L10n.string("automation.integration.merge.description", table: .automation)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: UUID?

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    var body: some View {
        if model.recentRuns.isEmpty {
            ContentUnavailableView {
                Label {
                    Text(L10n.string("history.empty.title", table: .history))
                        .foregroundStyle(palette.primaryText)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(palette.mutedText)
                }
            } description: {
                Text(L10n.string("history.empty.message", table: .history))
                    .foregroundStyle(palette.secondaryText)
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
                        ContentUnavailableView {
                            Label {
                                Text(L10n.string("history.select.title", table: .history))
                                    .foregroundStyle(palette.primaryText)
                            } icon: {
                                Image(systemName: "sidebar.left")
                                    .foregroundStyle(palette.mutedText)
                            }
                        }
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
                if let automationRuleName = run.automationRuleName {
                    LabeledContent(
                        L10n.string("history.automationRule", table: .history),
                        value: automationRuleName
                    )
                }
                if let integrationStrategy = run.integrationStrategy {
                    LabeledContent(
                        L10n.string("history.integrationStrategy", table: .history),
                        value: integrationTitle(integrationStrategy)
                    )
                }
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
