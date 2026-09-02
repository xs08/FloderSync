import AppKit
import SwiftUI
import XCTest
@testable import obsSync

@MainActor
final class UIRenderTests: XCTestCase {
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
}
