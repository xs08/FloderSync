import SwiftUI

@main
struct FloderSyncApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .environment(\.locale, model.appLanguage.locale)
                .preferredColorScheme(model.appTheme.preferredColorScheme)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)

                menuBarStatusBadge
            }
            .frame(width: 20, height: 18)
                .accessibilityLabel(Text("app.name"))
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("settings.open") {
                    SettingsWindowController.shared.show(model: model)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var menuBarStatusBadge: some View {
        switch model.overallState {
        case .ready:
            EmptyView()
        case .syncing:
            statusDot(color: .accentColor)
        case .problems:
            statusDot(color: .red)
        }
    }

    private func statusDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 0.8))
            .frame(width: 6, height: 6)
            .offset(x: 1, y: 1)
    }
}
