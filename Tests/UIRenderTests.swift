import AppKit
import SwiftUI
import XCTest
@testable import obsSync

@MainActor
final class UIRenderTests: XCTestCase {
    func testMenuBarRepositoryListHasVisibleBoundedHeight() {
        XCTAssertEqual(MenuBarView.repositoryListHeight(for: 0), 0)
        XCTAssertEqual(MenuBarView.repositoryListHeight(for: 1), 80)
        XCTAssertEqual(MenuBarView.repositoryListHeight(for: 3), 208)
        XCTAssertEqual(MenuBarView.repositoryListHeight(for: 20), 360)
    }

    func testMenuBarIconIsAvailableAsOriginalColorArtwork() throws {
        let icon = try XCTUnwrap(NSImage(named: "MenuBarIcon"))

        XCTAssertFalse(icon.isTemplate)
        XCTAssertGreaterThan(icon.size.width, 0)
        XCTAssertGreaterThan(icon.size.height, 0)
    }

    func testSettingsWindowUsesImmersiveChrome() throws {
        let defaults = UserDefaults.standard
        let originalTheme = defaults.string(forKey: AppTheme.defaultsKey)
        defer {
            if let originalTheme {
                defaults.set(originalTheme, forKey: AppTheme.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppTheme.defaultsKey)
            }
        }

        let model = AppModel()
        model.setAppTheme(.dark)
        let window = SettingsWindowController.makeWindow(model: model)
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertNil(window.toolbar)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertNotNil(window.standardWindowButton(.closeButton))
        XCTAssertNotNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNotNil(window.standardWindowButton(.zoomButton))

        let frameView = try XCTUnwrap(window.contentView?.superview)
        XCTAssertEqual(frameView.bounds.size, window.contentView?.bounds.size)
        try render(frameView, to: URL(fileURLWithPath: "/tmp/obsSync-settings-window-dark.png"))

        model.setAppTheme(.light)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        try render(frameView, to: URL(fileURLWithPath: "/tmp/obsSync-settings-window-light.png"))
    }

    func testDarkSettingsPaletteMeetsContrastTargets() throws {
        let palette = SettingsPalette(colorScheme: .dark)

        XCTAssertGreaterThanOrEqual(
            try contrastRatio(palette.primaryText, palette.contentBackground),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            try contrastRatio(palette.secondaryText, palette.contentBackground),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            try contrastRatio(palette.navigationText, palette.sidebarBackground),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            try contrastRatio(palette.selectionForeground, palette.selectionBackground),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            try contrastRatio(palette.selectionBackground, palette.sidebarBackground),
            3.0
        )
    }

    func testRenderRefinedDarkSettingsForVisualReview() throws {
        let defaults = UserDefaults.standard
        let originalLanguage = defaults.string(forKey: AppLanguage.defaultsKey)
        let originalTheme = defaults.string(forKey: AppTheme.defaultsKey)
        defer {
            if let originalLanguage {
                defaults.set(originalLanguage, forKey: AppLanguage.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.defaultsKey)
            }
            if let originalTheme {
                defaults.set(originalTheme, forKey: AppTheme.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppTheme.defaultsKey)
            }
        }

        let model = AppModel()
        model.setAppLanguage(.simplifiedChinese)
        model.setAppTheme(.dark)
        model.selectedSettingsSection = .automation

        try render(
            SettingsRootView(model: model)
                .environment(\.locale, model.appLanguage.locale)
                .environment(\.colorScheme, .dark),
            size: CGSize(width: 960, height: 640),
            to: URL(fileURLWithPath: "/tmp/FloderSync-settings-dark-refined.png")
        )
    }

    func testRenderMenuBarEmptyStatesForVisualReview() throws {
        let model = AppModel()

        try render(
            MenuBarView(model: model)
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .light)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 360, height: 340),
            to: URL(fileURLWithPath: "/tmp/obsSync-menu-en.png")
        )
        try render(
            MenuBarView(model: model)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.colorScheme, .dark)
                .background(Color.black),
            size: CGSize(width: 360, height: 340),
            to: URL(fileURLWithPath: "/tmp/obsSync-menu-zh.png")
        )
    }

    func testRenderSettingsEmptyStateForVisualReview() throws {
        let model = AppModel()

        try render(
            SettingsRootView(model: model)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.colorScheme, .light),
            size: CGSize(width: 960, height: 640),
            to: URL(fileURLWithPath: "/tmp/obsSync-settings-zh.png")
        )
        try render(
            SettingsRootView(model: model)
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .dark),
            size: CGSize(width: 960, height: 640),
            to: URL(fileURLWithPath: "/tmp/obsSync-settings-en-dark.png")
        )
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        to url: URL
    ) throws {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let representation = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }

    private func render(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }

    private func contrastRatio(_ foreground: Color, _ background: Color) throws -> CGFloat {
        let foregroundColor = try XCTUnwrap(NSColor(foreground).usingColorSpace(.sRGB))
        let backgroundColor = try XCTUnwrap(NSColor(background).usingColorSpace(.sRGB))
        let foregroundLuminance = relativeLuminance(foregroundColor)
        let backgroundLuminance = relativeLuminance(backgroundColor)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(color.redComponent)
            + 0.7152 * linearized(color.greenComponent)
            + 0.0722 * linearized(color.blueComponent)
    }
}
