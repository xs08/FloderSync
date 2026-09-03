import XCTest
@testable import floderSync

final class ScheduleCalculatorTests: XCTestCase {
    func testNextDailyDateChoosesLaterTimeToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2, hour: 10, minute: 30
        )))
        let times = [try DailyTime(hour: 9, minute: 0), try DailyTime(hour: 18, minute: 0)]

        let next = ScheduleCalculator.nextDailyDate(after: now, times: times, calendar: calendar)

        XCTAssertEqual(
            next,
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 18, minute: 0))
        )
    }

    func testNextDailyDateRollsToTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2, hour: 22, minute: 0
        )))
        let times = [try DailyTime(hour: 9, minute: 0)]

        let next = ScheduleCalculator.nextDailyDate(after: now, times: times, calendar: calendar)

        XCTAssertEqual(
            next,
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 9, minute: 0))
        )
    }
}
