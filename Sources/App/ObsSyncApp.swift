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
            Image(systemName: menuBarSymbol)
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

    private var menuBarSymbol: String {
        switch model.overallState {
        case .ready: "arrow.triangle.2.circlepath"
        case .syncing: "arrow.triangle.2.circlepath.circle.fill"
        case .problems: "exclamationmark.triangle.fill"
        }
    }
}
