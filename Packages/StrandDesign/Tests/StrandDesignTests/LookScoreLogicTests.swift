import XCTest
@testable import StrandDesign

final class LookScoreLogicTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func series(from start: Date, values: [Double]) -> [LookPoint] {
        values.enumerated().map { i, v in LookPoint(date: utc.date(byAdding: .day, value: i, to: start)!, value: v) }
    }

    // MARK: Day keys

    func testDayKeyParsesToTheStartOfThatDay() {
        XCTAssertEqual(LookDayKey.date("2026-10-14", calendar: utc), day(2026, 10, 14))
    }

    func testDayKeyIgnoresATrailingTime() {
        XCTAssertEqual(LookDayKey.date("2026-10-14T08:00:00", calendar: utc), day(2026, 10, 14))
    }

    func testDayKeyRejectsAMonthOfThirteen() {
        XCTAssertNil(LookDayKey.date("2026-13-01", calendar: utc))
    }

    func testDayKeyRejectsText() {
        XCTAssertNil(LookDayKey.date("yesterday", calendar: utc))
    }

    func testDayKeyRoundTrips() {
        XCTAssertEqual(LookDayKey.key(day(2026, 1, 5), calendar: utc), "2026-01-05")
    }

    // MARK: Series

    func testSeriesDropsRowsWithABadKeyOrValue() {
        let rows: [(day: String, value: Double)] = [("2026-10-01", 5), ("nope", 6), ("2026-10-03", .nan)]
        XCTAssertEqual(LookSeries.points(rows, calendar: utc).count, 1)
    }

    func testLatestIsTheNewestPointWhateverTheOrder() {
        let pts = [LookPoint(date: day(2026, 10, 3), value: 3), LookPoint(date: day(2026, 10, 9), value: 9),
                   LookPoint(date: day(2026, 10, 5), value: 5)]
        XCTAssertEqual(LookSeries.latest(pts)?.value, 9)
    }

    func testWithinKeepsBothEndsAndSortsOldestFirst() {
        let pts = series(from: day(2026, 10, 1), values: [1, 2, 3, 4, 5])
        let kept = LookSeries.within(pts.reversed(), from: day(2026, 10, 2), to: day(2026, 10, 4))
        XCTAssertEqual(kept.map(\.value), [2, 3, 4])
    }

    // MARK: Trailing average

    func testTrailingAverageOfASteadySeriesIsTheSeries() {
        let pts = series(from: day(2026, 10, 1), values: [4, 4, 4, 4])
        XCTAssertEqual(LookTrendStats.trailingAverage(pts, days: 7, calendar: utc).map(\.value), [4, 4, 4, 4])
    }

    func testTrailingAverageUsesOnlyTheWindowSoFarAtTheStart() {
        let pts = series(from: day(2026, 10, 1), values: [2, 4, 6])
        XCTAssertEqual(LookTrendStats.trailingAverage(pts, days: 7, calendar: utc).map(\.value), [2, 3, 4])
    }

    func testTrailingAverageDropsAPointOlderThanTheWindow() {
        let pts = series(from: day(2026, 10, 1), values: [10, 0, 0, 0, 0, 0, 0, 0])
        let last = LookTrendStats.trailingAverage(pts, days: 7, calendar: utc).last?.value
        XCTAssertEqual(last, 0)
    }

    func testTrailingAverageSkipsAGapInTheDays() {
        let pts = [LookPoint(date: day(2026, 10, 1), value: 10), LookPoint(date: day(2026, 10, 20), value: 2)]
        XCTAssertEqual(LookTrendStats.trailingAverage(pts, days: 7, calendar: utc).last?.value, 2)
    }

    func testTrailingAverageOfOneDayIsTheSeries() {
        let pts = series(from: day(2026, 10, 1), values: [1, 9])
        XCTAssertEqual(LookTrendStats.trailingAverage(pts, days: 1, calendar: utc).map(\.value), [1, 9])
    }

    // MARK: Baseline

    func testBaselineIsTheMeanOfTheThirtyDaysBeforeAndNotTheDayItself() {
        var pts = series(from: day(2026, 9, 14), values: Array(repeating: 40, count: 30))
        pts.append(LookPoint(date: day(2026, 10, 14), value: 100))
        XCTAssertEqual(LookBaseline.mean(of: pts, before: day(2026, 10, 14), calendar: utc), 40)
    }

    func testBaselineNeedsThreeReadings() {
        let pts = series(from: day(2026, 10, 1), values: [40, 42])
        XCTAssertNil(LookBaseline.mean(of: pts, before: day(2026, 10, 14), calendar: utc))
    }

    func testBaselineIgnoresReadingsOlderThanThirtyDays() {
        var pts = series(from: day(2026, 6, 1), values: [500, 500, 500])
        pts += series(from: day(2026, 10, 10), values: [10, 10, 10])
        XCTAssertEqual(LookBaseline.mean(of: pts, before: day(2026, 10, 14), calendar: utc), 10)
    }

    func testComparisonMarksHigherHrvAsFavourable() {
        var pts = series(from: day(2026, 9, 14), values: Array(repeating: 40, count: 30))
        pts.append(LookPoint(date: day(2026, 10, 14), value: 52))
        XCTAssertEqual(LookBaseline.comparison(pts, higherIsBetter: true, calendar: utc)?.mark,
                       LookTodayMark(pointsUp: true, tone: .favourable))
    }

    func testComparisonOfAnEmptySeriesIsNil() {
        XCTAssertNil(LookBaseline.comparison([], higherIsBetter: true, calendar: utc))
    }

    func testComparisonWithoutABaselineHasNoMark() {
        let pts = series(from: day(2026, 10, 13), values: [50, 60])
        XCTAssertNil(LookBaseline.comparison(pts, higherIsBetter: true, calendar: utc)?.mark)
    }

    // MARK: Week strip

    func testWeekHasSevenDaysEndingOnTheEndDate() {
        let days = LookWeek.days(points: [], endingOn: day(2026, 10, 14), calendar: utc)
        XCTAssertEqual(days.last?.date, day(2026, 10, 14))
    }

    func testWeekHasExactlySevenDays() {
        XCTAssertEqual(LookWeek.days(points: [], endingOn: day(2026, 10, 14), calendar: utc).count, 7)
    }

    func testWeekMarksOnlyTheLastDayAsToday() {
        let days = LookWeek.days(points: [], endingOn: day(2026, 10, 14), calendar: utc)
        XCTAssertEqual(days.filter(\.isToday).map(\.date), [day(2026, 10, 14)])
    }

    func testWeekLettersFollowTheWeekdays() {
        // 14 Oct 2026 is a Wednesday, so the strip reads Th F S S M T W.
        let letters = LookWeek.days(points: [], endingOn: day(2026, 10, 14), calendar: utc).map(\.letter)
        XCTAssertEqual(letters, ["T", "F", "S", "S", "M", "T", "W"])
    }

    func testWeekFillsAValueOnItsOwnDayAndLeavesTheRestEmpty() {
        let pts = [LookPoint(date: day(2026, 10, 12), value: 71)]
        let values = LookWeek.days(points: pts, endingOn: day(2026, 10, 14), calendar: utc).map(\.value)
        XCTAssertEqual(values, [nil, nil, nil, nil, 71, nil, nil])
    }

    // MARK: Rest bands

    func testHoursVsNeededIsOptimalAtAHundredPercent() {
        XCTAssertEqual(LookRestBands.hoursVsNeeded(100), .optimal)
    }

    func testHoursVsNeededIsSufficientAtEightyFive() {
        XCTAssertEqual(LookRestBands.hoursVsNeeded(85), .sufficient)
    }

    func testHoursVsNeededIsPoorUnderSeventy() {
        XCTAssertEqual(LookRestBands.hoursVsNeeded(69), .poor)
    }

    func testConsistencyIsOptimalFromEighty() {
        XCTAssertEqual(LookRestBands.consistency(80), .optimal)
    }

    func testEfficiencyIsPoorUnderSeventyFive() {
        XCTAssertEqual(LookRestBands.efficiency(71), .poor)
    }

    func testLowSleepStressIsOptimal() {
        XCTAssertEqual(LookRestBands.sleepStress(18), .optimal)
    }

    func testHighSleepStressIsPoor() {
        XCTAssertEqual(LookRestBands.sleepStress(52), .poor)
    }

    // MARK: Planner copy

    private func clock(_ date: Date) -> String {
        let c = utc.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var plannerWake: Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 5, minute: 50))! }

    private func planner(target: Int = 438, latency: Int = 12, peak: Int = 516) -> LookPlannerCopy {
        let bed = plannerWake.addingTimeInterval(-Double(target + latency) * 60)
        return LookPlannerCopy.make(bedtime: bed, wake: plannerWake, targetSleepMin: target, latencyMin: latency,
                                    peakSleepMin: peak, goalTitle: "Perform", percentText: "85 %", clock: clock)
    }

    func testPlannerSentenceNamesTheBedtimeAndTheSleep() {
        XCTAssertEqual(planner().sentence,
                       "Go to bed at 22:20 tonight to get 7:18 of sleep: Perform, 85 % of tonight's need.")
    }

    func testPlannerTimeInBedIsSleepPlusTimeToFallAsleep() {
        XCTAssertEqual(planner().timeInBedText, "7:30")
    }

    func testPlannerOptimalBracketReachesBackByTheFullNeed() {
        XCTAssertEqual(planner().optimalText, "21:02 \u{2013} 05:50")
    }

    func testPlannerBarIsShorterThanTheBracketForALowerGoal() {
        XCTAssertLessThan(planner().barFraction, 1)
    }

    func testPlannerBarFillsTheBracketAtThePeakGoal() {
        XCTAssertEqual(planner(target: 516).barFraction, 1)
    }

    func testPlannerPillNamesTheGoal() {
        XCTAssertEqual(planner().goalPillText, "REACH MY PERFORM GOAL")
    }

    // MARK: Overnight heart rate

    private func samples(_ values: [Double], start: Int, step: Int = 60) -> [(ts: Int, bpm: Double)] {
        values.enumerated().map { (ts: start + $0.offset * step, bpm: $0.element) }
    }

    func testHeartRateLineNeedsTwoReadings() {
        XCTAssertTrue(LookNightHR.points(samples([60], start: 1000), start: 1000, end: 2000).isEmpty)
    }

    func testHeartRateLineIgnoresReadingsOutsideTheNight() {
        let all = samples([60, 61, 62, 63], start: 1000)
        XCTAssertEqual(LookNightHR.points(all, start: 1060, end: 1120, maxPoints: 10).count, 2)
    }

    func testHeartRateLineRunsFromZeroToOne() {
        let line = LookNightHR.points(samples([60, 70, 80], start: 0), start: 0, end: 120, maxPoints: 3)
        XCTAssertEqual(line.map(\.x).map { ($0 * 100).rounded() / 100 }, [0, 0.5, 1])
    }

    func testHeartRateLineAveragesReadingsThatShareABin() {
        let line = LookNightHR.points(samples([60, 70], start: 0), start: 0, end: 600, maxPoints: 2)
        XCTAssertEqual(line.map(\.bpm), [65])
    }

    func testHeartRateLineBreaksAcrossALongGap() {
        let all = [(ts: 0, bpm: 60.0), (ts: 60, bpm: 61.0), (ts: 3600, bpm: 62.0), (ts: 3660, bpm: 63.0)]
        let line = LookNightHR.points(all, start: 0, end: 3700, maxPoints: 4)
        XCTAssertEqual(line.filter(\.breaksBefore).count, 1)
    }

    func testHeartRateAxisCoversTheReadings() {
        let line = LookNightHR.points(samples([52, 58, 66], start: 0), start: 0, end: 180, maxPoints: 3)
        let range = LookNightHR.axis(line)?.range
        XCTAssertTrue((range?.lowerBound ?? 100) <= 52 && (range?.upperBound ?? 0) >= 66)
    }
}
