import XCTest

/// Unit checks for the daily timing plan's arithmetic (DailyTimingLogic.swift and the app's own caffeine rule, both compiled into
/// this bundle). All times are made up.
final class DailyTimingLogicTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    private func cues(bed: Int, asleep: Double? = 450, session: Int? = nil) -> [DailyTiming.Cue] {
        DailyTiming.cues(bed: bed, coffeeCutoff: CaffeineDecay.cutoffMinutesSinceMidnight(bedtimeMinutes: bed),
                         asleepMin: asleep, sessionStart: session)
    }

    func testCuesCountBackFromBedtimeWithDaylightFirst() {
        XCTAssertEqual(cues(bed: at(22, 30)).map { "\($0.kind.rawValue) \($0.minutes.map(DailyTiming.clock) ?? "-")" },
                       ["daylight -", "coffee 11:30", "hardTraining 18:30", "dimLights 19:30", "bed 22:30"])
    }

    func testABedtimeAfterMidnightWrapsEveryCueAndKeepsTheOrder() {
        XCTAssertEqual(cues(bed: at(0, 30)).map { "\($0.kind.rawValue) \($0.minutes.map(DailyTiming.clock) ?? "-")" },
                       ["daylight -", "coffee 13:30", "hardTraining 20:30", "dimLights 21:30", "bed 00:30"])
    }

    func testAShortNightOfThreeHundredAndEightyNineMinutesAddsTheNap() {
        XCTAssertEqual(cues(bed: at(22, 30), asleep: 389).map(\.kind),
                       [.daylight, .coffee, .nap, .hardTraining, .dimLights, .bed])
    }

    func testANightOfThreeHundredAndNinetyMinutesHasNoNap() {
        XCTAssertFalse(cues(bed: at(22, 30), asleep: 390).contains { $0.kind == .nap })
    }

    func testAMissingNightHasNoNap() {
        XCTAssertFalse(DailyTiming.needsNap(asleepMin: nil))
    }

    func testAMorningSessionComesBeforeTheCoffeeCutOff() {
        XCTAssertEqual(cues(bed: at(22, 30), session: at(6)).map(\.kind),
                       [.daylight, .session, .coffee, .hardTraining, .dimLights, .bed])
    }

    func testTheNextCueSkipsTheOnesAlreadyPassed() {
        let bed = at(0, 30)
        let bedDate = Date(timeIntervalSince1970: 1_900_000_000)
        // Five hours before a 00:30 bedtime it is 19:30: coffee (13:30) is gone, hard training (20:30) is next.
        let now = bedDate.addingTimeInterval(-5 * 3_600)
        XCTAssertEqual(DailyTiming.nextCue(cues(bed: bed), bed: bed, bedDate: bedDate, now: now)?.kind, .hardTraining)
    }

    func testAfterTheLastCueThereIsNoNextOne() {
        let bed = at(22, 30)
        let bedDate = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertNil(DailyTiming.nextCue(cues(bed: bed), bed: bed, bedDate: bedDate, now: bedDate.addingTimeInterval(-3_600)))
    }

    func testAnEveningSessionStatesTheGapToBed() {
        XCTAssertEqual(DailyTiming.gapToBed(start: at(19), durationMin: 45, bed: at(22, 52)), 187)
    }

    func testASessionAcrossMidnightEndsAfterBed() {
        XCTAssertEqual(DailyTiming.gapToBed(start: at(23, 30), durationMin: 90, bed: at(0, 30)), -30)
    }

    func testASessionEndingExactlyFourHoursBeforeBedIsOutsideTheWindow() {
        XCTAssertFalse(DailyTiming.endsInsideHardWindow(start: at(18), durationMin: 30, bed: at(22, 30)))
    }

    func testAnEarlyStartMovesOneHourADayAndTheRemainderLast() {
        XCTAssertEqual(DailyTiming.cumulativeShifts(total: 150), [60, 120, 150])
    }

    func testAWholeNumberOfHoursHasNoRemainderStep() {
        XCTAssertEqual(DailyTiming.cumulativeShifts(total: 120), [60, 120])
    }

    func testTheEarlyPlanMovesBedWithWake() {
        let plan = DailyTiming.earlyPlan(currentWake: at(6), bed: at(22, 30), targetWake: at(3, 30),
                                         startDay: "2030-03-30", eventDay: "2030-04-02")
        XCTAssertEqual(plan?.days, [.init(day: "2030-03-30", wake: at(5), bed: at(21, 30)),
                                    .init(day: "2030-03-31", wake: at(4), bed: at(20, 30)),
                                    .init(day: "2030-04-01", wake: at(3, 30), bed: at(20))])
    }

    func testAStartTooLateSaysTheTargetIsNotReached() {
        let plan = DailyTiming.earlyPlan(currentWake: at(7), bed: at(23), targetWake: at(4),
                                         startDay: "2030-04-01", eventDay: "2030-04-02")
        XCTAssertEqual(plan?.reachesTargetInTime, false)
    }

    func testALaterWakeTimeIsNotAnEarlyStart() {
        XCTAssertNil(DailyTiming.earlierBy(current: at(6), target: at(7)))
    }

    func testTheWeekendPatternUsesTheLastFourteenWakeDaysAndSkipsNaps() {
        func block(_ day: String, _ wake: Int, hours: Int = 7) -> DailyTiming.Block {
            .init(wakeDay: day, wakeMinutes: wake, lengthSec: hours * 3_600)
        }
        // 2030-03-13 is a Wednesday; 02-28 is the first of the fourteen days and 02-27 is outside them.
        let nights = DailyTiming.mainNights([
            block("2030-02-27", at(11)), block("2030-02-28", at(6)), block("2030-03-01", at(6, 10)),
            block("2030-03-02", at(8)), block("2030-03-03", at(8, 20)),
            block("2030-03-13", at(6, 20)), block("2030-03-13", at(15), hours: 1),
        ])
        XCTAssertEqual(DailyTiming.pattern(nights, today: "2030-03-13"),
                       .init(weekdayWake: at(6, 10), weekendWake: at(8, 10), weekdayNights: 3, weekendNights: 2))
    }
}
