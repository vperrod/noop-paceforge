import XCTest
@testable import StrandAnalytics

final class ScoreReadoutTests: XCTestCase {

    private func driver(_ label: String, _ points: Int, _ value: String, _ baseline: String = "") -> ChargeDriver {
        ChargeDriver(label: label, deltaPoints: points, valueText: value, baselineText: baseline, verdict: "")
    }

    private func baseline(nValid: Int, status: BaselineStatus) -> BaselineState {
        BaselineState(baseline: 50, spread: 5, nValid: nValid, nightsSinceUpdate: 0, status: status)
    }

    // MARK: Charge

    func testChargeVerdictFollowsTheThirtyFourAndSixtySevenCutOffs() {
        func verdict(_ score: Double) -> String? {
            ScoreReadout.charge(score: score, drivers: [], hrvBaseline: nil).verdict
        }
        XCTAssertEqual(verdict(33.9), "Run down: under-recovered, keep it light")
        XCTAssertEqual(verdict(34), "Steady: partly recovered, a moderate day suits")
        XCTAssertEqual(verdict(66.9), "Steady: partly recovered, a moderate day suits")
        XCTAssertEqual(verdict(67), "Ready: well recovered, a hard day is fine")
    }

    func testTheDriverSentenceNamesTheBiggestMoverWithItsBaseline() {
        let drivers = [driver("Heart rate variability", 6, "62 ms", "55 ms baseline"), driver("Sleep quality", -3, "61%")]
        XCTAssertEqual(ScoreReadout.chargeDriverSentence(drivers),
                       "Mostly lifted by heart rate variability, 62 ms against your 55 ms baseline.")
    }

    func testANegativeMoverSaysPulledDownAndDropsAnEmptyBaseline() {
        let drivers = [driver("Sleep quality", -4, "61%"), driver("Resting heart rate", 1, "52 bpm", "53 bpm baseline")]
        XCTAssertEqual(ScoreReadout.chargeDriverSentence(drivers), "Mostly pulled down by sleep quality, 61%.")
    }

    func testDriversThatMovedNothingReadNearUsual() {
        let drivers = [driver("Heart rate variability", 0, "55 ms", "55 ms baseline")]
        XCTAssertEqual(ScoreReadout.chargeDriverSentence(drivers), "Everything sits near your usual.")
    }

    func testNoDriversGiveNoSentence() {
        XCTAssertNil(ScoreReadout.chargeDriverSentence([]))
    }

    func testAProvisionalBaselineShowsTheNightCounter() {
        let lines = ScoreReadout.charge(score: 60, drivers: [], hrvBaseline: baseline(nValid: 9, status: .provisional))
        XCTAssertEqual(lines.calibrationHave, 9)
        XCTAssertEqual(lines.calibrationNeed, 14)
    }

    func testATrustedBaselineHasNoCounter() {
        let lines = ScoreReadout.charge(score: 60, drivers: [], hrvBaseline: baseline(nValid: 20, status: .trusted))
        XCTAssertNil(lines.calibrationHave)
    }

    func testWithoutAScoreOnlyTheCounterIsLeft() {
        let lines = ScoreReadout.charge(score: nil, drivers: [], hrvBaseline: baseline(nValid: 2, status: .calibrating))
        XCTAssertNil(lines.verdict)
        XCTAssertNil(lines.driver)
        XCTAssertEqual(lines.calibrationHave, 2)
    }

    // MARK: Rest

    func testRestVerdictFollowsTheSeventyAndEightyFiveCutOffs() {
        func verdict(_ score: Double) -> String? {
            ScoreReadout.rest(score: score, hoursPct: nil, consistencyPct: nil, efficiencyPct: nil).verdict
        }
        XCTAssertEqual(verdict(69.9), "Poor: a short or broken night")
        XCTAssertEqual(verdict(70), "Sufficient: a decent night, short of your best")
        XCTAssertEqual(verdict(84.9), "Sufficient: a decent night, short of your best")
        XCTAssertEqual(verdict(85), "Optimal: a restorative night")
    }

    func testRestNamesTheLargestShortfallAgainstItsOwnBest() {
        // hours 74 of 100 is 26 % short; consistency 85 of 80 and efficiency 90 of 85 are not short.
        XCTAssertEqual(ScoreReadout.restDriverSentence(hoursPct: 74, consistencyPct: 85, efficiencyPct: 90),
                       "Mostly held back by hours slept, 74% of the sleep you needed.")
    }

    func testRestComparesShortfallsAsASharePerPart() {
        // efficiency 70 of 85 is 17.6 % short, hours 86 of 100 is 14 % short.
        XCTAssertEqual(ScoreReadout.restDriverSentence(hoursPct: 86, consistencyPct: 80, efficiencyPct: 70),
                       "Mostly held back by time awake in bed, 70% of it asleep.")
    }

    func testRestPartsWithinFivePercentOfBestHoldNothingBack() {
        XCTAssertEqual(ScoreReadout.restDriverSentence(hoursPct: 98, consistencyPct: 80, efficiencyPct: 90),
                       "Nothing is holding last night back.")
    }

    func testANonFiniteRestPartIsIgnoredRatherThanTrapping() {
        XCTAssertNil(ScoreReadout.restDriverSentence(hoursPct: .nan, consistencyPct: .infinity, efficiencyPct: nil))
        XCTAssertNil(ScoreReadout.effortDriverSentence(zones13Min: .nan, zones45Min: .infinity))
    }

    func testRestWithNoPartsHasNoSentence() {
        XCTAssertNil(ScoreReadout.restDriverSentence(hoursPct: nil, consistencyPct: nil, efficiencyPct: nil))
    }

    // MARK: Effort

    private func progress(_ effort: Double?, band: EffortTarget.Band?) -> EffortTarget.Progress {
        EffortTarget.progress(effort: effort, band: band)
    }

    func testEffortVerdictFollowsTodaysTargetBand() {
        let band = EffortTarget.Band(low: 55, high: 70)
        func verdict(_ effort: Double?) -> String? {
            ScoreReadout.effort(progress: progress(effort, band: band), zones13Min: nil, zones45Min: nil).verdict
        }
        XCTAssertEqual(verdict(42), "Building toward today's target")
        XCTAssertEqual(verdict(60), "Inside today's target")
        XCTAssertEqual(verdict(80), "Above today's target")
        XCTAssertNil(verdict(nil))
    }

    func testEffortWithoutATargetHasNoVerdict() {
        let lines = ScoreReadout.effort(progress: progress(42, band: nil), zones13Min: nil, zones45Min: nil)
        XCTAssertNil(lines.verdict)
    }

    func testEffortDriverIsTheHardZoneShareOfZoneMinutes() {
        XCTAssertEqual(ScoreReadout.effortDriverSentence(zones13Min: 57, zones45Min: 38),
                       "Zones 4-5 made up 38 of today's 95 minutes in heart-rate zones.")
    }

    func testEffortWithNoZoneMinutesSaysSo() {
        XCTAssertEqual(ScoreReadout.effortDriverSentence(zones13Min: 0, zones45Min: 0),
                       "No time in heart-rate zones yet today.")
        XCTAssertNil(ScoreReadout.effortDriverSentence(zones13Min: nil, zones45Min: nil))
    }
}
