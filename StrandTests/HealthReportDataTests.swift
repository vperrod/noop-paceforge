import XCTest
@testable import Strand

/// The health report: the last 30 nights of each vital as a latest reading, an average, a range and a series.
/// A missing reading is never counted as zero. All values are made up.
final class HealthReportDataTests: XCTestCase {

    private func nights(_ count: Int, endingOn end: String = "2030-03-30", build: (Int, String) -> HealthReportNight) -> [HealthReportNight] {
        (0..<count).map { index in
            let day = HealthReportData.day(end, minus: count - 1 - index)
            return build(index, day)
        }
    }

    private func vital(_ kind: HealthReportVitalKind, _ report: HealthReport) -> HealthReportVital {
        report.vitals.first { $0.kind == kind }!
    }

    // MARK: Window

    func testTheWindowIsThirtyDaysEndingToday() {
        let report = HealthReportData.build(nights: [], today: "2030-03-30")
        XCTAssertEqual([report.start, report.end], ["2030-03-01", "2030-03-30"])
    }

    func testNightsBeforeTheWindowAreLeftOut() {
        let list = [HealthReportNight(day: "2030-02-28", hrv: 90), HealthReportNight(day: "2030-03-01", hrv: 40)]
        XCTAssertEqual(vital(.hrv, HealthReportData.build(nights: list, today: "2030-03-30")).nights, 1)
    }

    func testNightsAfterTodayAreLeftOut() {
        let list = [HealthReportNight(day: "2030-03-31", hrv: 40)]
        XCTAssertEqual(vital(.hrv, HealthReportData.build(nights: list, today: "2030-03-30")).nights, 0)
    }

    func testDaySubtractionCrossesMonthsAndYears() {
        XCTAssertEqual([HealthReportData.day("2030-03-01", minus: 1), HealthReportData.day("2030-01-01", minus: 1)],
                       ["2030-02-28", "2029-12-31"])
    }

    // MARK: Statistics

    func testLatestIsTheMostRecentNightWithAReading() {
        let list = [HealthReportNight(day: "2030-03-10", hrv: 50), HealthReportNight(day: "2030-03-12", hrv: 62),
                    HealthReportNight(day: "2030-03-14")]
        let result = vital(.hrv, HealthReportData.build(nights: list, today: "2030-03-30"))
        XCTAssertEqual(result.latest, 62)
        XCTAssertEqual(result.latestDay, "2030-03-12")
    }

    func testAverageMinAndMaxAreOverTheNightsWithAReading() {
        let list = [HealthReportNight(day: "2030-03-10", restingHr: 50), HealthReportNight(day: "2030-03-11", restingHr: 60),
                    HealthReportNight(day: "2030-03-12")]
        let result = vital(.restingHr, HealthReportData.build(nights: list, today: "2030-03-30"))
        XCTAssertEqual([result.mean, result.minimum, result.maximum], [55, 50, 60])
    }

    func testSeriesIsOldestFirst() {
        let list = [HealthReportNight(day: "2030-03-12", respRate: 15), HealthReportNight(day: "2030-03-10", respRate: 14)]
        XCTAssertEqual(vital(.respRate, HealthReportData.build(nights: list, today: "2030-03-30")).series, [14, 15])
    }

    func testAMissingReadingIsNotCountedAsZero() {
        let list = [HealthReportNight(day: "2030-03-10", spo2: 0), HealthReportNight(day: "2030-03-11", spo2: 96)]
        let result = vital(.spo2, HealthReportData.build(nights: list, today: "2030-03-30"))
        XCTAssertEqual([Double(result.nights), result.mean ?? 0], [1, 96])
    }

    func testDeltaIsTheLatestAgainstTheOtherNights() {
        let list = [HealthReportNight(day: "2030-03-10", hrv: 40), HealthReportNight(day: "2030-03-11", hrv: 60),
                    HealthReportNight(day: "2030-03-12", hrv: 80)]
        XCTAssertEqual(vital(.hrv, HealthReportData.build(nights: list, today: "2030-03-30")).deltaVsAverage, 30)
    }

    func testOneReadingHasNoDelta() {
        let list = [HealthReportNight(day: "2030-03-10", hrv: 40)]
        XCTAssertNil(vital(.hrv, HealthReportData.build(nights: list, today: "2030-03-30")).deltaVsAverage)
    }

    func testAVitalWithNoReadingIsKeptWithZeroNights() {
        let report = HealthReportData.build(nights: [HealthReportNight(day: "2030-03-10", hrv: 40)], today: "2030-03-30")
        XCTAssertEqual(vital(.spo2, report).nights, 0)
    }

    func testEveryVitalIsListedInOrder() {
        let report = HealthReportData.build(nights: [], today: "2030-03-30")
        XCTAssertEqual(report.vitals.map(\.kind), [.hrv, .restingHr, .respRate, .spo2, .skinTemp])
    }

    func testAReportWithNoReadingsIsEmpty() {
        XCTAssertTrue(HealthReportData.build(nights: [HealthReportNight(day: "2030-03-10")], today: "2030-03-30").isEmpty)
    }

    func testAReportWithOneReadingIsNotEmpty() {
        XCTAssertFalse(HealthReportData.build(nights: [HealthReportNight(day: "2030-03-10", hrv: 40)], today: "2030-03-30").isEmpty)
    }

    func testThirtyNightsAreAllCounted() {
        let list = nights(30) { index, day in HealthReportNight(day: day, restingHr: 50 + Double(index % 3)) }
        XCTAssertEqual(vital(.restingHr, HealthReportData.build(nights: list, today: "2030-03-30")).nights, 30)
    }

    // MARK: Skin temperature

    func testSkinTemperatureKeepsNegativeDeviationsAsReadings() {
        let list = [HealthReportNight(day: "2030-03-10", skinTempDev: -0.4), HealthReportNight(day: "2030-03-11", skinTempDev: 0.2)]
        XCTAssertEqual(vital(.skinTemp, HealthReportData.build(nights: list, today: "2030-03-30")).minimum, -0.4)
    }

    func testSkinTemperatureIsSignedWithAMinusSign() {
        let list = [HealthReportNight(day: "2030-03-10", skinTempDev: -0.4)]
        let result = vital(.skinTemp, HealthReportData.build(nights: list, today: "2030-03-30"))
        XCTAssertEqual(result.text(-0.4), "\u{2212}0.40")
    }

    func testSkinTemperatureInFahrenheitScalesTheDeviation() {
        let result = vital(.skinTemp, HealthReportData.build(nights: [], today: "2030-03-30", fahrenheit: true))
        XCTAssertEqual(result.text(0.5), "+0.90")
    }

    func testSkinTemperatureUnitSaysVersusBaseline() {
        let celsius = vital(.skinTemp, HealthReportData.build(nights: [], today: "2030-03-30"))
        XCTAssertEqual(celsius.unit, "\u{00B0}C vs baseline")
    }

    func testOtherVitalsAreNotSigned() {
        let result = vital(.hrv, HealthReportData.build(nights: [], today: "2030-03-30"))
        XCTAssertEqual(result.text(58.4), "58")
    }

    func testDecimalsFollowTheVital() {
        let report = HealthReportData.build(nights: [], today: "2030-03-30")
        XCTAssertEqual([vital(.respRate, report).text(14.26), vital(.spo2, report).text(96.04)], ["14.3", "96.0"])
    }

    func testDeltaTextNamesTheWindow() {
        let list = [HealthReportNight(day: "2030-03-10", hrv: 40), HealthReportNight(day: "2030-03-11", hrv: 60),
                    HealthReportNight(day: "2030-03-12", hrv: 80)]
        let result = vital(.hrv, HealthReportData.build(nights: list, today: "2030-03-30"))
        XCTAssertEqual(result.deltaText(nightsInReport: 30), "+30 on your 30-night average")
    }

    func testDeltaTextOfNoChangeHasNoSign() {
        let list = [HealthReportNight(day: "2030-03-10", hrv: 50), HealthReportNight(day: "2030-03-11", hrv: 50)]
        let result = vital(.hrv, HealthReportData.build(nights: list, today: "2030-03-30"))
        XCTAssertEqual(result.deltaText(nightsInReport: 30), "0 on your 30-night average")
    }
}
