import Foundation
import XCTest
@testable import StrandAnalytics

final class SleepPlannerTests: XCTestCase {

    private func calendar(_ zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func date(_ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func clock(_ cal: Calendar, _ date: Date) -> String {
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%02d-%02d %02d:%02d", c.month!, c.day!, c.hour!, c.minute!)
    }

    // MARK: Need breakdown

    func testEffortAtOrBelowTypicalAddsNothing() {
        XCTAssertEqual(SleepPlanner.effortExtraMin(yesterdayEffort: 40, typicalEffort: 40), 0)
        XCTAssertEqual(SleepPlanner.effortExtraMin(yesterdayEffort: 10, typicalEffort: 40), 0)
    }

    func testEffortHalfAboveTypicalAddsTheFullFortyFiveMinutes() {
        XCTAssertEqual(SleepPlanner.effortExtraMin(yesterdayEffort: 60, typicalEffort: 40), 45)
        XCTAssertEqual(SleepPlanner.effortExtraMin(yesterdayEffort: 95, typicalEffort: 40), 45)
    }

    func testEffortTwentyPercentAboveTypicalAddsEighteenMinutes() {
        XCTAssertEqual(SleepPlanner.effortExtraMin(yesterdayEffort: 48, typicalEffort: 40), 18)
    }

    func testNoTypicalEffortAddsNothing() {
        XCTAssertEqual(SleepPlanner.effortExtraMin(yesterdayEffort: 80, typicalEffort: nil), 0)
    }

    func testATinyTypicalEffortAddsNothingBecauseTheRatioMeansNothing() {
        XCTAssertEqual(SleepPlanner.effortExtraMin(yesterdayEffort: 20, typicalEffort: 2), 0)
    }

    func testTypicalEffortNeedsSevenDays() {
        XCTAssertNil(SleepPlanner.typicalEffort([40, 42, 38, 41, 39, 40]))
        XCTAssertEqual(SleepPlanner.typicalEffort([40, 42, 38, 41, 39, 40, 40])!, 40, accuracy: 1e-9)
    }

    func testDebtRepaymentIsAQuarterOfTheDebt() {
        XCTAssertEqual(SleepPlanner.debtRepaymentMin(debtMin: 100), 25)
    }

    func testDebtRepaymentIsCappedAtAnHour() {
        XCTAssertEqual(SleepPlanner.debtRepaymentMin(debtMin: 400), 60)
    }

    func testNoDebtRepaysNothing() {
        XCTAssertEqual(SleepPlanner.debtRepaymentMin(debtMin: 0), 0)
        XCTAssertEqual(SleepPlanner.debtRepaymentMin(debtMin: -30), 0)
    }

    func testNapsAreCreditedUpToAnHour() {
        XCTAssertEqual(SleepPlanner.napCreditMin(napMin: 30), 30)
        XCTAssertEqual(SleepPlanner.napCreditMin(napMin: 120), 60)
    }

    func testTonightsNeedIsTheSumOfItsParts() {
        let b = SleepPlanner.breakdown(baselineMin: 480, yesterdayEffort: 48, typicalEffort: 40, debtMin: 100, napMin: 30)
        XCTAssertEqual(b, SleepPlanner.Breakdown(baselineMin: 480, effortExtraMin: 18, debtRepaymentMin: 25, napCreditMin: 30))
        XCTAssertEqual(b.tonightMin, 493)
    }

    func testWithNoExtrasTonightsNeedIsTheBaseline() {
        let b = SleepPlanner.breakdown(baselineMin: 480, yesterdayEffort: nil, typicalEffort: nil, debtMin: 0, napMin: 0)
        XCTAssertEqual(b.tonightMin, 480)
    }

    // MARK: Presets

    func testPresetsAreSeventyEightyFivePercentAndTheFullNeed() {
        XCTAssertEqual(SleepPlanner.targetSleepMin(needMin: 480, preset: .getBy), 336)
        XCTAssertEqual(SleepPlanner.targetSleepMin(needMin: 480, preset: .perform), 408)
        XCTAssertEqual(SleepPlanner.targetSleepMin(needMin: 480, preset: .peak), 480)
    }

    func testPerformIsTheDefaultPreset() {
        XCTAssertEqual(SleepPlanner.Preset.default, .perform)
    }

    func testPresetRowsShowWhatEachCostsAgainstTheSelectedOne() {
        let cal = calendar("UTC")
        let wake = date(cal, 2026, 6, 10, 7)
        let rows = SleepPlanner.presetRows(needMin: 480, wake: wake, latencyMin: 15, selected: .perform)
        XCTAssertEqual(rows.map(\.sleepShiftMin), [-72, 0, 72])
        XCTAssertEqual(rows.map(\.bedtimeShiftMin), [72, 0, -72])
    }

    // MARK: Bedtime

    func testBedtimeFallsOnThePreviousEveningForAFullNight() {
        let cal = calendar("UTC")
        let plan = SleepPlanner.plan(wake: date(cal, 2026, 6, 10, 7), targetSleepMin: 480, latencyMin: 15)
        XCTAssertEqual(clock(cal, plan.bedtime), "06-09 22:45")
        XCTAssertEqual(clock(cal, plan.asleepBy), "06-09 23:00")
    }

    func testBedtimeCrossesMidnightForAShortNight() {
        let cal = calendar("UTC")
        let plan = SleepPlanner.plan(wake: date(cal, 2026, 6, 10, 7), targetSleepMin: 360, latencyMin: 15)
        XCTAssertEqual(clock(cal, plan.bedtime), "06-10 00:45")
        XCTAssertEqual(clock(cal, plan.asleepBy), "06-10 01:00")
    }

    func testBedtimeKeepsTheFullSleepAcrossTheSpringClockChange() {
        // Dublin goes forward on 29 March 2026: the night is an hour shorter on the clock, not in sleep.
        let cal = calendar("Europe/Dublin")
        let plan = SleepPlanner.plan(wake: date(cal, 2026, 3, 29, 7), targetSleepMin: 480, latencyMin: 15)
        XCTAssertEqual(clock(cal, plan.bedtime), "03-28 21:45")
    }

    func testBedtimeKeepsTheFullSleepAcrossTheAutumnClockChange() {
        // Dublin goes back on 25 October 2026: the night is an hour longer on the clock.
        let cal = calendar("Europe/Dublin")
        let plan = SleepPlanner.plan(wake: date(cal, 2026, 10, 25, 7), targetSleepMin: 480, latencyMin: 15)
        XCTAssertEqual(clock(cal, plan.bedtime), "10-24 23:45")
    }

    func testNextWakeIsTodayWhenItIsStillAhead() {
        let cal = calendar("UTC")
        let wake = SleepPlanner.nextWake(baseMinutes: 7 * 60, after: date(cal, 2026, 6, 10, 3), calendar: cal)!
        XCTAssertEqual(clock(cal, wake), "06-10 07:00")
    }

    func testNextWakeIsTomorrowOnceTodaysHasPassed() {
        let cal = calendar("UTC")
        let wake = SleepPlanner.nextWake(baseMinutes: 7 * 60, after: date(cal, 2026, 6, 10, 7), calendar: cal)!
        XCTAssertEqual(clock(cal, wake), "06-11 07:00")
    }

    func testNextWakeUsesThatWeekdaysOverride() {
        // 28 March 2026 is a Saturday; Sunday (weekday 1) wakes at 09:00.
        let cal = calendar("Europe/Dublin")
        let wake = SleepPlanner.nextWake(baseMinutes: 7 * 60, overrides: [1: 9 * 60],
                                         after: date(cal, 2026, 3, 28, 20), calendar: cal)!
        XCTAssertEqual(clock(cal, wake), "03-29 09:00")
    }

    func testNextWakeAcrossTheSpringChangeStaysAtTheWallClockTime() {
        let cal = calendar("Europe/Dublin")
        let wake = SleepPlanner.nextWake(baseMinutes: 7 * 60, after: date(cal, 2026, 3, 28, 22), calendar: cal)!
        XCTAssertEqual(clock(cal, wake), "03-29 07:00")
    }

    // MARK: Wake source

    func testTheWindDownWakeWinsOverTheAlarmAndTheTypicalWake() {
        let r = SleepPlanner.resolveWake(windDownMinutes: 390, alarmMinutes: 420, typicalMinutes: 450)
        XCTAssertEqual(r.minutes, 390)
        XCTAssertEqual(r.source, .windDown)
    }

    func testTheAlarmWinsOverTheTypicalWake() {
        let r = SleepPlanner.resolveWake(windDownMinutes: nil, alarmMinutes: 420, typicalMinutes: 450)
        XCTAssertEqual(r.source, .alarm)
    }

    func testTheTypicalWakeIsUsedWhenNothingIsSet() {
        let r = SleepPlanner.resolveWake(windDownMinutes: nil, alarmMinutes: nil, typicalMinutes: 450)
        XCTAssertEqual(r.minutes, 450)
        XCTAssertEqual(r.source, .typical)
    }

    func testWithNothingAtAllTheWakeIsSevenOClock() {
        let r = SleepPlanner.resolveWake(windDownMinutes: nil, alarmMinutes: nil, typicalMinutes: nil)
        XCTAssertEqual(r.minutes, 420)
        XCTAssertEqual(r.source, .fallback)
    }

    func testAWakeTimeSetOnThePlannerWinsOverEverySource() {
        let r = SleepPlanner.resolveWake(userMinutes: 360, windDownMinutes: 390, alarmMinutes: 420, typicalMinutes: 450)
        XCTAssertEqual(r.minutes, 360)
        XCTAssertEqual(r.source, .user)
    }

    func testAPlannerWakeTimeStandsOnItsOwnWithNoOtherSource() {
        let r = SleepPlanner.resolveWake(userMinutes: 5 * 60 + 45, windDownMinutes: nil, alarmMinutes: nil, typicalMinutes: nil)
        XCTAssertEqual(r.source, .user)
    }

    func testMidnightIsAValidPlannerWakeTime() {
        let r = SleepPlanner.resolveWake(userMinutes: 0, windDownMinutes: 390, alarmMinutes: nil, typicalMinutes: nil)
        XCTAssertEqual(r.source, .user)
    }

    func testResettingThePlannerWakeTimeHandsBackToTheWindDownWake() {
        let r = SleepPlanner.resolveWake(userMinutes: nil, windDownMinutes: 390, alarmMinutes: 420, typicalMinutes: 450)
        XCTAssertEqual(r.source, .windDown)
    }

    func testResettingThePlannerWakeTimeHandsBackToTheTypicalWakeWhenNothingElseIsSet() {
        let r = SleepPlanner.resolveWake(userMinutes: nil, windDownMinutes: nil, alarmMinutes: nil, typicalMinutes: 450)
        XCTAssertEqual(r.minutes, 450)
    }

    func testAStoredValueThatIsNotATimeOfDayIsIgnored() {
        let r = SleepPlanner.resolveWake(userMinutes: 24 * 60, windDownMinutes: nil, alarmMinutes: nil, typicalMinutes: 450)
        XCTAssertEqual(r.source, .typical)
    }

    func testValidWakeMinutesRejectsNegativeAndMissing() {
        XCTAssertNil(SleepPlanner.validWakeMinutes(-1))
        XCTAssertNil(SleepPlanner.validWakeMinutes(nil))
    }

    func testWeekdayOverridesApplyWhenTheWindDownSuppliedTheWake() {
        XCTAssertEqual(SleepPlanner.weekdayOverrides(for: .windDown, [1: 540]), [1: 540])
    }

    func testWeekdayOverridesApplyWhenTheAlarmSuppliedTheWake() {
        XCTAssertEqual(SleepPlanner.weekdayOverrides(for: .alarm, [1: 540]), [1: 540])
    }

    func testWeekdayOverridesAreIgnoredOnceTheWakeWasSetOnThePlanner() {
        XCTAssertEqual(SleepPlanner.weekdayOverrides(for: .user, [1: 540]), [:])
    }

    func testWeekdayOverridesAreIgnoredForTheTypicalAndDefaultWake() {
        XCTAssertEqual(SleepPlanner.weekdayOverrides(for: .typical, [1: 540]), [:])
    }

    func testAPlannerWakeTimeLandsOnEveryDayDespiteAWeekdayOverride() {
        let cal = calendar("Europe/Dublin")
        // 2026-10-18 is a Sunday (weekday 1), where the override would say 09:00.
        let overrides = SleepPlanner.weekdayOverrides(for: .user, [1: 9 * 60])
        let wake = SleepPlanner.nextWake(baseMinutes: 6 * 60, overrides: overrides, after: date(cal, 2026, 10, 17, 22), calendar: cal)!
        XCTAssertEqual(clock(cal, wake), "10-18 06:00")
    }

    func testAWeekdayOverrideStillRetimesTheWakeWhenNoPlannerTimeIsSet() {
        let cal = calendar("Europe/Dublin")
        let overrides = SleepPlanner.weekdayOverrides(for: .windDown, [1: 9 * 60])
        let wake = SleepPlanner.nextWake(baseMinutes: 6 * 60, overrides: overrides, after: date(cal, 2026, 10, 17, 22), calendar: cal)!
        XCTAssertEqual(clock(cal, wake), "10-18 09:00")
    }

    func testThePlannerSourceTextSaysItCameFromHere() {
        XCTAssertEqual(SleepPlanner.WakeSource.user.sourceText, "the wake time you set here")
    }

    func testTypicalWakeIsTheMedianAndNeedsSevenNights() {
        XCTAssertNil(SleepPlanner.typicalWakeMinutes([420, 430, 410, 440, 420, 415]))
        XCTAssertEqual(SleepPlanner.typicalWakeMinutes([500, 420, 430, 410, 440, 420, 415]), 420)
    }

    // MARK: Falling asleep

    private func stage(_ s: Int, _ e: Int, _ name: String) -> StageSegment { StageSegment(start: s, end: e, stage: name) }

    func testLatencyIsTheLeadingWakeBeforeTheFirstSleepEpoch() {
        let stages = [stage(1000, 1600, "wake"), stage(1600, 5000, "light"), stage(5000, 6000, "deep")]
        XCTAssertEqual(SleepPlanner.latencyMinutes(stages: stages, sessionStart: 1000)!, 10, accuracy: 1e-9)
    }

    func testASessionThatStartsAsleepHasNoLatency() {
        XCTAssertEqual(SleepPlanner.latencyMinutes(stages: [stage(1000, 5000, "light")], sessionStart: 1000)!, 0, accuracy: 1e-9)
    }

    func testAllWakeOrNoStagesHasNoLatency() {
        XCTAssertNil(SleepPlanner.latencyMinutes(stages: [stage(1000, 5000, "wake")], sessionStart: 1000))
        XCTAssertNil(SleepPlanner.latencyMinutes(stages: [], sessionStart: 1000))
    }

    func testTypicalLatencyIsTheMedianOfSevenOrMoreNights() {
        let r = SleepPlanner.typicalLatency([10, 12, 14, 20, 22, 30, 11])
        XCTAssertEqual(r.minutes, 14)
        XCTAssertTrue(r.isPersonal)
    }

    func testTypicalLatencyOfAnEvenCountAveragesTheMiddlePair() {
        XCTAssertEqual(SleepPlanner.typicalLatency([10, 12, 14, 16, 18, 20, 22, 24]).minutes, 17)
    }

    func testFewerThanSevenNightsFallBackToFifteenMinutes() {
        let r = SleepPlanner.typicalLatency([5, 6, 7, 8, 9, 10])
        XCTAssertEqual(r.minutes, 15)
        XCTAssertFalse(r.isPersonal)
    }

    func testLatencyIsFlooredAtFiveAndCappedAtSixty() {
        XCTAssertEqual(SleepPlanner.typicalLatency(Array(repeating: 0.5, count: 7)).minutes, 5)
        XCTAssertEqual(SleepPlanner.typicalLatency(Array(repeating: 90, count: 7)).minutes, 60)
    }

    // MARK: Calibration

    func testUnderSevenNightsNamesHowManyMoreAreNeeded() {
        XCTAssertEqual(SleepPlanner.calibration(nights: 3), .needsNights(4))
        XCTAssertEqual(SleepPlanner.calibration(nights: 3).note, "Needs 4 more nights to personalise")
    }

    func testSixNightsNeedsOneMoreNightSingular() {
        XCTAssertEqual(SleepPlanner.calibration(nights: 6).note, "Needs 1 more night to personalise")
    }

    func testSevenNightsIsCalibrated() {
        XCTAssertEqual(SleepPlanner.calibration(nights: 7), .ready)
        XCTAssertNil(SleepPlanner.calibration(nights: 7).note)
    }

    // MARK: "Wake me when I have slept enough"

    func testGoalAlarmIsLightsOutPlusFallingAsleepPlusTheGoal() {
        let cal = calendar("UTC")
        let r = SleepPlanner.goalAlarm(lightsOut: date(cal, 2026, 6, 9, 23), latencyMin: 15, goalSleepMin: 420,
                                       latestWake: date(cal, 2026, 6, 10, 7))
        XCTAssertEqual(clock(cal, r.alarm), "06-10 06:15")
        XCTAssertFalse(r.isCappedByLatestWake)
    }

    func testGoalAlarmNeverGoesPastTheLatestWake() {
        let cal = calendar("UTC")
        let r = SleepPlanner.goalAlarm(lightsOut: date(cal, 2026, 6, 10, 1), latencyMin: 15, goalSleepMin: 420,
                                       latestWake: date(cal, 2026, 6, 10, 7))
        XCTAssertEqual(clock(cal, r.alarm), "06-10 07:00")
        XCTAssertTrue(r.isCappedByLatestWake)
    }

    // MARK: Text

    func testDurationsReadInHoursAndMinutes() {
        XCTAssertEqual(SleepPlanner.durationText(45), "45 min")
        XCTAssertEqual(SleepPlanner.durationText(480), "8 h")
        XCTAssertEqual(SleepPlanner.durationText(465), "7 h 45 min")
    }

    func testSignedDurationsCarryTheirSign() {
        XCTAssertEqual(SleepPlanner.signedDurationText(30), "+30 min")
        XCTAssertEqual(SleepPlanner.signedDurationText(-20), "\u{2212}20 min")
        XCTAssertEqual(SleepPlanner.signedDurationText(0), "0 min")
        XCTAssertEqual(SleepPlanner.signedDurationText(75), "+1 h 15 min")
    }
}
