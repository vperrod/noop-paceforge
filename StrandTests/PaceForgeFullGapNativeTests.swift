import XCTest
@testable import Strand

/// The iPhone side of the full-gap packet: a Coach turn that prepared an activity edit, where a planned session stands on the way to the
/// watch (`GET api/watch-status`), and whether today's report may be announced or listed as finished (`today.ready` of the reports list).
/// Every id, title and time is made up.
final class PaceForgeFullGapNativeTests: XCTestCase {
    private let proposalID = String(repeating: "a", count: 32)

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try PFPlan529Decoder.make().decode(type, from: Data(text.utf8))
    }

    // MARK: A Coach turn with an activity edit

    func testATurnReadsTheProposalItCarries() {
        XCTAssertEqual(PFActivityEdits.proposalID(json("{\"proposal_id\": \"\(proposalID)\"}")), proposalID)
    }

    func testAProposalIDThatIsNotThirtyTwoHexCharactersIsIgnored() {
        XCTAssertNil(PFActivityEdits.proposalID(json("{\"proposal_id\": \"12345\"}")))
    }

    func testATurnWithoutAnActivityEditHasNoProposal() {
        XCTAssertNil(PFActivityEdits.proposalID(PFJ(nil)))
    }

    func testTheBuiltChatTurnCarriesTheProposalID() throws {
        var raw = PFRawBundle()
        raw.state = json("""
        {"generated_at": "2030-03-13T08:00:00", "chat": {"turns": [
          {"role": "athlete", "text": "That was a walk", "ts": "2030-03-13T07:00:00"},
          {"role": "coach", "text": "I prepared an edit.", "ts": "2030-03-13T07:00:05", "activity_edit": {"proposal_id": "\(proposalID)"}}]}}
        """)
        raw.fitness = json("{}")
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
        XCTAssertEqual(snapshot.coach.chat.last?.activityEditProposalID, proposalID)
    }

    func testTheAthletesOwnTurnCarriesNoProposal() throws {
        var raw = PFRawBundle()
        raw.state = json("""
        {"generated_at": "2030-03-13T08:00:00", "chat": {"turns": [
          {"role": "athlete", "text": "That was a walk", "ts": "2030-03-13T07:00:00"}]}}
        """)
        raw.fitness = json("{}")
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
        XCTAssertNil(snapshot.coach.chat.first?.activityEditProposalID)
    }

    private func proposal(state: String = "pending") -> PFEditProposal {
        let text = """
        {"proposals":[{"id":"\(proposalID)","state":"\(state)","created_at":"2030-03-12T10:00:00+00:00","author":"coach","source":"chat",
         "edit":{"op":"relabel","activity_id":12345,"activity_type":"walking"},
         "preview":{"before":[{"activity_id":12345,"name":"Morning Run","activity_type":"running","duration_seconds":3000}],"after":[]}}]}
        """
        return PFActivityEdits.parse(Data(text.utf8)).proposals[0]
    }

    func testTheEditSheetOpensOnTheRecordingTheProposalNames() {
        XCTAssertEqual(PFActivityEdits.target(for: proposal()),
                       PFEditTarget(activityID: "12345", name: "Morning Run", type: "running", durationS: 3000))
    }

    func testAProposalThatNamesNoRecordingCannotOpenTheSheet() {
        let empty = PFEditProposal(id: proposalID, state: "pending", createdAt: "", author: "coach", source: "chat", rationale: nil,
                                   spec: PFEditSpec(op: "relabel", activityID: nil, activityIDs: [], startS: nil, endS: nil, atS: nil,
                                                    activityType: nil, name: nil, target: nil),
                                   preview: PFEditPreview())
        XCTAssertNil(PFActivityEdits.target(for: empty))
    }

    func testAPendingEditAsksForAReview() {
        XCTAssertEqual(PFActivityEdits.cardTitle(isPending: true), "The Coach prepared an edit \u{2014} review")
    }

    func testAnEditThatIsNoLongerWaitingDoesNotAskForAReview() {
        XCTAssertEqual(PFActivityEdits.cardTitle(isPending: false), "The Coach prepared an edit")
    }

    func testAPendingEditHasNoStatusLine() {
        XCTAssertNil(PFActivityEdits.cardStatus(state: "pending"))
    }

    func testADeclinedEditSaysNothingWasChanged() {
        XCTAssertEqual(PFActivityEdits.cardStatus(state: "rejected"), "You declined this edit. Nothing was changed.")
    }

    func testAnExpiredEditSaysNothingWasChanged() {
        XCTAssertEqual(PFActivityEdits.cardStatus(state: "expired"), "This edit expired after 7 days. Nothing was changed.")
    }

    // MARK: The watch

    private func session(_ state: String, reason: String? = nil, sport: String? = nil, evidence: String? = nil) -> PFWatchStatusDoc.Session {
        PFWatchStatusDoc.Session(sessionId: "s1", name: "Easy run", date: "2030-03-14", workoutType: "run", sport: sport, state: state,
                                 reason: reason, evidence: evidence)
    }

    func testOnWatchWithTheReadbackSaysOnYourWatch() {
        XCTAssertEqual(PFWatchStatus529.line(session("on_watch", evidence: "garmin_library_readback"))?.text, "On your watch")
    }

    func testOnWatchWithoutTheReadbackDoesNotClaimTheWatch() {
        XCTAssertEqual(PFWatchStatus529.line(session("on_watch")), PFWatchStatus529.sentToConnect)
    }

    func testSentToConnectIsNotYetConfirmedOnTheWatch() {
        XCTAssertEqual(PFWatchStatus529.line(session("sent_to_connect"))?.text, "Sent to Garmin Connect \u{2014} not yet confirmed on the watch")
    }

    func testNotSentCarriesTheServersReasonAsASentence() {
        XCTAssertEqual(PFWatchStatus529.line(session("not_sent", reason: "not mirrored yet"))?.detail, "Not mirrored yet.")
    }

    func testABlockedSessionNamesItsSport() {
        XCTAssertEqual(PFWatchStatus529.line(session("blocked_by_allowlist", sport: "strength_training"))?.detail,
                       "Strength training sessions are not sent to Garmin.")
    }

    func testAFailedSendCarriesTheReason() {
        XCTAssertEqual(PFWatchStatus529.line(session("failed", reason: "Garmin refused the upload"))?.detail, "Garmin refused the upload.")
    }

    func testAFailedSendIsNeverOnTheWatch() {
        XCTAssertEqual(PFWatchStatus529.line(session("failed"))?.tone, .failed)
    }

    func testAStateThisBuildDoesNotKnowClaimsNothing() {
        XCTAssertNil(PFWatchStatus529.line(session("teleported")))
    }

    func testTheStatusDocumentReadsItsSessions() throws {
        let doc = try decode(PFWatchStatusDoc.self, """
        {"as_of": "2030-03-13T06:20:00+00:00", "window_days": 21, "readback": "fresh", "readback_at": "2030-03-13T06:20:00+00:00",
         "last_pass": {"anything": 1}, "counts": {"on_watch": 1},
         "sessions": [{"session_id": "s1", "name": "Easy run", "date": "2030-03-14", "workout_type": "run", "sport": "running",
                       "state": "on_watch", "garmin_workout_id": 42, "evidence": "garmin_library_readback"}]}
        """)
        XCTAssertEqual(doc.session("s1")?.state, "on_watch")
    }

    func testASessionOutsideTheWindowHasNoStatus() throws {
        let doc = try decode(PFWatchStatusDoc.self, "{\"sessions\": []}")
        XCTAssertNil(doc.session("s9"))
    }

    // MARK: The report is ready

    private func today(ready: Bool?, reason: String? = nil) -> PFReportsListDoc.Row {
        PFReportsListDoc.Row(key: "2030-03-13", day: "Wed 13", verdict: "Rest today", sub: "Both low", ts: "2030-03-13T06:30:00+00:00",
                             ready: ready, reason: reason)
    }

    private func dailyItem(date: String = "2030-03-13", route: String = "report_daily") -> PFInboxDoc.Item {
        PFInboxDoc.Item(id: "today:\(date)", ts: "2030-03-13T06:31:00+00:00", kind: "today", notify: true, title: "Report", body: nil,
                        listTitle: nil, listSub: nil, link: PFInboxDoc.Link(route: route, date: date))
    }

    func testTheReportsListReadsReadyAndReason() throws {
        let doc = try decode(PFReportsListDoc.self, """
        {"today": {"key": "2030-03-13", "ready": false, "reason": "no device reading yet"}}
        """)
        XCTAssertEqual(doc.today?.reason, "no device reading yet")
    }

    func testARowWithReadyTrueIsReady() {
        XCTAssertTrue(PFReportReadiness529.isReady(today(ready: true)))
    }

    func testARowWithReadyFalseIsNotReady() {
        XCTAssertFalse(PFReportReadiness529.isReady(today(ready: false)))
    }

    func testARowWithoutTheFieldIsNotReady() {
        XCTAssertFalse(PFReportReadiness529.isReady(today(ready: nil)))
    }

    func testNoRowIsNotReady() {
        XCTAssertFalse(PFReportReadiness529.isReady(nil))
    }

    func testAPendingRowShowsTheServersReason() {
        XCTAssertEqual(PFReportReadiness529.pendingSub(today(ready: false, reason: "no device reading yet")), "No device reading yet.")
    }

    func testAPendingRowWithoutAReasonInventsNone() {
        XCTAssertNil(PFReportReadiness529.pendingSub(today(ready: false)))
    }

    func testAReadyDailyReportItemIsAnnounced() {
        XCTAssertEqual(PFReportReadiness529.announceable([dailyItem()], today: today(ready: true)).count, 1)
    }

    func testADailyReportItemWaitsWhileTheReportIsNotReady() {
        XCTAssertEqual(PFReportReadiness529.announceable([dailyItem()], today: today(ready: false)).count, 0)
    }

    func testADailyReportItemWaitsWhenTheListCannotBeRead() {
        XCTAssertEqual(PFReportReadiness529.announceable([dailyItem()], today: nil).count, 0)
    }

    func testADailyReportItemForAnotherDayWaitsBecauseNothingSaysItIsReady() {
        XCTAssertEqual(PFReportReadiness529.announceable([dailyItem(date: "2030-03-12")], today: today(ready: true)).count, 0)
    }

    func testAnItemThatIsNotADailyReportIsNeverHeld() {
        XCTAssertEqual(PFReportReadiness529.announceable([dailyItem(route: "week")], today: today(ready: false)).count, 1)
    }
}
