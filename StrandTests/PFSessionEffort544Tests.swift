import XCTest
@testable import Strand

/// The athlete's own effort and minutes on a session (build 544): the week document's new optional fields (and the old document without them),
/// the minutes limits, the `session-effort` inputs for set, change and clear, and the words "Your choice", "Estimated" and "Planned".
/// Every name and number is made up.
final class PFSessionEffort544Tests: XCTestCase {
    // MARK: Helpers

    private func item(_ text: String) throws -> PFPlanWeekDoc.Item {
        try PFPlan529Decoder.make().decode(PFPlanWeekDoc.Item.self, from: Data(text.utf8))
    }

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private func form(_ text: String) throws -> PFSessionEffortForm544 {
        PFSessionEffortForm544(item: try item(text), sessionID: "s-1")
    }

    private let chosen = """
    {"kind": "session", "session_id": "s-1", "title": "Run", "minutes": 45, "effort": "hard", "effort_label": "Hard", "status": "planned",
     "effort_choice": "hard", "minutes_choice": 45, "effort_estimated": false, "minutes_estimated": false}
    """

    private let estimated = """
    {"kind": "session", "session_id": "s-1", "title": "Run", "minutes": 54, "effort": "easy", "effort_label": "Easy", "status": "planned",
     "effort_choice": null, "minutes_choice": null, "effort_estimated": true, "minutes_estimated": true}
    """

    private let older = """
    {"kind": "session", "session_id": "s-1", "title": "Run", "minutes": 54, "effort": "easy", "effort_label": "Easy", "status": "planned"}
    """

    private let onlyMinutesChosen = """
    {"kind": "session", "session_id": "s-1", "title": "Run", "minutes": 40, "effort": "easy", "effort_label": "Easy", "status": "planned",
     "effort_choice": null, "minutes_choice": 40, "effort_estimated": true, "minutes_estimated": false}
    """

    // MARK: Decoding

    func testItemDecodesEffortChoice() throws {
        XCTAssertEqual(try item(chosen).effortChoice, "hard")
    }

    func testItemDecodesMinutesChoice() throws {
        XCTAssertEqual(try item(chosen).minutesChoice, 45)
    }

    func testItemDecodesEffortEstimatedFlag() throws {
        XCTAssertEqual(try item(estimated).effortEstimated, true)
    }

    func testItemDecodesMinutesEstimatedFlag() throws {
        XCTAssertEqual(try item(estimated).minutesEstimated, true)
    }

    func testNullChoicesDecodeAsNil() throws {
        XCTAssertNil(try item(estimated).effortChoice)
    }

    func testOlderItemWithoutTheFieldsHasNoEffortChoice() throws {
        XCTAssertNil(try item(older).effortChoice)
    }

    func testOlderItemWithoutTheFieldsHasNoMinutesChoice() throws {
        XCTAssertNil(try item(older).minutesChoice)
    }

    func testOlderItemWithoutTheFieldsKeepsItsMinutes() throws {
        XCTAssertEqual(try item(older).minutes, 54)
    }

    // MARK: Server words

    func testServerWordAllOutIsAChoice() {
        XCTAssertEqual(PFEffortChoice544(server: "all_out"), .allOut)
    }

    func testServerWordWithSpacesAndCapitalsIsAChoice() {
        XCTAssertEqual(PFEffortChoice544(server: "All out"), .allOut)
    }

    func testRaceIsNotAChoice() {
        XCTAssertNil(PFEffortChoice544(server: "race"))
    }

    func testNilWordIsNotAChoice() {
        XCTAssertNil(PFEffortChoice544(server: nil))
    }

    func testTheFourChoicesAreInOrder() {
        XCTAssertEqual(PFEffortChoice544.allCases.map(\.title), ["Easy", "Moderate", "Hard", "All out"])
    }

    // MARK: Minutes limits

    func testOneMinuteIsAccepted() {
        XCTAssertNil(PFSessionEffort544.minutesProblem(1))
    }

    func testThreeHundredSixtyMinutesIsAccepted() {
        XCTAssertNil(PFSessionEffort544.minutesProblem(360))
    }

    func testZeroMinutesIsRefused() {
        XCTAssertNotNil(PFSessionEffort544.minutesProblem(0))
    }

    func testThreeHundredSixtyOneMinutesIsRefused() {
        XCTAssertNotNil(PFSessionEffort544.minutesProblem(361))
    }

    func testNegativeMinutesIsRefused() {
        XCTAssertNotNil(PFSessionEffort544.minutesProblem(-5))
    }

    func testNoMinutesIsNotAProblem() {
        XCTAssertNil(PFSessionEffort544.minutesProblem(nil))
    }

    // MARK: The job payload

    func testSetSendsEffortAndMinutes() {
        assertSame(PFJobInputs.sessionEffort(sessionID: "s-1", effort: .hard, minutes: 45),
                   ["session_id": "s-1", "effort": "hard", "minutes": 45])
    }

    func testAllOutIsSentWithTheServersWord() {
        assertSame(PFJobInputs.sessionEffort(sessionID: "s-1", effort: .allOut, minutes: 30),
                   ["session_id": "s-1", "effort": "all_out", "minutes": 30])
    }

    func testEffortOnlySendsMinutesAsNull() {
        assertSame(PFJobInputs.sessionEffort(sessionID: "s-1", effort: .moderate, minutes: nil),
                   ["session_id": "s-1", "effort": "moderate", "minutes": NSNull()])
    }

    func testClearSendsBothAsNull() {
        assertSame(PFJobInputs.sessionEffort(sessionID: "s-1", effort: nil, minutes: nil),
                   ["session_id": "s-1", "effort": NSNull(), "minutes": NSNull()])
    }

    func testMinutesOutsideTheLimitsAreNotSent() {
        XCTAssertNil(PFJobInputs.sessionEffort(sessionID: "s-1", effort: .easy, minutes: 400))
    }

    func testASessionIdWithASpaceIsNotSent() {
        XCTAssertNil(PFJobInputs.sessionEffort(sessionID: "s 1", effort: .easy, minutes: 30))
    }

    func testNoSessionIdIsNotSent() {
        XCTAssertNil(PFJobInputs.sessionEffort(sessionID: nil, effort: .easy, minutes: 30))
    }

    func testThePayloadIsValidJSON() throws {
        let inputs = try XCTUnwrap(PFJobInputs.sessionEffort(sessionID: "s-1", effort: nil, minutes: nil))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(inputs))
    }

    func testTheClearPayloadReadsBackWithNulls() throws {
        let inputs = try XCTUnwrap(PFJobInputs.sessionEffort(sessionID: "s-1", effort: nil, minutes: nil))
        let text = try XCTUnwrap(PFJobRetryList.encodeInputs(inputs))
        XCTAssertEqual(text, #"{"effort":null,"minutes":null,"session_id":"s-1"}"#)
    }

    // MARK: The form

    func testFormWithoutChangesSendsNothing() throws {
        XCTAssertNil(try form(estimated).inputs())
    }

    func testFormSetsEffortAndKeepsNoMinutes() throws {
        var f = try form(estimated)
        f.effort = .hard
        assertSame(f.inputs(), ["session_id": "s-1", "effort": "hard", "minutes": NSNull()])
    }

    func testFormChangesEffortAndKeepsTheMinutesChoice() throws {
        var f = try form(chosen)
        f.effort = .moderate
        assertSame(f.inputs(), ["session_id": "s-1", "effort": "moderate", "minutes": 45])
    }

    func testFormChangesMinutesAndKeepsTheEffortChoice() throws {
        var f = try form(chosen)
        f.minutes = 60
        assertSame(f.inputs(), ["session_id": "s-1", "effort": "hard", "minutes": 60])
    }

    func testFormWithMinutesOutOfRangeSendsNothing() throws {
        var f = try form(estimated)
        f.minutes = 0
        XCTAssertNil(f.inputs())
    }

    func testFormWithMinutesOutOfRangeSaysWhy() throws {
        var f = try form(estimated)
        f.minutes = 361
        XCTAssertEqual(f.problem, PFSessionEffort544.minutesOutOfRange)
    }

    func testResetInputsClearBoth() throws {
        assertSame(try form(chosen).resetInputs(), ["session_id": "s-1", "effort": NSNull(), "minutes": NSNull()])
    }

    func testResetIsOfferedWhenAChoiceExists() throws {
        XCTAssertTrue(try form(chosen).hasChoice)
    }

    func testResetIsOfferedWhenOnlyMinutesAreChosen() throws {
        XCTAssertTrue(try form(onlyMinutesChosen).hasChoice)
    }

    func testResetIsNotOfferedWithoutAChoice() throws {
        XCTAssertFalse(try form(estimated).hasChoice)
    }

    func testResetIsNotOfferedOnAnOlderServer() throws {
        XCTAssertFalse(try form(older).hasChoice)
    }

    func testFormStartsWithTheServersChoice() throws {
        XCTAssertEqual(try form(chosen).effort, .hard)
    }

    func testFormAfterResetHasNoChoice() throws {
        XCTAssertFalse(try form(chosen).afterReset().hasChoice)
    }

    func testFormAfterResetHasNothingLeftToSave() throws {
        XCTAssertFalse(try form(chosen).afterReset().hasChanges)
    }

    func testFormAfterSavingOffersReset() throws {
        var f = try form(estimated)
        f.effort = .hard
        XCTAssertTrue(f.afterSaving().hasChoice)
    }

    func testFormAfterSavingHasNothingLeftToSave() throws {
        var f = try form(estimated)
        f.effort = .hard
        XCTAssertFalse(f.afterSaving().hasChanges)
    }

    // MARK: Your choice or Estimated

    func testAChoiceReadsYourChoice() {
        XCTAssertEqual(PFSessionEffort544.label(PFSessionEffort544.source(hasChoice: true, isEstimated: false)), "Your choice")
    }

    func testAChoiceReadsYourChoiceEvenWhenTheServerFlagsEstimated() {
        XCTAssertEqual(PFSessionEffort544.source(hasChoice: true, isEstimated: true), .yours)
    }

    func testAnEstimateReadsEstimated() {
        XCTAssertEqual(PFSessionEffort544.label(PFSessionEffort544.source(hasChoice: false, isEstimated: true)), "Estimated")
    }

    func testAValueThatIsNotAnEstimateReadsPlanned() {
        XCTAssertEqual(PFSessionEffort544.label(PFSessionEffort544.source(hasChoice: false, isEstimated: false)), "Planned")
    }

    func testAnOlderServerWithoutTheFlagReadsPlanned() {
        XCTAssertEqual(PFSessionEffort544.source(hasChoice: false, isEstimated: nil), .planned)
    }

    func testFormShowsYourChoiceForTheEffortYouChose() throws {
        XCTAssertEqual(try form(chosen).effortLabel, "Your choice")
    }

    func testFormShowsEstimatedForTheEffortThatIsAnEstimate() throws {
        XCTAssertEqual(try form(estimated).effortLabel, "Estimated")
    }

    func testFormShowsEstimatedForTheEffortYouDidNotChoose() throws {
        XCTAssertEqual(try form(onlyMinutesChosen).effortLabel, "Estimated")
    }

    func testFormShowsYourChoiceForMinutesYouChose() throws {
        XCTAssertEqual(try form(onlyMinutesChosen).minutesLabel, "Your choice")
    }

    func testFormShowsTheEstimatedMinutesWhileThereIsNoChoice() throws {
        XCTAssertEqual(try form(estimated).minutesShown, 54)
    }

    func testFormShowsTheChosenEffortWord() throws {
        var f = try form(estimated)
        f.effort = .allOut
        XCTAssertEqual(f.effortWord, "All out")
    }

    func testFormShowsTheEstimatedEffortWordWhileThereIsNoChoice() throws {
        XCTAssertEqual(try form(estimated).effortWord, "Easy")
    }

    func testPickingAnEffortFlipsTheLabelToYourChoice() throws {
        var f = try form(estimated)
        f.effort = .moderate
        XCTAssertEqual(f.effortLabel, "Your choice")
    }

    // MARK: The week row

    func testRowSaysSetByYouWhenTheAthleteChose() throws {
        XCTAssertEqual(PFPlanRow543.summary(try item(chosen)), "45 min \u{00B7} Hard \u{00B7} set by you")
    }

    func testRowSaysNothingExtraForAnEstimate() throws {
        XCTAssertEqual(PFPlanRow543.summary(try item(estimated)), "54 min \u{00B7} Easy")
    }

    func testRowOfAnOlderServerIsUnchanged() throws {
        XCTAssertEqual(PFPlanRow543.summary(try item(older)), "54 min \u{00B7} Easy")
    }

    func testSetByYouIsTrueWithOnlyAMinutesChoice() throws {
        XCTAssertTrue(PFSessionEffort544.isSetByYou(try item(onlyMinutesChosen)))
    }
}
