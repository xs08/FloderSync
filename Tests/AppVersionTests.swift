import Foundation
import XCTest
@testable import floderSync

final class AppVersionTests: XCTestCase {
    func testAppVersionReadsTheBundledSemanticVersion() {
        let version = AppVersion.current.semanticVersion
        let components = version.split(separator: ".", omittingEmptySubsequences: false)

        XCTAssertEqual(components.count, 3)
        XCTAssertTrue(components.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        XCTAssertEqual(
            version,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }

    func testAppVersionFallsBackWhenBundleValueIsMissingOrEmpty() {
        XCTAssertEqual(
            AppVersion(infoDictionary: nil).semanticVersion,
            AppVersion.fallbackSemanticVersion
        )
        XCTAssertEqual(
            AppVersion(infoDictionary: ["CFBundleShortVersionString": "  "]).semanticVersion,
            AppVersion.fallbackSemanticVersion
        )
    }
}
