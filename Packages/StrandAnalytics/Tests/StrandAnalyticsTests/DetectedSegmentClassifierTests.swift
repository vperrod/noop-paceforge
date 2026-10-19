import XCTest
@testable import StrandAnalytics

/// The walk-or-workout call on a detected stretch, the "already recorded" match and the auto-save rule.
/// The cases mirror what My Day lists on a normal day: short, calm stretches around 85 to 105 bpm.
final class DetectedSegmentClassifierTests: XCTestCase {

    private typealias C = DetectedSegmentClassifier

    /// A person with HRmax 185 and resting 52: reserve 133, 60 % of it is 132, zone 3 starts at 130 (70 % of
    /// HRmax, rounded). The ceiling for a walk's mean is therefore 130 bpm.
    private let profile = C.Profile(maxHr: 185, restingHr: 52, zone3LowerBpm: 130)

    private func guess(_ minutes: Int, avg: Int, peak: Int? = nil, series: [Double] = [],
                       gait: C.GaitMix? = nil, profile: C.Profile? = nil) -> C.Guess {
        C.classify(durationSec: minutes * 60, avgBpm: avg, peakBpm: peak ?? avg + 15, minuteBpm: series,
                   gait: gait, profile: profile ?? self.profile)
    }

    // MARK: The screenshot's segments

    func testFourteenMinutesAt101IsAWalk() { XCTAssertEqual(guess(14, avg: 101), .walk) }
    func testFourteenMinutesAt86IsAWalk() { XCTAssertEqual(guess(14, avg: 86), .walk) }
    func testTwentyMinutesAt93IsAWalk() { XCTAssertEqual(guess(20, avg: 93), .walk) }
    func testEighteenMinutesAt98IsAWalk() { XCTAssertEqual(guess(18, avg: 98), .walk) }
    func testFifteenMinutesAt88IsAWalk() { XCTAssertEqual(guess(15, avg: 88), .walk) }
    func testTwentyFiveMinutesAt135IsAWorkout() { XCTAssertEqual(guess(25, avg: 135, peak: 152), .workout) }

    func testAWorkoutAt135WithTheDefaultProfileIsStillAWorkout() {
        XCTAssertEqual(guess(25, avg: 135, peak: 152, profile: C.Profile()), .workout)
    }

    // MARK: Duration boundaries

    func testEightMinutesIsStillAWalk() { XCTAssertEqual(guess(8, avg: 100), .walk) }
    func testSevenMinutesFiftyNineIsNotOffered() {
        XCTAssertEqual(C.classify(durationSec: 479, avgBpm: 100, peakBpm: 110, minuteBpm: [], gait: nil, profile: profile), .workout)
    }
    func testTwoHoursIsStillAWalk() { XCTAssertEqual(guess(120, avg: 105), .walk) }
    func testTwoHoursAndOneSecondIsNotOffered() {
        XCTAssertEqual(C.classify(durationSec: 7201, avgBpm: 105, peakBpm: 115, minuteBpm: [], gait: nil, profile: profile), .workout)
    }

    // MARK: Heart-rate boundaries

    func testJustUnderTheCeilingIsAWalk() { XCTAssertEqual(guess(30, avg: 129, peak: 140), .walk) }
    func testExactlyOnTheCeilingIsAWorkout() { XCTAssertEqual(guess(30, avg: 130, peak: 140), .workout) }

    func testTheReserveShareLimitsAProfileWithAHighRestingRate() {
        // Resting 85, max 160: 60 % of the 75 bpm reserve is 130, but zone 3 only starts at 112. The lower wins.
        let p = C.Profile(maxHr: 160, restingHr: 85, zone3LowerBpm: 112)
        XCTAssertEqual(guess(20, avg: 112, peak: 120, profile: p), .workout)
    }

    func testTheReserveShareBindsWhenItIsLowerThanZoneThree() {
        // Resting 40, max 190: 60 % of the 150 bpm reserve is 130, below the default zone 3 start at 133.
        let p = C.Profile(maxHr: 190, restingHr: 40)
        XCTAssertEqual(guess(20, avg: 131, peak: 140, profile: p), .workout)
    }

    func testAMissingProfileFallsBackToTheDefaults() {
        XCTAssertEqual(guess(20, avg: 100, profile: C.Profile()), .walk)
    }

    func testAnImplausibleMaxHeartRateIsIgnored() {
        XCTAssertEqual(C.Profile(maxHr: 40).resolvedMax, C.defaultMaxHr)
    }

    // MARK: Steadiness

    func testASteadyMinuteSeriesIsAWalk() {
        XCTAssertEqual(guess(20, avg: 98, series: (0..<20).map { 98 + Double($0 % 3) }), .walk)
    }

    func testAHighlyVariableSeriesIsAWorkout() {
        // Intervals around a calm mean: 70 / 130 alternating has a standard deviation of 30.
        XCTAssertEqual(guess(20, avg: 100, series: (0..<20).map { $0 % 2 == 0 ? 70 : 130 }), .workout)
    }

    func testThreeMinutesInZoneThreeInARowIsAWorkout() {
        var series = [Double](repeating: 95, count: 20)
        series[8] = 131; series[9] = 133; series[10] = 135
        XCTAssertEqual(guess(20, avg: 100, series: series), .workout)
    }

    func testTwoMinutesInZoneThreeIsAHillNotAnEffort() {
        var series = [Double](repeating: 95, count: 20)
        series[8] = 131; series[9] = 133
        XCTAssertEqual(guess(20, avg: 97, series: series), .walk)
    }

    func testWithoutASeriesAPeakFarAboveTheMeanIsAWorkout() {
        XCTAssertEqual(guess(20, avg: 100, peak: 141), .workout)
    }

    func testWithoutASeriesAPeakFortyAboveTheMeanIsStillAWalk() {
        XCTAssertEqual(guess(20, avg: 100, peak: 140), .walk)
    }

    // MARK: Strap gait ticks

    func testManyRunTicksMakeAnEasyJogAWorkout() {
        let gait = C.GaitMix(walkShare: 0.2, runShare: 0.7, classedTicks: 400)
        XCTAssertEqual(guess(20, avg: 112, gait: gait), .workout)
    }

    func testMostlyStillTicksMeanItWasNotAWalk() {
        let gait = C.GaitMix(walkShare: 0.1, runShare: 0, classedTicks: 400)
        XCTAssertEqual(guess(20, avg: 95, gait: gait), .workout)
    }

    func testMostlyWalkTicksConfirmAWalk() {
        let gait = C.GaitMix(walkShare: 0.8, runShare: 0.02, classedTicks: 400)
        XCTAssertEqual(guess(20, avg: 112, gait: gait), .walk)
    }

    func testTooFewClassedTicksAreIgnored() {
        let gait = C.GaitMix(walkShare: 0, runShare: 1, classedTicks: 19)
        XCTAssertEqual(guess(20, avg: 95, gait: gait), .walk)
    }

    func testGaitMixCountsOnlyClassedTicks() {
        XCTAssertEqual(C.GaitMix.from(classes: [1, 1, 2, 0, nil, nil]), C.GaitMix(walkShare: 0.5, runShare: 0.25, classedTicks: 4))
    }

    func testGaitMixIsNilWhenNothingWasClassed() {
        XCTAssertNil(C.GaitMix.from(classes: [nil, nil]))
    }

    // MARK: Minute means

    func testMinuteMeansAverageEachMinuteAndSkipHoles() {
        let samples: [(ts: Int, bpm: Double)] = [(0, 90), (30, 100), (60, 110), (240, 120)]
        XCTAssertEqual(C.minuteMeans(samples: samples, start: 0, end: 300), [95, 110, 120])
    }

    // MARK: Matching a recorded workout

    private let run = C.Recorded(startTs: 1000, endTs: 3000, sport: "Running")

    func testASegmentMostlyInsideARecordedWorkoutMatchesIt() {
        XCTAssertEqual(C.recordedMatch(startTs: 1200, endTs: 2200, in: [run])?.sport, "Running")
    }

    func testExactlyHalfCoveredDoesNotMatch() {
        XCTAssertNil(C.recordedMatch(startTs: 2000, endTs: 4000, in: [run]))
    }

    func testJustOverHalfCoveredMatches() {
        XCTAssertEqual(C.recordedMatch(startTs: 1999, endTs: 3999, in: [run])?.sport, "Running")
    }

    func testTouchingWithoutOverlapDoesNotMatch() {
        XCTAssertNil(C.recordedMatch(startTs: 3000, endTs: 4000, in: [run]))
    }

    func testTheBiggestOverlapWins() {
        let walk = C.Recorded(startTs: 1000, endTs: 1500, sport: "Walking")
        XCTAssertEqual(C.recordedMatch(startTs: 1000, endTs: 2000, in: [walk, run])?.sport, "Running")
    }

    // MARK: Auto-save rule (on by default in the app; the setting is read by the loader)

    private func autoSave(_ guess: C.Guess = .walk, recorded: Bool = false, minutes: Int = 20, endedAgo: Int = 3600,
                          enabled: Bool = true) -> Bool {
        C.shouldAutoSave(guess: guess, isRecorded: recorded, durationSec: minutes * 60, endTs: 100_000 - endedAgo,
                         nowTs: 100_000, enabled: enabled)
    }

    func testAWalkIsSavedWhenTheSettingIsOn() { XCTAssertTrue(autoSave()) }
    func testNothingIsSavedWhenTheSettingIsOff() { XCTAssertFalse(autoSave(enabled: false)) }
    func testAWorkoutGuessIsNeverSavedByItself() { XCTAssertFalse(autoSave(.workout)) }
    func testARecordedSegmentIsNeverSavedAgain() { XCTAssertFalse(autoSave(recorded: true)) }
    func testFifteenMinutesIsLongEnough() { XCTAssertTrue(autoSave(minutes: 15)) }
    func testFourteenMinutesIsTooShort() { XCTAssertFalse(autoSave(minutes: 14)) }
    func testAWalkThatEndedTenMinutesAgoIsSettled() { XCTAssertTrue(autoSave(endedAgo: 600)) }
    func testAWalkThatEndedAMinuteAgoMayStillBeGoing() { XCTAssertFalse(autoSave(endedAgo: 60)) }

    func testTheSettingIsOnWhenItWasNeverStored() { XCTAssertTrue(C.autoSaveEnabled(stored: nil)) }
    func testTheSettingStaysOffWhenSwitchedOff() { XCTAssertFalse(C.autoSaveEnabled(stored: false)) }
    func testTheSettingIsOnWhenSwitchedOn() { XCTAssertTrue(C.autoSaveEnabled(stored: true)) }
}
