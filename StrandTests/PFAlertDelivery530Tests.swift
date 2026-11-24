import XCTest
@testable import Strand

/// Build 530, APP-4: whether the phone raises an alert now. One rule per test. Synthetic ids and times; the calendar is UTC so the clock
/// times of the `quiet` block read as written.
final class PFAlertDelivery530Tests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let quiet = PFInboxDoc.Quiet(usualBedtime: "23:00", usualWake: "07:00", windDown: "21:30")
    private let allKinds = Set(PFInboxKind529.allCases.map(\.rawValue))

    private func time(_ clock: String, day: String = "2026-11-16") -> Date {
        PFAlertDates.parse("\(day)T\(clock):00+00:00")!
    }

    private func item(_ id: String = "a", kind: String = "coach", notify: Bool? = true, ts: String? = "09:00", window: String? = nil,
                      notBefore: String? = nil) -> PFInboxDoc.Item {
        PFInboxDoc.Item(id: id, ts: ts.map { "2026-11-16T\($0):00+00:00" }, kind: kind, notify: notify, title: "A title", body: "A body",
                        listTitle: nil, listSub: nil, link: nil, window: window, notBefore: notBefore.map { "2026-11-16T\($0):00+00:00" })
    }

    private func verdict(_ item: PFInboxDoc.Item, at clock: String, quiet: PFInboxDoc.Quiet?? = nil, recording: Bool = false,
                         asleep: Bool? = nil, kinds: Set<String>? = nil, raised: Set<String> = [], today: Int = 0,
                         day: String = "2026-11-16") -> PFAlertVerdict530 {
        PFAlertDelivery530.verdict(item: item, now: time(clock, day: day), quiet: quiet ?? self.quiet, isRecordingWorkout: recording,
                                   isAsleep: asleep, enabledKinds: kinds ?? allKinds, raisedIDs: raised, raisedToday: today,
                                   calendar: calendar)
    }

    // MARK: The plain case

    func testAnItemInTheDayWithNothingAgainstItIsDelivered() {
        XCTAssertEqual(verdict(item(), at: "10:00"), .deliver)
    }

    func testAnItemWithNoReadableTimeIsDelivered() {
        XCTAssertEqual(verdict(item(ts: nil), at: "10:00"), .deliver)
    }

    // MARK: Window

    func testAMorningItemIsDeliveredInsideTheMorningWindow() {
        XCTAssertEqual(verdict(item(ts: "06:30", window: "morning"), at: "08:00"), .deliver)
    }

    func testAnEveningItemIsHeldUntilTheEveningWindowOpens() {
        XCTAssertEqual(verdict(item(ts: "08:00", window: "evening"), at: "15:00"), .hold)
    }

    func testAnEveningItemIsDeliveredInsideTheEveningWindow() {
        XCTAssertEqual(verdict(item(ts: "17:30", window: "evening"), at: "18:00"), .deliver)
    }

    func testAMorningItemWhoseWindowHasPassedIsNeverSentLate() {
        XCTAssertEqual(verdict(item(ts: "08:00", window: "morning"), at: "13:00"), .drop)
    }

    func testDailyReadinessAlertSurvivesItsOriginalWindow() {
        XCTAssertEqual(verdict(item(kind: "today", ts: "08:00", window: "morning"), at: "15:00"), .deliver)
    }

    func testWeeklyReviewAlertSurvivesSeveralDaysAndItsOriginalWindow() {
        XCTAssertEqual(verdict(item(kind: "review", ts: "18:00", window: "evening"), at: "10:00", day: "2026-11-19"), .deliver)
    }

    func testAWeeklyReviewStillWaitsForItsWindowStartOnTheSameDay() {
        XCTAssertEqual(verdict(item(kind: "review", ts: "08:00", window: "evening"), at: "10:00"), .hold)
    }

    func testDailyReadinessAlertExpiresAfterEighteenHours() {
        XCTAssertEqual(verdict(item(kind: "today", ts: "08:00", window: "morning"), at: "03:00", day: "2026-11-17"), .drop)
    }

    func testWeeklyReviewStillWaitsForQuietHoursToEnd() {
        XCTAssertEqual(verdict(item(kind: "review", ts: "22:00", window: "evening"), at: "23:30"), .hold)
    }

    func testWeeklyReviewStillWaitsForItsNotBeforeTime() {
        XCTAssertEqual(verdict(item(kind: "review", ts: "18:00", window: "evening", notBefore: "21:30"), at: "19:00"), .hold)
    }

    func testWeeklyReviewStillWaitsUntilAnActiveWorkoutEnds() {
        XCTAssertEqual(verdict(item(kind: "review", ts: "18:00", window: "evening"), at: "19:00", recording: true), .hold)
    }

    func testTheAfternoonQuestionIsDeliveredInTheDayWindow() {
        XCTAssertEqual(verdict(item(kind: "journal", ts: "15:00", window: "day"), at: "16:00"), .deliver)
    }

    func testAJournalQuestionIsStillRaisedAfterItsWindowEnds() {
        XCTAssertEqual(verdict(item(kind: "journal", ts: "15:00", window: "day"), at: "21:45"), .deliver)
    }

    func testTheMorningQuestionsAreRaisedAfterNoon() {
        XCTAssertEqual(verdict(item(kind: "journal", ts: "08:00", window: "morning"), at: "13:00"), .deliver)
    }

    func testAnItemWrittenInTheNightWaitsForTheMorningWindow() {
        XCTAssertEqual(verdict(item(ts: "03:00", window: "morning"), at: "03:30"), .hold)
    }

    func testAnEveningWindowThatEndsAfterMidnightStaysOpenUntilThen() {
        let late = PFInboxDoc.Quiet(usualBedtime: "00:30", usualWake: "08:00", windDown: "23:00")
        XCTAssertEqual(verdict(item(ts: "18:00", window: "evening"), at: "23:50", quiet: .some(late)), .deliver)
    }

    // MARK: not_before

    func testAnItemBeforeItsNotBeforeTimeIsHeld() {
        XCTAssertEqual(verdict(item(kind: "bedtime", ts: "08:00", window: "evening", notBefore: "21:30"), at: "18:00"), .hold)
    }

    func testAnItemAfterItsNotBeforeTimeIsDelivered() {
        XCTAssertEqual(verdict(item(kind: "bedtime", ts: "08:00", window: "evening", notBefore: "21:30"), at: "21:45"), .deliver)
    }

    // MARK: Quiet hours

    func testNothingIsDeliveredAfterTheUsualBedtime() {
        XCTAssertEqual(verdict(item(ts: "23:10"), at: "23:30"), .hold)
    }

    func testNothingIsDeliveredBeforeTheUsualWakeTime() {
        XCTAssertEqual(verdict(item(ts: "04:00"), at: "05:00"), .hold)
    }

    func testTheDeliveryResumesAtTheUsualWakeTime() {
        XCTAssertEqual(verdict(item(ts: "04:00"), at: "07:05"), .deliver)
    }

    func testAPhoneThatKnowsTheAthleteIsAwakeDeliversInsideTheClockQuietHours() {
        XCTAssertEqual(verdict(item(ts: "05:30"), at: "06:00", asleep: false), .deliver)
    }

    func testAPhoneThatKnowsTheAthleteIsAsleepHoldsInsideTheDay() {
        XCTAssertEqual(verdict(item(), at: "12:00", asleep: true), .hold)
    }

    func testWithoutAQuietBlockTheProposalsClockTimesApplyAtNight() {
        XCTAssertEqual(verdict(item(ts: "23:10"), at: "23:30", quiet: .some(nil)), .hold)
    }

    func testWithoutAQuietBlockTheDayIsOpen() {
        XCTAssertEqual(verdict(item(), at: "12:00", quiet: .some(nil)), .deliver)
    }

    // MARK: Recording a workout

    func testNothingIsDeliveredWhileAWorkoutIsRecording() {
        XCTAssertEqual(verdict(item(), at: "10:00", recording: true), .hold)
    }

    func testAWorkoutThatStartedHalfADayAgoIsNotRecording() {
        let now = time("12:00")
        XCTAssertFalse(PFAlertDelivery530.isRecording(startedAt: [now.addingTimeInterval(-13 * 3_600)], now: now))
    }

    func testAWorkoutThatStartedAnHourAgoIsRecording() {
        let now = time("12:00")
        XCTAssertTrue(PFAlertDelivery530.isRecording(startedAt: [now.addingTimeInterval(-3_600)], now: now))
    }

    // MARK: Switches, repeats, age

    func testAKindSwitchedOffIsDropped() {
        XCTAssertEqual(verdict(item(kind: "plan"), at: "10:00", kinds: ["coach"]), .drop)
    }

    func testAnItemAlreadyRaisedIsDropped() {
        XCTAssertEqual(verdict(item("a"), at: "10:00", raised: ["a"]), .drop)
    }

    func testAnItemTheServerDidNotMarkForNotificationIsDropped() {
        XCTAssertEqual(verdict(item(notify: false), at: "10:00"), .drop)
    }

    func testAnItemOverTwoDaysOldIsDropped() {
        XCTAssertEqual(verdict(item(ts: "09:00"), at: "10:00", day: "2026-11-19"), .drop)
    }

    // MARK: The daily cap

    func testTheSeventhAlertOfTheDayIsDropped() {
        XCTAssertEqual(verdict(item(), at: "10:00", today: 6), .drop)
    }

    func testTheSixthAlertOfTheDayIsDelivered() {
        XCTAssertEqual(verdict(item(), at: "10:00", today: 5), .deliver)
    }

    func testAJournalQuestionIsDeliveredOverTheCap() {
        XCTAssertEqual(verdict(item(kind: "journal", ts: "07:50", window: "morning"), at: "08:00", today: 6), .deliver)
    }

    func testAProblemIsDeliveredOverTheCap() {
        XCTAssertEqual(verdict(item(kind: "problem"), at: "10:00", today: 6), .deliver)
    }

    func testAListUsesUpTheCapAsItGoes() {
        let items = (1...4).map { item("c\($0)") }
        let plan = PFAlertDelivery530.plan(items: items, now: time("10:00"), quiet: quiet, isRecordingWorkout: false, isAsleep: nil,
                                           enabledKinds: allKinds, raisedIDs: [], raisedToday: 4, calendar: calendar)
        XCTAssertEqual(plan.deliver.map(\.id), ["c1", "c2"])
    }

    func testAListKeepsTheHeldIdsForTheNextContact() {
        let items = [item("now"), item("later", ts: "08:00", window: "evening")]
        let plan = PFAlertDelivery530.plan(items: items, now: time("10:00"), quiet: quiet, isRecordingWorkout: false, isAsleep: nil,
                                           enabledKinds: allKinds, raisedIDs: [], raisedToday: 0, calendar: calendar)
        XCTAssertEqual(plan.held, ["later"])
    }

    // MARK: Clock times

    func testAClockTimeReadsAsMinutesAfterMidnight() {
        XCTAssertEqual(PFAlertDelivery530.minutes("23:15"), 1_395)
    }

    func testAnUnreadableClockTimeReadsAsNothing() {
        XCTAssertNil(PFAlertDelivery530.minutes("late"))
    }
}
