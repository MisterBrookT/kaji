import XCTest
import KajiCore

final class MailBriefSchedulePolicyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    func testBeforeDailyTimeIsNotDue() {
        let now = date(2026, 8, 8, 8, 30)
        XCTAssertFalse(MailBriefSchedulePolicy.decision(now: now, hour: 9, minute: 0, calendar: calendar,
                                                        lastAutomaticSuccess: nil).isDue)
    }

    func testAfterDailyTimeIsDueOnce() {
        let now = date(2026, 8, 8, 11, 0)
        XCTAssertTrue(MailBriefSchedulePolicy.decision(now: now, hour: 9, minute: 0, calendar: calendar,
                                                       lastAutomaticSuccess: nil).isDue)
        XCTAssertFalse(MailBriefSchedulePolicy.decision(now: now, hour: 9, minute: 0, calendar: calendar,
                                                        lastAutomaticSuccess: date(2026, 8, 8, 9, 5)).isDue)
    }

    func testTwelveHourGuardPreventsTimezoneDoubleRun() {
        let now = date(2026, 8, 8, 21, 0)
        let recent = now.addingTimeInterval(-11 * 3600)
        XCTAssertFalse(MailBriefSchedulePolicy.decision(now: now, hour: 9, minute: 0, calendar: calendar,
                                                        lastAutomaticSuccess: recent).isDue)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: minute))!
    }
}
