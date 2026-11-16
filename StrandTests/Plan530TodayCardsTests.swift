import XCTest

/// Build 530, APP-2: which Today overview card shows (a pure function of the document and the clock), that a bad block never costs the
/// others, and the My Journal card's row and lines. The documents here are invented.
final class Plan530TodayCardsTests: XCTestCase {
    private func cards(_ json: String) throws -> PFTodayCards530 {
        try PFPlan529Decoder.make().decode(PFTodayCards530.self, from: Data(json.utf8))
    }

    private let morning = #""morning": {"verdict": "Go.", "rows": [{"title": "Today", "text": "Run."}]}"#
    private let evening = #""evening": {"date": "2030-03-12", "tonight": "In bed by 22:07."}"#

    private func minutes(_ clock: String) -> Int { PFTodayCards530.minutes(ofClock: clock) ?? -1 }

    // MARK: Which card

    func testMorningCardBeforeTheEveningStarts() throws {
        let doc = try cards(#"{"evening_from": "21:15", "morning_ready": true, \#(morning), \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("20:59")), .morning)
    }

    func testEveningCardFromTheEveningTimeOn() throws {
        let doc = try cards(#"{"evening_from": "21:15", "morning_ready": true, \#(morning), \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("21:15")), .evening)
    }

    func testEveningCardWhenThereIsNoMorningCardYetEvenBeforeTheEveningTime() throws {
        let doc = try cards(#"{"evening_from": "21:15", "morning_ready": false, "morning": null, \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("00:40")), .evening)
    }

    func testMorningCardAfterMidnightOnceTheNightIsProcessed() throws {
        let doc = try cards(#"{"evening_from": "21:15", "morning_ready": true, \#(morning), \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("07:30")), .morning)
    }

    func testPhaseDecidesWhenTheEveningTimeIsMissing() throws {
        let doc = try cards(#"{"phase": "evening", \#(morning), \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("08:00")), .evening)
    }

    func testMorningPhaseWithoutTheEveningTimeKeepsTheMorningCardAtNight() throws {
        let doc = try cards(#"{"phase": "morning", \#(morning), \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("23:00")), .morning)
    }

    func testMorningCardWhenTheEveningIsDueButThereIsNoEveningCard() throws {
        let doc = try cards(#"{"evening_from": "21:15", \#(morning), "evening": null}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("22:00")), .morning)
    }

    func testNothingWhenBothCardsAreMissing() throws {
        let doc = try cards(#"{"evening_from": "21:15", "morning": null, "evening": null}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("22:00")), .nothing)
    }

    func testNothingWhenBothCardsAreEmptyObjects() throws {
        let doc = try cards(#"{"morning": {}, "evening": {"found": []}}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("08:00")), .nothing)
    }

    func testAForcedEveningReplacesTheClock() throws {
        let doc = try cards(#"{"evening_from": "21:15", \#(morning), \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("08:00"), forcedEvening: true), .evening)
    }

    func testAMalformedEveningTimeFallsBackToThePhase() throws {
        let doc = try cards(#"{"evening_from": "late", "phase": "evening", \#(morning), \#(evening)}"#)
        XCTAssertEqual(doc.choice(minutesOfDay: minutes("08:00")), .evening)
    }

    // MARK: Decoding

    func testEveningCardWithNullVerdictAndMovedStillDecodes() throws {
        let doc = try cards(#"{"evening": {"date": "2030-03-12", "verdict": null, "moved": null, "found": ["Bed at 23:57"], "tonight": "In bed by 22:07."}}"#)
        XCTAssertEqual(doc.evening?.found, ["Bed at 23:57"])
    }

    func testAMalformedTrendDoesNotCostTheMorningVerdict() throws {
        let doc = try cards(#"{"morning": {"verdict": "Go.", "trend": "oops", "rows": []}}"#)
        XCTAssertEqual(doc.morning?.verdict, "Go.")
    }

    func testAMalformedMorningCardDoesNotCostTheEveningCard() throws {
        let doc = try cards(#"{"morning": [1, 2], "evening": {"tonight": "In bed by 22:07."}}"#)
        XCTAssertEqual(doc.evening?.tonight, "In bed by 22:07.")
    }

    func testTrendKeepsItsGapsAndColours() throws {
        let doc = try cards(#"{"morning": {"trend": [{"source": "WHOOP", "label": "recovery", "values": [58, null, 71], "bands": ["amber", null, "green"]}]}}"#)
        XCTAssertEqual(doc.morning?.trend?.first?.values?.count, 3)
    }

    func testTheEveningTimeAndReadyFlagDecode() throws {
        let doc = try cards(#"{"date": "2030-03-13", "evening_from": "21:15", "morning_ready": false}"#)
        XCTAssertEqual(doc.morningReady, false)
    }

    // MARK: My Journal

    private func journal(_ json: String) throws -> PFTodayJournal530 {
        try PFPlan529Decoder.make().decode(PFTodayJournal530.self, from: Data(json.utf8))
    }

    private let journalJSON = """
    {"week": [{"date": "2030-03-11", "logged": true}, {"date": "bad", "logged": "x"}],
     "prompts": [{"window": "morning", "open": 5}, {"window": "evening", "open": 4}],
     "auto": [{"date": "2030-03-12", "answers": [{"label": "Hard day", "answer": true}, {"label": "Late session", "answer": false}, {"label": "Unknown", "answer": null}]}],
     "insights": [{"label": "Bedtime after 23:30", "clear": true}, {"label": "Hard day", "clear": false}]}
    """

    func testWeekRowRunsMondayToSundayAroundToday() throws {
        let row = PFTodayJournalLogic530.weekRow(try journal(journalJSON), today: "2030-03-13", ownDays: [])
        XCTAssertEqual(row.map(\.date).first, "2030-03-11")
    }

    func testWeekRowMarksTheServedDayLogged() throws {
        let row = PFTodayJournalLogic530.weekRow(try journal(journalJSON), today: "2030-03-13", ownDays: [])
        XCTAssertEqual(row.first?.logged, true)
    }

    func testWeekRowMarksADayLoggedOnThePhoneBeforeTheServerKnows() throws {
        let row = PFTodayJournalLogic530.weekRow(try journal(journalJSON), today: "2030-03-13", ownDays: ["2030-03-12"])
        XCTAssertEqual(row[1].logged, true)
    }

    func testWeekRowWithoutADocumentStillHasSevenDays() {
        XCTAssertEqual(PFTodayJournalLogic530.weekRow(nil, today: "2030-03-13", ownDays: []).count, 7)
    }

    func testWeekRowMarksFutureDays() throws {
        let row = PFTodayJournalLogic530.weekRow(try journal(journalJSON), today: "2030-03-13", ownDays: [])
        XCTAssertEqual(row.map(\.isFuture), [false, false, false, true, true, true, true])
    }

    func testLineNamesYesterdayTheDevicesAnswersAndTheOpenQuestions() throws {
        XCTAssertEqual(PFTodayJournalLogic530.line(try journal(journalJSON), today: "2030-03-13"),
                       "About Tuesday: 2 answered by your devices, 5 questions for you.")
    }

    func testLineIsAbsentWithoutADocument() {
        XCTAssertNil(PFTodayJournalLogic530.line(nil, today: "2030-03-13"))
    }

    func testFillOutOpensTheMorningSheetWhileMorningQuestionsAreOpen() throws {
        XCTAssertEqual(PFTodayJournalLogic530.target(try journal(journalJSON)), .morning)
    }

    func testFillOutOpensTheEveningReflectionWhenOnlyTheEveningIsOpen() throws {
        let doc = try journal(#"{"prompts": [{"window": "morning", "open": 0}, {"window": "evening", "open": 4}]}"#)
        XCTAssertEqual(PFTodayJournalLogic530.target(doc), .evening)
    }

    func testAllAnsweredWhenNothingIsOpen() throws {
        let doc = try journal(#"{"prompts": [{"window": "morning", "open": 0}]}"#)
        XCTAssertTrue(PFTodayJournalLogic530.isAllAnswered(doc))
    }

    func testInsightsLineCountsTheClearOnes() throws {
        XCTAssertEqual(PFTodayJournalLogic530.insightsLine(try journal(journalJSON)), "1 clear so far: Bedtime after 23:30")
    }

    func testInsightsLineSaysNoClearEffectYet() throws {
        let doc = try journal(#"{"insights": [{"label": "Hard day", "clear": false}]}"#)
        XCTAssertEqual(PFTodayJournalLogic530.insightsLine(doc), "No clear effect yet")
    }
}
