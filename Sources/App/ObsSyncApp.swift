import SwiftUI

@main
struct FloderSyncApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .environment(\.locale, model.appLanguage.locale)
                .preferredColorScheme(preferredColorScheme)
        } label: {
            Image(systemName: menuBarSymbol)
                .accessibilityLabel(Text("app.name"))
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: model)
                .environment(\.locale, model.appLanguage.locale)
                .preferredColorScheme(preferredColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
    }

    private var menuBarSymbol: String {
        switch model.overallState {
        case .ready: "arrow.triangle.2.circlepath"
        case .syncing: "arrow.triangle.2.circlepath.circle.fill"
        case .problems: "exclamationmark.triangle.fill"
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.appTheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
