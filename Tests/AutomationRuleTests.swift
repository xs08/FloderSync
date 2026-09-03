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
                    .newCommits,
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
            policies: [.interval(seconds: 300)],
            integrationStrategy: .rebase,
            automaticCommit: AutomaticCommitConfiguration(
                isEnabled: false,
                messageTemplate: "Custom"
            ),
            automationRuleID: ruleID
        )

        let resolved = try XCTUnwrap(profile.resolved(using: [rule]))

        XCTAssertTrue(resolved.watchesNewCommits)
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

    func testDailyTimesAreSortedOnlyWhenConfigurationIsSaved() throws {
        let times = [
            try DailyTime(hour: 18, minute: 0),
            try DailyTime(hour: 8, minute: 30),
            try DailyTime(hour: 12, minute: 0)
        ]
        let configuration = AutomationConfiguration(policies: [.daily(times: times)])

        XCTAssertEqual(configuration.dailyTimes, times)
        XCTAssertEqual(
            try configuration.normalizedForSaving().dailyTimes,
            times.sorted()
        )
    }

    func testDuplicateDailyTimesPreventSaving() throws {
        let time = try DailyTime(hour: 23, minute: 0)
        let configuration = AutomationConfiguration(policies: [.daily(times: [time, time])])

        XCTAssertThrowsError(try configuration.normalizedForSaving()) { error in
            XCTAssertEqual(error as? SyncConfigurationError, .duplicateDailyTime)
        }
    }

    func testSuggestedDailyTimesStartAtMidnightAndAdvanceUntilTwentyThreeHundred() throws {
        let midnight = try DailyTime.suggestedAfter(nil)
        let oneAM = try DailyTime.suggestedAfter(midnight)
        let capped = try DailyTime.suggestedAfter(try DailyTime(hour: 23, minute: 0))

        XCTAssertEqual(midnight, try DailyTime(hour: 0, minute: 0))
        XCTAssertEqual(oneAM, try DailyTime(hour: 1, minute: 0))
        XCTAssertEqual(capped, try DailyTime(hour: 23, minute: 0))
    }
}
