import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class HeartRateRecoveryTests: XCTestCase {
    private let end = 10_000

    private func denseEligible(endHR: Int = 170) -> [HRSample] {
        // Five minutes of continuous Zone-3+ effort, ending at the requested cessation HR.
        (end - 300...end).map { HRSample(ts: $0, bpm: $0 >= end - 30 ? endHR : 145) }
    }

    private func window(minutes: Int, values: [Int]) -> [HRSample] {
        let target = end + minutes * 60
        return values.enumerated().map { i, bpm in HRSample(ts: target - values.count / 2 + i, bpm: bpm) }
    }

    private func result(for eligibilitySamples: [HRSample]) -> HeartRateRecovery.Result? {
        HeartRateRecovery.calculate(
            samples: eligibilitySamples + window(minutes: 1, values: [140, 140, 140]),
            workoutStart: end - 300,
            workoutEnd: end,
            maxHR: 200
        )
    }

    func testCalculatesOneTwoAndFiveMinuteDropsFromRobustReadings() {
        let samples = denseEligible()
            + window(minutes: 1, values: [146, 146, 220, 146, 146]) // optical spike cannot own the reading
            + window(minutes: 2, values: [132, 132, 132])
            + window(minutes: 5, values: [112, 112, 112])

        let result = HeartRateRecovery.calculate(samples: samples.shuffled(), workoutStart: end - 300,
                                                 workoutEnd: end, maxHR: 200)
        XCTAssertEqual(result, .init(endHR: 170, after1Minute: 24, after2Minutes: 38, after5Minutes: 58, maxHR: 200))
    }

    func testRequiresSustainedHighIntensityRatherThanOnePeak() {
        var samples = (end - 300...end).map { HRSample(ts: $0, bpm: 120) }
        samples.append(HRSample(ts: end, bpm: 190))
        samples += window(minutes: 1, values: [140, 140, 140])
        XCTAssertNil(HeartRateRecovery.calculate(samples: samples, workoutStart: end - 300,
                                                 workoutEnd: end, maxHR: 200))
    }

    func testRejectsDisconnectedHighIntensityFragments() {
        // Plenty of nominally-high points, but each is separated by more than the continuity cap.
        let sparse = stride(from: end - 300, through: end, by: 15).map { HRSample(ts: $0, bpm: 170) }
        let samples = sparse + window(minutes: 1, values: [140, 140, 140])
        XCTAssertNil(HeartRateRecovery.calculate(samples: samples, workoutStart: end - 300,
                                                 workoutEnd: end, maxHR: 200))
    }

    func testRejectsThreeSeparatedFortySecondHighIntensityRuns() {
        let samples = [
            HRSample(ts: end - 140, bpm: 170), HRSample(ts: end - 130, bpm: 170),
            HRSample(ts: end - 120, bpm: 170), HRSample(ts: end - 110, bpm: 170),
            HRSample(ts: end - 100, bpm: 120),
            HRSample(ts: end - 90, bpm: 170), HRSample(ts: end - 80, bpm: 170),
            HRSample(ts: end - 70, bpm: 170), HRSample(ts: end - 60, bpm: 170),
            HRSample(ts: end - 50, bpm: 120),
            HRSample(ts: end - 40, bpm: 170), HRSample(ts: end - 30, bpm: 170),
            HRSample(ts: end - 20, bpm: 170), HRSample(ts: end - 10, bpm: 170),
            HRSample(ts: end, bpm: 120),
        ]

        XCTAssertNil(result(for: samples))
    }

    func testGapExactlyAtCapUsesLeftSampleAndExactMinimumIsAccepted() {
        let samples = stride(from: end - 120, through: end - 10, by: 10)
            .map { HRSample(ts: $0, bpm: 170) }
            + [HRSample(ts: end, bpm: 120)]

        XCTAssertEqual(result(for: samples), .init(endHR: 170, after1Minute: 30,
                                                  after2Minutes: nil, after5Minutes: nil, maxHR: 200))
    }

    func testGapOverCapResetsTheQualifyingRun() {
        let beforeGap = stride(from: end - 180, through: end - 110, by: 10)
            .map { HRSample(ts: $0, bpm: 170) }
        let afterGap = stride(from: end - 99, through: end - 9, by: 10)
            .map { HRSample(ts: $0, bpm: 170) }
            + [HRSample(ts: end, bpm: 170)]

        XCTAssertNil(result(for: beforeGap + afterGap))
    }

    func testBelowThresholdIntervalResetsTheQualifyingRun() {
        let samples = stride(from: end - 130, through: end, by: 10).map { ts in
            HRSample(ts: ts, bpm: ts == end - 60 ? 120 : 170)
        }

        XCTAssertNil(result(for: samples))
    }

    func testDuplicateTimestampDoesNotBreakAnOtherwiseContinuousRun() {
        let samples = stride(from: end - 120, through: end, by: 10)
            .map { HRSample(ts: $0, bpm: 170) }
            + [HRSample(ts: end - 60, bpm: 120)]

        XCTAssertEqual(result(for: samples), .init(endHR: 170, after1Minute: 30,
                                                  after2Minutes: nil, after5Minutes: nil, maxHR: 200))
    }

    func testDoesNotCreditPreWorkoutHeartRateTowardEligibility() {
        let samples = denseEligible() + window(minutes: 1, values: [140, 140, 140])
        // Only the final minute belongs to this workout. The preceding high HR must not make it eligible.
        XCTAssertNil(HeartRateRecovery.calculate(samples: samples, workoutStart: end - 60,
                                                 workoutEnd: end, maxHR: 200))
    }

    func testReturnsOnlyMeasurementsWithRealCoverage() {
        let samples = denseEligible()
            + window(minutes: 1, values: [150, 150, 150])
            + window(minutes: 5, values: [110, 110]) // fewer than the coverage gate
        let result = HeartRateRecovery.calculate(samples: samples, workoutStart: end - 300,
                                                 workoutEnd: end, maxHR: 200)
        XCTAssertEqual(result, .init(endHR: 170, after1Minute: 20, after2Minutes: nil, after5Minutes: nil, maxHR: 200))
    }

    func testNoPostWorkoutCoverageReturnsNil() {
        XCTAssertNil(HeartRateRecovery.calculate(samples: denseEligible(), workoutStart: end - 300,
                                                 workoutEnd: end, maxHR: 200))
    }

    func testAHeartRateRiseRemainsSignedInsteadOfBeingClamped() {
        let samples = denseEligible(endHR: 160) + window(minutes: 1, values: [165, 165, 165])
        let result = HeartRateRecovery.calculate(samples: samples, workoutStart: end - 300,
                                                 workoutEnd: end, maxHR: 200)
        XCTAssertEqual(result?.after1Minute, -5)
    }

    // MARK: - Sparse (watch) streams and the reason for "unavailable"

    /// A watch that records every 30 s: five minutes of effort, then readings at 1 and 2 minutes.
    private func sparseSamples() -> [HRSample] {
        let effort = stride(from: end - 300, through: end, by: 30).map { HRSample(ts: $0, bpm: $0 >= end - 30 ? 170 : 145) }
        return effort + [HRSample(ts: end + 60, bpm: 150), HRSample(ts: end + 120, bpm: 135)]
    }

    func testSparseStreamIsNotHardEnoughUnderTheStrapGap() {
        XCTAssertEqual(
            HeartRateRecovery.evaluate(samples: sparseSamples(), workoutStart: end - 300, workoutEnd: end,
                                       maxHR: 200, minimumSamplesPerReading: 1, minimumCessationSamples: 1),
            .unavailable(.notHardEnough))
    }

    func testSparseStreamMeasuresWithAWiderContinuityGap() {
        let result = HeartRateRecovery.calculate(samples: sparseSamples(), workoutStart: end - 300,
                                                 workoutEnd: end, maxHR: 200,
                                                 minimumSamplesPerReading: 1, minimumCessationSamples: 1,
                                                 maximumContinuousGapSeconds: 30)
        XCTAssertEqual(result, .init(endHR: 170, after1Minute: 20, after2Minutes: 35, after5Minutes: nil, maxHR: 200))
    }

    func testNoReadingsAfterTheEndIsReportedAsSuch() {
        XCTAssertEqual(
            HeartRateRecovery.evaluate(samples: denseEligible(), workoutStart: end - 300, workoutEnd: end, maxHR: 200),
            .unavailable(.noReadingsAfterEnd))
    }

    func testAGentleWorkoutIsNotHardEnough() {
        let gentle = (end - 300...end).map { HRSample(ts: $0, bpm: 110) }
        XCTAssertEqual(
            HeartRateRecovery.evaluate(samples: gentle + window(minutes: 1, values: [100, 100, 100]),
                                       workoutStart: end - 300, workoutEnd: end, maxHR: 200),
            .unavailable(.notHardEnough))
    }

    func testNoReadingsAtTheEndIsReportedAsSuch() {
        XCTAssertEqual(
            HeartRateRecovery.evaluate(samples: window(minutes: 1, values: [140, 140, 140]),
                                       workoutStart: end - 300, workoutEnd: end, maxHR: 200),
            .unavailable(.tooFewReadingsAtEnd))
    }

    func testMissingMaxHeartRateIsReportedAsSuch() {
        XCTAssertEqual(
            HeartRateRecovery.evaluate(samples: denseEligible(), workoutStart: end - 300, workoutEnd: end, maxHR: 0),
            .unavailable(.missingMaxHR))
    }

    // MARK: - Stop reference, tags and context bands

    /// 145 bpm effort, a 180 bpm surge 30-10 s before the end, then 160 bpm for the final 10 s.
    private func surgeThenSettle() -> [HRSample] {
        (end - 300...end).map { ts in
            HRSample(ts: ts, bpm: ts >= end - 10 ? 160 : (ts >= end - 30 ? 180 : 145))
        }
    }

    private func surgeResult(oneMinute: [Int], twoMinutes: [Int] = []) -> HeartRateRecovery.Result? {
        HeartRateRecovery.calculate(
            samples: surgeThenSettle() + window(minutes: 1, values: oneMinute)
                + (twoMinutes.isEmpty ? [] : window(minutes: 2, values: twoMinutes)),
            workoutStart: end - 300, workoutEnd: end, maxHR: 200, maxHRSource: .override)
    }

    func testStopReferenceIsTheMedianOfTheLastTenSecondsNotThePeak() {
        XCTAssertEqual(surgeResult(oneMinute: [130, 130, 130])?.endHR, 160)
    }

    func testPeakKeepsTheHighestHeartRateOfTheLastThirtySeconds() {
        XCTAssertEqual(surgeResult(oneMinute: [130, 130, 130])?.peakHR, 180)
    }

    func testDropIsMeasuredFromTheStopReference() {
        XCTAssertEqual(surgeResult(oneMinute: [130, 130, 130])?.after1Minute, 30)
    }

    func testResultReportsTheMaxHeartRateUsedAndItsSource() {
        let result = surgeResult(oneMinute: [130, 130, 130])
        XCTAssertEqual(result?.maxHRSource, .override)
    }

    func testResultReportsTheMaxHeartRateValueUsed() {
        XCTAssertEqual(surgeResult(oneMinute: [130, 130, 130])?.maxHR, 200)
    }

    func testEligibilityGateUsesTheSuppliedMaxHeartRate() {
        // 145 bpm is 72 % of 200 (eligible) but 58 % of 250 (not hard enough).
        XCTAssertEqual(
            HeartRateRecovery.evaluate(samples: denseEligible() + window(minutes: 1, values: [130, 130, 130]),
                                       workoutStart: end - 300, workoutEnd: end, maxHR: 250),
            .unavailable(.notHardEnough))
    }

    func testHeartRateRisingAtTwoMinutesIsTaggedAndNotBanded() {
        let result = surgeResult(oneMinute: [150, 150, 150], twoMinutes: [168, 168, 168])
        XCTAssertEqual(result?.risingAfterStop, true)
    }

    func testRisingAfterStopHasNoContextBand() {
        let result = surgeResult(oneMinute: [150, 150, 150], twoMinutes: [168, 168, 168])
        XCTAssertNil(result?.contextBand)
    }

    func testRiseOfSevenBpmIsNotTagged() {
        XCTAssertEqual(surgeResult(oneMinute: [140, 140, 140], twoMinutes: [167, 167, 167])?.risingAfterStop, false)
    }

    func testRiseOfEightBpmIsTagged() {
        XCTAssertEqual(surgeResult(oneMinute: [140, 140, 140], twoMinutes: [168, 168, 168])?.risingAfterStop, true)
    }

    func testWalkingCooldownIsTaggedWhenOneMinuteIsWithinFiveBpm() {
        XCTAssertEqual(surgeResult(oneMinute: [156, 156, 156])?.walking, true)
    }

    func testWalkingCooldownHasNoContextBand() {
        XCTAssertNil(surgeResult(oneMinute: [156, 156, 156])?.contextBand)
    }

    func testDropOfSixBpmIsNotWalking() {
        XCTAssertEqual(surgeResult(oneMinute: [154, 154, 154])?.walking, false)
    }

    func testRealRecoveryIsNeitherWalkingNorRising() {
        let result = surgeResult(oneMinute: [130, 130, 130], twoMinutes: [120, 120, 120])
        XCTAssertEqual([result?.walking, result?.risingAfterStop], [false, false])
    }

    func testBandAtTwelveBpmIsFlag() { XCTAssertEqual(HeartRateRecovery.ContextBand.band(forOneMinuteDrop: 12), .flag) }
    func testBandBelowZeroIsFlag() { XCTAssertEqual(HeartRateRecovery.ContextBand.band(forOneMinuteDrop: -3), .flag) }
    func testBandAtThirteenBpmIsLow() { XCTAssertEqual(HeartRateRecovery.ContextBand.band(forOneMinuteDrop: 13), .low) }
    func testBandAtEighteenBpmIsLow() { XCTAssertEqual(HeartRateRecovery.ContextBand.band(forOneMinuteDrop: 18), .low) }
    func testBandAtNineteenBpmIsTypical() { XCTAssertEqual(HeartRateRecovery.ContextBand.band(forOneMinuteDrop: 19), .typical) }
    func testBandAtThirtyBpmIsTypical() { XCTAssertEqual(HeartRateRecovery.ContextBand.band(forOneMinuteDrop: 30), .typical) }
    func testBandAtThirtyOneBpmIsStrong() { XCTAssertEqual(HeartRateRecovery.ContextBand.band(forOneMinuteDrop: 31), .strong) }

    func testResultContextBandFollowsTheOneMinuteDrop() {
        XCTAssertEqual(surgeResult(oneMinute: [130, 130, 130])?.contextBand, .typical)
    }

    func testSparseStreamFallsBackToTheThirtySecondMedianWhenNothingIsNearTheEnd() {
        // Readings stop at end-20: the cessation window has them, the last 10 s has none.
        let effort = (end - 300...end - 20).map { HRSample(ts: $0, bpm: $0 >= end - 30 ? 170 : 145) }
        let result = HeartRateRecovery.calculate(samples: effort + window(minutes: 1, values: [150]),
                                                 workoutStart: end - 300, workoutEnd: end, maxHR: 200,
                                                 minimumSamplesPerReading: 1, minimumCessationSamples: 3)
        XCTAssertEqual(result?.endHR, 170)
    }
}
