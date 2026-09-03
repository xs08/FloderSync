import Foundation
import XCTest
@testable import floderSync

final class ConfigurationArchiveTests: XCTestCase {
    func testJSONRoundTripPreservesSettingsAndNormalizesDailyTimes() async throws {
        let earlier = try DailyTime(hour: 8, minute: 0)
        let later = try DailyTime(hour: 18, minute: 30)
        let rule = AutomationRule(
            name: "Daily",
            configuration: AutomationConfiguration(policies: [.daily(times: [later, earlier])])
        )
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/notes",
            automationRuleID: rule.id
        )
        let archive = ConfigurationArchive(
            profiles: [profile],
            automationRules: [rule],
            settings: ArchivedAppSettings(
                launchAtLogin: true,
                notifyOnFailure: false,
                language: .simplifiedChinese,
                theme: .dark
            )
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("configuration.json")
        let coder = JSONConfigurationArchiveCoder()

        try await coder.write(archive, to: url)
        let decodedArchive = try await coder.read(from: url)
        let decoded = try decodedArchive.validated()

        XCTAssertEqual(decoded.profiles, [profile])
        XCTAssertEqual(decoded.automationRules.first?.configuration.dailyTimes, [earlier, later])
        XCTAssertEqual(decoded.settings, archive.settings)
    }

    func testValidationRejectsDanglingAutomationRuleReference() {
        let archive = ConfigurationArchive(
            profiles: [
                SyncProfile(
                    name: "Notes",
                    localPath: "/tmp/notes",
                    automationRuleID: UUID()
                )
            ],
            automationRules: [],
            settings: ArchivedAppSettings(
                launchAtLogin: false,
                notifyOnFailure: true,
                language: .system,
                theme: .system
            )
        )

        XCTAssertThrowsError(try archive.validated()) { error in
            XCTAssertEqual(error as? ConfigurationArchiveError, .missingAutomationRule)
        }
    }
}
