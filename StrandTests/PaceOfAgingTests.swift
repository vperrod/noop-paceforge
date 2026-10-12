import XCTest
@testable import Strand

/// Pace of aging: needs four weekly Body Age readings in the last 30 days, fits a line through them, and says
/// the change in years and the pace in years per year. All values are made up.
final class PaceOfAgingTests: XCTestCase {

    private let today = "2030-03-30"

    /// Weekly readings ending on `today`, oldest first, starting at `start` and changing by `step` a week.
    private func weekly(_ count: Int, start: Double = 40, step: Double = 0) -> [(day: String, value: Double)] {
        (0..<count).map { index in
            (day: PaceOfAging.day(today, minus: 7 * (count - 1 - index)), value: start + step * Double(index))
        }
    }

    private func reading(_ outcome: PaceOfAging.Outcome) -> PaceOfAging.Reading? {
        if case .ready(let reading) = outcome { return reading }
        return nil
    }

    // MARK: Calibrating

    func testThreeWeeklyPointsAreNotEnough() {
        XCTAssertEqual(PaceOfAging.compute(series: weekly(3), today: today), .calibrating(have: 3, need: 4))
    }

    func testNoPointsAreNotEnough() {
        XCTAssertEqual(PaceOfAging.compute(series: [], today: today), .calibrating(have: 0, need: 4))
    }

    func testFourWeeklyPointsAreEnough() {
        XCTAssertNotNil(reading(PaceOfAging.compute(series: weekly(4), today: today)))
    }

    func testPointsOlderThanThirtyDaysDoNotCount() {
        let old = (0..<4).map { index in (day: PaceOfAging.day(today, minus: 60 + 7 * index), value: 40.0) }
        XCTAssertEqual(PaceOfAging.compute(series: old, today: today), .calibrating(have: 0, need: 4))
    }

    func testOnlyThePointsInsideTheWindowAreCounted() {
        let series = weekly(4) + [(day: PaceOfAging.day(today, minus: 90), value: 50.0)]
        XCTAssertEqual(reading(PaceOfAging.compute(series: series, today: today))?.pointsUsed, 4)
    }

    func testTheSameDayTwiceIsOnePoint() {
        let series = weekly(3) + [(day: today, value: 41.0), (day: today, value: 41.0)]
        XCTAssertEqual(PaceOfAging.compute(series: series, today: today), .calibrating(have: 3, need: 4))
    }

    func testTheCalibrationLineSaysHowManyThereAre() {
        XCTAssertEqual(PaceOfAging.calibrationLine(have: 2, need: 4),
                       "Pace of aging needs at least 4 weekly Body Age readings from the last 30 days. You have 2.")
    }

    // MARK: The line

    func testAFlatBodyAgeIsAPaceOfOne() {
        XCTAssertEqual(reading(PaceOfAging.compute(series: weekly(5), today: today))?.yearsPerYear ?? 0, 1, accuracy: 0.0001)
    }

    func testAFlatBodyAgeIsNoChange() {
        XCTAssertEqual(reading(PaceOfAging.compute(series: weekly(5), today: today))?.changeYears ?? 1, 0, accuracy: 0.0001)
    }

    func testAFallingBodyAgeIsAChangeBelowZero() {
        // 0.1 year down a week is 0.1 / 7 a day, 30 days of it is about 0.43 years.
        let result = reading(PaceOfAging.compute(series: weekly(5, step: -0.1), today: today))
        XCTAssertEqual(result?.changeYears ?? 0, -0.1 / 7 * 30, accuracy: 0.0001)
    }

    func testARisingBodyAgeIsAChangeAboveZero() {
        XCTAssertGreaterThan(reading(PaceOfAging.compute(series: weekly(5, step: 0.05), today: today))?.changeYears ?? 0, 0)
    }

    func testAFallingBodyAgeIsAPaceBelowOne() {
        XCTAssertLessThan(reading(PaceOfAging.compute(series: weekly(5, step: -0.01), today: today))?.yearsPerYear ?? 9, 1)
    }

    func testThePaceIsOnePlusTheYearlySlope() {
        // 0.007 years a week is 0.001 a day; a year of it is 0.36525, so the pace is 1.36525.
        let result = reading(PaceOfAging.compute(series: weekly(5, step: 0.007), today: today))
        XCTAssertEqual(result?.yearsPerYear ?? 0, 1.36525, accuracy: 0.0001)
    }

    func testAHugeSwingIsHeldToTheDisplayRange() {
        let result = reading(PaceOfAging.compute(series: weekly(5, step: -1), today: today))
        XCTAssertEqual(result?.yearsPerYear, PaceOfAging.paceRange.lowerBound)
    }

    func testAHeldPaceIsFlaggedAsCapped() {
        XCTAssertEqual(reading(PaceOfAging.compute(series: weekly(5, step: -1), today: today))?.isCapped, true)
    }

    func testAnOrdinaryPaceIsNotCapped() {
        XCTAssertEqual(reading(PaceOfAging.compute(series: weekly(5, step: -0.01), today: today))?.isCapped, false)
    }

    func testThePointsMayComeInAnyOrder() {
        let series = weekly(5, step: -0.1)
        let shuffled = [series[3], series[0], series[4], series[1], series[2]]
        XCTAssertEqual(reading(PaceOfAging.compute(series: shuffled, today: today))?.changeYears ?? 0,
                       reading(PaceOfAging.compute(series: series, today: today))?.changeYears ?? 1, accuracy: 0.0001)
    }

    // MARK: Words

    func testThePaceIsShownToOneDecimal() {
        let reading = PaceOfAging.Reading(changeYears: -0.2, yearsPerYear: 0.64, isCapped: false, pointsUsed: 5)
        XCTAssertEqual(PaceOfAging.paceText(reading), "0.6")
    }

    func testANegativePaceUsesAMinusSign() {
        let reading = PaceOfAging.Reading(changeYears: -0.6, yearsPerYear: -1.4, isCapped: false, pointsUsed: 5)
        XCTAssertEqual(PaceOfAging.paceText(reading), "\u{2212}1.4")
    }

    func testTheHeadlineSaysYearsPerYear() {
        let reading = PaceOfAging.Reading(changeYears: -0.2, yearsPerYear: 0.64, isCapped: false, pointsUsed: 5)
        XCTAssertEqual(PaceOfAging.headline(reading), "Ageing 0.6 years per year")
    }

    func testTheChangeLineSaysDownForAFall() {
        let reading = PaceOfAging.Reading(changeYears: -0.43, yearsPerYear: 0.5, isCapped: false, pointsUsed: 5)
        XCTAssertEqual(PaceOfAging.changeLine(reading), "Body Age down 0.4 years in 30 days")
    }

    func testTheChangeLineSaysUpForARise() {
        let reading = PaceOfAging.Reading(changeYears: 0.3, yearsPerYear: 1.5, isCapped: false, pointsUsed: 5)
        XCTAssertEqual(PaceOfAging.changeLine(reading), "Body Age up 0.3 years in 30 days")
    }

    func testNoChangeIsSteady() {
        let reading = PaceOfAging.Reading(changeYears: 0.01, yearsPerYear: 1.1, isCapped: false, pointsUsed: 5)
        XCTAssertEqual(PaceOfAging.changeLine(reading), "Body Age steady over 30 days")
    }

    func testDaySubtractionCrossesAMonthEnd() {
        XCTAssertEqual(PaceOfAging.day("2030-03-05", minus: 10), "2030-02-23")
    }
}
