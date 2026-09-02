import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            repositoryContent
            Divider()
            footer
        }
        .frame(width: 360)
        .task { model.start() }
        .alert("error.title", isPresented: errorIsPresented) {
            Button("action.ok", role: .cancel) { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title2)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("app.name")
                    .font(.headline)
                Text(statusKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.syncAll()
            } label: {
                Label("sync.all", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(model.profiles.isEmpty || model.overallState == .syncing)
        }
        .padding(16)
    }

    @ViewBuilder
    private var repositoryContent: some View {
        if model.profiles.isEmpty {
            ContentUnavailableView {
                Label("repositories.empty.title", systemImage: "externaldrive.badge.plus")
            } description: {
                Text("repositories.empty.message")
            } actions: {
                Button("settings.open") { openSettings() }
            }
            .frame(minHeight: 210)
            .padding(.horizontal, 20)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.profiles) { profile in
                        RepositoryRow(profile: profile, model: model)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 360)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Label("settings.open", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Button("app.quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(14)
    }

    private var statusSymbol: String {
        switch model.overallState {
        case .ready: "checkmark.circle.fill"
        case .syncing: "arrow.triangle.2.circlepath.circle.fill"
        case .problems: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch model.overallState {
        case .ready: .green
        case .syncing: .accentColor
        case .problems: .orange
        }
    }

    private var statusKey: LocalizedStringKey {
        switch model.overallState {
        case .ready: "status.ready"
        case .syncing: "status.syncing"
        case .problems: "status.problems"
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )
    }
}

private struct RepositoryRow: View {
    let profile: SyncProfile
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rowSymbol)
                .foregroundStyle(rowColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.sync(profile)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .disabled(model.syncingProfileIDs.contains(profile.id))
            .accessibilityLabel(Text("sync.repository"))
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var rowSymbol: String {
        if model.syncingProfileIDs.contains(profile.id) { return "arrow.triangle.2.circlepath" }
        switch model.latestRun(for: profile)?.result {
        case .failed, .needsUserAction: return "exclamationmark.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        default: return "circle.dashed"
        }
    }

    private var rowColor: Color {
        switch model.latestRun(for: profile)?.result {
        case .failed, .needsUserAction: .orange
        case .succeeded: .green
        default: .secondary
        }
    }

    private var detailText: String {
        guard let run = model.latestRun(for: profile) else {
            return String(localized: "repository.neverSynced")
        }
        return run.finishedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
