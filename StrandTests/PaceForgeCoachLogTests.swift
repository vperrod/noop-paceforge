import XCTest
@testable import Strand

final class PaceForgeCoachLogTests: XCTestCase {
    private let sample = Data("""
    [
      {"ts": "2026-11-08T07:30:00Z", "kind": "brief", "title": "Synthetic brief", "text": "Easy day."},
      {"ts": "2026-11-08T05:00:00.250Z", "kind": "mystery", "title": "Odd", "text": ""},
      {"ts": "2026-11-05T09:00:00Z", "kind": "failure", "title": "Old", "text": "x"},
      {"ts": "not a time", "kind": "chat", "title": "Bad", "text": "x"}
    ]
    """.utf8)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date { ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")! }

    func testParseDropsRowsWithoutATimeAndSortsNewestFirst() {
        XCTAssertEqual(PFCoachLog.parse(sample).map(\.title), ["Synthetic brief", "Odd", "Old"])
    }

    func testUnknownKindShowsCapitalised() {
        XCTAssertEqual(PFCoachLog.parse(sample)[1].kindLabel, "Mystery")
    }

    func testKnownKindUsesItsLabel() {
        XCTAssertEqual(PFCoachLog.parse(sample)[0].kindLabel, "Daily brief")
    }

    func testThreeDayWindowKeepsOnlyTodaysGroup() {
        let days = PFCoachLog.days(PFCoachLog.parse(sample), last: 3, now: now, calendar: utc)
        XCTAssertEqual(days.map { $0.entries.count }, [2])
    }

    func testFourteenDayWindowKeepsTheOlderDay() {
        let days = PFCoachLog.days(PFCoachLog.parse(sample), last: 14, now: now, calendar: utc)
        XCTAssertEqual(days.map { $0.entries.count }, [2, 1])
    }

    func testGarbageParsesToEmpty() {
        XCTAssertEqual(PFCoachLog.parse(Data("{}".utf8)), [])
    }
}
