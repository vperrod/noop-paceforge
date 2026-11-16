import XCTest

/// Build 530: when Today shows the Sunday review row, and for which week. The dates are invented (2030-03-10 is a Sunday).
final class PFTodayReviewWindow530Tests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour, minute: minute))!
    }

    private func isOpen(_ now: Date, windDown: Int? = 22 * 60) -> Bool {
        PFTodayReviewWindow530.isOpen(now: now, windDownMinutes: windDown, calendar: calendar)
    }

    func testClosedOnSundayBeforeTheWindDownTime() {
        XCTAssertFalse(isOpen(date(10, 21, 59)))
    }

    func testOpenOnSundayFromTheWindDownTime() {
        XCTAssertTrue(isOpen(date(10, 22)))
    }

    func testOpenOnMondayMorning() {
        XCTAssertTrue(isOpen(date(11, 11, 59)))
    }

    func testClosedOnMondayFromNoon() {
        XCTAssertFalse(isOpen(date(11, 12)))
    }

    func testClosedOnATuesday() {
        XCTAssertFalse(isOpen(date(12, 8)))
    }

    func testSundayWithoutAWindDownTimeUsesNinePm() {
        XCTAssertTrue(isOpen(date(10, 21), windDown: nil))
    }

    func testLatestFinishedWeekIsTheOneEndingLastOnOrBeforeToday() {
        let weeks = [
            PFPlanWeekIndexDoc.Week(week: "2030-W09", to: "2030-03-03"),
            PFPlanWeekIndexDoc.Week(week: "2030-W10", to: "2030-03-10"),
            PFPlanWeekIndexDoc.Week(week: "2030-W11", to: "2030-03-17"),
        ]
        XCTAssertEqual(PFTodayReviewWindow530.latestFinishedWeek(weeks, today: "2030-03-11"), "2030-W10")
    }

    func testNoFinishedWeekWhenNoneHasEnded() {
        let weeks = [PFPlanWeekIndexDoc.Week(week: "2030-W11", to: "2030-03-17")]
        XCTAssertNil(PFTodayReviewWindow530.latestFinishedWeek(weeks, today: "2030-03-11"))
    }
}
