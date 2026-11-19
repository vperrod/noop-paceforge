import XCTest
@testable import Strand

/// The inbox's decisions (build 529): which items raise a notification, how often the server is asked, the rows and unread marks, and
/// where a tap goes. All synthetic ids, titles and times.
final class PFInboxLogic529Tests: XCTestCase {
    private let now = PFAlertDates.parse("2026-11-15T20:00:00+00:00")!

    private func item(_ id: String, kind: String = "coach", notify: Bool = true, ts: String = "2026-11-15T19:30:00+00:00",
                      title: String = "A title", link: PFInboxDoc.Link? = nil) -> PFInboxDoc.Item {
        PFInboxDoc.Item(id: id, ts: ts, kind: kind, notify: notify, title: title, body: "A body", listTitle: nil, listSub: nil, link: link)
    }

    private func decide(_ items: [PFInboxDoc.Item], notified: [String]? = [], kinds: Set<String> = Set(PFInboxKind529.allCases.map(\.rawValue)),
                        legacy: Set<String> = [], raised: Set<String> = []) -> PFInboxLogic529.NotifyDecision {
        PFInboxLogic529.decide(items: items, notified: notified, enabledKinds: kinds, legacyNotified: legacy, raisedIDs: raised, now: now)
    }

    private func entry(_ id: String, source: PFAlertEntry.Source = .alert, date: String? = "2026-11-15T10:00:00+00:00") -> PFAlertEntry {
        PFAlertEntry(id: "\(source.rawValue):\(id)", source: source, rawID: id, kind: nil, severity: nil, title: "Old \(id)", body: nil,
                     date: PFAlertDates.parse(date), status: nil, activityID: nil)
    }

    // MARK: Which items notify

    func testTheFirstRunRecordsEveryIdAndNotifiesNone() {
        let decision = decide([item("a"), item("b")], notified: nil)
        XCTAssertEqual(decision.toNotify, [])
    }

    func testTheFirstRunRemembersTheIds() {
        XCTAssertEqual(decide([item("a"), item("b")], notified: nil).notified, ["a", "b"])
    }

    func testInboxDecodesServerMutesAndExplicitRetryFields() throws {
        let data = Data(#"{"version":2,"muted":["today"],"muted_at":"2026-11-16T19:30:00+00:00","items":[{"id":"today:2026-11-16","kind":"today","notify":true,"retry":true}]}"#.utf8)
        let doc = try PFPlan529Decoder.make().decode(PFInboxDoc.self, from: data)
        XCTAssertEqual(doc.muted, ["today"])
        XCTAssertEqual(doc.mutedAt, "2026-11-16T19:30:00+00:00")
        XCTAssertEqual(doc.items?.first?.retry, true)
    }

    func testANewItemWithNotifyOnAndItsKindOnIsAnnounced() {
        XCTAssertEqual(decide([item("a"), item("b")], notified: ["a"]).toNotify.map(\.id), ["b"])
    }

    func testAnOrdinaryItemSeenBeforeIsNotAnnouncedAgain() {
        XCTAssertEqual(decide([item("a")], notified: ["a"]).toNotify, [])
    }

    func testAnItemSeenWhileMutedNeedsAnExplicitServerRetryToBeReannounced() {
        XCTAssertEqual(decide([item("daily", kind: "today", notify: false)]).toNotify, [])
        XCTAssertEqual(decide([item("daily", kind: "today", notify: true)], notified: ["daily"]).toNotify, [])
        var reopened = item("daily", kind: "today", notify: true)
        reopened.retry = true
        XCTAssertEqual(decide([reopened], notified: ["daily"]).toNotify.map(\.id), ["daily"])
        XCTAssertEqual(decide([reopened], notified: ["daily"], raised: ["daily"]).toNotify, [])
    }

    func testAnUpgradeDoesNotReplayTheNewestRetainedReport() {
        let older = item("today:old", kind: "today", ts: "2026-11-15T18:00:00+00:00")
        let newest = item("today:new", kind: "today", ts: "2026-11-15T19:00:00+00:00")
        XCTAssertEqual(decide([older, newest], notified: ["today:old", "today:new"]).toNotify, [])
    }

    func testOnlyTheNewestExplicitlyReopenedReportOfEachKindCanRetry() {
        var older = item("today:old", kind: "today", ts: "2026-11-15T18:00:00+00:00")
        var newest = item("today:new", kind: "today", ts: "2026-11-15T19:00:00+00:00")
        older.retry = true
        newest.retry = true
        XCTAssertEqual(decide([older, newest], notified: ["today:old", "today:new"]).toNotify.map(\.id), ["today:new"])
    }

    func testLatestReportUsesFirstArrayEntryWhenItsTimestampCannotBeParsed() {
        let unparsed = item("today:unparsed", kind: "today", ts: "not a time")
        let parsed = item("today:parsed", kind: "today", ts: "2026-11-15T19:00:00+00:00")
        XCTAssertEqual(PFInboxLogic529.latestReportIDs(items: [unparsed, parsed]), ["today:unparsed"])
    }

    func testAnItemWithNotifyOffIsNotAnnounced() {
        XCTAssertEqual(decide([item("a", notify: false)]).toNotify, [])
    }

    func testAnItemWhoseKindIsSwitchedOffIsNotAnnounced() {
        XCTAssertEqual(decide([item("a", kind: "plan")], kinds: ["coach"]).toNotify, [])
    }

    func testAnItemOfAKindTheBuildDoesNotKnowIsNotAnnounced() {
        XCTAssertEqual(decide([item("a", kind: "brand-new-kind")]).toNotify, [])
    }

    func testAnItemOverTwoDaysOldIsOnlyRecorded() {
        XCTAssertEqual(decide([item("a", ts: "2026-11-12T10:00:00+00:00")]).toNotify, [])
    }

    func testAWeeklyReviewCanStillNotifyForFourteenDays() {
        XCTAssertEqual(decide([item("review:2026-W46", kind: "review", ts: "2026-11-12T10:00:00+00:00")]).toNotify.map(\.id), ["review:2026-W46"])
    }

    func testAWeeklyReviewOlderThanFourteenDaysIsOnlyRecorded() {
        XCTAssertEqual(decide([item("review:2026-W44", kind: "review", ts: "2026-10-31T10:00:00+00:00")]).toNotify, [])
    }

    func testAReadinessAlertOlderThanEighteenHoursIsOnlyRecorded() {
        XCTAssertEqual(decide([item("today:yesterday", kind: "today", ts: "2026-11-14T23:59:00+00:00")]).toNotify, [])
    }

    func testAnItemWithNoReadableTimeIsAnnounced() {
        XCTAssertEqual(decide([item("a", ts: "not a time")]).toNotify.map(\.id), ["a"])
    }

    func testAnItemSwitchedOffIsStillRemembered() {
        XCTAssertEqual(decide([item("a", kind: "plan")], kinds: ["coach"]).notified, ["a"])
    }

    func testTheSameIdTwiceInOneDocumentIsAnnouncedOnce() {
        XCTAssertEqual(decide([item("a"), item("a")]).toNotify.count, 1)
    }

    func testAnAlertTheEarlierPathAnnouncedIsNotAnnouncedAgain() {
        XCTAssertEqual(decide([item("alert:12", kind: "health")], legacy: ["12"]).toNotify, [])
    }

    func testAnAlertTheEarlierPathDidNotAnnounceIsAnnounced() {
        XCTAssertEqual(decide([item("alert:13", kind: "health")], legacy: ["12"]).toNotify.map(\.id), ["alert:13"])
    }

    func testAnIdThatOnlyEndsLikeAnEarlierIdIsNotTakenForIt() {
        XCTAssertEqual(decide([item("report:12", kind: "report")], legacy: ["12"]).toNotify.map(\.id), ["report:12"])
    }

    func testTheRememberedListKeepsTheNewestIds() {
        let decision = PFInboxLogic529.decide(items: [item("c")], notified: ["a", "b"], enabledKinds: ["coach"], legacyNotified: [], now: now, cap: 2)
        XCTAssertEqual(decision.notified, ["b", "c"])
    }

    // MARK: How often

    func testTheFirstCheckIsDue() {
        XCTAssertTrue(PFInboxLogic529.isDue(last: nil, now: now))
    }

    func testACheckFiveMinutesAgoIsNotDue() {
        XCTAssertFalse(PFInboxLogic529.isDue(last: now.addingTimeInterval(-300), now: now))
    }

    func testACheckTenMinutesAgoIsDue() {
        XCTAssertTrue(PFInboxLogic529.isDue(last: now.addingTimeInterval(-600), now: now))
    }

    func testACheckDatedInTheFutureIsDue() {
        XCTAssertTrue(PFInboxLogic529.isDue(last: now.addingTimeInterval(3_600), now: now))
    }

    // MARK: Rows, filters, unread

    func testRowsAreNewestFirst() {
        let rows = PFInboxLogic529.rows(items: [item("old", ts: "2026-11-15T08:00:00+00:00"), item("new", ts: "2026-11-15T19:00:00+00:00")], legacy: [])
        XCTAssertEqual(rows.map(\.id), ["new", "old"])
    }

    func testAnEarlierHistoryLineIsMergedInByTime() {
        let rows = PFInboxLogic529.rows(items: [item("a", ts: "2026-11-15T19:00:00+00:00")], legacy: [entry("1")])
        XCTAssertEqual(rows.map(\.id), ["a", "alert:1"])
    }

    func testAnEarlierHistoryLineTheDocumentAlreadyHasShowsOnce() {
        let rows = PFInboxLogic529.rows(items: [item("alert:1", kind: "health")], legacy: [entry("1")])
        XCTAssertEqual(rows.count, 1)
    }

    func testAnEarlierAlertIsUnderHealthAndAnEarlierNeedsYouItemUnderCoach() {
        let rows = PFInboxLogic529.rows(items: [], legacy: [entry("1"), entry("2", source: .needsYou, date: "2026-11-15T09:00:00+00:00")])
        XCTAssertEqual(rows.map { $0.kind ?? "" }, ["health", "coach"])
    }

    func testAnItemWithoutAnIdIsLeftOut() {
        let blank = PFInboxDoc.Item(id: nil, ts: nil, kind: "coach", notify: true, title: "x", body: nil, listTitle: nil, listSub: nil, link: nil)
        XCTAssertEqual(PFInboxLogic529.rows(items: [blank], legacy: []), [])
    }

    func testTheListTitleWinsOverTheNotificationTitle() {
        let listed = PFInboxDoc.Item(id: "a", ts: nil, kind: "report", notify: true, title: "Notification title", body: nil,
                                     listTitle: "List title", listSub: nil, link: nil)
        XCTAssertEqual(PFInboxLogic529.rows(items: [listed], legacy: []).first?.title, "List title")
    }

    func testTheCoachChipKeepsCoachNotesAndWorkoutReviews() {
        let rows = PFInboxLogic529.rows(items: [item("a", kind: "coach"), item("b", kind: "workout"), item("c", kind: "plan")], legacy: [])
        XCTAssertEqual(Set(PFInboxLogic529.filtered(rows, by: .coach).map(\.id)), ["a", "b"])
    }

    func testTheReportsChipKeepsReportsAndTheMorningVerdict() {
        let rows = PFInboxLogic529.rows(items: [item("a", kind: "report"), item("b", kind: "today"), item("c", kind: "plan")], legacy: [])
        XCTAssertEqual(Set(PFInboxLogic529.filtered(rows, by: .reports).map(\.id)), ["a", "b"])
    }

    func testTheHealthChipKeepsHealthAlertsAndProblems() {
        let rows = PFInboxLogic529.rows(items: [item("a", kind: "health"), item("b", kind: "problem"), item("c", kind: "coach")], legacy: [])
        XCTAssertEqual(Set(PFInboxLogic529.filtered(rows, by: .health).map(\.id)), ["a", "b"])
    }

    func testAKindTheBuildDoesNotKnowShowsUnderAllOnly() {
        let rows = PFInboxLogic529.rows(items: [item("a", kind: "brand-new-kind")], legacy: [])
        XCTAssertEqual(PFInboxFilter529.allCases.filter { !PFInboxLogic529.filtered(rows, by: $0).isEmpty }, [.all])
    }

    func testWithNoBaselineNothingIsUnread() {
        let rows = PFInboxLogic529.rows(items: [item("a")], legacy: [])
        XCTAssertEqual(PFInboxLogic529.unread(rows, seen: nil), [])
    }

    func testARowNotInTheSeenListIsUnread() {
        let rows = PFInboxLogic529.rows(items: [item("a"), item("b")], legacy: [])
        XCTAssertEqual(PFInboxLogic529.unread(rows, seen: ["a"]).map(\.id), ["b"])
    }

    func testAnUnreadPlanChangeLightsThePlanDot() {
        let unread = PFInboxLogic529.rows(items: [item("a", kind: "plan")], legacy: [])
        XCTAssertTrue(PFInboxLogic529.hasUnread(unread, kinds: PFInboxLogic529.planDotKinds))
    }

    func testAnUnreadPlanChangeDoesNotLightTheCoachDot() {
        let unread = PFInboxLogic529.rows(items: [item("a", kind: "plan")], legacy: [])
        XCTAssertFalse(PFInboxLogic529.hasUnread(unread, kinds: PFInboxLogic529.coachDotKinds))
    }

    func testAnUnreadCoachNoteLightsTheCoachDot() {
        let unread = PFInboxLogic529.rows(items: [item("a", kind: "coach")], legacy: [])
        XCTAssertTrue(PFInboxLogic529.hasUnread(unread, kinds: PFInboxLogic529.coachDotKinds))
    }

    func testMarkingReadAddsEachIdOnceAndKeepsTheNewest() {
        XCTAssertEqual(PFInboxLogic529.marking(["a", "b"], read: ["b", "c", "d"], cap: 3), ["b", "c", "d"])
    }

    // MARK: Where a tap goes

    private func route(_ route: String, week: String? = nil, date: String? = nil, key: String? = nil, activity: String? = nil, id: String? = nil) -> PFInboxRoute529 {
        PFInboxRoute529(link: PFInboxDoc.Link(route: route, week: week, id: id, date: date, key: key, activityId: activity))
    }

    func testTheWeekRouteOpensThatWeek() {
        XCTAssertEqual(route("week", week: "2026-W46"), .week("2026-W46"))
    }

    func testTheChangesRouteOpensTheWeekTheChangesAreAbout() {
        XCTAssertEqual(route("changes", week: "2026-W47"), .week("2026-W47"))
    }

    func testTheDailyReportRouteCarriesItsDate() {
        XCTAssertEqual(route("report_daily", date: "2026-11-15"), .dailyReport(date: "2026-11-15"))
    }

    func testTheMonthReportRouteCarriesItsKey() {
        XCTAssertEqual(route("report_month", key: "2026-10"), .monthReport(key: "2026-10"))
    }

    func testTheRaceRouteCarriesItsDate() {
        XCTAssertEqual(route("race", date: "2026-11-14", activity: "1"), .race(date: "2026-11-14"))
    }

    func testTheWorkoutRouteCarriesItsActivity() {
        XCTAssertEqual(route("workout", activity: "25080617023"), .workout(activityID: "25080617023", date: nil))
    }

    func testTheCoachNoticedRouteCarriesItsId() {
        XCTAssertEqual(route("coach_noticed", id: "a3_resting_hr_up:2026-11-15"), .coachNoticed(id: "a3_resting_hr_up:2026-11-15"))
    }

    func testTheStressRouteOpensStress() {
        XCTAssertEqual(route("stress"), .stress)
    }

    func testTheHeartRateRouteOpensHeartRate() {
        XCTAssertEqual(route("heart_rate"), .heartRate)
    }

    func testTheEffortRouteOpensEffort() {
        XCTAssertEqual(route("effort"), .effort)
    }

    func testTheNeedsYouRouteOpensNeedsYou() {
        XCTAssertEqual(route("needs_you"), .needsYou)
    }

    func testARouteTheBuildDoesNotKnowOpensTheInbox() {
        XCTAssertEqual(route("somewhere-new"), .inbox)
    }

    func testAnItemWithNoLinkOpensTheInbox() {
        XCTAssertEqual(PFInboxRoute529(link: nil), .inbox)
    }

    func testAWorkoutLinkWithoutItsActivityOpensTheInbox() {
        XCTAssertEqual(route("workout"), .inbox)
    }

    func testTheTodayRouteOpensToday() {
        XCTAssertEqual(route("today"), .today)
    }

    func testANotificationPayloadCarriesItsLinkBack() {
        let link = PFInboxDoc.Link(route: "report_daily", week: nil, id: nil, date: "2026-11-15", key: nil, activityId: nil)
        XCTAssertEqual(PFInboxPayload529.link(from: PFInboxPayload529.userInfo(for: item("a", link: link))), link)
    }

    func testANotificationThatIsNotAnInboxItemsCarriesNoLink() {
        XCTAssertNil(PFInboxPayload529.link(from: ["pf.kind": "alert", "pf.id": "12"]))
    }

    func testTheInboxPayloadUsesTheKeyTheNotificationPresenterLooksFor() {
        XCTAssertEqual(PFInboxPayload529.kindKey, "pf.kind")
    }

    // MARK: Delay

    func testTheDelayIsTheTimeFromTheServersTimestampToNow() {
        XCTAssertEqual(PFInboxLogic529.delay(of: item("a", ts: "2026-11-15T19:56:00+00:00"), now: now), 240)
    }

    func testTheDelayReadsInMinutes() {
        XCTAssertEqual(PFInboxLogic529.delayText(240), "4 min")
    }

    func testTheDelayReadsInHoursAndMinutes() {
        XCTAssertEqual(PFInboxLogic529.delayText(7_800), "2 h 10 min")
    }
}
