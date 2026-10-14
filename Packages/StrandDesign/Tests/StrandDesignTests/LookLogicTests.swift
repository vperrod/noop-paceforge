import XCTest
@testable import StrandDesign

final class LookLogicTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: Bands

    func testChargeBandIsGreenFromSixtySeven() {
        XCTAssertEqual(LookBand.forScore(67), .high)
    }

    func testChargeBandIsYellowAtSixtySix() {
        XCTAssertEqual(LookBand.forScore(66), .medium)
    }

    func testChargeBandUsesTheRoundedValueTheRingPrints() {
        XCTAssertEqual(LookBand.forScore(66.6), .high)
    }

    func testChargeBandIsYellowFromThirtyFour() {
        XCTAssertEqual(LookBand.forScore(34), .medium)
    }

    func testChargeBandIsRedAtThirtyThree() {
        XCTAssertEqual(LookBand.forScore(33.4), .low)
    }

    func testChargeBandClampsBelowZeroToRed() {
        XCTAssertEqual(LookBand.forScore(-5), .low)
    }

    // MARK: Today vs 30 days

    func testHigherHrvIsAnUpFavourableMark() {
        XCTAssertEqual(LookCompare.mark(today: 52, baseline: 46, higherIsBetter: true),
                       LookTodayMark(pointsUp: true, tone: .favourable))
    }

    func testLowerHrvIsADownUnfavourableMark() {
        XCTAssertEqual(LookCompare.mark(today: 43, baseline: 46, higherIsBetter: true),
                       LookTodayMark(pointsUp: false, tone: .unfavourable))
    }

    func testLowerRestingHeartRateIsADownFavourableMark() {
        XCTAssertEqual(LookCompare.mark(today: 59, baseline: 60, higherIsBetter: false),
                       LookTodayMark(pointsUp: false, tone: .favourable))
    }

    func testHigherRespiratoryRateIsAnUpUnfavourableMark() {
        XCTAssertEqual(LookCompare.mark(today: 16.1, baseline: 15.7, decimals: 1, higherIsBetter: false),
                       LookTodayMark(pointsUp: true, tone: .unfavourable))
    }

    func testValuesThatPrintTheSameGetNoMark() {
        XCTAssertNil(LookCompare.mark(today: 16.04, baseline: 15.96, decimals: 1, higherIsBetter: false))
    }

    func testMissingBaselineGetsNoMark() {
        XCTAssertNil(LookCompare.mark(today: 50, baseline: nil, higherIsBetter: true))
    }

    func testMetricWithoutAGoodDirectionIsNeutral() {
        XCTAssertEqual(LookCompare.mark(today: 9812, baseline: 11240, higherIsBetter: nil)?.tone, .neutral)
    }

    // MARK: Delta chips

    func testPercentChangeFromAToB() {
        XCTAssertEqual(LookDelta.percentChange(from: 106, to: 115)!, 8.49, accuracy: 0.01)
    }

    func testPercentChangeFromZeroIsNil() {
        XCTAssertNil(LookDelta.percentChange(from: 0, to: 5))
    }

    func testRiseIsAPositiveChipWhenHigherIsBetter() {
        XCTAssertEqual(LookDelta.chip(percent: 8.4), LookChip(text: "+8 %", tone: .positive))
    }

    func testFallIsANegativeChipWhenHigherIsBetter() {
        XCTAssertEqual(LookDelta.chip(percent: -2.6), LookChip(text: "-3 %", tone: .negative))
    }

    func testFallIsPositiveWhenLowerIsBetter() {
        XCTAssertEqual(LookDelta.chip(percent: -4, higherIsBetter: false)?.tone, .positive)
    }

    func testChangeThatRoundsToZeroIsNeutral() {
        XCTAssertEqual(LookDelta.chip(percent: 0.4), LookChip(text: "0 %", tone: .neutral))
    }

    func testNoPercentMeansNoChip() {
        XCTAssertNil(LookDelta.chip(percent: nil))
    }

    // MARK: Three steps

    func testBelowSufficientIsPoor() {
        XCTAssertEqual(LookStep.classify(60, sufficientFrom: 70, optimalFrom: 90), .poor)
    }

    func testBetweenIsSufficient() {
        XCTAssertEqual(LookStep.classify(80, sufficientFrom: 70, optimalFrom: 90), .sufficient)
    }

    func testAtOptimalFloorIsOptimal() {
        XCTAssertEqual(LookStep.classify(90, sufficientFrom: 70, optimalFrom: 90), .optimal)
    }

    // MARK: Dial geometry

    func testFractionClampsAboveMax() {
        XCTAssertEqual(LookDial.fraction(130, max: 100), 1)
    }

    func testFractionOfZeroMaxIsZero() {
        XCTAssertEqual(LookDial.fraction(5, max: 0), 0)
    }

    func testTargetArcOrdersItsEnds() {
        let arc = LookDial.targetArc(low: 16.5, high: 13.2, max: 21)!
        XCTAssertEqual(arc.start, 13.2 / 21, accuracy: 0.0001)
    }

    func testTargetArcOfEmptyRangeIsNil() {
        XCTAssertNil(LookDial.targetArc(low: 14, high: 14, max: 21))
    }

    func testTargetArcWithoutABandIsNil() {
        XCTAssertNil(LookDial.targetArc(low: nil, high: 16, max: 21))
    }

    func testHalfAFractionIsOneHundredEightyDegrees() {
        XCTAssertEqual(LookDial.degrees(forFraction: 0.5), 180)
    }

    // MARK: Stress

    func testStressUnderOneIsLow() {
        XCTAssertEqual(LookStressLevel.forScore(0.9), .low)
    }

    func testStressOnePointSevenIsMedium() {
        XCTAssertEqual(LookStressLevel.forScore(1.7), .medium)
    }

    func testStressTwoIsHigh() {
        XCTAssertEqual(LookStressLevel.forScore(2), .high)
    }

    // MARK: Formatting

    func testSixHoursTwentyMinutes() {
        XCTAssertEqual(LookFormat.hoursMinutes(minutes: 380), "6:20")
    }

    func testMinutesArePaddedToTwoDigits() {
        XCTAssertEqual(LookFormat.hoursMinutes(minutes: 65), "1:05")
    }

    func testClockWrapsPastMidnight() {
        XCTAssertEqual(LookFormat.clock(minutesAfterMidnight: 1500), "01:00")
    }

    func testClockHandlesNegativeMinutes() {
        XCTAssertEqual(LookFormat.clock(minutesAfterMidnight: -60), "23:00")
    }

    // MARK: Ranges

    func testSixMonthWindowSpansOneHundredEightyDays() {
        let w = LookRange.sixMonths.window(endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(utc.component(.day, from: w.start), 14)
    }

    func testSixMonthWindowStartsInApril() {
        let w = LookRange.sixMonths.window(endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(utc.component(.month, from: w.start), 4)
    }

    func testWeekWindowIsSevenDaysInclusive() {
        let w = LookRange.week.window(endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(utc.component(.day, from: w.start), 4)
    }

    func testRangeLabelMatchesTheReference() {
        XCTAssertEqual(LookRange.sixMonths.label(endingOn: day(2026, 10, 10), calendar: utc), "APR 14 \u{2013} OCT 10, 26")
    }

    func testRangeLabelInsideOneMonthShowsTheMonthOnce() {
        XCTAssertEqual(LookRange.week.label(endingOn: day(2026, 10, 10), calendar: utc), "OCT 4 \u{2013} 10, 26")
    }

    func testSteppingBackMovesOneWindow() {
        let end = LookRange.week.stepped(end: day(2026, 10, 10), by: -1, today: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(utc.component(.day, from: end), 3)
    }

    func testSteppingForwardNeverPassesToday() {
        let end = LookRange.week.stepped(end: day(2026, 10, 8), by: 1, today: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(utc.component(.day, from: end), 10)
    }

    func testCannotStepForwardFromToday() {
        XCTAssertFalse(LookRange.month.canStepForward(end: day(2026, 10, 10), today: day(2026, 10, 10), calendar: utc))
    }

    func testCanStepForwardFromThePast() {
        XCTAssertTrue(LookRange.month.canStepForward(end: day(2026, 9, 1), today: day(2026, 10, 10), calendar: utc))
    }

    func testOnlyTheLongViewsUseMonthlySegments() {
        XCTAssertEqual(LookRange.allCases.filter(\.usesMonthlySegments), [.sixMonths, .year])
    }

    // MARK: Statistics

    func testAverageOfNothingIsNil() {
        XCTAssertNil(LookTrendStats.average([]))
    }

    func testTypicalRangeIsMeanPlusMinusOneSd() {
        let range = LookTrendStats.typicalRange(of: [2, 4, 4, 4, 5, 5, 7, 9])!
        XCTAssertEqual(range.lowerBound, 3, accuracy: 0.0001)
    }

    func testTypicalRangeNeedsThreeValues() {
        XCTAssertNil(LookTrendStats.typicalRange(of: [1, 2]))
    }

    func testMonthlySegmentsAverageEachMonth() {
        let pts = [LookPoint(date: day(2026, 5, 3), value: 100), LookPoint(date: day(2026, 5, 20), value: 120),
                   LookPoint(date: day(2026, 6, 2), value: 90)]
        XCTAssertEqual(LookTrendStats.monthlySegments(pts, calendar: utc).map(\.average), [110, 90])
    }

    func testFirstMonthHasNoChange() {
        let pts = [LookPoint(date: day(2026, 5, 3), value: 100), LookPoint(date: day(2026, 6, 2), value: 90)]
        XCTAssertNil(LookTrendStats.monthlySegments(pts, calendar: utc).first?.percentChange)
    }

    func testSecondMonthChangeIsAgainstTheFirst() {
        let pts = [LookPoint(date: day(2026, 5, 3), value: 100), LookPoint(date: day(2026, 6, 2), value: 90)]
        XCTAssertEqual(LookTrendStats.monthlySegments(pts, calendar: utc)[1].percentChange!, -10, accuracy: 0.0001)
    }

    func testMonthlySegmentsAreInDateOrderWhateverTheInputOrder() {
        let pts = [LookPoint(date: day(2026, 7, 1), value: 1), LookPoint(date: day(2026, 5, 1), value: 2)]
        XCTAssertEqual(LookTrendStats.monthlySegments(pts, calendar: utc).map(\.average), [2, 1])
    }

    func testNiceTicksCoverTheData() {
        let t = LookTrendStats.niceTicks(min: 63, max: 178, count: 6)
        XCTAssertTrue(t.first! <= 63 && t.last! >= 178)
    }

    func testNiceTicksStepOnOneTwoFive() {
        XCTAssertEqual(LookTrendStats.niceTicks(min: 0, max: 100, count: 6), [0, 20, 40, 60, 80, 100])
    }

    // MARK: Trend window

    private func dailyPoints(from start: Date, days: Int, value: (Int) -> Double) -> [LookPoint] {
        (0..<days).map { LookPoint(date: utc.date(byAdding: .day, value: $0, to: start)!, value: value($0)) }
    }

    func testWindowAverageCoversOnlyThePointsInsideIt() {
        let pts = dailyPoints(from: day(2026, 10, 1), days: 10, value: { Double($0 + 1) })
        let w = LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(w.average!, 7, accuracy: 0.0001)
    }

    func testWindowKeepsPointsOldestFirst() {
        let pts = dailyPoints(from: day(2026, 10, 4), days: 7, value: { Double($0) }).reversed()
        let w = LookTrendWindow.make(points: Array(pts), range: .week, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(w.points.first?.value, 0)
    }

    func testPreviousAverageIsTheWindowBefore() {
        let pts = dailyPoints(from: day(2026, 9, 27), days: 14, value: { $0 < 7 ? 100 : 110 })
        let w = LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(w.previousAverage!, 100, accuracy: 0.0001)
    }

    func testDeltaPercentComparesWithThePreviousWindow() {
        let pts = dailyPoints(from: day(2026, 9, 27), days: 14, value: { $0 < 7 ? 100 : 110 })
        let w = LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(w.deltaPercent!, 10, accuracy: 0.0001)
    }

    func testNoEarlierWindowMeansNoDelta() {
        let pts = dailyPoints(from: day(2026, 10, 4), days: 7, value: { _ in 50 })
        let w = LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertNil(w.deltaPercent)
    }

    func testWeekHasNoMonthlySegments() {
        let pts = dailyPoints(from: day(2026, 10, 4), days: 7, value: { _ in 50 })
        XCTAssertTrue(LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc).spans.isEmpty)
    }

    func testSixMonthWindowHasASegmentPerMonth() {
        let pts = dailyPoints(from: day(2026, 4, 14), days: 180, value: { _ in 100 })
        let w = LookTrendWindow.make(points: pts, range: .sixMonths, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(w.spans.count, 7)
    }

    func testFirstSegmentStartsAtTheWindowStartNotTheMonthStart() {
        let pts = dailyPoints(from: day(2026, 4, 14), days: 180, value: { _ in 100 })
        let w = LookTrendWindow.make(points: pts, range: .sixMonths, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(utc.component(.day, from: w.spans[0].from), 14)
    }

    func testLastSegmentEndsAtTheWindowEnd() {
        let pts = dailyPoints(from: day(2026, 4, 14), days: 180, value: { _ in 100 })
        let w = LookTrendWindow.make(points: pts, range: .sixMonths, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(utc.component(.day, from: w.spans.last!.to), 10)
    }

    func testTypicalOverrideWinsOverTheComputedBand() {
        let pts = dailyPoints(from: day(2026, 10, 4), days: 7, value: { Double($0) })
        let w = LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc,
                                     typicalOverride: 2...4)
        XCTAssertEqual(w.typical, 2...4)
    }

    func testYDomainCoversTheTypicalBand() {
        let pts = dailyPoints(from: day(2026, 10, 4), days: 7, value: { _ in 50 })
        let w = LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc,
                                     typicalOverride: 40...70)
        XCTAssertTrue(w.yDomain.lowerBound <= 40 && w.yDomain.upperBound >= 70)
    }

    func testEarlierDataEnablesSteppingBack() {
        let pts = dailyPoints(from: day(2026, 9, 1), days: 40, value: { _ in 1 })
        XCTAssertTrue(LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc).hasEarlierData)
    }

    func testWeekAxisLabelsEveryDay() {
        let pts = dailyPoints(from: day(2026, 10, 4), days: 7, value: { _ in 1 })
        let w = LookTrendWindow.make(points: pts, range: .week, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(w.xTickDates(calendar: utc).count, 7)
    }

    func testMonthAxisLabelsEverySeventhDay() {
        let pts = dailyPoints(from: day(2026, 9, 11), days: 30, value: { _ in 1 })
        let w = LookTrendWindow.make(points: pts, range: .month, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertEqual(w.xTickDates(calendar: utc).count, 5)
    }

    func testEmptyDataHasNoAverage() {
        let w = LookTrendWindow.make(points: [], range: .month, endingOn: day(2026, 10, 10), calendar: utc)
        XCTAssertNil(w.average)
    }

    // MARK: Sticky

    func testMiniDialsHiddenWhileTheHeroIsOnScreen() {
        XCTAssertFalse(LookSticky.isVisible(heroBottomY: 300, topInset: 59))
    }

    func testMiniDialsShowOnceTheHeroPassesTheTopInset() {
        XCTAssertTrue(LookSticky.isVisible(heroBottomY: 40, topInset: 59))
    }
}
