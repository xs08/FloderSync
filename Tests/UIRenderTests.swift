import AppKit
import SwiftUI
import XCTest
@testable import obsSync

@MainActor
final class UIRenderTests: XCTestCase {
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
}
