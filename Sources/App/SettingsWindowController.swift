import AppKit
import SwiftUI

/// Owns the settings window so its AppKit chrome is configured before the first visible frame.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(model: AppModel) {
        if window == nil {
            window = Self.makeWindow(model: model)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func makeWindow(model: AppModel) -> NSWindow {
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        // Configure the titlebar before attaching or displaying SwiftUI content. Keeping the
        // titled mask preserves standard window controls; full-size content plus a transparent
        // titlebar removes the separate titlebar material and lets the root view paint behind it.
        window.title = L10n.string("settings.title", table: .settings)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 560)
        window.setFrameAutosaveName("FloderSyncSettingsWindow")

        let rootView = SettingsWindowContent(model: model)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        return window
    }
}

private struct SettingsWindowContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsRootView(model: model)
            .environment(\.locale, model.appLanguage.locale)
            .preferredColorScheme(model.appTheme.preferredColorScheme)
    }
}

extension AppTheme {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
