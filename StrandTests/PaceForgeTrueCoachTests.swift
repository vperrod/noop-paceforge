import XCTest
@testable import Strand

/// The coach's TrueCoach week on the iPhone: the two jobs and the three confirm flags, how a refusal asks for a confirmation, how
/// `GET api/truecoach-status` reads (including the replan) and the words of the Coach week card, the coach's session and the weekly rhythm.
/// Every name, day and time is made up.
final class PaceForgeTrueCoachTests: XCTestCase {
    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private func status(_ text: String) -> PFTrueCoachStatus? { PFTrueCoachStatus.parse(Data(text.utf8)) }

    private func decodeItem(_ text: String) throws -> PFPlanWeekDoc.Item {
        try PFPlan529Decoder.make().decode(PFPlanWeekDoc.Item.self, from: Data(text.utf8))
    }

    private let fullStatus = """
    {"last_sync": "2030-03-13T08:00:00+00:00", "last_error": null, "count": 3,
     "workouts": [
       {"date": "2030-03-12", "title": "Lower body", "external_id": "tc:11", "session_id": "s-11"},
       {"date": "2030-03-14", "title": "Long run", "external_id": "tc:12", "session_id": null},
       {"date": "2030-03-15", "external_id": "tc:13"}],
     "rest_days": [{"date": "2030-03-16", "external_id": "tc:14", "note": "Rest"}],
     "week": [
       {"session_id": "s-11", "status": "missed", "skipped": true, "flag": true},
       {"session_id": "s-12", "status": "planned", "skipped": false}],
     "replan": {"removed": 2, "kept": 1,
                "conflicts": ["Spin class Tue 18:00", {"title": "Yoga", "date": "2030-03-12"}],
                "warnings": ["One draft run could not move"]}}
    """

    // MARK: Jobs

    func testTheSyncJobHasTheContractsName() {
        XCTAssertEqual(PFJobName.truecoachSync.rawValue, "truecoach-sync")
    }

    func testTheUndoJobHasTheContractsName() {
        XCTAssertEqual(PFJobName.truecoachReplanUndo.rawValue, "truecoach-replan-undo")
    }

    func testTheSyncJobIsASlowOne() {
        XCTAssertGreaterThan(PFJobName.truecoachSync.expectedSeconds, 300)
    }

    func testTheSyncJobIsNotReplayedWhenItGotNoAnswer() {
        XCTAssertFalse(PFJobName.truecoachSync.isQueueable)
    }

    func testTheUndoJobIsNotReplayedWhenItGotNoAnswer() {
        XCTAssertFalse(PFJobName.truecoachReplanUndo.isQueueable)
    }

    func testTheSyncRequestCarriesNoInputs() {
        let body = PFJobRequest.body(.truecoachSync, inputs: PFJobInputs.truecoachSync())
        XCTAssertEqual((body["inputs"] as? [String: Any])?.count, 0)
    }

    func testTheUndoRequestCarriesNoInputs() {
        let body = PFJobRequest.body(.truecoachReplanUndo, inputs: PFJobInputs.truecoachReplanUndo())
        XCTAssertEqual((body["inputs"] as? [String: Any])?.count, 0)
    }

    // MARK: Confirm flags

    func testAMoveCarriesNoConfirmationUntilTheAthleteGivesOne() {
        XCTAssertNil(PFJobInputs.calendarMove(sessionID: "s1", to: "2030-03-20")?["confirm_leave_week"])
    }

    func testAConfirmedMoveOutOfTheWeekCarriesTheLeaveWeekFlag() {
        assertSame(PFJobInputs.confirmed(PFJobInputs.calendarMove(sessionID: "s1", to: "2030-03-20"), .leaveWeek),
                   ["session_id": "s1", "action": "reschedule", "new_date": "2030-03-20", "confirm_leave_week": true])
    }

    func testAConfirmedSkipCarriesTheSkipMandatoryFlag() {
        assertSame(PFJobInputs.confirmed(PFJobInputs.calendarDelete(sessionID: "s1"), .skipMandatory),
                   ["session_id": "s1", "action": "delete", "confirm_skip_mandatory": true])
    }

    func testAConfirmedSwapCarriesTheReplaceMandatoryFlag() {
        let swap: [String: Any] = ["date": "2030-03-12", "session_id": "s1", "kind": "run"]
        assertSame(PFJobInputs.confirmed(swap, .replaceMandatory),
                   ["date": "2030-03-12", "session_id": "s1", "kind": "run", "confirm_replace_mandatory": true])
    }

    func testAConfirmationFlagIsTheBooleanTrue() {
        let flag = PFJobInputs.confirmed(["session_id": "s1"], .skipMandatory)?["confirm_skip_mandatory"]
        XCTAssertEqual(flag as? Bool, true)
    }

    func testARequestThatCouldNotBeBuiltIsNeverConfirmed() {
        XCTAssertNil(PFJobInputs.confirmed(nil, .leaveWeek))
    }

    // MARK: Which refusal asks for which confirmation

    func testTheMoveRefusalAsksToLeaveTheWeek() {
        let refusal = PFJobError.refused("Choose a day from that week, or send confirm_leave_week: true to move it out.")
        XCTAssertEqual(PFMandatoryConfirm.needed(by: refusal), .leaveWeek)
    }

    func testTheSkipRefusalAsksToSkipTheCoachsSession() {
        let refusal = PFJobError.refused("Skipping it is recorded as a missed coach session. Send confirm_skip_mandatory: true to skip it.")
        XCTAssertEqual(PFMandatoryConfirm.needed(by: refusal), .skipMandatory)
    }

    func testTheSwapRefusalAsksToReplaceTheCoachsSession() {
        let refusal = PFJobError.refused("Lower body is a session from your coach. Send confirm_replace_mandatory: true to swap it.")
        XCTAssertEqual(PFMandatoryConfirm.needed(by: refusal), .replaceMandatory)
    }

    func testAnotherRefusalAsksForNoConfirmation() {
        XCTAssertNil(PFMandatoryConfirm.needed(by: .refused("That session is no longer on your plan.")))
    }

    func testAFailureThatIsNotARefusalAsksForNoConfirmation() {
        XCTAssertNil(PFMandatoryConfirm.needed(by: .offline))
    }

    func testTheLeaveWeekQuestionIsTheCoachsQuestion() {
        XCTAssertEqual(PFMandatoryConfirm.leaveWeek.question, "This is your coach's session. Move it out of its week anyway?")
    }

    func testTheSkipQuestionSaysItIsRecordedAsMissed() {
        XCTAssertEqual(PFMandatoryConfirm.skipMandatory.question, "Skip your coach's session? It will be recorded as missed.")
    }

    func testTheReplaceQuestionSaysItStaysTheCoachsSession() {
        XCTAssertTrue(PFMandatoryConfirm.replaceMandatory.question.hasSuffix("It stays your coach's session."))
    }

    func testEveryConfirmationHasItsOwnButtonWords() {
        XCTAssertEqual(PFMandatoryConfirm.allCases.map { $0.confirmTitle }, ["Move anyway", "Skip anyway", "Replace anyway"])
    }

    // MARK: Reading the status

    func testTheLastSyncIsRead() {
        XCTAssertEqual(status(fullStatus)?.lastSync, "2030-03-13T08:00:00+00:00")
    }

    func testTheCountIsRead() {
        XCTAssertEqual(status(fullStatus)?.count, 3)
    }

    func testAWorkoutWithoutATitleIsLeftOut() {
        XCTAssertEqual(status(fullStatus)?.workouts.map { $0.title }, ["Lower body", "Long run"])
    }

    func testAWorkoutKeepsItsSessionId() {
        XCTAssertEqual(status(fullStatus)?.workouts.first?.sessionID, "s-11")
    }

    func testAWorkoutNotYetOnTheCalendarHasNoSessionId() {
        XCTAssertNil(status(fullStatus)?.workouts.last?.sessionID)
    }

    func testRestDaysAreCounted() {
        XCTAssertEqual(status(fullStatus)?.restDays, 1)
    }

    func testAnErrorOfNullReadsAsNoError() {
        XCTAssertNil(status(fullStatus)?.lastError)
    }

    func testTheLastErrorIsRead() {
        XCTAssertEqual(status("{\"last_error\": \"could not log in\", \"workouts\": []}")?.lastError, "could not log in")
    }

    func testAMissingCountFallsBackToTheWorkoutsListed() {
        XCTAssertEqual(status("{\"workouts\": [{\"date\": \"2030-03-12\", \"title\": \"Lower body\"}]}")?.count, 1)
    }

    func testASkippedSessionIsFoundInTheWeekRows() {
        XCTAssertEqual(status(fullStatus)?.weekRow(sessionID: "s-11")?.skipped, true)
    }

    func testASessionThatIsNotInTheWeekRowsHasNoRow() {
        XCTAssertNil(status(fullStatus)?.weekRow(sessionID: "s-99"))
    }

    func testABodyThatIsNotAnObjectIsNotAStatus() {
        XCTAssertNil(status("[1, 2]"))
    }

    func testNoBodyIsNotAStatus() {
        XCTAssertNil(PFTrueCoachStatus.parse(nil))
    }

    // MARK: Reading the replan

    func testTheReplanCountsWhatItRemoved() {
        XCTAssertEqual(status(fullStatus)?.replan?.removed, 2)
    }

    func testTheReplanCountsWhatItKept() {
        XCTAssertEqual(status(fullStatus)?.replan?.kept, 1)
    }

    func testAConflictGivenAsTextIsKept() {
        XCTAssertEqual(status(fullStatus)?.replan?.conflicts.first, "Spin class Tue 18:00")
    }

    func testAConflictGivenAsARowNamesItsDay() {
        XCTAssertEqual(status(fullStatus)?.replan?.conflicts.last, "Tue 12 Mar: Yoga")
    }

    func testTheReplanWarningsAreRead() {
        XCTAssertEqual(status(fullStatus)?.replan?.warnings, ["One draft run could not move"])
    }

    func testRemovedGivenAsAListIsCountedByItsLength() {
        XCTAssertEqual(status("{\"replan\": {\"removed\": [{\"title\": \"Easy run\"}, {\"title\": \"Bike\"}]}}")?.replan?.removed, 2)
    }

    func testAStatusWithoutAReplanHasNone() {
        XCTAssertNil(status("{\"workouts\": []}")?.replan)
    }

    func testAReplanThatDidNothingIsEmpty() {
        XCTAssertEqual(status("{\"replan\": {\"removed\": 0, \"kept\": 0, \"conflicts\": [], \"warnings\": []}}")?.replan?.isEmpty, true)
    }

    // MARK: Words of the Coach week card

    private func moment(_ text: String, plusHours hours: Double) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text)).addingTimeInterval(hours * 3600)
    }

    func testTheLastReadSaysHowLongAgo() throws {
        let now = try moment("2030-03-13T08:00:00+00:00", plusHours: 3)
        XCTAssertEqual(PFTrueCoachWording.lastSync("2030-03-13T08:00:00+00:00", now: now), "Last read 3 h ago")
    }

    func testAPlanNeverReadSaysSo() {
        XCTAssertEqual(PFTrueCoachWording.lastSync(nil), "Not read yet")
    }

    func testTheCountNamesSessionsAndRestDays() throws {
        let read = try XCTUnwrap(status(fullStatus))
        XCTAssertEqual(PFTrueCoachWording.count(read), "3 sessions from your coach, 1 rest day")
    }

    func testOneSessionIsNotPlural() throws {
        let read = try XCTUnwrap(status("{\"count\": 1}"))
        XCTAssertEqual(PFTrueCoachWording.count(read), "1 session from your coach")
    }

    func testAnErrorIsToldInPlainWords() throws {
        let failed = try XCTUnwrap(status("{\"last_error\": \"the page listed 0 workouts\"}"))
        XCTAssertEqual(PFTrueCoachWording.error(failed), "Could not read your TrueCoach plan: the page listed 0 workouts")
    }

    func testNoErrorSaysNothing() throws {
        let read = try XCTUnwrap(status(fullStatus))
        XCTAssertNil(PFTrueCoachWording.error(read))
    }

    func testTheRemovedLineNamesTheCount() throws {
        let replan = try XCTUnwrap(status(fullStatus)?.replan)
        XCTAssertEqual(PFTrueCoachWording.removed(replan), "I removed 2 of my own draft sessions to make room")
    }

    func testNothingRemovedSaysNothing() throws {
        let replan = try XCTUnwrap(status("{\"replan\": {\"removed\": 0, \"kept\": 3}}")?.replan)
        XCTAssertNil(PFTrueCoachWording.removed(replan))
    }

    func testTheKeptLineNamesTheCount() throws {
        let replan = try XCTUnwrap(status(fullStatus)?.replan)
        XCTAssertEqual(PFTrueCoachWording.kept(replan), "I kept 1 that still fit")
    }

    func testTheCardsButtonsAndHeadingAreTheAgreedWords() {
        XCTAssertEqual([PFTrueCoachWording.title, PFTrueCoachWording.syncButton, PFTrueCoachWording.undoButton, PFTrueCoachWording.checkThese],
                       ["Coach week", "Sync now", "Undo", "Check these"])
    }

    // MARK: A coach's session

    func testTheBadgeIsCoach() {
        XCTAssertEqual(PFCoachSession.badge, "Coach")
    }

    func testTheMustLineNamesTheCoachsWeek() {
        XCTAssertEqual(PFCoachSession.mustLine(weekStart: "2030-03-11"), "Must be done this week (Mon 11 Mar to Sun 17 Mar)")
    }

    func testTheMustLineWithoutAWeekStartLeavesTheRangeOut() {
        XCTAssertEqual(PFCoachSession.mustLine(weekStart: nil), "Must be done this week")
    }

    func testASkippedCoachSessionCountsAsMissed() {
        XCTAssertEqual(PFCoachSession.skippedLine, "Skipped \u{2014} counts as missed")
    }

    func testASessionIsSkippedWhenItsItemSaysSo() {
        XCTAssertTrue(PFCoachSession.isSkipped(itemFlag: true, row: nil))
    }

    func testASessionIsSkippedWhenTheStatusRowSaysSo() {
        XCTAssertTrue(PFCoachSession.isSkipped(itemFlag: nil, row: PFTrueCoachStatus.WeekRow(sessionID: "s1", status: "missed", skipped: true)))
    }

    func testASessionNeitherSaysIsNotSkipped() {
        XCTAssertFalse(PFCoachSession.isSkipped(itemFlag: nil, row: PFTrueCoachStatus.WeekRow(sessionID: "s1", status: "planned", skipped: false)))
    }

    func testTheCoachsTextKeepsItsLineBreaks() {
        XCTAssertEqual(PFCoachSession.details("  Warm-up\r\nA. Squat 5 x 5\nB. Row 3 x 10\n"), "Warm-up\nA. Squat 5 x 5\nB. Row 3 x 10")
    }

    func testBlankCoachTextIsNoDetails() {
        XCTAssertNil(PFCoachSession.details(" \n "))
    }

    func testAShortPrescriptionDoesNotScroll() {
        XCTAssertFalse(PFCoachSession.needsScroll("Warm-up\nA. Squat 5 x 5\nB. Row 3 x 10"))
    }

    func testALongPrescriptionScrollsInsideItsCard() {
        XCTAssertTrue(PFCoachSession.needsScroll((1...15).map { "Exercise \($0): 3 x 10" }.joined(separator: "\n")))
    }

    func testAPlanWeekItemReadsTheCoachFields() throws {
        let item = try decodeItem("""
        {"kind": "session", "session_id": "s-11", "title": "Lower body", "coach_assigned": true, "mandatory": true,
         "coach_details": "Warm-up\\nA. Squat 5 x 5", "week_start": "2030-03-11"}
        """)
        XCTAssertEqual(item.coachDetails, "Warm-up\nA. Squat 5 x 5")
    }

    func testAPlanWeekItemReadsTheCoachsWeekAndThatItIsMandatory() throws {
        let item = try decodeItem("""
        {"kind": "session", "session_id": "s-11", "coach_assigned": true, "mandatory": true, "week_start": "2030-03-11"}
        """)
        XCTAssertEqual([item.coachAssigned, item.mandatory], [true, true])
        XCTAssertEqual(item.weekStart, "2030-03-11")
    }

    func testAnItemThatIsNotTheCoachsHasNoCoachFields() throws {
        let item = try decodeItem("{\"kind\": \"session\", \"session_id\": \"s-12\", \"title\": \"Easy run\"}")
        XCTAssertNil(item.coachAssigned)
    }

    // MARK: Weekly rhythm

    func testTheRhythmTellsTheSundayScheduleAndTheCoachsRule() {
        XCTAssertEqual(PFWeeklyRhythm.text,
                       "Sunday 19:00 week analysis \u{2192} 19:15 your TrueCoach week is read \u{2192} 19:30 next week is drafted from that analysis "
                       + "and your coach's sessions \u{2192} 20:00 Coach review. "
                       + "Your coach's sessions are mandatory in their week but can move to any day of it.")
    }

    func testTheRhythmNamesTheLastReadWhenTheServerGivesIt() throws {
        let now = try moment("2030-03-13T08:00:00+00:00", plusHours: 3)
        XCTAssertEqual(PFWeeklyRhythm.lastRead("2030-03-13T08:00:00+00:00", now: now), "Your TrueCoach week was last read 3 h ago.")
    }

    func testTheRhythmNamesNoLastReadWhenTheServerNeverReadIt() {
        XCTAssertNil(PFWeeklyRhythm.lastRead(nil))
    }
}
