import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            RepositorySettingsView(model: model)
                .tabItem { Label("settings.repositories", systemImage: "externaldrive") }
            AutomationSettingsView(model: model)
                .tabItem { Label("settings.automation", systemImage: "clock") }
            GeneralSettingsView(model: model)
                .tabItem { Label("settings.general", systemImage: "gearshape") }
            HistorySettingsView(model: model)
                .tabItem { Label("settings.diagnostics", systemImage: "waveform.path.ecg") }
        }
        .frame(width: 720, height: 480)
        .task { model.start() }
        .alert("error.title", isPresented: errorIsPresented) {
            Button("action.ok", role: .cancel) { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )
    }
}

private struct RepositorySettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: UUID?
    @State private var pendingRemoval: SyncProfile?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.profiles) { profile in
                    HStack(spacing: 8) {
                        Image(systemName: profile.isEnabled ? "externaldrive.fill" : "externaldrive")
                            .foregroundStyle(profile.isEnabled ? Color.accentColor : .secondary)
                        Text(profile.name)
                            .lineLimit(1)
                    }
                    .tag(profile.id)
                }
            }
            .navigationTitle("settings.repositories")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(action: chooseRepository) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("repository.add"))
                    Button(action: removeSelection) {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .accessibilityLabel(Text("repository.remove"))
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(10)
                .background(.bar)
            }
            .frame(minWidth: 220)
            .alert("repository.remove.confirm.title", isPresented: removalIsPresented) {
                Button("action.cancel", role: .cancel) { pendingRemoval = nil }
                Button("repository.remove", role: .destructive) {
                    guard let pendingRemoval else { return }
                    model.removeProfile(id: pendingRemoval.id)
                    selection = nil
                    self.pendingRemoval = nil
                }
            } message: {
                Text("repository.remove.confirm.message")
            }
        } detail: {
            if let profile = selectedProfile {
                RepositoryDetailView(profile: profile, model: model)
            } else {
                ContentUnavailableView {
                    Label("repository.select.title", systemImage: "sidebar.left")
                } description: {
                    Text("repository.select.message")
                }
            }
        }
    }

    private var selectedProfile: SyncProfile? {
        guard let selection else { return nil }
        return model.profiles.first(where: { $0.id == selection })
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "repository.picker.title")
        panel.prompt = String(localized: "repository.picker.action")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if await model.addRepository(at: url) {
                selection = model.profiles.first(where: { $0.localPath == url.path })?.id
            }
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
}

private struct RepositoryDetailView: View {
    let profile: SyncProfile
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("repository.section.identity") {
                LabeledContent("repository.name") {
                    TextField(
                        "repository.name",
                        text: Binding(
                            get: { profile.name },
                            set: { model.setProfileName(id: profile.id, name: $0) }
                        )
                    )
                    .labelsHidden()
                }
                LabeledContent("repository.path") {
                    Text(profile.localPath)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                LabeledContent("repository.remote") {
                    TextField(
                        "repository.remote",
                        text: Binding(
                            get: { profile.remoteName },
                            set: { model.setRemoteName(id: profile.id, remoteName: $0) }
                        )
                    )
                    .labelsHidden()
                }
            }

            Section("repository.section.behavior") {
                Toggle(
                    "repository.enabled",
                    isOn: Binding(
                        get: { profile.isEnabled },
                        set: { model.setProfileEnabled(id: profile.id, enabled: $0) }
                    )
                )
                LabeledContent("repository.branchPolicy", value: String(localized: "repository.currentBranch"))
                LabeledContent("repository.commitTemplate") {
                    TextField(
                        "repository.commitTemplate",
                        text: Binding(
                            get: { profile.commitMessageTemplate },
                            set: { model.setCommitMessageTemplate(id: profile.id, template: $0) }
                        )
                    )
                    .labelsHidden()
                }
            }

            Section {
                HStack {
                    Button("sync.repository") { model.sync(profile) }
                        .disabled(model.syncingProfileIDs.contains(profile.id))
                    Button("repository.checkConnection") { model.checkConnection(for: profile) }
                        .disabled(
                            profile.remoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            model.connectionChecks[profile.id] == .checking
                        )
                    if model.connectionChecks[profile.id] == .succeeded {
                        Label("repository.connection.succeeded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle(profile.name)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("general.startup.section") {
                Toggle(
                    "general.launchAtLogin",
                    isOn: Binding(
                        get: { model.launchAtLoginStatus == .enabled },
                        set: { enabled in model.setLaunchAtLogin(enabled) }
                    )
                )
                if model.launchAtLoginStatus == .requiresApproval {
                    LabeledContent {
                        Button("general.openLoginItems") { model.openLoginItemsSettings() }
                    } label: {
                        Label("general.approvalRequired", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("general.notifications.section") {
                Toggle(
                    "general.notifyOnFailure",
                    isOn: Binding(
                        get: { model.notifyOnFailure },
                        set: { enabled in model.setNotifyOnFailure(enabled) }
                    )
                )
            }

            Section("general.language.section") {
                LabeledContent("general.language") {
                    Text("general.language.system")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
}

private struct AutomationSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.profiles.isEmpty {
            ContentUnavailableView {
                Label("repositories.empty.title", systemImage: "clock.badge.exclamationmark")
            } description: {
                Text("automation.empty.message")
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
                    "automation.fileChanges",
                    isOn: Binding(
                        get: { profile.watchesFileChanges },
                        set: { model.setFileChangeSync(id: profile.id, enabled: $0) }
                    )
                )

                Picker(
                    "automation.interval",
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
                    Text("automation.repositoryDisabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!profile.isEnabled)
    }

    private func intervalLabel(_ interval: TimeInterval?) -> String {
        guard let interval else { return String(localized: "automation.interval.off") }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return String(format: String(localized: "automation.interval.minutes"), minutes)
        }
        return String(format: String(localized: "automation.interval.hours"), minutes / 60)
    }
}

private struct DailyTimesEditor: View {
    let times: [DailyTime]
    let onChange: ([DailyTime]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("automation.daily")
                Spacer()
                Button {
                    addTime()
                } label: {
                    Label("automation.daily.add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if times.isEmpty {
                Text("automation.daily.off")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                    HStack {
                        DatePicker(
                            "automation.daily.time",
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
                        .accessibilityLabel(Text("automation.daily.remove"))
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
                Label("history.empty.title", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("history.empty.message")
            }
            .padding(24)
        } else {
            NavigationSplitView {
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
                .navigationTitle("settings.diagnostics")
                .frame(minWidth: 250)
            } detail: {
                if let run = selectedRun {
                    SyncRunDetailView(run: run, profileName: profileName(for: run))
                } else {
                    ContentUnavailableView("history.select.title", systemImage: "sidebar.left")
                }
            }
        }
    }

    private var selectedRun: SyncRunRecord? {
        guard let selection else { return nil }
        return model.recentRuns.first(where: { $0.id == selection })
    }

    private func profileName(for run: SyncRunRecord) -> String {
        model.profiles.first(where: { $0.id == run.profileID })?.name
            ?? String(localized: "history.unknownRepository")
    }
}

private struct SyncRunDetailView: View {
    let run: SyncRunRecord
    let profileName: String

    var body: some View {
        Form {
            Section("history.summary") {
                LabeledContent("history.repository", value: profileName)
                LabeledContent("history.result", value: resultText(run.result))
                LabeledContent("history.trigger", value: triggerText(run.trigger))
                LabeledContent("history.started", value: run.startedAt.formatted())
                LabeledContent("history.duration", value: durationText)
            }
            Section("history.steps") {
                ForEach(run.steps, id: \.step) { record in
                    Label(stepText(record.step), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            if let message = run.failureMessage {
                Section("history.error") {
                    Text(message)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle(profileName)
    }

    private var durationText: String {
        let duration = run.finishedAt.timeIntervalSince(run.startedAt)
        return String(format: String(localized: "history.duration.seconds"), duration)
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
    case .succeeded: String(localized: "history.result.succeeded")
    case .failed: String(localized: "history.result.failed")
    case .needsUserAction: String(localized: "history.result.needsUserAction")
    case .cancelled: String(localized: "history.result.cancelled")
    }
}

private func triggerText(_ trigger: SyncTrigger) -> String {
    switch trigger {
    case .manual: String(localized: "history.trigger.manual")
    case .scheduled: String(localized: "history.trigger.scheduled")
    case .interval: String(localized: "history.trigger.interval")
    case .fileChanges: String(localized: "history.trigger.fileChanges")
    case .wakeCatchUp: String(localized: "history.trigger.wakeCatchUp")
    }
}

private func stepText(_ step: SyncStep) -> String {
    switch step {
    case .validation: String(localized: "history.step.validation")
    case .status: String(localized: "history.step.status")
    case .staging: String(localized: "history.step.staging")
    case .committing: String(localized: "history.step.committing")
    case .pulling: String(localized: "history.step.pulling")
    case .pushing: String(localized: "history.step.pushing")
    }
}
