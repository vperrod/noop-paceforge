import XCTest
@testable import StrandAnalytics

/// Charge read in two parts. The cases pin the arithmetic on hand-worked z-scores: a baseline with mean 50 and sigma 10 makes
/// the z of a reading simply (value - 50) / 10.
final class ChargeSplitTests: XCTestCase {

    private func baseline(mean: Double, sigma: Double, nValid: Int = 14) -> BaselineState {
        BaselineState(baseline: mean, spread: sigma / 1.253, nValid: nValid,
                      nightsSinceUpdate: 0, status: nValid >= 14 ? .trusted : .calibrating)
    }

    private var hrvBase: BaselineState { baseline(mean: 50, sigma: 10) }

    func testHeartRateVariabilityAloneIsTheWholeBodyReading() {
        let split = RecoveryScorer.chargeSplit(hrv: 60, rhr: 60, resp: nil, hrvBaseline: hrvBase,
                                               rhrBaseline: nil, respBaseline: nil, sleepPerf: nil)
        XCTAssertEqual(split?.body?.value, 3.3)
        XCTAssertEqual(split?.body?.state, .settled)
        XCTAssertEqual(split?.body?.line, "Body signals: nervous system settled")
        XCTAssertEqual(split?.bodyInputs, ["hrv"])
        XCTAssertNil(split?.sleep)
    }

    func testBodyReadingIsTheChargeWeightedMeanOfThePresentTerms() {
        // hrv z -1 at weight 0.55 and resting-HR z -0.4 at 0.20: (-0.55 - 0.08) / 0.75 = -0.84.
        let split = RecoveryScorer.chargeSplit(hrv: 40, rhr: 62, resp: nil, hrvBaseline: hrvBase,
                                               rhrBaseline: baseline(mean: 60, sigma: 5), respBaseline: nil, sleepPerf: nil)
        XCTAssertEqual(split?.body?.z ?? 0, -0.84, accuracy: 0.0001)
        XCTAssertEqual(split?.body?.value, -2.8)
        XCTAssertEqual(split?.body?.state, .behind)
        XCTAssertEqual(split?.bodyInputs, ["hrv", "rhr"])
    }

    func testSleepIsLeftOutOfTheBodyReading() {
        let withSleep = RecoveryScorer.chargeSplit(hrv: 60, rhr: 60, resp: nil, hrvBaseline: hrvBase,
                                                   rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.5)
        XCTAssertEqual(withSleep?.body?.value, 3.3)
    }

    func testSleepIsRestAgainstAGoodNight() {
        // (0.61 - 0.85) / 0.12 = -2 spreads, so -6.6 on the scale, well short of a good night.
        let split = RecoveryScorer.chargeSplit(hrv: 50, rhr: 60, resp: nil, hrvBaseline: hrvBase,
                                               rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.61)
        XCTAssertEqual(split?.sleep?.value, -6.6)
        XCTAssertEqual(split?.sleep?.state, .wellBehind)
        XCTAssertEqual(split?.sleep?.line, "Sleep: well short of a good night")
    }

    func testAGoodNightReadsSettledAtZero() {
        let split = RecoveryScorer.chargeSplit(hrv: 50, rhr: 60, resp: nil, hrvBaseline: hrvBase,
                                               rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.85)
        XCTAssertEqual(split?.sleep?.value, 0)
        XCTAssertEqual(split?.sleep?.state, .settled)
    }

    func testSkinTemperatureDriftPullsTheBodyReadingDownAtItsSmallWeight() {
        // hrv z 0, skin z -0.4 at weight 0.05 of 0.60: -0.0333 spreads, -0.11 on the scale, rounds to -0.1.
        let split = RecoveryScorer.chargeSplit(hrv: 50, rhr: 60, resp: nil, hrvBaseline: hrvBase,
                                               rhrBaseline: nil, respBaseline: nil, sleepPerf: nil, skinTempDev: 0.4)
        XCTAssertEqual(split?.body?.value, -0.1)
        XCTAssertEqual(split?.bodyInputs, ["hrv", "skin_temp"])
    }

    func testTheScaleStopsAtTen() {
        let split = RecoveryScorer.chargeSplit(hrv: 100, rhr: 60, resp: nil, hrvBaseline: hrvBase,
                                               rhrBaseline: nil, respBaseline: nil, sleepPerf: nil)
        XCTAssertEqual(split?.body?.value, 10)
    }

    func testNoSplitWhileTheHeartRateVariabilityBaselineIsStillCalibrating() {
        let young = baseline(mean: 50, sigma: 10, nValid: 2)
        XCTAssertNil(RecoveryScorer.chargeSplit(hrv: 60, rhr: 60, resp: nil, hrvBaseline: young,
                                                rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.9))
    }

    func testAnUnusableRestingHeartRateBaselineIsNotACountedTerm() {
        let young = baseline(mean: 60, sigma: 5, nValid: 2)
        let split = RecoveryScorer.chargeSplit(hrv: 60, rhr: 90, resp: nil, hrvBaseline: hrvBase,
                                               rhrBaseline: young, respBaseline: nil, sleepPerf: nil)
        XCTAssertEqual(split?.bodyInputs, ["hrv"])
    }
}
