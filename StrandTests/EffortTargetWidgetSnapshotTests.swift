import XCTest

/// The Effort target widget's feed: which snapshots are still worth drawing, and what counts as a change.
/// `WidgetSnapshot.swift` is compiled straight into this bundle.
final class EffortTargetWidgetSnapshotTests: XCTestCase {

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 6, day: d, hour: h, minute: m))!
    }

    private func snapshot(day: String?, at: Date?) -> WidgetSnapshot {
        WidgetSnapshot(recovery: 72, bpm: nil, batteryPct: nil, bonded: false, updated: at ?? Date(),
                       effortTargetEffort: 42, effortTargetEffortText: "42",
                       effortBandLow: 55, effortBandHigh: 70, effortBandText: "55\u{2013}70",
                       effortToGo: "13\u{2013}28 to go", effortTargetDay: day, effortTargetAt: at)
    }

    func testATargetBuiltForTodayAndWrittenRecentlyIsFresh() {
        let now = date(10, 14)
        XCTAssertTrue(snapshot(day: "2026-06-10", at: date(10, 12)).effortTargetIsFresh(now: now, calendar: utc))
    }

    func testYesterdaysTargetIsStale() {
        let now = date(10, 14)
        XCTAssertFalse(snapshot(day: "2026-06-09", at: date(10, 13)).effortTargetIsFresh(now: now, calendar: utc))
    }

    func testATargetOlderThanSixHoursIsStale() {
        let now = date(10, 20)
        XCTAssertFalse(snapshot(day: "2026-06-10", at: date(10, 13)).effortTargetIsFresh(now: now, calendar: utc))
    }

    func testBeforeTheFourAMRolloverTodayIsStillTheDayBefore() {
        let now = date(11, 3)
        XCTAssertTrue(snapshot(day: "2026-06-10", at: date(11, 2)).effortTargetIsFresh(now: now, calendar: utc))
    }

    func testAfterTheRolloverThePreviousDaysTargetIsStale() {
        let now = date(11, 5)
        XCTAssertFalse(snapshot(day: "2026-06-10", at: date(11, 4, 30)).effortTargetIsFresh(now: now, calendar: utc))
    }

    func testASnapshotWithoutATargetIsStale() {
        XCTAssertFalse(snapshot(day: nil, at: nil).effortTargetIsFresh(now: date(10, 14), calendar: utc))
    }

    func testASnapshotFromAnOlderBuildStillDecodes() throws {
        let old = #"{"recovery":72,"bonded":false,"updated":0}"#
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(decoded.effortBandLow)
    }

    func testTheSameTargetInTheSameHourIsNotAChange() {
        let a = snapshot(day: "2026-06-10", at: date(10, 12, 5))
        let b = snapshot(day: "2026-06-10", at: date(10, 12, 40))
        XCTAssertFalse(WidgetSnapshot.renderedContentChanged(from: a, to: b))
    }

    func testTheSameTargetAnHourLaterIsAChangeSoTheStampStaysFresh() {
        let a = snapshot(day: "2026-06-10", at: date(10, 12, 5))
        let b = snapshot(day: "2026-06-10", at: date(10, 13, 5))
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: a, to: b))
    }

    func testANewToGoSentenceIsAChange() {
        let a = snapshot(day: "2026-06-10", at: date(10, 12, 5))
        var b = a
        b.effortToGo = "In your range"
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: a, to: b))
    }
}
