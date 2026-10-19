import XCTest
@testable import StrandAnalytics

final class DayTimelineTests: XCTestCase {

    /// 2026-06-10 00:00 UTC. Every test day is a plain 24 h day unless it builds its own bounds.
    private let day0 = 1_781_049_600

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Int {
        day0 + day * 86_400 + hour * 3600 + minute * 60
    }

    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    /// A finished plain day unless `now` says otherwise.
    private func input(now: Int? = nil) -> DayTimeline.Input {
        DayTimeline.Input(dayStart: date(day0), dayEnd: date(day0 + 86_400), now: date(now ?? day0 + 2 * 86_400))
    }

    /// One sample per `step` seconds over each `[from, to)` range.
    private func samples(_ ranges: [(Int, Int)], step: Int = 60, bpm: Double = 70) -> [DayTimeline.Input.HRSample] {
        ranges.flatMap { range in
            stride(from: range.0, to: range.1, by: step).map { DayTimeline.Input.HRSample(ts: $0, bpm: bpm) }
        }
    }

    /// A whole worn day (per-minute means) so that a test only sees the gap it makes.
    private func wornDay(_ i: inout DayTimeline.Input, except hole: (Int, Int)? = nil) {
        i.hrSampleSpanSec = 60
        if let hole {
            i.hr = samples([(day0, hole.0), (hole.1, day0 + 86_400)])
        } else {
            i.hr = samples([(day0, day0 + 86_400)])
        }
    }

    private func events(_ timeline: DayTimeline, _ kind: DayTimeline.Kind) -> [DayTimeline.Event] {
        timeline.events.filter { $0.kind == kind }
    }

    private func dublin() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }

    // MARK: Workouts from several sources

    func testWorkoutsFromThreeSourcesBecomeOneEvent() {
        var i = input()
        i.workouts = [
            .init(key: "s", startTs: at(7), endTs: at(7, 45), title: "Run", sources: [.strap], avgHr: 150),
            .init(key: "g", startTs: at(7, 3), endTs: at(7, 44), title: "Running", sources: [.garmin, .paceforge], avgHr: 148),
            .init(key: "a", startTs: at(7, 5), endTs: at(7, 40), title: "Run", sources: [.apple]),
        ]
        XCTAssertEqual(events(DayTimeline.build(i), .workout).count, 1)
    }

    func testMergedWorkoutListsEverySourceBadge() {
        var i = input()
        i.workouts = [
            .init(key: "s", startTs: at(7), endTs: at(7, 45), title: "Run", sources: [.strap]),
            .init(key: "g", startTs: at(7, 3), endTs: at(7, 44), title: "Running", sources: [.garmin, .paceforge]),
            .init(key: "a", startTs: at(7, 5), endTs: at(7, 40), title: "Run", sources: [.apple]),
        ]
        XCTAssertEqual(events(DayTimeline.build(i), .workout).first?.sources, [.strap, .garmin, .apple, .paceforge])
    }

    func testGarminIsCanonicalForMetricsAndTheStrapFillsWhatItLacks() {
        var i = input()
        i.workouts = [
            .init(key: "s", startTs: at(7), endTs: at(7, 45), title: "Run", sources: [.strap], avgHr: 150, maxHr: 171),
            .init(key: "g", startTs: at(7, 3), endTs: at(7, 44), title: "Running", sources: [.garmin], avgHr: 148,
                  distanceM: 6100),
        ]
        let merged = events(DayTimeline.build(i), .workout).first
        XCTAssertEqual([merged?.title, merged?.metrics.avgHr.map { String($0) }, merged?.metrics.maxHr.map { String($0) }],
                       ["Running", "148", "171"])
    }

    func testWorkoutsThatStartMoreThanTenMinutesApartStayTwo() {
        var i = input()
        i.workouts = [
            .init(key: "a", startTs: at(7), endTs: at(8), title: "Run", sources: [.strap]),
            .init(key: "b", startTs: at(7, 15), endTs: at(8), title: "Run", sources: [.apple]),
        ]
        XCTAssertEqual(events(DayTimeline.build(i), .workout).count, 2)
    }

    func testBackToBackWorkoutsStayTwo() {
        var i = input()
        i.workouts = [
            .init(key: "a", startTs: at(7), endTs: at(7, 30), title: "Run", sources: [.strap]),
            .init(key: "b", startTs: at(7, 30), endTs: at(8), title: "Run", sources: [.strap]),
        ]
        XCTAssertEqual(events(DayTimeline.build(i), .workout).count, 2)
    }

    func testAnOutsideMatcherCanJoinWorkoutsThatDoNotOverlap() {
        var i = input()
        i.workouts = [
            .init(key: "a", startTs: at(7), endTs: at(7, 45), title: "Run", sources: [.strap]),
            .init(key: "b", startTs: at(9), endTs: at(9, 40), title: "Run", sources: [.garmin]),
        ]
        i.sameWorkoutPairs = [.init(a: "a", b: "b")]
        XCTAssertEqual(events(DayTimeline.build(i), .workout).count, 1)
    }

    // MARK: Sleep and naps

    func testNapIsShownAsItsOwnEventBesideTheNight() {
        var i = input()
        i.sleeps = [
            .init(startTs: at(23, 0, day: -1), endTs: at(6, 30), isNap: false),
            .init(startTs: at(14), endTs: at(14, 40), isNap: true),
        ]
        XCTAssertEqual(DayTimeline.build(i).events.filter { $0.kind == .sleep || $0.kind == .nap }.map(\.kind), [.nap, .sleep])
    }

    func testMidnightSpanningSleepAppearsOnBothDaysWithItsRealTimes() {
        var next = input()
        next.sleeps = [.init(startTs: at(23, 0, day: -1), endTs: at(7), isNap: false)]
        var previous = DayTimeline.Input(dayStart: date(day0 - 86_400), dayEnd: date(day0), now: date(day0 + 2 * 86_400))
        previous.sleeps = next.sleeps

        let wakeDay = events(DayTimeline.build(next), .sleep).first
        let bedDay = events(DayTimeline.build(previous), .sleep).first
        XCTAssertEqual([wakeDay?.continuesFromPreviousDay, wakeDay?.continuesToNextDay,
                        bedDay?.continuesFromPreviousDay, bedDay?.continuesToNextDay],
                       [true, false, false, true])
    }

    func testMidnightSpanningSleepKeepsItsFullDuration() {
        var i = input()
        i.sleeps = [.init(startTs: at(23, 0, day: -1), endTs: at(7), isNap: false)]
        XCTAssertEqual(events(DayTimeline.build(i), .sleep).first?.subtitle, "8h 00m")
    }

    // MARK: Gaps

    func testTenMinutesWithoutHeartRateBecomesANoDataEvent() {
        var i = input()
        wornDay(&i, except: (at(6), at(6, 10)))
        let gaps = events(DayTimeline.build(i), .noData)
        XCTAssertEqual(gaps.map { [Int($0.start.timeIntervalSince1970), Int($0.end?.timeIntervalSince1970 ?? 0)] },
                       [[at(6), at(6, 10)]])
    }

    func testNineMinutesWithoutHeartRateIsNotAGap() {
        var i = input()
        wornDay(&i, except: (at(6), at(6, 9)))
        XCTAssertTrue(events(DayTimeline.build(i), .noData).isEmpty)
    }

    func testAGapOnTodayStopsAtNowRatherThanRunningToMidnight() {
        var i = input(now: at(14))
        i.hrSampleSpanSec = 60
        i.hr = samples([(day0, at(13, 30))])
        let gap = events(DayTimeline.build(i), .noData).first
        XCTAssertEqual(gap?.end, date(at(14)))
    }

    func testSkippingTheHeartRateSeriesReportsNoGapRatherThanAWholeDayOfThem() {
        var i = input()
        i.detectsGaps = false
        XCTAssertTrue(events(DayTimeline.build(i), .noData).isEmpty)
    }

    func testAFutureDayHasNoGaps() {
        var i = input(now: day0 - 3600)
        i.hr = []
        XCTAssertTrue(events(DayTimeline.build(i), .noData).isEmpty)
    }

    func testADayWithNoHeartRateAtAllIsOneGapOverTheWholeDay() {
        let gaps = events(DayTimeline.build(input()), .noData)
        XCTAssertEqual(gaps.map { [Int($0.start.timeIntervalSince1970), Int($0.end?.timeIntervalSince1970 ?? 0)] },
                       [[day0, day0 + 86_400]])
    }

    func testChargingExplainsTheGap() {
        var i = input()
        wornDay(&i, except: (at(6), at(6, 40)))
        i.battery = [.init(ts: at(6, 2), soc: 80, charging: true)]
        XCTAssertEqual(events(DayTimeline.build(i), .noData).first?.noDataReason, .charging)
    }

    func testAnEmptyBatteryExplainsTheGap() {
        var i = input()
        wornDay(&i, except: (at(6), at(8)))
        i.battery = [.init(ts: at(5, 50), soc: 2, charging: false)]
        XCTAssertEqual(events(DayTimeline.build(i), .noData).first?.noDataReason, .batteryEmpty)
    }

    func testPendingSyncExplainsAGapAtTheTailOfToday() {
        var i = input(now: at(14))
        i.hrSampleSpanSec = 60
        i.hr = samples([(day0, at(12))])
        i.syncPending = true
        XCTAssertEqual(events(DayTimeline.build(i), .noData).first?.noDataReason, .syncPending)
    }

    func testWithoutAHintTheReasonIsPlain() {
        var i = input()
        wornDay(&i, except: (at(6), at(8)))
        XCTAssertEqual(events(DayTimeline.build(i), .noData).first?.noDataReason, .noHeartRate)
    }

    func testTheCurveLiftsThePenAcrossAGapAndNeverJoinsIt() {
        var i = input()
        wornDay(&i, except: (at(6), at(8)))
        let lifted = DayTimeline.build(i).hr.filter(\.startsRun).map(\.ts)
        XCTAssertEqual(lifted.count, 2, "the first point of the day and the first one after the gap")
    }

    func testTheFirstPointAfterAGapIsTheOneThatStartsTheNewRun() {
        var i = input()
        wornDay(&i, except: (at(6), at(8)))
        let afterGap = DayTimeline.build(i).hr.first { $0.startsRun && $0.ts > at(6) }
        XCTAssertGreaterThanOrEqual(afterGap?.ts ?? 0, at(8))
    }

    // MARK: Curves

    func testTheHeartRateCurveNeverExceedsSixHundredPoints() {
        var i = input()
        i.hr = samples([(day0, day0 + 86_400)], step: 10)
        XCTAssertLessThanOrEqual(DayTimeline.build(i).hr.count, DayTimeline.maxCurvePoints)
    }

    func testStepsAccumulateAcrossTheDay() {
        var i = input()
        i.steps = [.init(ts: at(8), seconds: 3600, steps: 1200), .init(ts: at(9), seconds: 3600, steps: 100)]
        XCTAssertEqual(DayTimeline.build(i).stepsCumulative.last?.cumulative, 1300)
    }

    func testOnlyARealStretchOfWalkingBecomesAStepsBurst() {
        var i = input()
        i.steps = [.init(ts: at(8), seconds: 3600, steps: 1200), .init(ts: at(9), seconds: 3600, steps: 100)]
        XCTAssertEqual(events(DayTimeline.build(i), .stepsBurst).map(\.subtitle), ["1200 steps"])
    }

    func testHourlyStressIsKeptWithItsGapsAndMasks() {
        var i = input()
        i.stress = [.init(ts: at(9), level: 1.2), .init(ts: at(10), level: nil, maskedForActivity: true)]
        XCTAssertEqual(DayTimeline.build(i).stress.map(\.maskedForActivity), [false, true])
    }

    // MARK: Plan

    func testAPlanWithNoSlotIsUntimed() {
        var i = input(now: at(10))
        i.planned = [.init(id: "p1", title: "Intervals", detail: "8.0 km")]
        XCTAssertEqual(events(DayTimeline.build(i), .planned).first?.isUntimed, true)
    }

    func testAPlanThatWasNeverMatchedIsMissedOnceTheDayHasPassed() {
        var i = input()
        i.planned = [.init(id: "p1", title: "Intervals")]
        XCTAssertEqual(events(DayTimeline.build(i), .planned).first?.status, .missed)
    }

    func testAPlanStaysPlannedWhileTheDayIsStillRunning() {
        var i = input(now: at(10))
        i.planned = [.init(id: "p1", title: "Intervals")]
        XCTAssertEqual(events(DayTimeline.build(i), .planned).first?.status, .planned)
    }

    func testAMatchedPlanFoldsIntoTheWorkoutItBecameByActivityId() {
        var i = input()
        i.workouts = [.init(key: "g", startTs: at(7), endTs: at(7, 40), title: "Running",
                            sources: [.garmin, .paceforge], externalId: "9001")]
        i.planned = [.init(id: "p1", title: "Easy run", matchedActivityIds: ["9001"])]
        let timeline = DayTimeline.build(i)
        XCTAssertEqual([events(timeline, .planned).count, events(timeline, .workout).count], [0, 1])
    }

    func testAFoldedPlanAddsThePlanBadgeAndNamesItself() {
        var i = input()
        i.workouts = [.init(key: "g", startTs: at(7), endTs: at(7, 40), title: "Running",
                            sources: [.garmin], externalId: "9001")]
        i.planned = [.init(id: "p1", title: "Easy run", matchedActivityIds: ["9001"])]
        let workout = events(DayTimeline.build(i), .workout).first
        XCTAssertEqual([workout?.sources.contains(.plan), workout?.subtitle.contains("Plan: Easy run")], [true, true])
    }

    func testAMatchedPlanFindsItsWorkoutByOverlapWhenTheRecordCarriesNoId() {
        var i = input()
        i.workouts = [.init(key: "s", startTs: at(7, 2), endTs: at(7, 41), title: "Run", sources: [.strap])]
        i.planned = [.init(id: "p1", title: "Easy run", matchedActivityIds: ["9001"])]
        i.planActivities = [.init(id: "9001", startTs: at(7), endTs: at(7, 40))]
        XCTAssertTrue(events(DayTimeline.build(i), .planned).isEmpty)
    }

    func testAMatchedPlanWithNoWorkoutRowIsDone() {
        var i = input()
        i.planned = [.init(id: "p1", title: "Easy run", matchedActivityIds: ["9001"])]
        i.planActivities = [.init(id: "9001", startTs: at(7), endTs: at(7, 40))]
        XCTAssertEqual(events(DayTimeline.build(i), .planned).first?.status, .done)
    }

    func testADonePlanSitsWhereItsActivityHappened() {
        var i = input()
        i.planned = [.init(id: "p1", title: "Easy run", matchedActivityIds: ["9001"])]
        i.planActivities = [.init(id: "9001", startTs: at(7), endTs: at(7, 40))]
        XCTAssertEqual(events(DayTimeline.build(i), .planned).first?.start, date(at(7)))
    }

    // MARK: Journal, detected, order

    func testJournalAnswersAreOneUntimedNote() {
        var i = input()
        i.journal = [.init(label: "Caffeine", yes: true), .init(label: "Alcohol", yes: false), .init(label: "Late meal", yes: true)]
        let notes = events(DayTimeline.build(i), .dayNote)
        XCTAssertEqual(notes.map { [$0.isUntimed.description, $0.subtitle] }, [["true", "Caffeine, Late meal"]])
    }

    func testADetectedWindowMostlyInsideASavedWorkoutIsMarkedAlreadyRecordedWithItsSport() {
        var i = input()
        i.workouts = [.init(key: "s", startTs: at(18), endTs: at(18, 40), title: "Running", sources: [.strap])]
        i.detected = [.init(startTs: at(18, 2), endTs: at(18, 38), avgBpm: 150, peakBpm: 170)]
        let e = events(DayTimeline.build(i), .detected).first
        XCTAssertEqual([e?.title, e?.suggestion?.recordedAs, e?.subtitle],
                       ["Running", "Running", "Already recorded \u{00B7} 36 min \u{00B7} avg 150 bpm"])
    }

    func testADetectedWindowJustOverHalfCoveredByAGarminActivityIsAlreadyRecorded() {
        var i = input()
        i.workouts = [.init(key: "g", startTs: at(9), endTs: at(9, 31), title: "Walking", sources: [.garmin])]
        i.detected = [.init(startTs: at(9, 15), endTs: at(9, 45), avgBpm: 100, peakBpm: 115)]
        XCTAssertEqual(events(DayTimeline.build(i), .detected).first?.suggestion?.isRecorded, true)
    }

    func testADetectedWindowHalfCoveredByALongerWorkoutIsDropped() {
        var i = input()
        i.workouts = [.init(key: "g", startTs: at(9), endTs: at(9, 30), title: "Walking", sources: [.garmin])]
        i.detected = [.init(startTs: at(9, 15), endTs: at(9, 45), avgBpm: 100, peakBpm: 115)]
        XCTAssertTrue(events(DayTimeline.build(i), .detected).isEmpty)
    }

    func testASmallSavedWorkoutInsideALongWindowStillHidesIt() {
        var i = input()
        i.workouts = [.init(key: "s", startTs: at(9, 10), endTs: at(9, 20), title: "Workout", sources: [.strap])]
        i.detected = [.init(startTs: at(9), endTs: at(9, 50), avgBpm: 100, peakBpm: 115)]
        XCTAssertTrue(events(DayTimeline.build(i), .detected).isEmpty)
    }

    func testADetectedWindowInsideAnApproximateSleepIsDropped() {
        var i = input()
        i.sleeps = [.init(startTs: at(13), endTs: at(14), isNap: true)]
        i.detected = [.init(startTs: at(13, 5), endTs: at(13, 40), avgBpm: 95, peakBpm: 105)]
        XCTAssertTrue(events(DayTimeline.build(i), .detected).isEmpty)
    }

    func testACalmDetectedWindowIsShownAsAWalk() {
        var i = input()
        i.segmentProfile = .init(maxHr: 185, restingHr: 52)
        i.detected = [.init(startTs: at(12), endTs: at(12, 14), avgBpm: 101, peakBpm: 116)]
        let e = events(DayTimeline.build(i), .detected).first
        XCTAssertEqual([e?.title, e?.suggestion?.guess.rawValue], ["Walk", "walk"])
    }

    func testAHardDetectedWindowStaysAWorkout() {
        var i = input()
        i.segmentProfile = .init(maxHr: 185, restingHr: 52)
        i.detected = [.init(startTs: at(12), endTs: at(12, 25), avgBpm: 135, peakBpm: 152)]
        let e = events(DayTimeline.build(i), .detected).first
        XCTAssertEqual([e?.title, e?.suggestion?.guess.rawValue], ["Looks like a workout", "workout"])
    }

    func testTheDaysHeartRateSeriesDecidesSteadiness() {
        var i = input()
        i.hrSampleSpanSec = 60
        i.segmentProfile = .init(maxHr: 185, restingHr: 52)
        i.hr = (0..<25).map { .init(ts: at(12) + $0 * 60, bpm: $0 % 2 == 0 ? 75 : 125) }
        i.detected = [.init(startTs: at(12), endTs: at(12, 25), avgBpm: 100, peakBpm: 125)]
        XCTAssertEqual(events(DayTimeline.build(i), .detected).first?.suggestion?.guess, .workout)
    }

    func testStrapRunTicksTurnACalmWindowIntoAWorkout() {
        var i = input()
        i.segmentProfile = .init(maxHr: 185, restingHr: 52)
        i.detected = [.init(startTs: at(12), endTs: at(12, 25), avgBpm: 110, peakBpm: 120,
                            gait: .init(walkShare: 0.1, runShare: 0.8, classedTicks: 300))]
        XCTAssertEqual(events(DayTimeline.build(i), .detected).first?.suggestion?.guess, .workout)
    }

    func testADetectedWindowNobodyHasSavedIsKeptAsASuggestion() {
        var i = input()
        i.detected = [.init(startTs: at(18, 2), endTs: at(18, 38), avgBpm: 150, peakBpm: 170)]
        XCTAssertEqual(events(DayTimeline.build(i), .detected).first?.subtitle, "36 min \u{00B7} avg 150 bpm")
    }

    func testAllDayRowsComeFirstThenTimedRowsNewestFirst() {
        var i = input()
        i.detectsGaps = false
        i.planned = [.init(id: "p1", title: "Intervals")]
        i.sleeps = [.init(startTs: at(0), endTs: at(6), isNap: false)]
        i.workouts = [.init(key: "w", startTs: at(17), endTs: at(18), title: "Run", sources: [.strap])]
        XCTAssertEqual(DayTimeline.build(i).events.map(\.kind), [.planned, .workout, .sleep])
    }

    // MARK: Day length

    func testASpringForwardDayIsTwentyThreeHoursLong() {
        let calendar = dublin()
        let noon = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        let bounds = DayTimeline.dayBounds(containing: noon, calendar: calendar)
        XCTAssertEqual(bounds.end.timeIntervalSince(bounds.start), 23 * 3600)
    }

    func testAFallBackDayIsTwentyFiveHoursLong() {
        let calendar = dublin()
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let bounds = DayTimeline.dayBounds(containing: noon, calendar: calendar)
        XCTAssertEqual(bounds.end.timeIntervalSince(bounds.start), 25 * 3600)
    }

    private func wornTwentyFiveHourDay() -> DayTimeline {
        let calendar = dublin()
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let bounds = DayTimeline.dayBounds(containing: noon, calendar: calendar)
        var i = DayTimeline.Input(dayStart: bounds.start, dayEnd: bounds.end,
                                  now: bounds.end.addingTimeInterval(86_400))
        let start = Int(bounds.start.timeIntervalSince1970), end = Int(bounds.end.timeIntervalSince1970)
        i.hrSampleSpanSec = 30
        i.hr = samples([(start, end)], step: 30)
        return DayTimeline.build(i)
    }

    func testAContinuouslyWornTwentyFiveHourDayHasNoGap() {
        XCTAssertTrue(events(wornTwentyFiveHourDay(), .noData).isEmpty)
    }

    func testATwentyFiveHourDayIsLaidOutOverItsRealLength() {
        XCTAssertEqual(wornTwentyFiveHourDay().dayLengthSec, 25 * 3600)
    }

    func testATwentyFiveHourDayCurveStaysUnderTheCap() {
        XCTAssertLessThanOrEqual(wornTwentyFiveHourDay().hr.count, DayTimeline.maxCurvePoints)
    }

    func testAContinuouslyWornTwentyThreeHourDayHasNoGap() {
        let calendar = dublin()
        let noon = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        let bounds = DayTimeline.dayBounds(containing: noon, calendar: calendar)
        var i = DayTimeline.Input(dayStart: bounds.start, dayEnd: bounds.end,
                                  now: bounds.end.addingTimeInterval(86_400))
        let start = Int(bounds.start.timeIntervalSince1970), end = Int(bounds.end.timeIntervalSince1970)
        i.hrSampleSpanSec = 60
        i.hr = samples([(start, end)], step: 60)
        XCTAssertTrue(events(DayTimeline.build(i), .noData).isEmpty)
    }
}
