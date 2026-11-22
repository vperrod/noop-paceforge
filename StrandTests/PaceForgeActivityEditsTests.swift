import XCTest
@testable import Strand

/// Editing a recorded activity without touching it: the inputs of the four activity-edit jobs, the form's rules and how the activity-edits
/// document reads. Field names are the job contract's (and the server's validator's). All values are made up.
final class PaceForgeActivityEditsTests: XCTestCase {
    private let idA = String(repeating: "a", count: 32)
    private let idB = String(repeating: "b", count: 32)
    private let idC = String(repeating: "c", count: 32)
    private let idD = String(repeating: "d", count: 32)

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private func draft(_ change: (inout PFActivityEditDraft) -> Void = { _ in }) -> PFActivityEditDraft {
        var form = PFActivityEditDraft(activityID: "12345", currentType: "running", currentName: "Morning Run", durationS: 3000)
        change(&form)
        return form
    }

    // MARK: activity-edit-propose

    func testRelabelSendsTheOpAndTheIdAsANumber() {
        assertSame(PFJobInputs.activityEditPropose(.relabel, activityID: "12345", activityType: "walking"),
                   ["op": "relabel", "activity_id": 12345, "activity_type": "walking"])
    }

    func testRelabelWithATypeOutsideTheClosedListIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.relabel, activityID: "12345", activityType: "parkour"))
    }

    func testRelabelWithNeitherATypeNorANameIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.relabel, activityID: "12345"))
    }

    func testRelabelWithAnEightyOneCharacterNameIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.relabel, activityID: "12345", name: String(repeating: "x", count: 81)))
    }

    func testRelabelNameIsTrimmed() {
        assertSame(PFJobInputs.activityEditPropose(.relabel, activityID: "12345", name: "  Dog walk "),
                   ["op": "relabel", "activity_id": 12345, "name": "Dog walk"])
    }

    func testTrimWithOnlyAStartSendsOnlyTheStart() {
        assertSame(PFJobInputs.activityEditPropose(.trim, activityID: "12345", startS: 150),
                   ["op": "trim", "activity_id": 12345, "start_s": 150.0])
    }

    func testTrimWithNeitherBoundIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.trim, activityID: "12345"))
    }

    func testTrimBeyondTwoDaysIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.trim, activityID: "12345", endS: 172_801))
    }

    func testSplitSendsThePoint() {
        assertSame(PFJobInputs.activityEditPropose(.split, activityID: "12345", atS: 1200),
                   ["op": "split", "activity_id": 12345, "at_s": 1200.0])
    }

    func testSplitWithoutAPointIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.split, activityID: "12345"))
    }

    func testGroupSendsEveryIdAsANumber() {
        assertSame(PFJobInputs.activityEditPropose(.group, activityID: nil, groupIDs: ["12345", "12346"]),
                   ["op": "group", "activity_ids": [12345, 12346]])
    }

    func testGroupOfOneRecordingIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.group, activityID: nil, groupIDs: ["12345"]))
    }

    func testGroupOfElevenRecordingsIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.group, activityID: nil, groupIDs: (1...11).map { String(100 + $0) }))
    }

    func testGroupWithARecordingTwiceIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.group, activityID: nil, groupIDs: ["12345", "12345"]))
    }

    func testUngroupSendsTheGroupsId() {
        assertSame(PFJobInputs.activityEditPropose(.ungroup, activityID: "12345"), ["op": "ungroup", "activity_id": 12345])
    }

    func testAnIdThatIsNotDigitsIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.ungroup, activityID: "bike:2030-03-13"))
    }

    func testAnIdOfSixteenDigitsIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.ungroup, activityID: "1234567890123456"))
    }

    func testTheRationaleGoesWhenWritten() {
        assertSame(PFJobInputs.activityEditPropose(.ungroup, activityID: "12345", rationale: " It was a walk "),
                   ["op": "ungroup", "activity_id": 12345, "rationale": "It was a walk"])
    }

    func testARationaleOverFourHundredCharactersIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditPropose(.ungroup, activityID: "12345", rationale: String(repeating: "x", count: 401)))
    }

    // MARK: confirm, reject, undo

    func testConfirmSendsTheProposalIdOnly() {
        assertSame(PFJobInputs.activityEditConfirm(proposalID: idA), ["proposal_id": idA])
    }

    func testConfirmWithUpperCaseHexIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditConfirm(proposalID: String(repeating: "A", count: 32)))
    }

    func testConfirmWithAShortIdIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditConfirm(proposalID: "abc123"))
    }

    func testRejectCarriesAReasonWhenGiven() {
        assertSame(PFJobInputs.activityEditReject(proposalID: idA, reason: " Not now "), ["proposal_id": idA, "reason": "Not now"])
    }

    func testRejectWithoutAReasonSendsTheIdOnly() {
        assertSame(PFJobInputs.activityEditReject(proposalID: idA), ["proposal_id": idA])
    }

    func testRejectCutsTheReasonAtTwoHundredCharacters() {
        let inputs = PFJobInputs.activityEditReject(proposalID: idA, reason: String(repeating: "x", count: 250))
        XCTAssertEqual((inputs?["reason"] as? String)?.count, 200)
    }

    func testUndoSendsTheEditId() {
        assertSame(PFJobInputs.activityEditUndo(editID: idB), ["edit_id": idB])
    }

    func testUndoWithoutAnIdIsNotSent() {
        XCTAssertNil(PFJobInputs.activityEditUndo(editID: nil))
    }

    func testTheJobNamesAreTheContractsNames() {
        XCTAssertEqual([PFJobName.activityEditPropose, .activityEditConfirm, .activityEditReject, .activityEditUndo, .hrZonesAdd].map { $0.rawValue },
                       ["activity-edit-propose", "activity-edit-confirm", "activity-edit-reject", "activity-edit-undo", "hr-zones-add"])
    }

    func testTheEditJobsAreNeverReplayedAfterALostReply() {
        XCTAssertEqual([PFJobName.activityEditPropose, .activityEditConfirm, .activityEditReject, .activityEditUndo, .hrZonesAdd].map { $0.isQueueable },
                       [false, false, false, false, false])
    }

    // MARK: Typed times

    func testMinutesAndSecondsRead() {
        XCTAssertEqual(PFActivityEditRules.seconds("12:30"), 750)
    }

    func testHoursMinutesAndSecondsRead() {
        XCTAssertEqual(PFActivityEditRules.seconds("1:02:03"), 3723)
    }

    func testPlainNumbersAreSeconds() {
        XCTAssertEqual(PFActivityEditRules.seconds("750"), 750)
    }

    func testSecondsOverFiftyNineAfterAColonAreRefused() {
        XCTAssertNil(PFActivityEditRules.seconds("12:75"))
    }

    func testLettersAreRefused() {
        XCTAssertNil(PFActivityEditRules.seconds("abc"))
    }

    func testANegativeTimeIsRefused() {
        XCTAssertNil(PFActivityEditRules.seconds("-5"))
    }

    func testFourFieldsAreRefused() {
        XCTAssertNil(PFActivityEditRules.seconds("1:2:3:4"))
    }

    func testMoreThanTwoDaysIsRefused() {
        XCTAssertNil(PFActivityEditRules.seconds("200000"))
    }

    // MARK: The form

    func testRelabelingToTheSameSportIsNothingChanged() {
        XCTAssertEqual(draft { $0.typeKey = "running" }.problem, "Nothing has changed.")
    }

    func testRelabelingToWalkingHasNoProblem() {
        XCTAssertNil(draft { $0.typeKey = "walking" }.problem)
    }

    func testRelabelSendsOnlyWhatChanged() {
        assertSame(draft { $0.typeKey = "running"; $0.name = "Dog walk" }.inputs, ["op": "relabel", "activity_id": 12345, "name": "Dog walk"])
    }

    func testTrimNeedsABound() {
        XCTAssertEqual(draft { $0.op = .trim }.problem, "Give a start, an end or both.")
    }

    func testTrimBeyondTheEndOfTheRecordingSaysSo() {
        XCTAssertEqual(draft { $0.op = .trim; $0.endText = "60:00" }.problem, "That is outside the recording, which is 50:00 long.")
    }

    func testTrimThatKeepsTheWholeRecordingSaysSo() {
        XCTAssertEqual(draft { $0.op = .trim; $0.startText = "0:00"; $0.endText = "50:00" }.problem, "That keeps the whole recording.")
    }

    func testTrimLeavingUnderTenSecondsIsRefused() {
        XCTAssertEqual(draft { $0.op = .trim; $0.startText = "10:00"; $0.endText = "10:05" }.problem, "Keep at least 10 seconds.")
    }

    func testTrimSendsTheTypedBoundsInSeconds() {
        assertSame(draft { $0.op = .trim; $0.startText = "2:30"; $0.endText = "38:00" }.inputs,
                   ["op": "trim", "activity_id": 12345, "start_s": 150.0, "end_s": 2280.0])
    }

    func testSplitTooCloseToTheEndIsRefused() {
        XCTAssertNotNil(draft { $0.op = .split; $0.splitText = "49:55" }.problem)
    }

    func testSplitSendsThePointInSeconds() {
        assertSame(draft { $0.op = .split; $0.splitText = "20:00" }.inputs, ["op": "split", "activity_id": 12345, "at_s": 1200.0])
    }

    func testGroupNeedsAnotherRecording() {
        XCTAssertEqual(draft { $0.op = .group }.problem, "Pick at least one more recording.")
    }

    func testGroupSendsThisRecordingFirstThenTheOthers() {
        assertSame(draft { $0.op = .group; $0.groupWith = ["12347", "12346"] }.inputs, ["op": "group", "activity_ids": [12345, 12346, 12347]])
    }

    func testAFormWithAProblemSendsNothing() {
        XCTAssertNil(draft { $0.op = .trim }.inputs)
    }

    func testAFailedSendLeavesTheFormWhole() {
        let typed = draft { $0.op = .trim; $0.startText = "2:30" }
        XCTAssertEqual(PFDraftKeeping.afterSend(typed, tookIt: false), typed)
    }

    // MARK: The document

    private func documentJSON() -> Data {
        let text = """
        {"edits":[
         {"id":"\(idA)","seq":1,"ts":"2030-03-12T09:00:00+00:00","author":"athlete","source":"app","op":"relabel","activity_id":12345,"activity_type":"walking"},
         {"id":"\(idB)","seq":2,"ts":"2030-03-12T09:05:00+00:00","author":"athlete","source":"app","op":"undo","target":"\(idA)"},
         {"id":"\(idC)","seq":3,"ts":"2030-03-12T09:10:00+00:00","author":"coach","source":"app","op":"trim","activity_id":12345,"start_s":150}
        ],
        "proposals":[{"id":"\(idD)","state":"pending","created_at":"2030-03-12T10:00:00+00:00","author":"coach","source":"coach","rationale":"Looks like a walk",
         "edit":{"op":"relabel","activity_id":12345,"activity_type":"walking"},"basis_seq":3,
         "preview":{"before":[{"activity_id":12345,"name":"Morning Run","activity_type":"running","duration_seconds":3000,"distance_meters":5000,"avg_hr":150}],
                    "after":[{"activity_id":12345,"name":"Morning Run","activity_type":"walking","duration_seconds":3000,"distance_meters":5000,"avg_hr":null,
                              "basis":{"unknown":["avg_hr"]}}],
                    "totals":{"before":{"count":1,"duration_seconds":3000,"distance_meters":5000},"after":{"count":1,"duration_seconds":3000,"distance_meters":5000}}}}],
        "edited":[{"id":12345,"kind":"trim","source_ids":[12345],"edit_ids":["\(idC)"]},{"id":99999,"kind":"group","source_ids":[99999,100000],"edit_ids":[]}],
        "skipped":[]}
        """
        return Data(text.utf8)
    }

    func testTheHistoryOfARecordingIsOldestFirst() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).history(for: "12345").map { $0.id }, [idA, idB, idC])
    }

    func testAnUnrelatedRecordingHasNoHistory() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).history(for: "777").count, 0)
    }

    func testAnUndoneEditIsNotInForce() {
        let doc = PFActivityEdits.parse(documentJSON())
        XCTAssertFalse(doc.isActive(doc.edits[0]))
    }

    func testTheUndoRecordItselfIsNotInForce() {
        let doc = PFActivityEdits.parse(documentJSON())
        XCTAssertFalse(doc.isActive(doc.edits[1]))
    }

    func testALaterEditIsInForce() {
        let doc = PFActivityEdits.parse(documentJSON())
        XCTAssertTrue(doc.isActive(doc.edits[2]))
    }

    func testThePendingProposalIsFirstForTheRecording() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).proposals(for: "12345").first?.id, idD)
    }

    func testAProposalFromTheCoachSaysSo() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).proposals.first?.isFromCoach, true)
    }

    func testAProposalHoldsItsReason() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).proposals.first?.rationale, "Looks like a walk")
    }

    func testThePreviewRowShowsTheBeforeFigures() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).proposals.first?.preview.before.first?.line,
                       "Run \u{00B7} 50:00 \u{00B7} 5.0 km \u{00B7} avg 150 bpm")
    }

    func testAFigureTheServerCouldNotWorkOutReadsAsUnknown() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).proposals.first?.preview.after.first?.line,
                       "Walk \u{00B7} 50:00 \u{00B7} 5.0 km \u{00B7} average heart rate unknown")
    }

    func testThePreviewTotalsRead() {
        XCTAssertEqual(PFActivityEdits.parse(documentJSON()).proposals.first?.preview.afterTotals?.line, "1 recording, 50:00, 5.0 km")
    }

    func testARecordingThatIsAGroupCanBeUngrouped() {
        XCTAssertTrue(PFActivityEdits.parse(documentJSON()).isGroup("99999"))
    }

    func testATrimmedRecordingIsNotAGroup() {
        XCTAssertFalse(PFActivityEdits.parse(documentJSON()).isGroup("12345"))
    }

    func testTheEditsReadInWords() {
        let specs = PFActivityEdits.parse(documentJSON()).edits.map { $0.spec.summary }
        XCTAssertEqual(specs, ["Labelled as walk", "Undid an earlier edit", "Trimmed to start at 2:30"])
    }

    func testAGroupAndASplitReadInWords() {
        let group = PFEditSpec(op: "group", activityID: nil, activityIDs: ["1", "2", "3"], startS: nil, endS: nil, atS: nil, activityType: nil, name: nil, target: nil)
        let split = PFEditSpec(op: "split", activityID: "1", activityIDs: [], startS: nil, endS: nil, atS: 1200, activityType: nil, name: nil, target: nil)
        XCTAssertEqual([group.summary, split.summary], ["Grouped 3 recordings", "Split at 20:00"])
    }

    func testAnUnreadableDocumentIsEmpty() {
        XCTAssertEqual(PFActivityEdits.parse(Data("not json".utf8)), PFEditsDoc())
    }
}
