import XCTest

/// The build-530 journal's decisions (PFJournalLogic530) and its document (PFJournalDoc530): the day an answer is saved on, which questions
/// a window asks, "Same as yesterday", the writes that turn what is saved into what is staged, the device answers with their corrections,
/// and how the flat insights are grouped. All synthetic questions, days and numbers.
final class PFJournalLogic530Tests: XCTestCase {
    typealias Logic = PFJournalLogic530
    typealias Question = PFJournalDoc530.Question
    typealias Answer = Logic.Answer

    private func question(_ key: String, window: String? = "morning", about: String? = "yesterday", kind: String? = "yes_no",
                          state: String? = nil) -> Question {
        Question(key: key, label: key, prompt: "\(key)?", hint: nil, kind: kind, window: window, about: about, yes: "Yes", no: "No",
                 state: state, stateSource: nil, nYes: nil, nNo: nil)
    }

    // MARK: Days

    func testAMorningAnswerIsSavedOnYesterday() {
        XCTAssertEqual(Logic.behaviourDay(about: "yesterday", window: "morning", today: "2030-03-13"), "2030-03-12")
    }

    func testAnEveningAnswerIsSavedOnToday() {
        XCTAssertEqual(Logic.behaviourDay(about: "today", window: "evening", today: "2030-03-13"), "2030-03-13")
    }

    func testAWindowWithNoWordForItsDayUsesItsUsual() {
        XCTAssertEqual(Logic.behaviourDay(about: nil, window: "morning", today: "2030-03-01"), "2030-02-28")
    }

    func testYesterdayCrossesAYearEnd() {
        XCTAssertEqual(Logic.addDays("2031-01-01", -1), "2030-12-31")
    }

    func testAWindowTakesItsDayFromItsFirstQuestion() {
        XCTAssertEqual(Logic.day(window: "evening", questions: [question("A", window: "evening", about: "yesterday")], today: "2030-03-13"), "2030-03-12")
    }

    func testADayNameIsWeekdayDayAndMonth() {
        XCTAssertEqual(Logic.dayName("2030-03-13"), "Wednesday 13 Mar")
    }

    // MARK: Questions of a window

    func testAWindowAsksOnlyItsOwnQuestionsInOrder() {
        let list = [question("A"), question("B", window: "evening"), question("C"), question("D", window: "afternoon")]
        XCTAssertEqual(Logic.questions(in: list, window: "morning").compactMap(\.key), ["A", "C"])
    }

    func testAQuestionWithoutAKeyIsLeftOut() {
        let list = [question("A"), Question(key: nil, label: "x", prompt: "x", hint: nil, kind: nil, window: "morning", about: nil, yes: nil,
                                           no: nil, state: nil, stateSource: nil, nYes: nil, nNo: nil)]
        XCTAssertEqual(Logic.questions(in: list, window: "morning").count, 1)
    }

    func testAQuestionHiddenInTheJournalEditorIsLeftOutWhateverItsCaseAndSpacing() {
        let list = [question("Did you  read?"), question("B")]
        XCTAssertEqual(Logic.questions(in: list, window: "morning", hidden: ["did you read?"]).compactMap(\.key), ["B"])
    }

    func testAQuestionAddedOnThePhoneFollowsTheListInItsOwnWindow() {
        let custom = Logic.Custom(key: "A late call?", kind: "yes_no", window: "evening")
        XCTAssertEqual(Logic.questions(in: [question("A", window: "evening")], window: "evening", extra: [custom.question]).compactMap(\.key),
                       ["A", "A late call?"])
    }

    func testTheListHoldsTenQuestions() {
        let list = (1...12).map { question("Q\($0)") }
        XCTAssertEqual(Logic.questions(in: list, window: "morning").count, 10)
    }

    func testAQuestionWithNoWindowIsAskedInTheEvening() {
        XCTAssertEqual(Logic.questions(in: [question("A", window: nil)], window: "evening").count, 1)
    }

    func testAnUnknownKindIsYesOrNo() {
        XCTAssertEqual(Logic.kind(question("A", kind: "slider")), "yes_no")
    }

    // MARK: Same as yesterday

    func testSameAsYesterdayFillsAQuestionWithNoAnswerYet() {
        let staged = Logic.staged(saved: [:], previous: ["A": Answer(yes: true)], usePrevious: true, keys: ["A", "B"], edits: [:])
        XCTAssertEqual(staged, ["A": Answer(yes: true)])
    }

    func testSameAsYesterdayNeverReplacesASavedAnswer() {
        let staged = Logic.staged(saved: ["A": Answer(yes: false)], previous: ["A": Answer(yes: true)], usePrevious: true, keys: ["A"], edits: [:])
        XCTAssertEqual(staged["A"], Answer(yes: false))
    }

    func testSameAsYesterdayOffFillsNothing() {
        XCTAssertEqual(Logic.staged(saved: [:], previous: ["A": Answer(yes: true)], usePrevious: false, keys: ["A"], edits: [:]), [:])
    }

    func testSameAsYesterdayCarriesTheNumberButNotTheNote() {
        let previous = ["A": Answer(yes: true, number: 2, note: "last 21:30")]
        XCTAssertEqual(Logic.staged(saved: [:], previous: previous, usePrevious: true, keys: ["A"], edits: [:])["A"], Answer(yes: true, number: 2))
    }

    func testAnEditWinsOverTheFill() {
        let staged = Logic.staged(saved: [:], previous: ["A": Answer(yes: true)], usePrevious: true, keys: ["A"], edits: ["A": .set(Answer(yes: false))])
        XCTAssertEqual(staged["A"], Answer(yes: false))
    }

    func testTakingAnAnswerAwayWinsOverTheFill() {
        XCTAssertEqual(Logic.staged(saved: [:], previous: ["A": Answer(yes: true)], usePrevious: true, keys: ["A"], edits: ["A": .cleared]), [:])
    }

    func testAFillOfAQuestionNotInTheWindowIsIgnored() {
        XCTAssertEqual(Logic.staged(saved: [:], previous: ["Z": Answer(yes: true)], usePrevious: true, keys: ["A"], edits: [:]), [:])
    }

    // MARK: Choosing an answer

    func testTheChosenChipTappedAgainTakesTheAnswerAway() {
        XCTAssertEqual(Logic.choose(kind: "yes_no", yes: true, current: Answer(yes: true), defaultTime: 600), .cleared)
    }

    func testTheOtherChipChoosesIt() {
        XCTAssertEqual(Logic.choose(kind: "yes_no", yes: false, current: Answer(yes: true), defaultTime: 600), .set(Answer(yes: false)))
    }

    func testAYesToACountStartsAtOne() {
        XCTAssertEqual(Logic.choose(kind: "count", yes: true, current: nil, defaultTime: 600), .set(Answer(yes: true, number: 1)))
    }

    func testAYesToATimeStartsAtTheGivenTime() {
        XCTAssertEqual(Logic.choose(kind: "time", yes: true, current: nil, defaultTime: 600), .set(Answer(yes: true, number: 600)))
    }

    func testANoCarriesNoNumber() {
        XCTAssertEqual(Logic.withNumber(Answer(yes: false), 3), Answer(yes: false))
    }

    func testANumberKeepsTheNote() {
        XCTAssertEqual(Logic.withNumber(Answer(yes: true, number: 1, note: "last 20:00"), 2), Answer(yes: true, number: 2, note: "last 20:00"))
    }

    func testAnEmptyNoteIsNoNote() {
        XCTAssertEqual(Logic.withNote(Answer(yes: true, number: 1, note: "last 20:00"), ""), Answer(yes: true, number: 1))
    }

    // MARK: Writes

    func testNothingStagedBeyondWhatIsSavedWritesNothing() {
        XCTAssertEqual(Logic.writes(saved: ["A": Answer(yes: true)], staged: ["A": Answer(yes: true)], keys: ["A"]), [])
    }

    func testANewAnswerIsSaved() {
        XCTAssertEqual(Logic.writes(saved: [:], staged: ["A": Answer(yes: true)], keys: ["A"]), [.save(question: "A", answer: Answer(yes: true))])
    }

    func testAChangedNumberIsSavedWithTheAnswer() {
        let writes = Logic.writes(saved: ["A": Answer(yes: true, number: 1)], staged: ["A": Answer(yes: true, number: 3)], keys: ["A"])
        XCTAssertEqual(writes, [.save(question: "A", answer: Answer(yes: true, number: 3))])
    }

    func testAYesChangedToANoIsSavedAsANoNotCleared() {
        let writes = Logic.writes(saved: ["A": Answer(yes: true, number: 2)], staged: ["A": Answer(yes: false)], keys: ["A"])
        XCTAssertEqual(writes, [.save(question: "A", answer: Answer(yes: false))])
    }

    func testAnAnswerTakenAwayIsCleared() {
        XCTAssertEqual(Logic.writes(saved: ["A": Answer(yes: true)], staged: [:], keys: ["A"]), [.clear(question: "A")])
    }

    func testOnlyTheWindowsOwnKeysAreWritten() {
        XCTAssertEqual(Logic.writes(saved: [:], staged: ["Z": Answer(yes: true)], keys: ["A"]), [])
    }

    func testWritesComeInKeyOrder() {
        let writes = Logic.writes(saved: [:], staged: ["B": Answer(yes: true), "A": Answer(yes: false)], keys: ["B", "A"])
        XCTAssertEqual(writes.first, Logic.Write.save(question: "A", answer: Answer(yes: false)))
    }

    func testTheAnsweredCountCountsSavedAnswersOfTheWindowsKeys() {
        XCTAssertEqual(Logic.answeredCount(keys: ["A", "B", "C"], saved: ["A": Answer(yes: true), "C": Answer(yes: false), "Z": Answer(yes: true)]), 2)
    }

    // MARK: Time of the last one

    func testALastNoteReadsBackAsTheSameMinutes() {
        XCTAssertEqual(Logic.minutes(ofNote: Logic.note(lastAt: 1290)), 1290)
    }

    func testAMinuteOutsideTheDayHasNoNote() {
        XCTAssertNil(Logic.note(lastAt: 1500))
    }

    func testAnotherNoteIsNotATime() {
        XCTAssertNil(Logic.minutes(ofNote: "felt rough"))
    }

    // MARK: Answered by the devices

    private func document() -> PFJournalDoc530 {
        PFJournalDoc530(auto: [
            PFJournalDoc530.AutoDay(date: "2030-03-12", answers: [
                PFJournalDoc530.AutoAnswer(id: "hard_day", label: "A hard day", answer: true, evidence: "Race, 66 min · Garmin"),
                PFJournalDoc530.AutoAnswer(id: "long_run", label: "A long run", answer: false, evidence: "No run of 90 min · Garmin"),
            ]),
        ])
    }

    func testTheDevicesAnswersOfTheDayAreRows() {
        XCTAssertEqual(Logic.autoRows(document(), date: "2030-03-12", corrections: [:]).map(\.id), ["hard_day", "long_run"])
    }

    func testADayWithNoDeviceAnswersHasNoRows() {
        XCTAssertEqual(Logic.autoRows(document(), date: "2030-03-11", corrections: [:]), [])
    }

    func testACorrectionReplacesTheDevicesAnswer() {
        let row = Logic.autoRows(document(), date: "2030-03-12", corrections: ["long_run": true]).last
        XCTAssertEqual(row?.yes == true && row?.isCorrected == true, true)
    }

    func testTappingADeviceAnswerSavesTheOppositeUnderItsId() {
        let row = Logic.autoRows(document(), date: "2030-03-12", corrections: [:])[0]
        XCTAssertEqual(Logic.correction(for: row), .save(question: "hard_day", answer: Answer(yes: false)))
    }

    func testTappingACorrectedAnswerTakesTheCorrectionAway() {
        let row = Logic.autoRows(document(), date: "2030-03-12", corrections: ["hard_day": false])[0]
        XCTAssertEqual(Logic.correction(for: row), .clear(question: "hard_day"))
    }

    // MARK: The afternoon notification

    func testTheAfternoonQuestionIsTheOneTheDocumentNames() {
        let doc = PFJournalDoc530(list: [question("A"), question("Caffeine?", window: "afternoon", about: "today")])
        XCTAssertEqual(Logic.afternoonKey(doc), "Caffeine?")
    }

    func testWithoutADocumentTheAfternoonQuestionIsTheStarterOne() {
        XCTAssertEqual(Logic.afternoonKey(nil), "Did you have caffeine late in the day?")
    }

    func testAJournalItemIdNamesItsDayAndWindow() {
        XCTAssertEqual(Logic.journalItem("journal:2030-03-13:afternoon")?.date, "2030-03-13")
    }

    func testAnotherItemIdIsNotAJournalItem() {
        XCTAssertNil(Logic.journalItem("report:week:2030-W11"))
    }

    // MARK: Insights

    private func insight(_ behaviour: String, outcome: String = "recovery", device: String = "WHOOP", measure: String = "Charge", unit: String = "%",
                         lag: Int = 1, mean: (Double, Double), diff: Double, clear: Bool) -> PFJournalDoc530.Insight {
        PFJournalDoc530.Insight(behaviour: behaviour, label: behaviour, outcome: outcome, device: device, measure: measure, unit: unit, lag: lag,
                                nWith: 10, nWithout: 20, meanWith: mean.0, meanWithout: mean.1, diff: diff, clear: clear, note: nil, byAmount: nil)
    }

    func testAnOutcomeHasOneSeriesPerDeviceAndMeasure() {
        let insights = [insight("a", mean: (1, 2), diff: -1, clear: false), insight("b", device: "Garmin", measure: "Readiness", mean: (1, 2), diff: -1, clear: false),
                        insight("c", mean: (1, 2), diff: -1, clear: false)]
        XCTAssertEqual(Logic.series(insights, outcome: "recovery").map(\.title), ["Charge (WHOOP)", "Readiness (Garmin)"])
    }

    func testTheClearOnesComeFirstAndTheStrongestOfThemFirst() {
        let insights = [insight("weak", mean: (50, 55), diff: -5, clear: true), insight("none", mean: (53, 51), diff: 2, clear: false),
                        insight("strong", mean: (26, 61), diff: -35, clear: true)]
        let series = Logic.series(insights, outcome: "recovery")[0]
        XCTAssertEqual(Logic.split(insights, series: series, lag: 1).clear.compactMap(\.behaviour), ["strong", "weak"])
    }

    func testTheOtherLagHasItsOwnValues() {
        let insights = [insight("a", lag: 1, mean: (63, 48), diff: 15, clear: false), insight("a", lag: 2, mean: (58, 55), diff: 3, clear: false)]
        let series = Logic.series(insights, outcome: "recovery")[0]
        XCTAssertEqual(Logic.split(insights, series: series, lag: 2).noEffect.first?.meanWith, 58)
    }

    func testADevicesResultsAreNeverMixedWithAnother() {
        let insights = [insight("a", mean: (63, 48), diff: 15, clear: false), insight("a", device: "Garmin", measure: "Readiness", mean: (40, 41), diff: -1, clear: false)]
        let series = Logic.series(insights, outcome: "recovery")[1]
        XCTAssertEqual(Logic.split(insights, series: series, lag: 1).noEffect.compactMap(\.meanWith), [40])
    }

    func testAnEntryWithoutItsMeansIsLeftOut() {
        var broken = insight("a", mean: (1, 2), diff: -1, clear: false)
        broken.meanWith = nil
        let series = Logic.series([broken], outcome: "recovery")[0]
        XCTAssertEqual(Logic.split([broken], series: series, lag: 1), Logic.Split(clear: [], noEffect: []))
    }

    func testOnlyQuestionsStillCollectingAreListedAsCollecting() {
        let list = [question("A", state: "collecting"), question("B", state: "clear"), question("C", state: "no_effect")]
        XCTAssertEqual(Logic.collecting(list).compactMap(\.key), ["A"])
    }

    func testProgressCountsUpToFiveYesAndFiveNoDays() {
        XCTAssertEqual(Logic.progress(yes: 9, no: 2), 0.7, accuracy: 0.0001)
    }

    func testAPercentBarIsTheMeanOutOfOneHundred() {
        XCTAssertEqual(Logic.barFraction(61, unit: "%"), 0.61, accuracy: 0.0001)
    }

    func testAnEffortBarIsTheMeanOutOfTwentyOne() {
        XCTAssertEqual(Logic.barFraction(10.5, unit: "of 21"), 0.5, accuracy: 0.0001)
    }

    func testValuesCarryTheirUnit() {
        XCTAssertEqual([Logic.valueText(26, unit: "%"), Logic.valueText(6.14, unit: "h"), Logic.valueText(72, unit: "")], ["26 %", "6.1 h", "72"])
    }

    func testALowerMeanWithTheBehaviourHurts() {
        XCTAssertEqual(Logic.verdict(-35), "Hurts")
    }

    // MARK: The list of ten

    func testAQuestionCanBeAddedUntilTheListHoldsTen() {
        XCTAssertEqual([Logic.canAdd(listCount: 9, customCount: 0), Logic.canAdd(listCount: 8, customCount: 2)], [true, false])
    }

    func testANewQuestionIsTrimmedAndAnExistingOneIsRefused() {
        XCTAssertEqual([Logic.newKey("  A late call?  ", existing: []), Logic.newKey("did you  read?", existing: ["Did you read?"])], ["A late call?", nil])
    }

    // MARK: The document

    private func decode(_ json: String) throws -> PFJournalDoc530 {
        try PFPlan529Decoder.make().decode(PFJournalDoc530.self, from: Data(json.utf8))
    }

    func testFlatInsightsAndListCountsDecode() throws {
        let doc = try decode("""
        {"list":[{"key":"Q","state":"collecting","n_yes":1,"n_no":0,"state_source":null}],
         "insights":[{"behaviour":"hard_day","outcome":"recovery","device":"WHOOP","measure":"Charge","unit":"%","lag":2,"n_with":9,"n_without":30,
                      "mean_with":58.5,"mean_without":55,"diff":3.5,"clear":false,"by_amount":[{"amount":"3+","n":5,"mean":41.5}]}]}
        """)
        XCTAssertEqual([doc.list?.first?.nYes, doc.insights?.first?.lag, doc.insights?.first?.nWithout, doc.insights?.first?.byAmount?.first?.n], [1, 2, 30, 5])
    }

    func testOneMalformedEntryCostsThatEntryNotTheDocument() throws {
        let doc = try decode("""
        {"list":[{"key":"A"},{"key":7},{"key":"C"}],"insights":"not a list","week":[{"date":"2030-03-11","logged":true}]}
        """)
        XCTAssertEqual([doc.list?.compactMap(\.key).joined(), doc.insights == nil ? "none" : "some", doc.week?.first?.date], ["AC", "none", "2030-03-11"])
    }

    func testTheOlderNestedInsightsShapeIsReadAsEntriesWithNoOutcome() throws {
        let doc = try decode("""
        {"insights":[{"behaviour":"x","label":"X","outcomes":[{"outcome":"recovery","lags":[]}]}]}
        """)
        XCTAssertEqual(Logic.series(doc.insights, outcome: "recovery"), [])
    }
}
