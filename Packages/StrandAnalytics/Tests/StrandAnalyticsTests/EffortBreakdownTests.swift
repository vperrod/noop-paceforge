import XCTest
import WhoopProtocol
@testable import StrandAnalytics

/// `StrainScorer.breakdown` explains a score, so it must agree with `strain` on the number and add the
/// stretches that counted. Reserve here is 190 - 60 = 130, so the 50% line sits at 125 bpm.
final class EffortBreakdownTests: XCTestCase {
    private let t0 = 1_700_000_000

    /// 1 Hz readings: `calmSeconds` at 60 bpm, then `hardSeconds` at 140 bpm (zone 2, 61.5% of reserve).
    private func series(calmSeconds: Int, hardSeconds: Int) -> [HRSample] {
        (0..<calmSeconds).map { HRSample(ts: t0 + $0, bpm: 60) }
            + (0..<hardSeconds).map { HRSample(ts: t0 + calmSeconds + $0, bpm: 140) }
    }

    func testEffortMatchesTheScorer() {
        let hr = series(calmSeconds: 600, hardSeconds: 600)
        let b = StrainScorer.breakdown(hr, maxHR: 190, restingHR: 60)
        XCTAssertEqual(b.effort, StrainScorer.strain(hr, maxHR: 190, restingHR: 60))
    }

    func testThresholdIsHalfTheReserveAboveResting() {
        let b = StrainScorer.breakdown(series(calmSeconds: 600, hardSeconds: 600), maxHR: 190, restingHR: 60)
        XCTAssertEqual(b.thresholdBpm, 125.0, accuracy: 1e-9)
    }

    func testTenMinutesInZoneTwoIsTwentyTrimp() throws {
        let b = StrainScorer.breakdown(series(calmSeconds: 600, hardSeconds: 600), maxHR: 190, restingHR: 60)
        XCTAssertEqual(try XCTUnwrap(b.trimp), 20.0, accuracy: 1e-6)
    }

    func testCountedStretchStartsWhenTheHeartRateClimbs() {
        let b = StrainScorer.breakdown(series(calmSeconds: 600, hardSeconds: 600), maxHR: 190, restingHR: 60)
        XCTAssertEqual(b.stretches.first?.startTs, t0 + 600)
    }

    func testCountedStretchPeak() {
        let b = StrainScorer.breakdown(series(calmSeconds: 600, hardSeconds: 600), maxHR: 190, restingHR: 60)
        XCTAssertEqual(b.stretches.first?.peakBpm, 140)
    }

    func testCountedStretchMinutes() throws {
        let b = StrainScorer.breakdown(series(calmSeconds: 600, hardSeconds: 600), maxHR: 190, restingHR: 60)
        XCTAssertEqual(try XCTUnwrap(b.stretches.first).minutes, 10.0, accuracy: 1e-6)
    }

    func testAGapLongerThanTwoMinutesSplitsAStretch() {
        // 5 minutes of hard effort, a 5 minute hole, 5 more minutes; padded so the window is scoreable.
        let calm = (0..<600).map { HRSample(ts: t0 + $0, bpm: 60) }
        let first = (0..<300).map { HRSample(ts: t0 + 600 + $0, bpm: 140) }
        let second = (0..<300).map { HRSample(ts: t0 + 1200 + $0, bpm: 150) }
        let b = StrainScorer.breakdown(calm + first + second, maxHR: 190, restingHR: 60)
        XCTAssertEqual(b.stretches.map(\.peakBpm), [140, 150])
    }

    func testTopStretchesLongestFirst() {
        let calm = (0..<600).map { HRSample(ts: t0 + $0, bpm: 60) }
        let short = (0..<120).map { HRSample(ts: t0 + 600 + $0, bpm: 150) }
        let rest = (0..<120).map { HRSample(ts: t0 + 720 + $0, bpm: 60) }
        let long = (0..<360).map { HRSample(ts: t0 + 840 + $0, bpm: 140) }
        let b = StrainScorer.breakdown(calm + short + rest + long, maxHR: 190, restingHR: 60)
        XCTAssertEqual(b.topStretches(1).map(\.peakBpm), [140])
    }

    func testTooLittleDataIsRefusedWithTheSpanItHad() {
        let hr = (0..<30).map { HRSample(ts: t0 + $0, bpm: 140) }
        let b = StrainScorer.breakdown(hr, maxHR: 190, restingHR: 60)
        XCTAssertEqual(b.spanSeconds, 29)
    }

    func testTooLittleDataHasNoEffort() {
        let hr = (0..<30).map { HRSample(ts: t0 + $0, bpm: 140) }
        XCTAssertNil(StrainScorer.breakdown(hr, maxHR: 190, restingHR: 60).effort)
    }

    func testNoSamplesIsRefusedWithoutCrashing() {
        XCTAssertFalse(StrainScorer.breakdown([], maxHR: 190, restingHR: 60).enoughData)
    }

    func testBanisterCountsFromTheSedentaryFloor() {
        let b = StrainScorer.breakdown(series(calmSeconds: 600, hardSeconds: 600), maxHR: 190,
                                       restingHR: 60, method: .banister)
        XCTAssertEqual(b.thresholdBpm, 60 + 0.10 * 130, accuracy: 1e-9)
    }
}
