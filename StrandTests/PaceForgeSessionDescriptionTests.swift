import XCTest
@testable import Strand

/// Editing the description of a session and writing one's own: the limits (4000 / 120), the `calendar-edit` and `add-session` inputs, the reassess
/// flag, the draft kept on the phone, the restore flow and how the result reads. All values are made up.
final class PaceForgeSessionDescriptionTests: XCTestCase {
    private let today = "2030-03-13"

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private func draft(_ text: String = "Warm-up\nA. Squat 5 x 5", name: String = "Lower body") -> PFSessionDescriptionDraft {
        PFSessionDescriptionDraft(sessionID: "s-11", description: text, name: name)
    }

    private func result(_ json: String) -> PFSessionDescriptionResult {
        PFSessionDescriptionResult(PFJ(data: Data(json.utf8)))
    }

    // MARK: Limits

    func testADescriptionOf4000CharactersIsAccepted() {
        XCTAssertNil(PFSessionDescription.descriptionProblem(String(repeating: "a", count: 4_000)))
    }

    func testADescriptionOf4001CharactersIsRefused() {
        XCTAssertNotNil(PFSessionDescription.descriptionProblem(String(repeating: "a", count: 4_001)))
    }

    func testADescriptionOfOnlySpacesIsRefused() {
        XCTAssertNotNil(PFSessionDescription.descriptionProblem(" \n  "))
    }

    func testANameOf120CharactersIsAccepted() {
        XCTAssertNil(PFSessionDescription.nameProblem(String(repeating: "n", count: 120)))
    }

    func testANameOf121CharactersIsRefused() {
        XCTAssertNotNil(PFSessionDescription.nameProblem(String(repeating: "n", count: 121)))
    }

    func testLengthIsCountedInCharactersTheWayTheServerDoes() {
        XCTAssertEqual(PFSessionDescription.length("\u{1F468}\u{200D}\u{1F469}"), 3)
    }

    func testTheLimitHoldsForTextWithMultiScalarEmoji() {
        XCTAssertNotNil(PFSessionDescription.descriptionProblem(String(repeating: "\u{1F468}\u{200D}\u{1F469}", count: 1_400)))
    }

    // MARK: The text the sheet starts from

    func testTheSheetStartsFromTheSessionsOwnDescriptionWhenItHasOne() {
        XCTAssertEqual(PFSessionDescription.currentText(description: "Mine", coachDetails: "Coach", do: "Do"), "Mine")
    }

    func testTheSheetStartsFromTheCoachsTextWhenThereIsNoDescription() {
        XCTAssertEqual(PFSessionDescription.currentText(description: nil, coachDetails: "Coach", do: "Do"), "Coach")
    }

    func testTheSheetStartsFromTheDoLineWhenNothingElseIsWritten() {
        XCTAssertEqual(PFSessionDescription.currentText(description: " ", coachDetails: nil, do: "Do"), "Do")
    }

    func testTheStartingTextKeepsItsLineBreaks() {
        XCTAssertEqual(PFSessionDescription.currentText(description: "A\r\nB\n\nC", coachDetails: nil, do: nil), "A\nB\n\nC")
    }

    func testALongTextIsNotCutWhenTheSheetOpens() {
        let long = String(repeating: "line\n", count: 1_500) + "end"
        XCTAssertEqual(PFSessionDescription.currentText(description: long, coachDetails: nil, do: nil), long)
    }

    // MARK: calendar-edit inputs

    func testSavingADescriptionSendsTheSessionTheEditActionAndTheText() {
        assertSame(PFJobInputs.calendarDescribe(sessionID: "s-11", description: "Easy 40 min"),
                   ["session_id": "s-11", "action": "edit", "description": "Easy 40 min"])
    }

    func testTheDescriptionIsTrimmedAndKeepsItsInnerLineBreaks() {
        XCTAssertEqual(PFJobInputs.calendarDescribe(sessionID: "s-11", description: "  A\r\nB \n")?["description"] as? String, "A\nB")
    }

    func testTheNameIsSentTrimmed() {
        XCTAssertEqual(PFJobInputs.calendarDescribe(sessionID: "s-11", name: "  Tempo  ")?["name"] as? String, "Tempo")
    }

    func testAnEditWithNeitherTextNorNameIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarDescribe(sessionID: "s-11", reassess: true))
    }

    func testATooLongDescriptionIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarDescribe(sessionID: "s-11", description: String(repeating: "a", count: 4_001)))
    }

    func testATooLongNameIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarDescribe(sessionID: "s-11", name: String(repeating: "n", count: 121)))
    }

    func testASessionIdTheServerWouldRefuseIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarDescribe(sessionID: "../x", description: "Easy"))
    }

    func testTheReassessFlagGoesWithTheEditWhenGiven() {
        XCTAssertEqual(PFJobInputs.calendarDescribe(sessionID: "s-11", description: "Easy", reassess: false)?["reassess"] as? Bool, false)
    }

    func testNoReassessFlagGoesWhenNoneIsGiven() {
        XCTAssertNil(PFJobInputs.calendarDescribe(sessionID: "s-11", description: "Easy")?["reassess"])
    }

    // MARK: Reassess flag

    func testAPlainSaveOnADoneWorkoutSaysNoReassessExplicitly() {
        XCTAssertEqual(PFSessionDescription.reassessFlag(isDone: true, wantsReassess: false), false)
    }

    func testSaveAndReassessOnADoneWorkoutSaysYes() {
        XCTAssertEqual(PFSessionDescription.reassessFlag(isDone: true, wantsReassess: true), true)
    }

    func testASessionThatIsNotDoneNeverSendsTheFlag() {
        XCTAssertNil(PFSessionDescription.reassessFlag(isDone: false, wantsReassess: true))
    }

    // MARK: The form

    func testAFormNobodyTouchedHasNothingToSend() {
        XCTAssertNil(draft().inputs(reassess: nil))
    }

    func testOnlyTheChangedTextIsSent() {
        var form = draft()
        form.description = "Warm-up\nA. Squat 5 x 5\nB. Row 3 x 10"
        assertSame(form.inputs(reassess: nil), ["session_id": "s-11", "action": "edit", "description": "Warm-up\nA. Squat 5 x 5\nB. Row 3 x 10"])
    }

    func testOnlyTheChangedNameIsSent() {
        var form = draft()
        form.name = "Lower body B"
        assertSame(form.inputs(reassess: nil), ["session_id": "s-11", "action": "edit", "name": "Lower body B"])
    }

    func testAChangeThatOnlyAddsTrailingSpaceIsNoChange() {
        var form = draft()
        form.description += "  \n"
        XCTAssertFalse(form.hasChanges)
    }

    func testClearingTheWholeTextIsAProblem() {
        var form = draft()
        form.description = ""
        XCTAssertNotNil(form.problem)
    }

    func testAnUntouchedEmptyDescriptionIsNotAProblem() {
        XCTAssertNil(draft("").problem)
    }

    func testATooLongTextCannotBeSent() {
        var form = draft()
        form.description = String(repeating: "a", count: 4_001)
        XCTAssertFalse(form.canSend)
    }

    func testAClearedNameIsAProblem() {
        var form = draft()
        form.name = "  "
        XCTAssertNotNil(form.problem)
    }

    func testTheReassessFlagIsPassedToTheInputs() {
        var form = draft()
        form.description = "New"
        XCTAssertEqual(form.inputs(reassess: true)?["reassess"] as? Bool, true)
    }

    // MARK: Draft kept on the phone

    func testAFailedSendKeepsTheFormWhole() {
        var form = draft()
        form.description = "What I typed"
        XCTAssertEqual(PFDraftKeeping.afterSend(form, tookIt: false)?.description, "What I typed")
    }

    func testASendTheServerTookLeavesNothingKept() {
        XCTAssertNil(PFDraftKeeping.afterSend(draft(), tookIt: true))
    }

    func testAnUnsentEditIsStoredAndReadBackWhole() {
        var form = draft()
        form.description = "Line one\nLine two"
        let again = PFSessionDescriptionKeeping.decode(PFSessionDescriptionKeeping.toStore(form))
        XCTAssertEqual(again, form)
    }

    func testAFormWithNoChangeStoresNothing() {
        XCTAssertNil(PFSessionDescriptionKeeping.toStore(draft()))
    }

    func testTheSheetOpensWithTheKeptEditWhenThereIsOne() {
        var form = draft()
        form.description = "Unsent words"
        let opened = PFSessionDescriptionKeeping.opening(kept: PFSessionDescriptionKeeping.toStore(form), sessionID: "s-11",
                                                         description: "Warm-up\nA. Squat 5 x 5", name: "Lower body")
        XCTAssertEqual(opened.description, "Unsent words")
    }

    func testAKeptEditIsMeasuredAgainstWhatTheServerHasNow() {
        var form = draft()
        form.description = "Unsent words"
        let opened = PFSessionDescriptionKeeping.opening(kept: PFSessionDescriptionKeeping.toStore(form), sessionID: "s-11",
                                                         description: "Changed on the server", name: "Lower body")
        XCTAssertEqual(opened.originalDescription, "Changed on the server")
    }

    func testAKeptEditThatNowMatchesTheServerIsDropped() {
        var form = draft()
        form.description = "Same now"
        let opened = PFSessionDescriptionKeeping.opening(kept: PFSessionDescriptionKeeping.toStore(form), sessionID: "s-11",
                                                         description: "Same now", name: "Lower body")
        XCTAssertFalse(opened.hasChanges)
    }

    func testAKeptEditOfAnotherSessionIsNotUsed() {
        var other = PFSessionDescriptionDraft(sessionID: "s-99", description: "x", name: "y")
        other.description = "Other session's words"
        let opened = PFSessionDescriptionKeeping.opening(kept: PFSessionDescriptionKeeping.toStore(other), sessionID: "s-11",
                                                         description: "Mine", name: "Lower body")
        XCTAssertEqual(opened.description, "Mine")
    }

    func testStartingOverGoesBackToWhatTheServerHad() {
        var form = draft()
        form.description = "Unsent"
        XCTAssertEqual(form.startedOver().description, "Warm-up\nA. Squat 5 x 5")
    }

    func testEachSessionKeepsItsDraftUnderItsOwnKey() {
        XCTAssertNotEqual(PFSessionDescription.draftKey(sessionID: "s-11"), PFSessionDescription.draftKey(sessionID: "s-12"))
    }

    // MARK: Restore the coach's text

    func testRestoringSendsTheSessionAndTheRestoreAction() {
        assertSame(PFJobInputs.calendarRestoreCoachText(sessionID: "s-11"), ["session_id": "s-11", "action": "restore_coach_text"])
    }

    func testRestoringWithoutAValidSessionSendsNothing() {
        XCTAssertNil(PFJobInputs.calendarRestoreCoachText(sessionID: nil))
    }

    func testRestoreIsOfferedOnACoachSession() {
        XCTAssertTrue(PFSessionDescription.canRestoreCoachText(isCoachAssigned: true))
    }

    func testRestoreIsNotOfferedOnYourOwnSession() {
        XCTAssertFalse(PFSessionDescription.canRestoreCoachText(isCoachAssigned: false))
    }

    func testRestoringAsksBeforeItReplacesWhatYouWrote() {
        XCTAssertTrue(PFSessionDescription.restoreQuestion.contains("What you wrote is lost"))
    }

    // MARK: The result

    func testAReassessedSaveSaysTheCoachIsReassessing() {
        let parsed = result(#"{"session_id": "s-11", "description_saved": true, "analysis_id": "12001", "partial": false}"#)
        XCTAssertEqual(parsed.note(reassessAsked: true), "Saved. The Coach is reassessing this workout.")
    }

    func testAPlainSaveSaysSaved() {
        let parsed = result(#"{"session_id": "s-11", "description_saved": true, "analysis_id": null, "partial": false}"#)
        XCTAssertEqual(parsed.note(reassessAsked: false), "Saved.")
    }

    func testANumericAnalysisIdReads() {
        XCTAssertEqual(result(#"{"analysis_id": 12001}"#).analysisID, "12001")
    }

    func testANullAnalysisIdReadsAsNone() {
        XCTAssertNil(result(#"{"analysis_id": null}"#).analysisID)
    }

    func testAReassessThatTheServerDidNotQueueDoesNotClaimTheCoachIsReading() {
        let parsed = result(#"{"session_id": "s-11", "description_saved": true, "analysis_id": null, "partial": false}"#)
        XCTAssertEqual(parsed.note(reassessAsked: true), "Saved.")
    }

    func testAPartialSaveSaysTheCoachCouldNotBeQueued() {
        let parsed = result(#"{"session_id": "s-11", "description_saved": true, "analysis_id": null, "partial": true}"#)
        XCTAssertEqual(parsed.note(reassessAsked: true), PFSessionDescription.partialNote)
    }

    func testTheResultReadsWhetherTheDescriptionWasSaved() {
        XCTAssertEqual(result(#"{"description_saved": true}"#).descriptionSaved, true)
    }

    // MARK: Plan-week items

    private func decodeItem(_ text: String) throws -> PFPlanWeekDoc.Item {
        try PFPlan529Decoder.make().decode(PFPlanWeekDoc.Item.self, from: Data(text.utf8))
    }

    func testAPlanWeekItemReadsItsDescription() throws {
        let item = try decodeItem(#"{"kind": "session", "session_id": "s-11", "description": "Warm-up\nA. Squat", "athlete_edited": true}"#)
        XCTAssertEqual(item.description, "Warm-up\nA. Squat")
    }

    func testAPlanWeekItemReadsThatTheAthleteEditedIt() throws {
        let item = try decodeItem(#"{"kind": "session", "session_id": "s-11", "athlete_edited": true}"#)
        XCTAssertEqual(item.athleteEdited, true)
    }

    // MARK: add-session with a description

    func testAddingASessionWithoutADescriptionSendsNone() {
        XCTAssertNil(PFAddSessionDraft(date: "2030-03-16").inputs(today: today)?["description"])
    }

    func testAddingASessionSendsItsDescriptionTrimmedWithLineBreaksKept() {
        var form = PFAddSessionDraft(date: "2030-03-16")
        form.descriptionText = "  Warm-up 10 min\n4 x 4 min hard\n"
        XCTAssertEqual(form.inputs(today: today)?["description"] as? String, "Warm-up 10 min\n4 x 4 min hard")
    }

    func testAnAddFormWithADescriptionOver4000CharactersHasAProblem() {
        var form = PFAddSessionDraft(date: "2030-03-16")
        form.descriptionText = String(repeating: "a", count: 4_001)
        XCTAssertNotNil(form.problem(today: today))
    }

    func testAnAddFormWithADescriptionOf4000CharactersCanBeSent() {
        var form = PFAddSessionDraft(date: "2030-03-16")
        form.descriptionText = String(repeating: "a", count: 4_000)
        XCTAssertNotNil(form.inputs(today: today))
    }

    func testTheAddFormKeepsTheOtherFieldsWithADescription() {
        var form = PFAddSessionDraft(date: "2030-03-16")
        form.descriptionText = "Easy"
        form.repeatWeeks = 4
        assertSame(form.inputs(today: today), ["date": "2030-03-16", "sport": "Run", "minutes": 45, "description": "Easy", "repeat_weeks": 4])
    }

    func testTheAddHintIsTheOneTheAthleteWasPromised() {
        XCTAssertEqual(PFSessionDescription.addHint,
                       "Write what the workout is: warm-up, sets x reps, intervals, effort, anything the Coach should know")
    }
}
