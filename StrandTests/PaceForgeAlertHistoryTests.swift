import XCTest
@testable import Strand

/// The Alerts history behind the bell on Today: merging the server's alerts with the announced Needs you items, grouping by day,
/// counting what is unread and the seen-ids bookkeeping. The clock and the calendar are passed in. All values are made up.
final class PaceForgeAlertHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// 2030-03-13 15:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_899_644_400)

    private func alert(_ id: String, kind: String? = "sleep_debt", created: String? = "2030-03-13T10:15:00Z",
                       status: String? = "open", activityID: String? = nil) -> PFAlert {
        PFAlert(id: id, kind: kind, severity: "watch", createdAt: created, title: "Title \(id)", body: "Body \(id)",
                activityID: activityID, status: status)
    }

    private func need(_ id: String, at seconds: TimeInterval, activityID: String? = nil) -> PFAnnouncedNeed {
        PFAnnouncedNeed(id: id, kind: "rpe", title: "Rate \(id)", activityID: activityID, date: Date(timeIntervalSince1970: seconds))
    }

    private func entry(_ id: String, at seconds: TimeInterval?) -> PFAlertEntry {
        PFAlertEntry(id: id, source: .alert, rawID: id, title: id, date: seconds.map { Date(timeIntervalSince1970: $0) })
    }

    private func item(_ id: String) -> PFNeedsItem { PFNeedsItem(id: id, kind: .rpe, title: "Rate \(id)") }

    // MARK: Dates

    func testAnIsoTimeWithAZoneIsRead() {
        XCTAssertEqual(PFAlertDates.parse("2030-03-13T10:15:00Z")?.timeIntervalSince1970, 1_899_627_300)
    }

    func testAnIsoTimeWithFractionsIsRead() {
        XCTAssertEqual(PFAlertDates.parse("2030-03-13T10:15:30.000Z")?.timeIntervalSince1970, 1_899_627_330)
    }

    func testAnOffsetIsRead() {
        XCTAssertEqual(PFAlertDates.parse("2030-03-13T11:15:00+01:00")?.timeIntervalSince1970, 1_899_627_300)
    }

    func testABareLocalTimeIsReadInThisPhonesZone() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: PFAlertDates.parse("2030-03-13T10:15:00")!)
        XCTAssertEqual([parts.hour, parts.minute], [10, 15])
    }

    func testNoTimeOrNonsenseIsNoDate() {
        XCTAssertNil(PFAlertDates.parse("yesterday"))
    }

    // MARK: Merging

    func testTheMergedListIsNewestFirst() {
        let list = PFAlertHistory.entries(alerts: [alert("a1", created: "2030-03-13T10:15:00Z"), alert("a2", created: "2030-03-13T12:00:00Z")],
                                          announced: [need("r1", at: 1_899_630_000)], openNeedsIDs: [])
        XCTAssertEqual(list.map { $0.id }, ["alert:a2", "needsYou:r1", "alert:a1"])
    }

    func testALineWithoutADateGoesLast() {
        let list = PFAlertHistory.entries(alerts: [alert("a1", created: nil), alert("a2")], announced: [], openNeedsIDs: nil)
        XCTAssertEqual(list.map { $0.id }, ["alert:a2", "alert:a1"])
    }

    func testEqualDatesKeepAFixedOrderById() {
        let list = PFAlertHistory.entries(alerts: [alert("b"), alert("a")], announced: [], openNeedsIDs: nil)
        XCTAssertEqual(list.map { $0.id }, ["alert:a", "alert:b"])
    }

    func testAnAlertListedTwiceShowsOnce() {
        XCTAssertEqual(PFAlertHistory.entries(alerts: [alert("a1"), alert("a1")], announced: [], openNeedsIDs: nil).count, 1)
    }

    func testAnAlertAndANeedsItemWithTheSameIdAreTwoLines() {
        XCTAssertEqual(PFAlertHistory.entries(alerts: [alert("x")], announced: [need("x", at: 1_899_630_000)], openNeedsIDs: nil).count, 2)
    }

    func testAnAlertKeepsTheServersStatus() {
        let list = PFAlertHistory.entries(alerts: [alert("a1", status: "dismissed")], announced: [], openNeedsIDs: nil)
        XCTAssertEqual(list.first?.status, .dismissed)
    }

    func testAnAlertWithAnUnknownStatusHasNone() {
        let list = PFAlertHistory.entries(alerts: [alert("a1", status: "snoozed")], announced: [], openNeedsIDs: nil)
        XCTAssertNil(list.first?.status)
    }

    func testAnAnnouncedItemStillOnTheServersListIsOpen() {
        let list = PFAlertHistory.entries(alerts: [], announced: [need("r1", at: 1_899_630_000)], openNeedsIDs: ["r1"])
        XCTAssertEqual(list.first?.status, .open)
    }

    func testAnAnnouncedItemGoneFromTheServersListWasAnswered() {
        let list = PFAlertHistory.entries(alerts: [], announced: [need("r1", at: 1_899_630_000)], openNeedsIDs: [])
        XCTAssertEqual(list.first?.status, .answered)
    }

    func testAnAnnouncedItemBeforeTheListHasLoadedClaimsNothing() {
        let list = PFAlertHistory.entries(alerts: [], announced: [need("r1", at: 1_899_630_000)], openNeedsIDs: nil)
        XCTAssertNil(list.first?.status)
    }

    func testAnAnnouncedItemKeepsItsTitleAndDate() {
        let line = PFAlertHistory.entries(alerts: [], announced: [need("r1", at: 1_899_630_000)], openNeedsIDs: nil).first
        XCTAssertEqual([line?.title, line?.date.map { String($0.timeIntervalSince1970) }], ["Rate r1", "1899630000.0"])
    }

    // MARK: Kind, status and where a line leads

    func testKindsReadAsTheirLabels() {
        let tags = ["load_spike", "sleep_debt", "hrv_below", "hrr2_flag", "live_stress_sustained", "something_new"].map { PFAlertTag.tag(alertKind: $0) }
        XCTAssertEqual(tags, [.loadSpike, .sleepDebt, .hrvLow, .heartRateRecovery, .live, .other])
    }

    func testANeedsItemIsInputNeeded() {
        let line = PFAlertHistory.entries(alerts: [], announced: [need("r1", at: 1_899_630_000)], openNeedsIDs: nil)[0]
        XCTAssertEqual(line.tag, .inputNeeded)
    }

    func testServerStatusesAreRead() {
        XCTAssertEqual([PFAlertStatus(server: "open"), PFAlertStatus(server: "DONE"), PFAlertStatus(server: nil)], [.open, .done, nil])
    }

    func testAnAlertAboutAnActivityLeadsToItsResults() {
        let line = PFAlertHistory.entries(alerts: [alert("a1", kind: "load_spike", activityID: "91")], announced: [], openNeedsIDs: nil)[0]
        XCTAssertEqual(line.route, .activity("91"))
    }

    func testAnAlertAboutADayLeadsToTheNeedsYouCard() {
        let line = PFAlertHistory.entries(alerts: [alert("a1")], announced: [], openNeedsIDs: nil)[0]
        XCTAssertEqual(line.route, .needsYou)
    }

    func testANeedsItemLeadsToTheNeedsYouCardEvenWithAnActivity() {
        let line = PFAlertHistory.entries(alerts: [], announced: [need("r1", at: 1_899_630_000, activityID: "91")], openNeedsIDs: nil)[0]
        XCTAssertEqual(line.route, .needsYou)
    }

    func testALinesPayloadIsTheOneItsNotificationCarries() {
        let line = PFAlertHistory.entries(alerts: [], announced: [need("r1", at: 1_899_630_000)], openNeedsIDs: nil)[0]
        XCTAssertEqual(line.userInfo[PFAlertRoute.kindKey] as? String, PFAlertRoute.needsYouKind)
    }

    // MARK: Grouping

    func testUnreadLinesComeFirstWhateverTheirDay() {
        let lines = [entry("old", at: 1_899_460_800), entry("new", at: 1_899_627_300)]
        let sections = PFAlertHistory.sections(lines, seen: ["new"], now: now, calendar: calendar)
        XCTAssertEqual(sections.map { $0.group }, [.unread, .today])
    }

    func testReadLinesGroupAsTodayYesterdayAndEarlier() {
        let lines = [entry("t", at: 1_899_627_300), entry("y", at: 1_899_588_600), entry("e", at: 1_899_460_800)]
        let sections = PFAlertHistory.sections(lines, seen: ["t", "y", "e"], now: now, calendar: calendar)
        XCTAssertEqual(sections.map { $0.entries.map { $0.id } }, [["t"], ["y"], ["e"]])
    }

    func testJustAfterMidnightIsTodayAndJustBeforeIsYesterday() {
        let lines = [entry("after", at: 1_899_592_200), entry("before", at: 1_899_588_600)]
        let sections = PFAlertHistory.sections(lines, seen: ["after", "before"], now: now, calendar: calendar)
        XCTAssertEqual(sections.map { $0.group }, [.today, .yesterday])
    }

    func testALineWithoutADateIsEarlier() {
        let sections = PFAlertHistory.sections([entry("none", at: nil)], seen: ["none"], now: now, calendar: calendar)
        XCTAssertEqual(sections.map { $0.group }, [.earlier])
    }

    func testEmptyGroupsAreLeftOut() {
        XCTAssertEqual(PFAlertHistory.sections([entry("t", at: 1_899_627_300)], seen: ["t"], now: now, calendar: calendar).count, 1)
    }

    func testNoLinesGiveNoSections() {
        XCTAssertEqual(PFAlertHistory.sections([], seen: [], now: now, calendar: calendar), [])
    }

    func testTheOrderInsideAGroupIsTheOrderGiven() {
        let lines = [entry("b", at: 1_899_627_300), entry("a", at: 1_899_627_000)]
        let sections = PFAlertHistory.sections(lines, seen: [], now: now, calendar: calendar)
        XCTAssertEqual(sections[0].entries.map { $0.id }, ["b", "a"])
    }

    // MARK: Unread and read

    func testUnreadCountsTheLinesNotSeen() {
        XCTAssertEqual(PFAlertHistory.unreadCount([entry("a", at: 1), entry("b", at: 2), entry("c", at: 3)], seen: ["b"]), 2)
    }

    func testNothingSeenMeansEverythingIsUnread() {
        XCTAssertEqual(PFAlertHistory.unreadCount([entry("a", at: 1), entry("b", at: 2)], seen: []), 2)
    }

    func testMarkingAddsTheIdsAtTheEnd() {
        XCTAssertEqual(PFAlertHistory.marking(["a"], read: ["b", "c"]), ["a", "b", "c"])
    }

    func testMarkingAnIdTwiceKeepsOne() {
        XCTAssertEqual(PFAlertHistory.marking(["a", "b"], read: ["b", "c", "c"]), ["a", "b", "c"])
    }

    func testMarkingKeepsTheNewest300() {
        let seen = (0..<299).map { "s\($0)" }
        let marked = PFAlertHistory.marking(seen, read: ["x", "y", "z"])
        XCTAssertEqual([marked.count, marked.first ?? "", marked.last ?? ""], [300, "s2", "z"])
    }

    func testMarkingAllReadsEveryLine() {
        let lines = [entry("a", at: 1), entry("b", at: 2)]
        let seen = PFAlertHistory.markingAll([], entries: lines)
        XCTAssertEqual(PFAlertHistory.unreadCount(lines, seen: Set(seen)), 0)
    }

    func testAMarkedLineLeavesTheUnreadGroup() {
        let lines = [entry("a", at: 1_899_627_300)]
        let seen = PFAlertHistory.marking([], read: ["a"])
        XCTAssertEqual(PFAlertHistory.sections(lines, seen: Set(seen), now: now, calendar: calendar).map { $0.group }, [.today])
    }

    func testMarkingAllPastTheCapKeepsTheNewestLines() {
        let lines = (0..<305).map { entry("e\($0)", at: TimeInterval(1_000 - $0)) }
        let seen = PFAlertHistory.markingAll([], entries: lines)
        XCTAssertEqual([seen.count, seen.contains("e0") ? 1 : 0, seen.contains("e304") ? 1 : 0], [300, 1, 0])
    }

    func testTheFirstRunPastTheCapLeavesTheNewestLinesRead() {
        let lines = (0..<305).map { entry("e\($0)", at: TimeInterval(1_000 - $0)) }
        let seen = PFAlertHistory.adopting(stored: nil, entries: lines)
        XCTAssertEqual(PFAlertHistory.unreadCount(Array(lines.prefix(300)), seen: Set(seen)), 0)
    }

    // MARK: First run

    func testTheFirstRunCountsEverythingThatExistsAsRead() {
        let lines = [entry("a", at: 1), entry("b", at: 2)]
        let seen = PFAlertHistory.adopting(stored: nil, entries: lines)
        XCTAssertEqual(PFAlertHistory.unreadCount(lines, seen: Set(seen)), 0)
    }

    func testALineFirstSeenAfterTheFirstRunIsUnread() {
        let seen = PFAlertHistory.adopting(stored: nil, entries: [entry("a", at: 1)])
        XCTAssertEqual(PFAlertHistory.unreadCount([entry("a", at: 1), entry("later", at: 2)], seen: Set(seen)), 1)
    }

    func testAStoredSeenListIsNotReplacedByTheFirstRun() {
        XCTAssertEqual(PFAlertHistory.adopting(stored: ["a"], entries: [entry("a", at: 1), entry("b", at: 2)]), ["a"])
    }

    func testAnEmptyFirstRunStillStartsTheList() {
        XCTAssertEqual(PFAlertHistory.adopting(stored: nil, entries: []), [])
    }

    // MARK: Announced record

    func testRecordingAddsTheItemWithTheTimeItWasAnnounced() {
        let list = PFAlertHistory.recording([], adding: [item("r1")], at: Date(timeIntervalSince1970: 1_899_630_000))
        XCTAssertEqual(list, [PFAnnouncedNeed(id: "r1", kind: "rpe", title: "Rate r1", activityID: nil, date: Date(timeIntervalSince1970: 1_899_630_000))])
    }

    func testRecordingAnItemAgainKeepsTheFirstTime() {
        let first = PFAlertHistory.recording([], adding: [item("r1")], at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(PFAlertHistory.recording(first, adding: [item("r1")], at: Date(timeIntervalSince1970: 2)).map { $0.date.timeIntervalSince1970 }, [1])
    }

    func testRecordingKeepsTheNewest100() {
        let first = PFAlertHistory.recording([], adding: (0..<99).map { item("n\($0)") }, at: Date(timeIntervalSince1970: 1))
        let list = PFAlertHistory.recording(first, adding: [item("x"), item("y")], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual([list.count, list.first?.id ?? "", list.last?.id ?? ""], [100, "n1", "y"])
    }

    func testTheRecordSurvivesBeingStoredAndRead() {
        let list = [need("r1", at: 1_899_630_000, activityID: "91"), need("r2", at: 1_899_630_500)]
        XCTAssertEqual(PFAnnouncedNeed.decode(PFAnnouncedNeed.encode(list)), list)
    }

    func testNothingStoredReadsAsNoItems() {
        XCTAssertEqual(PFAnnouncedNeed.decode(nil), [])
    }

    func testAnUnreadableRecordReadsAsNoItems() {
        XCTAssertEqual(PFAnnouncedNeed.decode(Data("not json".utf8)), [])
    }

    // MARK: The builder keeps every alert for the history

    private let alertsDocument = """
    {"alerts":[
     {"id":"a1","kind":"sleep_debt","severity":"watch","title":"Sleep debt","status":"open","created_at":"2030-03-13T10:15:00Z"},
     {"id":"a2","kind":"hydration","severity":"watch","title":"Hydration","status":"dismissed","created_at":"2030-03-12T10:15:00Z"},
     {"id":"a3","kind":"load_spike","key":"load_spike:91","severity":"watch","title":"Big session","status":"done","created_at":"2030-03-11T10:15:00Z"}
    ]}
    """

    func testOnlyTheOpenAlertsStayOnTheCards() {
        XCTAssertEqual(PFBuilder.alerts(PFJ(data: Data(alertsDocument.utf8))).map { $0.id }, ["a1"])
    }

    func testTheHistoryHoldsEveryAlertWhateverItsStatus() {
        XCTAssertEqual(PFBuilder.alertHistory(PFJ(data: Data(alertsDocument.utf8))).map { $0.id }, ["a1", "a2", "a3"])
    }

    func testTheHistoryKeepsTheStatusAndTheActivity() {
        let last = PFBuilder.alertHistory(PFJ(data: Data(alertsDocument.utf8))).last
        XCTAssertEqual([last?.status, last?.activityID], ["done", "91"])
    }
}
