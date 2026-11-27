import XCTest

/// The figures behind the share cards (StrandiOS/Share/ShareCardData.swift, compiled into this bundle). Plain unit
/// checks that launch no app. Every number is made up.
final class ShareCardDataTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func values(_ day: String, charge: Double? = nil, sleep: Double? = nil, effort: Double? = nil,
                        hrv: Double? = nil, rhr: Double? = nil) -> ShareDayValues {
        ShareDayValues(day: day, charge: charge, sleepMin: sleep, effort: effort, hrv: hrv, restingHr: rhr)
    }

    private func figures(_ shown: ShareDayValues, history: [ShareDayValues] = [], whoopRows: [ShareDayValues]? = nil,
                         strapLiveEffort: Double? = nil, hidesScores: Bool = false) -> ShareDayFigures {
        ShareDayFigures.make(shown: shown, history: history, whoopRows: whoopRows ?? history + [shown],
                             strapLiveEffort: strapLiveEffort, hidesScores: hidesScores, calendar: calendar)
    }

    private let earlier = ["2030-03-10", "2030-03-11", "2030-03-12"]

    func testAverageLeavesOutTheShownDayAndLaterDays() {
        let history = zip(earlier, [40.0, 50, 60]).map { values($0.0, charge: $0.1) }
            + [values("2030-03-13", charge: 99), values("2030-03-14", charge: 1)]
        XCTAssertEqual(figures(values("2030-03-13", charge: 99), history: history).charge,
                       ShareFigure(value: 99, average: 50))
    }

    func testAverageCoversThirtyDaysBeforeTheShownDay() {
        // 11 Feb is the 30th day before 13 Mar 2030; 10 Feb is the 31st.
        let history = [values("2030-02-10", hrv: 900), values("2030-02-11", hrv: 30)]
            + earlier.map { values($0, hrv: 50) }
        XCTAssertEqual(figures(values("2030-03-13", hrv: 70), history: history).hrv?.average, 45)
    }

    func testTooFewEarlierDaysGiveNoAverage() {
        let history = [values("2030-03-11", rhr: 40), values("2030-03-12", rhr: 42)]
        XCTAssertEqual(figures(values("2030-03-13", rhr: 44), history: history).restingHr,
                       ShareFigure(value: 44, average: nil))
    }

    func testMissingAndZeroReadingsAreLeftOff() {
        let result = figures(values("2030-03-13", sleep: 0, hrv: nil, rhr: 44))
        XCTAssertEqual(result, ShareDayFigures(restingHr: ShareFigure(value: 44, average: nil)))
    }

    func testZeroEffortIsAScore() {
        XCTAssertEqual(figures(values("2030-03-13", effort: 0)).effort?.value, 0)
    }

    func testAFigureNoWhoopRowCarriesIsLeftOff() {
        let shown = values("2030-03-13", charge: 77, rhr: 44)
        let result = figures(shown, whoopRows: [values("2030-03-13", charge: 12, rhr: 44)])
        XCTAssertEqual(result, ShareDayFigures(restingHr: ShareFigure(value: 44, average: nil)))
    }

    func testAverageSkipsDaysFilledByAnotherSource() {
        let history = ["2030-03-09", "2030-03-10", "2030-03-11", "2030-03-12"].map { values($0, rhr: 40) }
        var merged = history
        merged[0].restingHr = 80
        let shown = values("2030-03-13", rhr: 44)
        // The WHOOP rows have no resting HR on 9 Mar: the merged 80 came from somewhere else.
        let whoop = [values("2030-03-09")] + Array(history.dropFirst()) + [shown]
        XCTAssertEqual(figures(shown, history: merged, whoopRows: whoop).restingHr?.average, 40)
    }

    func testLiveStrapEffortStaysWithoutAStoredRow() {
        XCTAssertEqual(figures(values("2030-03-13", effort: 12), whoopRows: [], strapLiveEffort: 12).effort?.value, 12)
    }

    func testHiddenScoresStayOffTheCard() {
        let result = figures(values("2030-03-13", charge: 77, sleep: 400, effort: 55), hidesScores: true)
        XCTAssertEqual(result, ShareDayFigures(sleepMin: ShareFigure(value: 400, average: nil)))
    }

    func testWorkoutLeavesOutMissingAndZeroReadings() {
        let result = ShareWorkoutFigures(durationS: 1111, avgHr: nil, maxHr: 0, kcal: 222, distanceM: 0, effort: nil)
        XCTAssertEqual(result, ShareWorkoutFigures(durationS: 1111, avgHr: nil, maxHr: nil, kcal: 222, distanceM: nil,
                                                   effort: nil))
    }
}
