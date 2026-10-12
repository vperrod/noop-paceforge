import Foundation
import XCTest
@testable import StrandAnalytics

final class EffortTargetTests: XCTestCase {

    // MARK: Band

    func testBandOnTheStoredAxisIsTheWhoopBandRescaled() {
        let band = EffortTarget.Band(whoopLow: 14, whoopHigh: 18)
        XCTAssertEqual(band.low, 14 * 100.0 / 21.0, accuracy: 1e-9)
        XCTAssertEqual(band.high, 18 * 100.0 / 21.0, accuracy: 1e-9)
    }

    // MARK: Progress

    private let band = EffortTarget.Band(low: 55, high: 70)

    func testBelowTheBandReadsHowMuchIsToGo() {
        let p = EffortTarget.progress(effort: 42, band: band)
        XCTAssertEqual(p.text, "Effort 42 of 55\u{2013}70: 13\u{2013}28 to go")
    }

    func testInsideTheBandReadsInYourRange() {
        let p = EffortTarget.progress(effort: 60, band: band)
        XCTAssertEqual(p.text, "Effort 60 of 55\u{2013}70: In your range")
    }

    func testTheBandEdgesCountAsInRange() {
        XCTAssertEqual(EffortTarget.progress(effort: 55, band: band).status, .inRange)
        XCTAssertEqual(EffortTarget.progress(effort: 70, band: band).status, .inRange)
    }

    func testAboveTheBandReadsByHowMuch() {
        let p = EffortTarget.progress(effort: 75, band: band)
        XCTAssertEqual(p.text, "Effort 75 of 55\u{2013}70: Above range by 5")
    }

    func testNoScoreYetKeepsTheBandAndSaysSo() {
        let p = EffortTarget.progress(effort: nil, band: band)
        XCTAssertEqual(p.text, "Effort target 55\u{2013}70: Not scored yet")
    }

    func testNoBandNeverGuessesATarget() {
        let p = EffortTarget.progress(effort: 42, band: nil)
        XCTAssertEqual(p.status, .noTarget)
    }

    func testTheToGoFiguresAddUpOnTheDisplayedNumbers() {
        // 41.6 shows as 42, the band 54.6-69.6 shows as 55-70: the sentence must say 13-28, not 13-28.0x.
        let p = EffortTarget.progress(effort: 41.6, band: EffortTarget.Band(low: 54.6, high: 69.6))
        XCTAssertEqual(p.text, "Effort 42 of 55\u{2013}70: 13\u{2013}28 to go")
    }

    func testTheZeroToTwentyOneScaleShowsOneDecimalAndTheNativeBand() {
        let band = EffortTarget.Band(whoopLow: 14, whoopHigh: 18)
        let p = EffortTarget.progress(effort: 50, band: band, displayFactor: 21.0 / 100.0)
        XCTAssertEqual(p.text, "Effort 10.5 of 14.0\u{2013}18.0: 3.5\u{2013}7.5 to go")
    }

    func testTheEffortAloneIsPrintedOnTheDisplayScale() {
        XCTAssertEqual(EffortTarget.progress(effort: 42, band: band).effortText, "42")
        XCTAssertEqual(EffortTarget.progress(effort: 50, band: band, displayFactor: 21.0 / 100.0).effortText, "10.5")
        XCTAssertNil(EffortTarget.progress(effort: nil, band: band).effortText)
    }

    func testFractionsStayOnTheStoredAxisWhateverTheDisplayScale() {
        let p = EffortTarget.progress(effort: 50, band: band, displayFactor: 21.0 / 100.0)
        XCTAssertEqual(p.effortFraction, 0.5)
    }

    // MARK: Training State thresholds

    func testHighLoadWithAGreenChargeIsBuilding() {
        XCTAssertEqual(EffortTarget.classify(recovery: .high, loadRatio: 1.4), .building)
    }

    func testHighLoadWithAYellowChargeIsOverreaching() {
        XCTAssertEqual(EffortTarget.classify(recovery: .mid, loadRatio: 1.3), .overreaching)
    }

    func testHighLoadWithARedChargeIsOverreaching() {
        XCTAssertEqual(EffortTarget.classify(recovery: .low, loadRatio: 1.5), .overreaching)
    }

    func testRisingLoadWithAGreenChargeIsBuilding() {
        XCTAssertEqual(EffortTarget.classify(recovery: .high, loadRatio: 1.1), .building)
    }

    func testRisingLoadWithAYellowChargeIsBalanced() {
        XCTAssertEqual(EffortTarget.classify(recovery: .mid, loadRatio: 1.2), .balanced)
    }

    func testRisingLoadWithARedChargeIsRestoring() {
        XCTAssertEqual(EffortTarget.classify(recovery: .low, loadRatio: 1.2), .restoring)
    }

    func testUsualLoadWithAnythingButRedIsBalanced() {
        XCTAssertEqual(EffortTarget.classify(recovery: .mid, loadRatio: 1.0), .balanced)
    }

    func testUsualLoadWithARedChargeIsRestoring() {
        XCTAssertEqual(EffortTarget.classify(recovery: .low, loadRatio: 0.8), .restoring)
    }

    func testLightLoadWithAGreenChargeIsBalanced() {
        XCTAssertEqual(EffortTarget.classify(recovery: .high, loadRatio: 0.6), .balanced)
    }

    func testLightLoadWithAYellowChargeIsRestoring() {
        XCTAssertEqual(EffortTarget.classify(recovery: .mid, loadRatio: 0.79), .restoring)
    }

    func testWithoutARatioOnlyARedChargeIsRestoring() {
        XCTAssertEqual(EffortTarget.classify(recovery: .low, loadRatio: nil), .restoring)
        XCTAssertEqual(EffortTarget.classify(recovery: .high, loadRatio: nil), .balanced)
    }

    func testChargeBandsSplitWhereTheOptimalBandDoes() {
        XCTAssertEqual(EffortTarget.RecoveryBand(recovery: 67), .high)
        XCTAssertEqual(EffortTarget.RecoveryBand(recovery: 66.9), .mid)
        XCTAssertEqual(EffortTarget.RecoveryBand(recovery: 34), .mid)
        XCTAssertEqual(EffortTarget.RecoveryBand(recovery: 33.9), .low)
        XCTAssertNil(EffortTarget.RecoveryBand(recovery: nil))
    }

    // MARK: Training State from the engine

    func testAStepUpInLoadWithAYellowChargeReadsOverreaching() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 50.0, count: 7) + Array(repeating: 100.0, count: 7))
        let reading = EffortTarget.trainingState(recovery: 50, load: load)
        XCTAssertEqual(reading.state, .overreaching)
    }

    func testAStepDownInLoadWithAYellowChargeReadsRestoring() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 100.0, count: 7) + Array(repeating: 20.0, count: 14))
        let reading = EffortTarget.trainingState(recovery: 50, load: load)
        XCTAssertEqual(reading.state, .restoring)
    }

    func testSteadyLoadWithAGreenChargeReadsBalanced() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 50.0, count: 42))
        let reading = EffortTarget.trainingState(recovery: 80, load: load)
        XCTAssertEqual(reading.state, .balanced)
    }

    func testTooLittleHistoryShowsNoWordAndSaysHowManyDaysAreNeeded() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 50.0, count: 10))
        let reading = EffortTarget.trainingState(recovery: 80, load: load)
        XCTAssertNil(reading.state)
        XCTAssertEqual(reading.calibration, .needsDays(4))
    }

    func testBetweenTheMinimumAndTheEstablishedWindowTheWordShowsWithACalibratingNote() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 50.0, count: 20))
        let reading = EffortTarget.trainingState(recovery: 80, load: load)
        XCTAssertEqual(reading.calibration, .calibrating(days: 20, of: 42))
        XCTAssertNotNil(reading.state)
    }

    func testEstablishedHistoryHasNoCalibrationNote() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 50.0, count: 42))
        XCTAssertNil(EffortTarget.trainingState(recovery: 80, load: load).calibration.note)
    }

    func testAnUnscoredChargeShowsNoWord() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 50.0, count: 42))
        XCTAssertNil(EffortTarget.trainingState(recovery: nil, load: load).state)
    }

    func testAVeryLowChronicLoadHasNoRatio() {
        let load = TrainingLoadEngine.evaluateDense(Array(repeating: 2.0, count: 42))
        XCTAssertNil(EffortTarget.trainingState(recovery: 80, load: load).loadRatio)
    }

    func testTheCalibrationNoteNamesTheDaysStillNeeded() {
        XCTAssertEqual(EffortTarget.LoadCalibration.needsDays(1).note, "Needs 1 more day of Effort to read your load")
        XCTAssertEqual(EffortTarget.LoadCalibration.needsDays(4).note, "Needs 4 more days of Effort to read your load")
    }

    func testTheCalibratingNoteNamesHowFarTheBaselineHasFilled() {
        XCTAssertEqual(EffortTarget.LoadCalibration.calibrating(days: 20, of: 42).note, "Still calibrating: 20 of 42 days")
    }
}
