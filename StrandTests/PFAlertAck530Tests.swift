import XCTest
@testable import Strand

/// Build 530, APP-4: the acknowledgement queue behind `POST /app/inbox-ack`, the dismiss-twice rule and the raised ledger.
final class PFAlertAck530Tests: XCTestCase {
    // MARK: Queue

    func testARaisedIdWaitsInTheQueue() {
        var queue = PFAckQueue530()
        queue.addRaised("coach:a")
        XCTAssertEqual(queue.next?.raised, ["coach:a"])
    }

    func testTheSameIdIsQueuedOnce() {
        var queue = PFAckQueue530()
        queue.addOpened("a")
        queue.addOpened("a")
        XCTAssertEqual(queue.next?.opened, ["a"])
    }

    func testAnIdTheServerWouldRefuseIsNotQueued() {
        var queue = PFAckQueue530()
        queue.addRaised("has a space")
        XCTAssertNil(queue.next)
    }

    func testAnIdOver120CharactersIsNotQueued() {
        var queue = PFAckQueue530()
        queue.addRaised(String(repeating: "a", count: 121))
        XCTAssertNil(queue.next)
    }

    func testAfterAHundredIdsOfAKeyANewBatchStarts() {
        var queue = PFAckQueue530()
        for n in 0...100 { queue.addRaised("id\(n)") }
        XCTAssertEqual(queue.batches.map(\.raised.count), [100, 1])
    }

    func testADismissalAfterAnUnmuteStartsANewBatch() {
        var queue = PFAckQueue530()
        queue.addDismissed("a")
        queue.addUnmute("coach")
        queue.addDismissed("b")
        XCTAssertEqual(queue.batches.map(\.dismissed), [["a"], ["b"]])
    }

    func testAnUnmuteOfAnotherKindStartsANewBatch() {
        var queue = PFAckQueue530()
        queue.addUnmute("coach")
        queue.addUnmute("plan")
        XCTAssertEqual(queue.batches.map(\.unmute), ["coach", "plan"])
    }

    func testASettledSendTakesOutOnlyWhatItCarried() {
        var queue = PFAckQueue530()
        queue.addRaised("a")
        let sent = queue.next!
        queue.addRaised("b")
        queue.settle(sent)
        XCTAssertEqual(queue.next?.raised, ["b"])
    }

    func testASettledSendOfTheWholeBatchEmptiesTheQueue() {
        var queue = PFAckQueue530()
        queue.addOpened("a")
        queue.settle(queue.next!)
        XCTAssertNil(queue.next)
    }

    func testTheQueueSurvivesTheRoundTripThroughJSON() throws {
        var queue = PFAckQueue530()
        queue.addRaised("a")
        queue.addUnmute("coach")
        let back = try JSONDecoder().decode(PFAckQueue530.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(back, queue)
    }

    func testTheBodyCarriesOnlyTheKeysThatHaveContent() {
        var queue = PFAckQueue530()
        queue.addOpened("a")
        XCTAssertEqual(Set(queue.next!.body.keys), ["opened"])
    }

    func testAnAcceptedSendIsSettled() {
        XCTAssertTrue(PFAckQueue530.isSettled(status: 200))
    }

    func testARefusedBodyIsSettledBecauseItWouldBeRefusedAgain() {
        XCTAssertTrue(PFAckQueue530.isSettled(status: 400))
    }

    func testTheHourlyCapKeepsTheBatchForALaterContact() {
        XCTAssertFalse(PFAckQueue530.isSettled(status: 429))
    }

    func testAServerErrorKeepsTheBatch() {
        XCTAssertFalse(PFAckQueue530.isSettled(status: 503))
    }

    // MARK: Dismiss twice

    func testTwoDismissalsOfAKindMuteIt() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "coach")
        mute.dismissed(id: "b", kind: "coach")
        XCTAssertEqual(mute.muted, ["coach"])
    }

    func testOneDismissalDoesNotMuteAKind() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "coach")
        XCTAssertTrue(mute.muted.isEmpty)
    }

    func testTheSameItemDismissedTwiceCountsOnce() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "coach")
        mute.dismissed(id: "a", kind: "coach")
        XCTAssertTrue(mute.muted.isEmpty)
    }

    func testAnOpenBetweenTwoDismissalsStartsTheCountAgain() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "coach")
        mute.opened(kind: "coach")
        mute.dismissed(id: "b", kind: "coach")
        XCTAssertTrue(mute.muted.isEmpty)
    }

    func testTheProblemsAreNeverMuted() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "problem")
        mute.dismissed(id: "b", kind: "problem")
        XCTAssertTrue(mute.muted.isEmpty)
    }

    func testTheJournalQuestionsAreNeverMuted() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "journal")
        mute.dismissed(id: "b", kind: "journal")
        XCTAssertTrue(mute.muted.isEmpty)
    }

    func testTurningAKindBackOnClearsTheMuteAndTheCount() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "coach")
        mute.dismissed(id: "b", kind: "coach")
        mute.unmute(kind: "coach")
        XCTAssertEqual(mute, PFMuteState530(muted: [], streaks: ["coach": []]))
    }

    func testWhatTheServerMutedStaysMutedHere() {
        var mute = PFMuteState530()
        mute.merge(server: ["plan"])
        XCTAssertEqual(mute.muted, ["plan"])
    }

    func testServerMuteMergePreservesAnUnfinishedDismissalStreak() {
        var mute = PFMuteState530()
        mute.dismissed(id: "a", kind: "coach")
        mute.merge(server: ["plan"])
        XCTAssertEqual(mute.streaks["coach"], ["a"])
    }

    func testServerUnmuteClearsOnlyTheUnmutedKindsStreak() {
        var mute = PFMuteState530()
        mute.merge(server: ["coach", "plan"])
        mute.streaks["coach"] = ["a", "b"]
        mute.streaks["plan"] = ["c"]
        mute.merge(server: ["plan"])
        XCTAssertEqual(mute.muted, ["plan"])
        XCTAssertEqual(mute.streaks["coach"], [])
        XCTAssertEqual(mute.streaks["plan"], ["c"])
    }

    func testServerRefreshWithNoMutedKindsReconcilesAWebSideUnmute() {
        var mute = PFMuteState530()
        mute.merge(server: ["today"])
        mute.streaks["today"] = ["a", "b"]
        mute.merge(server: [])
        XCTAssertTrue(mute.muted.isEmpty)
        XCTAssertEqual(mute.streaks["today"], [])
    }

    func testAnOlderInFlightMuteSnapshotIsRejectedAfterANewerAck() {
        let saved = PFAlertDates.parse("2026-11-16T19:30:01+00:00")!
        let stale = PFAlertDates.parse("2026-11-16T19:30:00+00:00")!
        XCTAssertFalse(PFMuteState530.acceptsServerRevision(stale, after: saved))
        XCTAssertFalse(PFMuteState530.acceptsServerRevision(saved, after: saved))
        XCTAssertTrue(PFMuteState530.acceptsServerRevision(saved.addingTimeInterval(0.000001), after: saved))
    }

    func testQueuedDismissalsProtectALocalMuteFromAStaleServerSnapshot() {
        var queue = PFAckQueue530()
        queue.addDismissed("coach:first")
        queue.addDismissed("coach:second")
        let items = [
            PFInboxDoc.Item(id: "coach:first", ts: nil, kind: "coach", notify: true, title: nil, body: nil, listTitle: nil, listSub: nil, link: nil),
            PFInboxDoc.Item(id: "coach:second", ts: nil, kind: "coach", notify: true, title: nil, body: nil, listTitle: nil, listSub: nil, link: nil)
        ]
        XCTAssertEqual(queue.reconciledMuted(server: [], local: ["coach"], items: items), ["coach"])
    }

    func testQueuedUnmuteWinsOverAStaleServerMute() {
        var queue = PFAckQueue530()
        queue.addUnmute("today")
        let result = queue.reconciledMuted(server: ["today"], local: ["today"], items: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testQueuedDismissalsAfterAnAcceptedBatchProtectTheLocalMute() {
        var queue = PFAckQueue530()
        queue.addUnmute("today")
        queue.addDismissed("today:first")
        queue.addDismissed("today:second")
        queue.settle(queue.next!)
        XCTAssertEqual(queue.reconciledMuted(server: [], local: ["today"], items: []), ["today"])
    }

    func testTheServerCannotMuteTheJournalHere() {
        var mute = PFMuteState530()
        mute.merge(server: ["journal"])
        XCTAssertTrue(mute.muted.isEmpty)
    }

    // MARK: Raised today

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let noon = PFAlertDates.parse("2026-11-16T12:00:00+00:00")!

    func testTodaysRaisedAlertsAreCounted() {
        var ledger = PFRaisedLedger530()
        ledger.add(id: "a", kind: "coach", at: noon.addingTimeInterval(-3_600))
        ledger.add(id: "b", kind: "plan", at: noon.addingTimeInterval(-7_200))
        XCTAssertEqual(ledger.countToday(now: noon, calendar: calendar), 2)
    }

    func testYesterdaysAlertsDoNotCount() {
        var ledger = PFRaisedLedger530()
        ledger.add(id: "a", kind: "coach", at: noon.addingTimeInterval(-86_400))
        XCTAssertEqual(ledger.countToday(now: noon, calendar: calendar), 0)
    }

    func testJournalAndProblemAlertsDoNotCount() {
        var ledger = PFRaisedLedger530()
        ledger.add(id: "a", kind: "journal", at: noon)
        ledger.add(id: "b", kind: "problem", at: noon)
        XCTAssertEqual(ledger.countToday(now: noon, calendar: calendar), 0)
    }

    func testTheLedgerKeepsAWeeklyReportForFourteenDays() {
        var ledger = PFRaisedLedger530()
        ledger.add(id: "weekly", kind: "review", at: noon.addingTimeInterval(-13 * 86_400))
        ledger.add(id: "new", kind: "coach", at: noon)
        XCTAssertEqual(ledger.ids, ["weekly", "new"])
    }

    func testTheLedgerForgetsAlertsOverFourteenDaysOld() {
        var ledger = PFRaisedLedger530()
        ledger.add(id: "old", kind: "review", at: noon.addingTimeInterval(-15 * 86_400))
        ledger.add(id: "new", kind: "coach", at: noon)
        XCTAssertEqual(ledger.ids, ["new"])
    }
}
