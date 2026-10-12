import XCTest
@testable import Strand

/// The Sleep Planner's hooks into the existing wind-down reminder. The planner's maths is pinned in
/// StrandAnalytics (`SleepPlannerTests`); these cover how its answer reaches the reminder.
@MainActor
final class SleepPlannerIntegrationTests: XCTestCase {

    private let keys = ["windDown.wakeMinutes", "windDown.sleepNeedMinutes", "windDown.leadMinutes",
                        "windDown.perDayWakeMinutes", SleepPlannerStore.useForReminderKey,
                        SleepPlannerStore.plannedSpanKey, SleepPlannerStore.presetKey]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        WindDownNudge.setWakeMinutes(7 * 60)
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testWithoutThePlannerTheReminderCountsBackOverTheSleepNeedSetting() {
        // 07:00 wake - 8 h need - 30 min lead = 22:30.
        XCTAssertEqual(WindDownNudge.nudgeMinuteOfDay(), 22 * 60 + 30)
    }

    func testFollowingThePlanTheReminderLandsTheLeadBeforeThePlannedBedtime() {
        // Goal 6 h 48 min + 15 min to fall asleep = 7 h 03 min: bedtime 23:57, reminder 30 min earlier.
        SleepPlannerStore.plannedSpanMin = 408 + 15
        SleepPlannerStore.useForReminder = true
        XCTAssertEqual(WindDownNudge.nudgeMinuteOfDay(), 23 * 60 + 27)
    }

    func testAPlanThatIsNotFollowedLeavesTheReminderAlone() {
        SleepPlannerStore.plannedSpanMin = 408 + 15
        SleepPlannerStore.useForReminder = false
        XCTAssertEqual(WindDownNudge.nudgeMinuteOfDay(), 22 * 60 + 30)
    }

    func testThePlannedSpanIsClampedToWhatTheReminderCanSchedule() {
        SleepPlannerStore.plannedSpanMin = 60
        SleepPlannerStore.useForReminder = true
        XCTAssertEqual(SleepPlannerStore.reminderSpanMinutes, 5 * 60)
    }

    func testPerWeekdayWakeOverridesStillApplyWhenFollowingThePlan() {
        SleepPlannerStore.plannedSpanMin = 480
        SleepPlannerStore.useForReminder = true
        WindDownNudge.setWakeOverride(weekday: 7, minutes: 9 * 60)
        // Saturday wakes at 09:00: 09:00 - 8 h - 30 min = 00:30.
        XCTAssertEqual(WindDownNudge.nudgeMinuteOfDay(forWeekday: 7), 30)
    }

    func testPresetDefaultsToPerformAndRoundTrips() {
        XCTAssertEqual(SleepPlannerStore.preset, .perform)
        SleepPlannerStore.preset = .peak
        XCTAssertEqual(SleepPlannerStore.preset, .peak)
    }

    func testPreviousDayKeyStepsBackOneCalendarDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Dublin")!
        XCTAssertEqual(SleepPlannerLoader.previousDayKey("2026-03-29", calendar: cal), "2026-03-28")
        XCTAssertEqual(SleepPlannerLoader.previousDayKey("2026-03-01", calendar: cal), "2026-02-28")
    }
}
