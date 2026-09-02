import XCTest
@testable import obsSync

final class CatchUpCalculatorTests: XCTestCase {
    func testIntervalCatchesUpOnceThresholdIsExceeded() {
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/Notes",
            policies: [.interval(seconds: 300)]
        )
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(CatchUpCalculator.shouldRunCatchUp(
            profile: profile,
            lastRunAt: Date(timeIntervalSince1970: 600),
            now: now
        ))
        XCTAssertFalse(CatchUpCalculator.shouldRunCatchUp(
            profile: profile,
            lastRunAt: Date(timeIntervalSince1970: 800),
            now: now
        ))
    }

    func testNeverRunProfileDoesNotCatchUp() {
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/Notes",
            policies: [.interval(seconds: 300)]
        )

        XCTAssertFalse(CatchUpCalculator.shouldRunCatchUp(profile: profile, lastRunAt: nil))
    }

    func testDailyPolicyDetectsMissedTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let profile = SyncProfile(
            name: "Notes",
            localPath: "/tmp/Notes",
            policies: [.daily(times: [try DailyTime(hour: 9, minute: 0)])]
        )
        let lastRun = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 1, hour: 18
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2, hour: 10
        )))

        XCTAssertTrue(CatchUpCalculator.shouldRunCatchUp(
            profile: profile,
            lastRunAt: lastRun,
            now: now,
            calendar: calendar
        ))
    }
}
