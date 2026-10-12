import XCTest
@testable import Strand

/// Weekly goals: the Monday-to-Sunday week, the clock arithmetic for bedtimes, how each target is counted and
/// what the presets ask for. All values are made up.
final class WeeklyGoalsTests: XCTestCase {

    private func days(_ build: (Int) -> WeeklyGoalDay) -> [WeeklyGoalDay] { (0..<7).map(build) }
    private let week = WeeklyGoalEngine.weekDays(startingAt: "2030-03-11")

    // MARK: Week

    func testAWednesdayBelongsToTheWeekThatBeganOnMonday() {
        XCTAssertEqual(WeeklyGoalEngine.weekStart(containing: "2030-03-13"), "2030-03-11")
    }

    func testMondayStartsItsOwnWeek() {
        XCTAssertEqual(WeeklyGoalEngine.weekStart(containing: "2030-03-11"), "2030-03-11")
    }

    func testSundayBelongsToTheWeekBeforeIt() {
        XCTAssertEqual(WeeklyGoalEngine.weekStart(containing: "2030-03-17"), "2030-03-11")
    }

    func testAWeekCanStartInTheMonthBefore() {
        XCTAssertEqual(WeeklyGoalEngine.weekStart(containing: "2030-04-02"), "2030-04-01")
        XCTAssertEqual(WeeklyGoalEngine.weekStart(containing: "2030-03-31"), "2030-03-25")
    }

    func testAWeekCanStartInTheYearBefore() {
        XCTAssertEqual(WeeklyGoalEngine.weekStart(containing: "2031-01-01"), "2030-12-30")
    }

    func testTheWeekHasSevenDaysMondayFirst() {
        XCTAssertEqual(week, ["2030-03-11", "2030-03-12", "2030-03-13", "2030-03-14", "2030-03-15", "2030-03-16", "2030-03-17"])
    }

    func testTheNextWeekStartsAgainOnMonday() {
        XCTAssertEqual(WeeklyGoalEngine.weekStart(containing: "2030-03-18"), "2030-03-18")
    }

    // MARK: Clock

    func testDistanceTakesTheShorterWayRound() {
        XCTAssertEqual(WeeklyGoalEngine.circularDistance(23 * 60 + 30, 30), 60)
    }

    func testDistanceOfTheSameMinuteIsZero() {
        XCTAssertEqual(WeeklyGoalEngine.circularDistance(600, 600), 0)
    }

    func testLaterIsPositiveAndEarlierIsNegative() {
        XCTAssertEqual([WeeklyGoalEngine.signedDifference(23 * 60 + 10, from: 22 * 60 + 40),
                        WeeklyGoalEngine.signedDifference(22 * 60, from: 22 * 60 + 40)], [30, -40])
    }

    func testSignedDifferenceCrossesMidnight() {
        XCTAssertEqual(WeeklyGoalEngine.signedDifference(10, from: 23 * 60 + 50), 20)
    }

    func testUsualBedtimeAveragesAcrossMidnight() {
        let usual = WeeklyGoalEngine.usualBedtime([23 * 60 + 30, 30])
        XCTAssertEqual(WeeklyGoalEngine.circularDistance(usual ?? 720, 0), 0)
    }

    func testUsualBedtimeOfOneNightIsThatNight() {
        XCTAssertEqual(WeeklyGoalEngine.usualBedtime([22 * 60 + 45]), 22 * 60 + 45)
    }

    func testNoBedtimesHaveNoUsualBedtime() {
        XCTAssertNil(WeeklyGoalEngine.usualBedtime([]))
    }

    // MARK: Counting

    func testSleepNightsCountSevenHoursOrMore() {
        let list = days { WeeklyGoalDay(day: week[$0], sleepMinutes: $0 < 3 ? 7 * 60 : 6 * 60 + 59) }
        XCTAssertEqual(WeeklyGoalEngine.value(for: .sleepHours, days: list, usualBedtime: nil), 3)
    }

    func testANightWithNoSleepRecordIsNotCounted() {
        let list = [WeeklyGoalDay(day: week[0])]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .sleepHours, days: list, usualBedtime: nil), 0)
    }

    func testBedtimeWithinFortyFiveMinutesOfUsualCounts() {
        let list = [WeeklyGoalDay(day: week[0], bedtimeMinute: 22 * 60 + 45),
                    WeeklyGoalDay(day: week[1], bedtimeMinute: 22 * 60 + 46),
                    WeeklyGoalDay(day: week[2], bedtimeMinute: 22 * 60)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .sleepConsistency, days: list, usualBedtime: 22 * 60), 2)
    }

    func testRegularityNeedsAUsualBedtime() {
        let list = [WeeklyGoalDay(day: week[0], bedtimeMinute: 22 * 60)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .sleepConsistency, days: list, usualBedtime: nil), 0)
    }

    func testRegularityCountsAcrossMidnight() {
        let list = [WeeklyGoalDay(day: week[0], bedtimeMinute: 20)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .sleepConsistency, days: list, usualBedtime: 23 * 60 + 50), 1)
    }

    func testHardMinutesAreSummed() {
        let list = [WeeklyGoalDay(day: week[0], zone45Minutes: 12.5), WeeklyGoalDay(day: week[1]),
                    WeeklyGoalDay(day: week[2], zone45Minutes: 30)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .zone45Minutes, days: list, usualBedtime: nil), 42.5)
    }

    func testActiveDaysNeedEightThousandSteps() {
        let list = [WeeklyGoalDay(day: week[0], steps: 8_000), WeeklyGoalDay(day: week[1], steps: 7_999),
                    WeeklyGoalDay(day: week[2], steps: 12_000)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .steps, days: list, usualBedtime: nil), 2)
    }

    func testWindDownCountsNightsAsleepWithinThirtyMinutesOfThePlan() {
        let list = [WeeklyGoalDay(day: week[0], bedtimeMinute: 22 * 60 + 30, plannedBedtimeMinute: 22 * 60),
                    WeeklyGoalDay(day: week[1], bedtimeMinute: 22 * 60 + 31, plannedBedtimeMinute: 22 * 60),
                    WeeklyGoalDay(day: week[2], bedtimeMinute: 21 * 60, plannedBedtimeMinute: 22 * 60)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .windDown, days: list, usualBedtime: nil), 2)
    }

    func testWindDownWithoutAPlannedBedtimeCountsNothing() {
        let list = [WeeklyGoalDay(day: week[0], bedtimeMinute: 21 * 60)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .windDown, days: list, usualBedtime: nil), 0)
    }

    func testWindDownAfterMidnightPlanIsComparedOnTheClock() {
        let list = [WeeklyGoalDay(day: week[0], bedtimeMinute: 10, plannedBedtimeMinute: 23 * 60 + 50)]
        XCTAssertEqual(WeeklyGoalEngine.value(for: .windDown, days: list, usualBedtime: nil), 1)
    }

    // MARK: Progress

    func testProgressFractionIsCappedAtOne() {
        XCTAssertEqual(WeeklyGoalProgress(metric: .steps, value: 7, target: 5).fraction, 1)
    }

    func testProgressFractionIsTheShareOfTheTarget() {
        XCTAssertEqual(WeeklyGoalProgress(metric: .zone45Minutes, value: 30, target: 60).fraction, 0.5)
    }

    func testReachingTheTargetMarksItMet() {
        XCTAssertTrue(WeeklyGoalProgress(metric: .steps, value: 5, target: 5).isMet)
    }

    func testBelowTheTargetIsNotMet() {
        XCTAssertFalse(WeeklyGoalProgress(metric: .steps, value: 4, target: 5).isMet)
    }

    func testProgressTextReadsAsOfTheTarget() {
        XCTAssertEqual(WeeklyGoalProgress(metric: .sleepHours, value: 4, target: 5).valueText, "4 of 5 nights")
    }

    func testProgressFollowsThePlansTargetsInOrder() {
        let list = days { WeeklyGoalDay(day: week[$0], sleepMinutes: 8 * 60, steps: 9_000) }
        let result = WeeklyGoalEngine.progress(plan: .preset(.feelBetter), days: list, usualBedtime: nil)
        XCTAssertEqual(result.map(\.metric), [.steps, .sleepHours, .sleepConsistency])
    }

    func testProgressValuesComeFromTheWeek() {
        let list = days { WeeklyGoalDay(day: week[$0], sleepMinutes: 8 * 60, steps: 9_000) }
        let result = WeeklyGoalEngine.progress(plan: .preset(.feelBetter), days: list, usualBedtime: nil)
        XCTAssertEqual(result.map(\.value), [7, 7, 0])
    }

    // MARK: Presets and custom

    func testEveryPresetAsksForTwoOrThreeTargets() {
        for preset in [WeeklyGoalPreset.sleepDeeper, .boostFitness, .feelBetter] {
            XCTAssertTrue((2...3).contains(preset.targets.count), "\(preset.title) should have two or three targets.")
        }
    }

    func testPresetTargetsAreInTheirOwnRanges() {
        for preset in WeeklyGoalPreset.allCases {
            for target in preset.targets {
                XCTAssertTrue(target.metric.targetRange.contains(target.target), "\(preset.title) \(target.metric.title)")
            }
        }
    }

    func testPresetTitlesAreTheThreeNamed() {
        XCTAssertEqual([WeeklyGoalPreset.sleepDeeper, .boostFitness, .feelBetter].map(\.title),
                       ["Sleep deeper", "Boost fitness", "Feel better"])
    }

    func testCustomPlanKeepsAtMostThreeTargets() {
        let picks = WeeklyGoalMetric.allCases.map { WeeklyGoalTarget(metric: $0, target: $0.defaultTarget) }
        XCTAssertEqual(WeeklyGoalPlan.custom(picks).targets.count, 3)
    }

    func testCustomPlanKeepsOneTargetPerMetric() {
        let picks = [WeeklyGoalTarget(metric: .steps, target: 3), WeeklyGoalTarget(metric: .steps, target: 6)]
        XCTAssertEqual(WeeklyGoalPlan.custom(picks).targets, [WeeklyGoalTarget(metric: .steps, target: 3)])
    }

    func testCustomTargetsAreClampedToTheirRange() {
        let plan = WeeklyGoalPlan.custom([WeeklyGoalTarget(metric: .steps, target: 40),
                                          WeeklyGoalTarget(metric: .zone45Minutes, target: 1)])
        XCTAssertEqual(plan.targets.map(\.target), [7, 10])
    }

    func testOnlyAPlanWithWindDownNeedsTheReminder() {
        XCTAssertEqual([WeeklyGoalPlan.preset(.sleepDeeper).needsWindDown, WeeklyGoalPlan.preset(.boostFitness).needsWindDown],
                       [true, false])
    }

    // MARK: Storage

    func testThePlanSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "weekly-goals-test")!
        defaults.removePersistentDomain(forName: "weekly-goals-test")
        WeeklyGoalStore.save(.preset(.boostFitness), to: defaults)
        XCTAssertEqual(WeeklyGoalStore.load(defaults), .preset(.boostFitness))
    }

    func testClearingThePlanRemovesIt() {
        let defaults = UserDefaults(suiteName: "weekly-goals-clear")!
        defaults.removePersistentDomain(forName: "weekly-goals-clear")
        WeeklyGoalStore.save(.preset(.feelBetter), to: defaults)
        WeeklyGoalStore.save(nil, to: defaults)
        XCTAssertNil(WeeklyGoalStore.load(defaults))
    }
}
