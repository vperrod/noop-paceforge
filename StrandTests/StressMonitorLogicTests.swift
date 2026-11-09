import XCTest
@testable import Strand

/// The Stress monitor's day line: which hours are real readings, where the line breaks, and where a point sits.
final class StressMonitorLogicTests: XCTestCase {

    private func hour(_ h: Int, _ level: Double?, masked: Bool = false) -> StressMonitorLogic.Hour {
        StressMonitorLogic.Hour(startTs: 1_900_000_000 + h * 3600, level: level, masked: masked)
    }

    func testNothingScoredMeansNoData() {
        XCTAssertFalse(StressMonitorLogic.hasData([hour(8, nil), hour(9, nil, masked: true)]))
    }

    func testOneScoredHourMeansData() {
        XCTAssertTrue(StressMonitorLogic.hasData([hour(8, nil), hour(9, 1.2)]))
    }

    func testNoHoursMeansNoData() {
        XCTAssertFalse(StressMonitorLogic.hasData([]))
    }

    func testLatestIsTheLastScoredHourNotTheLastHour() {
        XCTAssertEqual(StressMonitorLogic.latest([hour(8, 1.0), hour(9, 2.0), hour(10, nil)])?.level, 2.0)
    }

    func testLatestIgnoresTheOrderTheHoursArriveIn() {
        XCTAssertEqual(StressMonitorLogic.latest([hour(10, 0.5), hour(8, 2.5)])?.level, 0.5)
    }

    func testLatestIsClampedToTheScale() {
        XCTAssertEqual(StressMonitorLogic.latest([hour(8, 3.4)])?.level, 3.0)
    }

    func testLatestOfNothingIsNil() {
        XCTAssertNil(StressMonitorLogic.latest([hour(8, nil)]))
    }

    func testConsecutiveScoredHoursAreOneRun() {
        XCTAssertEqual(StressMonitorLogic.runs([hour(8, 1), hour(9, 2), hour(10, 1)]).map(\.count), [3])
    }

    func testAnUnscoredHourBreaksTheLine() {
        XCTAssertEqual(StressMonitorLogic.runs([hour(8, 1), hour(9, nil), hour(10, 1)]).map(\.count), [1, 1])
    }

    func testAMaskedHourBreaksTheLine() {
        XCTAssertEqual(StressMonitorLogic.runs([hour(8, 1), hour(9, 2, masked: true), hour(10, 1)]).map(\.count), [1, 1])
    }

    func testALongGapBreaksTheLineEvenWithoutAnUnscoredHourBetween() {
        XCTAssertEqual(StressMonitorLogic.runs([hour(6, 1), hour(10, 1)]).map(\.count), [1, 1])
    }

    func testAGapOfTwoHoursIsStillOneRun() {
        XCTAssertEqual(StressMonitorLogic.runs([hour(6, 1), hour(8, 1)]).map(\.count), [2])
    }

    func testRunsAreInTimeOrder() {
        XCTAssertEqual(StressMonitorLogic.runs([hour(9, 2), hour(8, 1)]).first?.map(\.level), [1, 2])
    }

    func testMaskedStartsListTheExerciseHours() {
        XCTAssertEqual(StressMonitorLogic.maskedStarts([hour(9, nil, masked: true), hour(8, 1), hour(7, nil, masked: true)]),
                       [hour(7, nil).startTs, hour(9, nil).startTs])
    }

    func testStartOfTheDayIsAtTheLeftEdge() {
        XCTAssertEqual(StressMonitorLogic.xFraction(ts: 1000, dayStart: 1000), 0)
    }

    func testNoonIsHalfwayAcrossTheDay() {
        XCTAssertEqual(StressMonitorLogic.xFraction(ts: 1000 + 43_200, dayStart: 1000), 0.5, accuracy: 0.0001)
    }

    func testAPointBeforeTheDayIsClampedToTheLeft() {
        XCTAssertEqual(StressMonitorLogic.xFraction(ts: 0, dayStart: 1000), 0)
    }

    func testLevelOneAndAHalfIsHalfwayUp() {
        XCTAssertEqual(StressMonitorLogic.yFraction(level: 1.5), 0.5, accuracy: 0.0001)
    }

    func testLevelsAreClampedOnTheChart() {
        XCTAssertEqual(StressMonitorLogic.yFraction(level: 4), 1)
    }

    func testLevelTextIsOneDecimal() {
        XCTAssertEqual(StressMonitorLogic.levelText(2), "2.0")
    }

    func testLastUpdatedIsTheEndOfTheLatestScoredHour() {
        XCTAssertEqual(StressMonitorLogic.lastUpdated([hour(8, 1)], now: 1_900_000_000 + 20 * 3600), 1_900_000_000 + 9 * 3600)
    }

    func testLastUpdatedIsNeverInTheFuture() {
        XCTAssertEqual(StressMonitorLogic.lastUpdated([hour(8, 1)], now: 1_900_000_000 + 8 * 3600 + 600), 1_900_000_000 + 8 * 3600 + 600)
    }

    func testLastUpdatedWithoutAReadingIsNil() {
        XCTAssertNil(StressMonitorLogic.lastUpdated([hour(8, nil)], now: 1_900_000_000))
    }
}
