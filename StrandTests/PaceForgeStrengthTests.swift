import XCTest
@testable import Strand

/// Strength imports and the server's strength history: the inputs of the two import jobs, how a preview, a summary preview and the saved
/// result read, and which exercises the Lift Log does not already show. Every value is made up.
final class PaceForgeStrengthTests: XCTestCase {
    private let previewID = String(repeating: "ab12", count: 16)

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    // MARK: Inputs

    func testPreviewSendsTheProviderAndTheFileText() {
        assertSame(PFJobInputs.strengthImportPreview(provider: .hevy, content: "date,exercise\n"), ["provider": "hevy", "content": "date,exercise\n"])
    }

    func testPreviewOfAnEmptyFileIsNotSent() {
        XCTAssertNil(PFJobInputs.strengthImportPreview(provider: .hevy, content: "  \n "))
    }

    func testPreviewOfAFileOverTheLimitIsNotSent() {
        XCTAssertNil(PFJobInputs.strengthImportPreview(provider: .hevy, content: String(repeating: "x", count: PFStrengthImport.maxChars + 1)))
    }

    func testPreviewOfAFileAtTheLimitIsSent() {
        XCTAssertNotNil(PFJobInputs.strengthImportPreview(provider: .hevy, content: String(repeating: "x", count: PFStrengthImport.maxChars)))
    }

    func testExerciseMapRidesAlongWhenItHasNames() {
        let inputs = PFJobInputs.strengthImportPreview(provider: .hevy, content: "a", exerciseMap: ["Bench": "bb_bench_press"])
        assertSame(inputs, ["provider": "hevy", "content": "a", "exercise_map": ["Bench": "bb_bench_press"]])
    }

    func testAnEmptyExerciseMapIsLeftOut() {
        XCTAssertNil(PFJobInputs.strengthImportPreview(provider: .hevy, content: "a", exerciseMap: [:])?["exercise_map"])
    }

    func testConfirmCarriesThePreviewID() {
        let inputs = PFJobInputs.strengthImport(provider: .strava, content: "a", confirm: previewID)
        XCTAssertEqual(inputs?["confirm"] as? String, previewID)
    }

    func testConfirmWithoutAPreviewIDIsNotSent() {
        XCTAssertNil(PFJobInputs.strengthImport(provider: .hevy, content: "a", confirm: "not-a-preview"))
    }

    func testOnlyHevyIsASetFile() {
        XCTAssertEqual(PFStrengthProvider.allCases.filter { !$0.isSummary }, [.hevy])
    }

    // MARK: Preview

    private let setPreview = """
    {"provider": "hevy", "kind": "sets", "preview_id": "\(String(repeating: "ab12", count: 16))", "can_confirm": true, "blocked": null,
     "counts": {"new": 2, "duplicate": 1, "conflict": 0, "rejected": 2, "skipped": 3, "items": 3},
     "items": [{"id": "hevy:1", "date": "2030-03-04", "title": "Push day", "status": "new", "reason": "", "set_count": 5, "exercises": ["Barbell bench press"]},
               {"id": "hevy:2", "date": "2030-03-06", "title": "Pull day", "status": "duplicate", "reason": "same sets already saved", "set_count": 4, "exercises": ["Row"]}],
     "mapping": [{"provider_name": "Strange Machine Move", "exercise_id": null, "name": null, "rows": 2},
                 {"provider_name": "Bench Press (Barbell)", "exercise_id": "bb_bench_press", "name": "Barbell bench press", "rows": 4}],
     "units_normalised": {"kg": 3, "lb": 2},
     "rejected": [{"row": 7, "reason": "unsupported unit 'stone'"}, {"row": 9, "reason": "unsupported unit 'stone'"}],
     "rejected_reasons": {"unsupported unit '...'": 2},
     "skipped": [{"row": 1, "reason": "warm-up set"}], "note": "Sets only from rows the file recorded."}
    """

    func testPreviewReadsTheCountsAndTheItems() {
        let preview = PFStrengthPreview.parse(json(setPreview))
        XCTAssertEqual(preview?.counts, PFStrengthPreview.Counts(new: 2, duplicate: 1, conflict: 0, rejected: 2, skipped: 3, items: 3))
        XCTAssertEqual(preview?.items.map(\.status), ["new", "duplicate"])
        XCTAssertEqual(preview?.items.first?.exercises, ["Barbell bench press"])
    }

    func testPreviewListsTheNamesTheServerCouldNotPlace() {
        XCTAssertEqual(PFStrengthPreview.parse(json(setPreview))?.unmapped.map(\.providerName), ["Strange Machine Move"])
    }

    func testPreviewKeepsTheRejectedRowsWithTheirReasons() {
        let rejected = PFStrengthPreview.parse(json(setPreview))?.rejected
        XCTAssertEqual(rejected?.first, PFStrengthPreview.Row(row: 7, reason: "unsupported unit 'stone'"))
    }

    func testPreviewGroupsTheRejectedReasons() {
        XCTAssertEqual(PFStrengthPreview.parse(json(setPreview))?.rejectedReasons, [PFStrengthPreview.Reason(text: "unsupported unit '...'", count: 2)])
    }

    func testPreviewReadsTheUnitsItConverted() {
        let preview = PFStrengthPreview.parse(json(setPreview))
        XCTAssertEqual([preview?.kgCount, preview?.lbCount], [3, 2])
    }

    func testPreviewCountLinesLeaveOutZeros() {
        XCTAssertEqual(PFStrengthPreview.parse(json(setPreview))?.countLines,
                       ["2 new", "1 already saved", "2 rows rejected", "3 rows skipped"])
    }

    func testPreviewOfSetsOffersToSaveWorkouts() {
        XCTAssertEqual(PFStrengthPreview.parse(json(setPreview))?.confirmTitle, "Save 2 workouts")
    }

    func testPreviewCanBeConfirmedOnlyWhenTheServerSaysSo() {
        let blocked = setPreview.replacingOccurrences(of: "\"can_confirm\": true, \"blocked\": null",
                                                      with: "\"can_confirm\": false, \"blocked\": \"Saving 2 more would push older records out\"")
        let preview = PFStrengthPreview.parse(json(blocked))
        XCTAssertEqual([preview?.canConfirm, preview?.blocked != nil], [false, true])
    }

    func testPreviewWithoutAPreviewIDIsNotUsable() {
        XCTAssertNil(PFStrengthPreview.parse(json("{\"provider\": \"hevy\", \"kind\": \"sets\"}")))
    }

    func testSummaryPreviewIsASummaryAndNeverSets() {
        let text = """
        {"provider": "strava", "kind": "summary", "preview_id": "\(previewID)", "can_confirm": true, "blocked": null,
         "counts": {"new": 2, "duplicate": 0, "conflict": 0, "rejected": 0, "skipped": 0, "items": 2},
         "items": [{"id": "strava:s1", "date": "2030-03-04", "title": "Gym", "status": "new", "reason": "", "duration_seconds": 3600, "exercises": []}],
         "mapping": [], "units_normalised": {"kg": 0, "lb": 0}, "rejected": [], "rejected_reasons": {}, "skipped": [],
         "note": "A summary is kept as a summary; it is never turned into sets."}
        """
        let preview = PFStrengthPreview.parse(json(text))
        XCTAssertEqual([preview?.isSummary, preview?.items.first?.setCount == nil, preview?.confirmTitle == "Save 2 summaries"], [true, true, true])
    }

    func testPreviewOfAFileThatAddsNothingSaysWhy() {
        let text = setPreview.replacingOccurrences(of: "\"new\": 2", with: "\"new\": 0")
        XCTAssertEqual(PFStrengthPreview.parse(json(text))?.nothingToSave, "Everything in this file is already saved or cannot be saved.")
    }

    func testStatusWordsAreReadable() {
        XCTAssertEqual(["new", "duplicate", "conflict"].map(PFStrengthPreview.statusLabel), ["New", "Already saved", "Differs from saved"])
    }

    // MARK: Result

    func testResultLineSaysWhatWasSavedAndWhatWasAlreadyThere() {
        let result = PFStrengthImportResult.parse(json("{\"provider\": \"hevy\", \"kind\": \"sets\", \"saved\": 2, \"ids\": [\"a\", \"b\"], \"already_imported\": 1, \"conflicts\": 0, \"rejected\": 0, \"skipped\": 0}"))
        XCTAssertEqual(result?.line, "Saved 2 workouts. 1 already saved.")
    }

    func testResultOfSummariesCallsThemSummaries() {
        let result = PFStrengthImportResult.parse(json("{\"kind\": \"summary\", \"saved\": 1}"))
        XCTAssertEqual(result?.line, "Saved 1 summary.")
    }

    func testResultOfAnImportThatSavedNothingSaysSo() {
        XCTAssertEqual(PFStrengthImportResult.parse(json("{\"kind\": \"sets\", \"saved\": 0, \"already_imported\": 3}"))?.line,
                       "Nothing new was saved. 3 already saved.")
    }

    // MARK: History

    private let historyJSON = """
    {"since": "2029-03-13", "through": "2030-03-13", "equation": "Epley estimated 1RM, sets of up to 12 reps",
     "exercises": [
      {"key": "barbell bench press", "name": "Barbell bench press", "exercise_id": "bb_bench_press", "sets": 3, "pr_count": 1,
       "best_weight": {"weight_kg": 90.0, "reps": 3, "e1rm_kg": 99.0, "date": "2030-03-08", "source": "hevy"},
       "best_e1rm": null,
       "history": [{"date": "2030-03-08", "weight_kg": 90.0, "reps": 3, "e1rm_kg": 99.0, "rpe": null, "source": "hevy", "pr": true},
                   {"date": "2030-03-01", "weight_kg": 80.0, "reps": 5, "e1rm_kg": 93.3, "rpe": 8, "source": "noop_phone_log", "pr": false}]},
      {"key": "squat", "name": "Squat", "exercise_id": null, "sets": 1, "pr_count": 0, "best_weight": null, "best_e1rm": null,
       "history": [{"date": "2030-03-02", "weight_kg": 100.0, "reps": 5, "e1rm_kg": 116.7, "rpe": null, "source": "noop_phone_log", "pr": false}]}],
     "summaries": [{"summary_id": "strava:s-1", "provider": "strava", "date": "2030-03-12", "title": "Gym", "duration_seconds": 3600}],
     "summaries_note": "Summaries never count toward a best."}
    """

    func testHistoryReadsBestsAndPoints() {
        let history = PFStrengthHistory.parse(json(historyJSON))
        XCTAssertEqual(history?.exercises.first?.bestWeight, PFStrengthHistory.Best(weightKg: 90, reps: 3, e1rmKg: 99, date: "2030-03-08", source: "hevy"))
    }

    func testHistoryDropsAnExerciseWhoseSetsAreAllThePhonesOwn() {
        XCTAssertEqual(PFStrengthHistory.parse(json(historyJSON))?.beyondThisPhone.map(\.name), ["Barbell bench press"])
    }

    func testHistoryKeepsOnlyTheSetsTheLiftLogDoesNotHold() {
        let kept = PFStrengthHistory.parse(json(historyJSON))?.beyondThisPhone.first?.history
        XCTAssertEqual(kept?.map(\.source), ["hevy"])
    }

    func testHistoryMarksAPersonalRecord() {
        XCTAssertEqual(PFStrengthHistory.parse(json(historyJSON))?.exercises.first?.history.first?.isPR, true)
    }

    func testHistoryListsSummariesApartFromSets() {
        XCTAssertEqual(PFStrengthHistory.parse(json(historyJSON))?.summaries.first?.durationSeconds, 3600)
    }

    func testHistoryWithoutAnExercisesListIsNotUsable() {
        XCTAssertNil(PFStrengthHistory.parse(json("{\"since\": \"2029-03-13\"}")))
    }

    func testSourceLabelsNameWhereASetCameFrom() {
        XCTAssertEqual(["paceforge_log", "hevy", "noop_phone_log"].map { PFStrengthHistory.sourceLabel($0) },
                       ["PaceForge log", "Hevy", "This iPhone's Lift Log"])
    }

    func testWeightsShowInPoundsWhenAsked() {
        XCTAssertEqual(PFStrengthHistory.weightText(kg: 100, pounds: true), "220.5 lb")
    }

    func testWeightsShowInKilogramsByDefault() {
        XCTAssertEqual(PFStrengthHistory.weightText(kg: 92.5, pounds: false), "92.5 kg")
    }

    func testASetReadsWeightTimesReps() {
        XCTAssertEqual(PFStrengthHistory.setText(weightKg: 90, reps: 3, pounds: false), "90 kg \u{00D7} 3")
    }

    func testDurationsReadInMinutesThenHours() {
        XCTAssertEqual([PFStrengthHistory.durationText(seconds: 2700), PFStrengthHistory.durationText(seconds: 3900)], ["45 min", "1:05 h"])
    }
}
