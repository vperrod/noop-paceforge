import XCTest
@testable import Strand

/// PaceForge's wave-2 documents decode leniently: every field is optional, a missing file hides its
/// section, and the neutral wording the screens depend on (the two answers, the trust line) is exact.
/// All values are made up.
final class PaceForgeWave2Tests: XCTestCase {
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    // MARK: Feel

    func testFeelSummaryReadsTodayAndTheStrip() {
        let summary = PFWave2Parse.feelSummary(json("""
        {"date":"2030-03-13","today":{"answered":false,"feel":null},
         "days":[{"date":"2030-03-12","feel":4,"score":80,"band":"green","agreement":"match","gap":0},
                 {"date":"2030-03-13","feel":null,"score":78,"band":"green","agreement":null,"gap":null}],
         "answers":1,"compared":1,"needs":5,"sentence":"One answer so far."}
        """))
        XCTAssertEqual(summary?.days.map(\.agreement), ["match", nil])
    }

    func testFeelSummaryIsAbsentWhenTheServerHasNoTodayBlock() {
        XCTAssertNil(PFWave2Parse.feelSummary(json(#"{"date":"2030-03-13"}"#)))
    }

    func testFeelAnsweringMarksTodayAnsweredAndFillsTheLastDot() {
        var summary = PFFeelSummary(date: "2030-03-13", days: [PFFeelDay(date: "2030-03-13")])
        summary = summary.answering(4)
        XCTAssertEqual(summary.days.last?.feel, 4)
    }

    func testFeelSavedReadsTheServersAnswerBody() {
        let saved = PFWave2Parse.feelSaved(json(#"{"saved":{"date":"2030-03-13","feel":4,"source":"ios"},"summary":{"today":{"answered":true,"feel":4}}}"#))
        XCTAssertEqual(saved?.summary?.feel, 4)
    }

    func testFeelSavedRejectsAnOutOfRangeValue() {
        XCTAssertNil(PFWave2Parse.feelSaved(json(#"{"saved":{"feel":9}}"#)))
    }

    // MARK: Answers

    func testAnswersMapTrueFalseAndCaution() {
        let answers = PFWave2Parse.answers(json(#"{"train":{"ok":true,"reason":"a"},"train_hard":{"ok":"caution","reason":"b"}}"#))
        XCTAssertEqual(answers?.widgetLine, "Train: yes \u{00B7} Hard: careful")
    }

    func testAFalseAnswerReadsAsNotToday() {
        let answers = PFWave2Parse.answers(json(#"{"train":{"ok":false,"reason":"a"},"train_hard":{"ok":false,"reason":"b"}}"#))
        XCTAssertEqual(answers?.widgetLine, "Train: not today \u{00B7} Hard: not today")
    }

    func testAnswersAreAbsentWhenNeitherAnswerIsUsable() {
        XCTAssertNil(PFWave2Parse.answers(json(#"{"train":{"ok":null},"planned_overload":true}"#)))
    }

    // MARK: Trust

    func testLowTrustNamesItsFirstReason() {
        let trust = PFWave2Parse.trust(json(#"{"level":"low","reasons":["the watch recorded only 52% of the night","x"]}"#))
        XCTAssertEqual(trust?.text, "Low confidence: the watch recorded only 52% of the night")
    }

    func testOkTrustHasNoText() {
        XCTAssertNil(PFWave2Parse.trust(json(#"{"level":"ok","reasons":[]}"#))?.text)
    }

    // MARK: What changed

    func testWhatChangedKeepsToneAndCalibration() {
        let changes = PFWave2Parse.whatChanged(json("""
        {"date":"2030-03-13","summary":"Since yesterday: x.","calibrating":[],
         "metrics":[{"id":"hrv_7d","label":"HRV","unit":"ms","value":41.3,"previous":40.1,"delta":1.2,
                     "direction":"up","tone":"better","calibrating":true,
                     "calibration":{"have":12,"need":21,"unit":"nights","ready":false,"line":"Day 12 of 21"}}]}
        """))
        XCTAssertEqual(changes?.metrics.first?.calibration?.line, "Day 12 of 21")
    }

    func testWhatChangedWithNothingInItIsAbsent() {
        XCTAssertNil(PFWave2Parse.whatChanged(json(#"{"date":"2030-03-13","metrics":[]}"#)))
    }

    func testCalibrationFractionIsTheShareDone() {
        let calibration = PFCalibration(have: 12, need: 21, unit: "nights", ready: false, line: "Day 12 of 21")
        XCTAssertEqual(calibration.fraction, 12.0 / 21.0, accuracy: 0.0001)
    }

    func testAReadyCalibrationIsFull() {
        XCTAssertEqual(PFCalibration(have: 30, need: 21, unit: nil, ready: true, line: nil).fraction, 1)
    }

    // MARK: Explainers and behaviour

    func testExplainersKeepTheirCalibration() {
        let list = PFWave2Parse.explainers(json("""
        {"metrics":[{"id":"hrv_status","title":"HRV status","plain":"p","how":"h","usual_range":"u","caveat":"c","unlocks":"x",
                     "calibration":{"have":3,"need":5,"unit":"nights","ready":false,"line":"Day 3 of 5"}}]}
        """))
        XCTAssertEqual(list.first?.calibration?.need, 5)
    }

    func testExplainersCarryTheForYouAndEffectLines() {
        let list = PFWave2Parse.explainers(json("""
        {"metrics":[{"id":"recovery","title":"Recovery","you":"Latest 91%.","effect":"Sets the strain target."}]}
        """))
        XCTAssertEqual([list.first?.forYou, list.first?.effect], ["Latest 91%.", "Sets the strain target."])
    }

    // MARK: Page notes

    private let pageNotesJSON = """
    {"date":"2030-03-13","generated_at":"2030-03-13T18:11:55",
     "pages":{"today":{"tone":"alert","text":"Load ratio is 1.58.","facts":["a","b"]},
              "sleep":{"tone":"ok","text":"   "},
              "body":{"text":"Weight is steady."}}}
    """

    func testPageNoteCarriesToneTextAndFacts() {
        let notes = PFWave2Parse.pageNotes(json(pageNotesJSON))
        XCTAssertEqual(notes?.note("today", today: "2030-03-13"),
                       PFPageNoteItem(tone: "alert", text: "Load ratio is 1.58.", facts: ["a", "b"]))
    }

    func testPageNoteWithoutToneReadsAsOk() {
        XCTAssertEqual(PFWave2Parse.pageNotes(json(pageNotesJSON))?.note("body", today: "2030-03-13")?.tone, "ok")
    }

    func testPageNoteWithEmptyTextIsLeftOut() {
        XCTAssertNil(PFWave2Parse.pageNotes(json(pageNotesJSON))?.note("sleep", today: "2030-03-13"))
    }

    func testPageNoteForAnUnknownPageIsAbsent() {
        XCTAssertNil(PFWave2Parse.pageNotes(json(pageNotesJSON))?.note("vitals", today: "2030-03-13"))
    }

    func testMissingPageNotesFileIsAbsent() {
        XCTAssertNil(PFWave2Parse.pageNotes(PFJ(nil)))
    }

    func testPageNotesWithNoTextAnywhereAreAbsent() {
        XCTAssertNil(PFWave2Parse.pageNotes(json(#"{"date":"2030-03-13","pages":{"today":{"tone":"ok","text":""}}}"#)))
    }

    func testPageNoteStillShowsOnTheSecondDayAfterTheFile() {
        XCTAssertNotNil(PFWave2Parse.pageNotes(json(pageNotesJSON))?.note("today", today: "2030-03-15"))
    }

    func testPageNoteIsHiddenWhenTheFileIsOlderThanTwoDays() {
        XCTAssertNil(PFWave2Parse.pageNotes(json(pageNotesJSON))?.note("today", today: "2030-03-16"))
    }

    func testPageNoteIsHiddenWhenTheFileHasNoDate() {
        XCTAssertNil(PFWave2Parse.pageNotes(json(#"{"pages":{"today":{"tone":"ok","text":"Fine."}}}"#))?.note("today", today: "2030-03-13"))
    }

    func testPageNoteUpdatedLabelIsTheClockTimeForTodaysFile() {
        XCTAssertEqual(PFWave2Parse.pageNotes(json(pageNotesJSON))?.updatedLabel(today: "2030-03-13"), "18:11")
    }

    func testPageNoteUpdatedLabelIsTheShortDateForAnEarlierFile() {
        XCTAssertEqual(PFWave2Parse.pageNotes(json(pageNotesJSON))?.updatedLabel(today: "2030-03-14"), "13 Mar")
    }

    func testPageNotesAreNotPartOfTheWidgetSummaryInputs() {
        XCTAssertFalse(PFDocs.summaryInputs.contains(PFDocs.pageNotes))
    }

    // MARK: Live alerts

    private let liveAlertJSON = """
    {"alerts":[
      {"id":"a1","kind":"live_stress_sustained","severity":"watch","created_at":"2030-03-13T14:00:00+00:00",
       "title":"Your stress is high and staying high","body":"Your stress has stayed above your usual range for 40 minutes.",
       "status":"open","actions":[{"id":"ack","label":"Got it"}],
       "metrics":{"reading":"stress averaging 71 for 40 min","his_normal":"above 62 is his 90th percentile",
                  "source":"Garmin","since":"2030-03-13T13:20:00+00:00","plan_effect":"nothing automatic"}},
      {"id":"a2","kind":"live_hr_at_rest","severity":"alert","created_at":"2030-03-13T15:00:00+00:00",
       "title":"Your heart rate is high at rest","body":"x","status":"done","metrics":{"reading":"r"}},
      {"id":"a3","kind":"sleep_debt","severity":"watch","created_at":"2030-03-13T05:00:00+00:00",
       "title":"Sleep debt is growing","body":"y","status":"open","metrics":{"reading":"not a live alert"}}]}
    """

    func testLiveAlertKeepsItsKindAndShowsAsAnOpenAlert() {
        XCTAssertEqual(PFBuilder.alerts(json(liveAlertJSON)).map { $0.kind }, ["live_stress_sustained", "sleep_debt"])
    }

    func testLiveAlertCarriesReadingNormalSourceAndPlanEffect() {
        let live = PFBuilder.alerts(json(liveAlertJSON)).first { $0.kind == "live_stress_sustained" }?.live
        XCTAssertEqual(live, PFLiveAlertFacts(reading: "stress averaging 71 for 40 min",
                                              hisNormal: "above 62 is his 90th percentile",
                                              source: "Garmin", planEffect: "nothing automatic"))
    }

    func testClearedLiveAlertDisappears() {
        XCTAssertFalse(PFBuilder.alerts(json(liveAlertJSON)).contains { $0.kind == "live_hr_at_rest" })
    }

    func testAnAlertThatIsNotLiveCarriesNoLiveFacts() {
        XCTAssertNil(PFBuilder.alerts(json(liveAlertJSON)).first { $0.kind == "sleep_debt" }?.live)
    }

    func testLiveOnlyFilterKeepsTheLiveKindsAndDropsTheDailyOnes() {
        XCTAssertEqual(PFBuilder.alerts(json(liveAlertJSON)).filter { $0.isLive }.map { $0.kind }, ["live_stress_sustained"])
    }

    func testLiveAlertWithoutMetricsStillShowsWithNoFacts() {
        let doc = json(#"{"alerts":[{"id":"a1","kind":"live_stress_sustained","title":"t","status":"open"}]}"#)
        XCTAssertNil(PFBuilder.alerts(doc).first?.live)
    }

    func testBehaviourWithNoQualifyingQuestionKeepsTheWaitingList() {
        let impact = PFWave2Parse.behaviourImpact(json("""
        {"min_each":5,"items":[],"insufficient":[{"question":"Did you use a sauna?","label":"sauna","yes":2,"no":30}]}
        """))
        XCTAssertEqual(impact?.insufficient.first?.yes, 2)
    }

    func testBehaviourEffectsStayWithTheirOwnSource() {
        let impact = PFWave2Parse.behaviourImpact(json("""
        {"items":[{"question":"q","label":"l","days_yes":9,"days_no":40,"primary":"pf_recovery","line":"x",
                   "effects":{"pf_recovery":{"source":"PaceForge","what":"w","unit":"points","n_yes":9,"n_no":38,"diff":-9.2},
                              "noop_recovery":{"source":"NOOP","what":"w","unit":"points","n_yes":9,"n_no":36,"diff":-8.5}}}]}
        """))
        XCTAssertEqual(impact?.items.first?.orderedEffects.map { $0.effect.source }, ["PaceForge", "NOOP"])
    }

    func testBehaviourWithNoQuestionsAtAllIsAbsent() {
        XCTAssertNil(PFWave2Parse.behaviourImpact(json(#"{"items":[],"insufficient":[]}"#)))
    }
}
