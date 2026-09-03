import XCTest
@testable import floderSync

final class AutomationRuleTests: XCTestCase {
    func testReferencedRuleOverridesCustomConfigurationAtRuntime() throws {
        let ruleID = UUID()
        let rule = AutomationRule(
            id: ruleID,
            name: "Rule 1",
            configuration: AutomationConfiguration(
                policies: [
                    .fileChanges(debounceSeconds: 10),
                    .interval(seconds: 600)
                ],
                integrationStrategy: .merge,
                automaticCommit: AutomaticCommitConfiguration(
                    authorName: "Rule User",
                    authorEmail: "rule@example.com",
                    messageTemplate: "Rule ${time}"
                )
            )
        )
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/Notes",
            policies: [.fileChanges(debounceSeconds: 5)],
            integrationStrategy: .rebase,
            automaticCommit: AutomaticCommitConfiguration(
                isEnabled: false,
                messageTemplate: "Custom"
            ),
            automationRuleID: ruleID
        )

        let resolved = try XCTUnwrap(profile.resolved(using: [rule]))

        XCTAssertEqual(resolved.fileChangeDebounceSeconds, 10)
        XCTAssertEqual(resolved.intervalSeconds, 600)
        XCTAssertEqual(resolved.integrationStrategy, .merge)
        XCTAssertTrue(resolved.automaticCommit.isEnabled)
        XCTAssertEqual(resolved.automaticCommit.authorName, "Rule User")
        XCTAssertEqual(resolved.automaticCommit.authorEmail, "rule@example.com")
        XCTAssertEqual(resolved.automaticCommit.messageTemplate, "Rule ${time}")
        XCTAssertEqual(resolved.automationRuleID, ruleID)
    }

    func testCustomRepositoryIsIndependentFromRules() throws {
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/Notes",
            policies: [.interval(seconds: 300)],
            integrationStrategy: .rebase,
            automaticCommit: AutomaticCommitConfiguration(
                isEnabled: false,
                messageTemplate: "Repository only"
            )
        )
        let unrelatedRule = AutomationRule(
            name: "Rule 1",
            configuration: AutomationConfiguration(
                policies: [.daily(times: [try DailyTime(hour: 8, minute: 0)])],
                integrationStrategy: .merge
            )
        )

        let resolved = try XCTUnwrap(profile.resolved(using: [unrelatedRule]))

        XCTAssertEqual(resolved.intervalSeconds, 300)
        XCTAssertEqual(resolved.integrationStrategy, .rebase)
        XCTAssertFalse(resolved.automaticCommit.isEnabled)
        XCTAssertEqual(resolved.automaticCommit.messageTemplate, "Repository only")
    }

    func testMissingRuleFailsClosedForAutomaticResolution() {
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/Notes",
            automationRuleID: UUID()
        )

        XCTAssertNil(profile.resolved(using: []))
    }
}
