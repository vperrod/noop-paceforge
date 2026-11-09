import XCTest
@testable import StrandAnalytics

final class SleepRegularityTests: XCTestCase {
    private let day = 86_400
    private let hour = 3_600

    /// A night 23:00 to 07:00 around local midnight `k` (day `k` of the fixture, UTC).
    private func regular(_ k: Int) -> SleepRegularity.Span {
        SleepRegularity.Span(start: k * day - hour, end: k * day + 7 * hour)
    }

    /// The same night, two hours later: 01:00 to 09:00.
    private func shifted(_ k: Int) -> SleepRegularity.Span {
        SleepRegularity.Span(start: k * day + hour, end: k * day + 9 * hour)
    }

    /// Fourteen days (0 to 13) ending at 08:00 on day 13, after that morning's wake.
    private var endTs: Int { 13 * day + 8 * hour }

    func testTheSamePatternEveryDayReadsFullyRegular() {
        let spans = (0...13).map(regular)
        let reading = SleepRegularity.reading(spans: spans, endingAt: endTs)
        XCTAssertEqual(reading?.matchPercent ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(reading?.sri ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(reading?.nights, 14)
    }

    func testOneNightTwoHoursLaterCostsExactlyTheMismatchedMinutes() {
        // 48 five-minute points differ from the usual pattern; each sits in two 24-hour pairs, out of 3552 pairs.
        let spans = (0...13).map { $0 == 7 ? shifted($0) : regular($0) }
        let reading = SleepRegularity.reading(spans: spans, endingAt: endTs)
        XCTAssertEqual(reading?.matchPercent ?? 0, 100.0 * 3456.0 / 3552.0, accuracy: 0.001)
        XCTAssertEqual(reading?.sri ?? 0, -100 + 200.0 * 3456.0 / 3552.0, accuracy: 0.001)
    }

    func testTheSameWindowShiftedByTheClockOffsetReadsTheSame() {
        let offset = 3 * hour
        let spans = (0...13).map(regular)
        let reading = SleepRegularity.reading(spans: spans, endingAt: endTs, tzOffsetSeconds: offset)
        XCTAssertEqual(reading?.matchPercent ?? 0, 100, accuracy: 0.0001)
    }

    func testFewerThanFiveNightsGivesNoReading() {
        let spans = (10...13).map(regular)
        XCTAssertNil(SleepRegularity.reading(spans: spans, endingAt: endTs))
    }

    func testNapsDoNotCountAsNights() {
        let naps = (0...13).map { SleepRegularity.Span(start: $0 * day + 14 * hour, end: $0 * day + 15 * hour) }
        XCTAssertNil(SleepRegularity.reading(spans: naps, endingAt: endTs))
    }

    func testNoSpansGivesNoReading() {
        XCTAssertNil(SleepRegularity.reading(spans: [], endingAt: endTs))
    }

    func testDayStartFloorsForNegativeLocalTimes() {
        XCTAssertEqual(SleepRegularity.dayStart(-1, tz: 0), -day)
        XCTAssertEqual(SleepRegularity.dayStart(day + 5, tz: 0), day)
        XCTAssertEqual(SleepRegularity.dayStart(day - 1, tz: 3_600), day - 3_600)
    }

    // MARK: Own baseline

    /// Eight weeks (day 0 to 69) of regular nights, ending 08:00 on day 69, with `irregular` days shifted two hours later.
    private func weeks(irregular: Set<Int>) -> [SleepRegularity.Span] {
        (0...69).map { irregular.contains($0) ? shifted($0) : regular($0) }
    }

    private var weeksEnd: Int { 69 * day + 8 * hour }

    func testAnUnchangedPatternReadsUsualAgainstItsOwnBaseline() {
        let assessment = SleepRegularity.assess(spans: weeks(irregular: []), endingAt: weeksEnd)
        XCTAssertEqual(assessment?.trend, .usual)
        XCTAssertEqual(assessment?.baselinePercent ?? 0, 100, accuracy: 0.0001)
    }

    func testAMessyRecentFortnightAgainstSteadyEarlierWeeksReadsLessSteady() {
        let messy = Set(stride(from: 58, through: 68, by: 2))
        let assessment = SleepRegularity.assess(spans: weeks(irregular: messy), endingAt: weeksEnd)
        XCTAssertEqual(assessment?.trend, .lessSteady)
    }

    func testASteadyRecentFortnightAfterMessyEarlierWeeksReadsSteadier() {
        let messy = Set(stride(from: 0, through: 55, by: 2))
        let assessment = SleepRegularity.assess(spans: weeks(irregular: messy), endingAt: weeksEnd)
        XCTAssertEqual(assessment?.trend, .steadier)
    }

    func testTooLittleHistoryGivesAReadingButNoComparison() {
        let spans = (0...13).map(regular)
        let assessment = SleepRegularity.assess(spans: spans, endingAt: endTs)
        XCTAssertNotNil(assessment?.reading)
        XCTAssertNil(assessment?.trend)
    }
}
