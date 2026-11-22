import XCTest
@testable import Strand

/// Heart-rate zone sets per sport, comparable earlier runs, repetitions against the plan and a race's course notes: the inputs, the forms' rules
/// and how each document reads (shapes from the job contract's "Training analytics" section). All values are made up.
final class PaceForgeTrainingAnalyticsTests: XCTestCase {
    private let today = "2030-03-13"

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    // MARK: hr-zones-add

    func testAZoneSetSendsExactlyTheContractsFields() {
        assertSame(PFJobInputs.hrZonesAdd(sport: "cycling", effectiveFrom: "2030-03-01", source: "manual", floors: [100, 120, 140, 160, 175], maxHr: 190),
                   ["sport": "cycling", "effective_from": "2030-03-01", "source": "manual", "floors": [100, 120, 140, 160, 175], "max_hr": 190])
    }

    func testAZoneSetCarriesANoteWhenWritten() {
        let inputs = PFJobInputs.hrZonesAdd(sport: "running", effectiveFrom: "2030-03-01", source: "lab_test", floors: [100, 120, 140, 160, 175], maxHr: 190,
                                            note: " Lab visit ")
        XCTAssertEqual(inputs?["note"] as? String, "Lab visit")
    }

    func testFloorsThatDoNotRiseAreNotSent() {
        XCTAssertNil(PFJobInputs.hrZonesAdd(sport: "running", effectiveFrom: "2030-03-01", source: "manual", floors: [100, 120, 120, 160, 175], maxHr: 190))
    }

    func testAFloorBelowThirtyIsNotSent() {
        XCTAssertNil(PFJobInputs.hrZonesAdd(sport: "running", effectiveFrom: "2030-03-01", source: "manual", floors: [25, 120, 140, 160, 175], maxHr: 190))
    }

    func testTheLastFloorAtTheMaximumIsNotSent() {
        XCTAssertNil(PFJobInputs.hrZonesAdd(sport: "running", effectiveFrom: "2030-03-01", source: "manual", floors: [100, 120, 140, 160, 190], maxHr: 190))
    }

    func testFourFloorsAreNotSent() {
        XCTAssertNil(PFJobInputs.hrZonesAdd(sport: "running", effectiveFrom: "2030-03-01", source: "manual", floors: [100, 120, 140, 160], maxHr: 190))
    }

    func testASourceOutsideTheClosedListIsNotSent() {
        XCTAssertNil(PFJobInputs.hrZonesAdd(sport: "running", effectiveFrom: "2030-03-01", source: "guess", floors: [100, 120, 140, 160, 175], maxHr: 190))
    }

    func testASportWithCapitalsIsNotSent() {
        XCTAssertNil(PFJobInputs.hrZonesAdd(sport: "Running", effectiveFrom: "2030-03-01", source: "manual", floors: [100, 120, 140, 160, 175], maxHr: 190))
    }

    func testANoteOverThreeHundredCharactersIsNotSent() {
        XCTAssertNil(PFJobInputs.hrZonesAdd(sport: "running", effectiveFrom: "2030-03-01", source: "manual", floors: [100, 120, 140, 160, 175], maxHr: 190,
                                            note: String(repeating: "x", count: 301)))
    }

    // MARK: The zone-set form

    private func zoneDraft(_ change: (inout PFZoneSetDraft) -> Void = { _ in }) -> PFZoneSetDraft {
        var form = PFZoneSetDraft(effectiveFrom: "2030-03-01")
        form.sport = "Cycling"
        form.floorTexts = ["100", "120", "140", "160", "175"]
        form.maxHrText = "190"
        change(&form)
        return form
    }

    func testTheSportIsTypedAnyWayAndSentAsAKey() {
        XCTAssertEqual(zoneDraft { $0.sport = " Mountain Biking " }.sportKey, "mountain_biking")
    }

    func testAFilledZoneFormHasNoProblem() {
        XCTAssertNil(zoneDraft().problem(today: today))
    }

    func testAFilledZoneFormSendsTheKeyAndTheNumbers() {
        assertSame(zoneDraft().inputs(today: today),
                   ["sport": "cycling", "effective_from": "2030-03-01", "source": "manual", "floors": [100, 120, 140, 160, 175], "max_hr": 190])
    }

    func testAZoneFormWithATextFloorSaysSo() {
        XCTAssertEqual(zoneDraft { $0.floorTexts[2] = "abc" }.problem(today: today), "Each zone's lowest heart rate is a whole number from 30 to 230.")
    }

    func testAZoneFormWithZonesThatDoNotRiseSaysSo() {
        XCTAssertEqual(zoneDraft { $0.floorTexts[3] = "130" }.problem(today: today), "The zones have to rise from zone 1 to zone 5.")
    }

    func testAZoneFormWithZoneFiveAtTheMaximumSaysSo() {
        XCTAssertEqual(zoneDraft { $0.maxHrText = "175" }.problem(today: today), "Zone 5 has to start below the maximum.")
    }

    func testAStartBeforeTheYearTwoThousandIsOutOfRange() {
        XCTAssertEqual(zoneDraft { $0.effectiveFrom = "1999-12-31" }.problem(today: today), "That start day is out of range.")
    }

    func testAStartMoreThanAYearAheadIsOutOfRange() {
        XCTAssertEqual(zoneDraft { $0.effectiveFrom = "2031-03-15" }.problem(today: today), "That start day is out of range.")
    }

    func testAZoneFormWithAProblemSendsNothing() {
        XCTAssertNil(zoneDraft { $0.maxHrText = "" }.inputs(today: today))
    }

    func testAFailedZoneSendLeavesTheFormWhole() {
        let typed = zoneDraft()
        XCTAssertEqual(PFDraftKeeping.afterSend(typed, tookIt: false), typed)
    }

    // MARK: The zones document

    private let zonesDocument = """
    {"sets": [{"id": "zs-0001", "sport": "cycling", "effective_from": "2030-01-01", "source": "manual", "floors": [100, 120, 140, 160, 175],
               "max_hr": 190, "note": null, "created_at": "2030-01-01T09:00:00+00:00"},
              {"id": "zs-0002", "sport": "cycling", "effective_from": "2030-03-01", "source": "lab_test", "floors": [105, 125, 145, 165, 180],
               "max_hr": 192, "note": "Lab visit", "created_at": "2030-03-01T09:00:00+00:00"}],
     "date": "2030-03-13",
     "resolved": [{"sport": "cycling", "date": "2030-03-13", "resolved": "per_sport", "id": "zs-0002", "effective_from": "2030-03-01",
                   "source": "lab_test", "max_hr": 192,
                   "zones": [{"zone": 1, "low_bpm": 105, "high_bpm": 124}, {"zone": 2, "low_bpm": 125, "high_bpm": 144}, {"zone": 3, "low_bpm": 145, "high_bpm": 164},
                             {"zone": 4, "low_bpm": 165, "high_bpm": 179}, {"zone": 5, "low_bpm": 180, "high_bpm": 192}]},
                  {"sport": "running", "date": "2030-03-13", "resolved": "global", "id": "global:ab12cd34", "effective_from": null,
                   "source": "garmin_profile", "max_hr": 185, "zones": []}]}
    """

    func testBothStoredSetsRead() {
        XCTAssertEqual(PFHRZones.parse(json(zonesDocument)).sets.count, 2)
    }

    func testASetKeepsItsFloorsAndMaximum() {
        let set = PFHRZones.parse(json(zonesDocument)).sets[1]
        XCTAssertEqual([set.floors, [set.maxHr ?? 0]], [[105, 125, 145, 165, 180], [192]])
    }

    func testTheSetsOfASportAreNewestFirst() {
        let doc = PFHRZones.parse(json(zonesDocument))
        XCTAssertEqual(PFHRZones.sets(of: "cycling", in: doc).map { $0.id }, ["zs-0002", "zs-0001"])
    }

    func testTheResolvedZonesOfASportAreItsFiveBands() {
        let resolved = PFHRZones.parse(json(zonesDocument)).resolved[0]
        XCTAssertEqual(resolved.zones.map { $0.low }, [105, 125, 145, 165, 180])
    }

    func testAStoredSetIsDescribedAsTheAthletesOwn() {
        let resolved = PFHRZones.parse(json(zonesDocument)).resolved[0]
        XCTAssertTrue(resolved.line.hasPrefix("Your cycling zone set from "))
    }

    func testAStoredSetNamesItsSource() {
        let resolved = PFHRZones.parse(json(zonesDocument)).resolved[0]
        XCTAssertTrue(resolved.line.hasSuffix(", lab test"))
    }

    func testTheGlobalFallbackNamesItsHash() {
        let resolved = PFHRZones.parse(json(zonesDocument)).resolved[1]
        XCTAssertEqual(resolved.line, "Garmin's profile zones (global:ab12cd34), no set of your own for running")
    }

    func testAnAnalysisThatRecordedNoDefinitionSaysSo() {
        XCTAssertEqual(PFHRZones.describe(resolved: "none", sport: "cycling", effectiveFrom: nil, source: nil, id: nil), "No zone definition was recorded")
    }

    func testARideRecordsTheDefinitionItUsed() {
        let definition = PFZoneDefinition.parse(PFJ(data: json("""
        {"id": "zs-0002", "sport": "cycling", "resolved": "per_sport", "effective_from": "2030-03-01", "source": "lab_test"}
        """)))
        XCTAssertEqual(definition?.id, "zs-0002")
    }

    func testARideWithoutADefinitionHasNone() {
        XCTAssertNil(PFZoneDefinition.parse(PFJ(nil)))
    }

    func testAnUnreadableZonesDocumentIsEmpty() {
        XCTAssertEqual(PFHRZones.parse(json("nope")), PFHRZonesDoc())
    }

    // MARK: Comparable earlier runs

    private let comparableDocument = """
    {"activity_id": 100, "available": true, "window_days": 120, "limit": 5, "planned_class": "easy", "older_than_window": 3,
     "comparable": [{"activity_id": 1, "date": "2030-03-01", "name": "County Run", "distance_m": 10000.0, "duration_s": 3000.0,
                     "pace_s_per_km": 300.0, "avg_hr": 150, "planned_class": "easy",
                     "match": {"condition": "outdoor", "size_ratio": 1.0, "size_basis": "distance", "route": "unknown", "terrain": "similar climb", "planned": "easy"}},
                    {"activity_id": 3, "date": "2030-02-20", "name": "Belt run", "distance_m": null, "duration_s": 2400.0, "pace_s_per_km": null, "avg_hr": null,
                     "planned_class": null, "match": {"condition": "treadmill", "size_ratio": 0.9, "size_basis": "duration", "route": "unknown", "terrain": "unknown", "planned": "unknown"}}],
     "excluded": [{"activity_id": 2, "date": "2030-02-10", "name": "Short jog", "reason": "size_differs", "detail": "0.50 times this run's distance, outside 0.75-1.33"}]}
    """

    func testTheComparableRunsRead() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).comparable.map { $0.id }, ["1", "3"])
    }

    func testTheWindowAndTheOlderRunsRead() {
        let doc = PFComparable.parse(json(comparableDocument))
        XCTAssertEqual([doc.windowDays, doc.olderThanWindow], [120, 3])
    }

    func testWhatWasCheckedIsSaidInWords() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).comparable[0].matchLines,
                       ["Same conditions: outdoor", "Size: 1.0 times this run's distance", "Start place not known", "Similar climbing", "Planned: easy"])
    }

    func testAnUnknownPropertyIsNeverPresentedAsAMatch() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).comparable[1].matchLines,
                       ["Same conditions: treadmill", "Size: 0.9 times this run's duration", "Start place not known", "Climbing not known", "Planned type not known"])
    }

    func testARunSummaryReadsDistanceTimePaceAndHeartRate() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).comparable[0].summary,
                       "10.0 km \u{00B7} 50:00 \u{00B7} 5:00 /km \u{00B7} avg 150 bpm")
    }

    func testAnUnconfirmedBeltPaceSaysSo() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).comparable[1].summary, "40:00 \u{00B7} pace not confirmed")
    }

    func testTheExcludedRunKeepsItsReasonCode() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).excluded.first?.reason, "size_differs")
    }

    func testTheExcludedReasonReadsInWords() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).excluded.first?.reasonText, "A different length")
    }

    func testTheExcludedRunKeepsTheServersDetail() {
        XCTAssertEqual(PFComparable.parse(json(comparableDocument)).excluded.first?.detail, "0.50 times this run's distance, outside 0.75-1.33")
    }

    func testEveryReasonCodeTheServerSendsHasWords() {
        let codes = ["condition_differs", "size_differs", "size_unknown", "no_size", "pace_pending", "route_differs", "terrain_differs", "planned_type_differs", "beyond_limit"]
        XCTAssertFalse(codes.contains { PFComparable.reasonText($0).contains("_") })
    }

    func testAnUnknownReasonCodeStillReads() {
        XCTAssertEqual(PFComparable.reasonText("some_new_reason"), "Some new reason")
    }

    func testANonRunIsNotAvailableAndKeepsTheReason() {
        let doc = PFComparable.parse(json("""
        {"activity_id": 5, "available": false, "reason": "the activity is not a run with a start time", "comparable": [], "excluded": []}
        """))
        XCTAssertEqual([doc.isAvailable ? "yes" : "no", doc.reason ?? ""], ["no", "the activity is not a run with a start time"])
    }

    // MARK: Repetitions against the plan

    private let repsDocument = """
    {"session_id": "s1", "date": "2030-03-10", "name": "3 x 1 km", "activity_id": 100, "matched_activity_ids": ["100"],
     "available": true, "method": "index", "planned_reps": 3, "trusted_pace": true,
     "reps": [{"n": 1, "alignment": "exact", "lap_indexes": [2],
               "planned": {"step_type": "interval", "distance_m": 1000.0, "duration_s": null, "target_type": "pace", "target_low": 235.0, "target_high": 245.0},
               "actual": {"distance_m": 1000.0, "duration_s": 240.0, "pace_s_per_km": 240.0, "avg_hr": 168},
               "delta": {"distance_m": 0.0, "duration_s": null, "pace_outside_band_s": 0.0, "pace_in_band": true, "hr_outside_band_bpm": null, "hr_in_band": null}},
              {"n": 2, "alignment": "size_mismatch", "lap_indexes": [4],
               "planned": {"step_type": "interval", "distance_m": 1000.0, "duration_s": null, "target_type": "pace", "target_low": 235.0, "target_high": 245.0},
               "actual": {"distance_m": 980.0, "duration_s": 252.4, "pace_s_per_km": 257.6, "avg_hr": 171},
               "delta": {"distance_m": -20.0, "duration_s": null, "pace_outside_band_s": 12.6, "pace_in_band": false, "hr_outside_band_bpm": 6.0, "hr_in_band": false}},
              {"n": 3, "alignment": "unmatched", "lap_indexes": [],
               "planned": {"step_type": "interval", "distance_m": 1000.0, "duration_s": null, "target_type": "pace", "target_low": 235.0, "target_high": 245.0},
               "actual": null, "delta": null}],
     "unmatched_laps": [1, 5], "note": "Raw lap pace, not heat adjusted."}
    """

    func testEveryPlannedRepetitionIsARow() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps.map { $0.n }, [1, 2, 3])
    }

    func testThePlannedStepReadsAsDistanceAndPaceBand() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps[0].plannedLine, "1 km, pace 3:55 to 4:05 /km")
    }

    func testTheRecordedLapReadsAsDistanceTimePaceAndHeartRate() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps[0].actualLine, "1.00 km in 4:00 (4:00 /km), avg 168 bpm")
    }

    func testARepInsideTheBandSaysSo() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps[0].paceVerdict, "Pace inside the band")
    }

    func testARepWithoutAHeartRateCheckHasNoHeartRateVerdict() {
        XCTAssertNil(PFReps.parse(json(repsDocument)).reps[0].heartRateVerdict)
    }

    func testASlowRepSaysBySomuch() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps[1].paceVerdict, "Pace 13 s/km slower than the band")
    }

    func testAHighHeartRateRepSaysBySoMuch() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps[1].heartRateVerdict, "Heart rate 6 bpm above the band")
    }

    func testAFasterRepSaysFaster() {
        let row = PFRepRow(n: 1, alignment: "exact", lapIndexes: [1], stepType: nil, plannedDistanceM: 1000, plannedDurationS: nil, targetType: "pace",
                           targetLow: 235, targetHigh: 245, actualDistanceM: 1000, actualDurationS: 225, actualPaceSPerKm: 225, actualAvgHr: nil,
                           paceOutsideBandS: -10, paceInBand: false, hrOutsideBandBpm: nil, hrInBand: nil, hasActual: true)
        XCTAssertEqual(row.paceVerdict, "Pace 10 s/km faster than the band")
    }

    func testALapPickedByPositionWithADifferentSizeIsSaidToBe() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps[1].alignmentNote, "Taken by position; the lap's size differs from the plan")
    }

    func testAnExactLapNeedsNoNote() {
        XCTAssertNil(PFReps.parse(json(repsDocument)).reps[0].alignmentNote)
    }

    func testARepWithNoLapSaysNoLapWasFound() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).reps[2].actualLine, "No lap found for this repetition")
    }

    func testTheLapsLeftOverAreListed() {
        XCTAssertEqual(PFReps.parse(json(repsDocument)).unmatchedLaps, [1, 5])
    }

    func testAMissedLapPressIsExplained() {
        let row = PFRepRow(n: 2, alignment: "combined", lapIndexes: [3], stepType: nil, plannedDistanceM: nil, plannedDurationS: 180, targetType: nil,
                           targetLow: nil, targetHigh: nil, actualDistanceM: nil, actualDurationS: nil, actualPaceSPerKm: nil, actualAvgHr: nil,
                           paceOutsideBandS: nil, paceInBand: nil, hrOutsideBandBpm: nil, hrInBand: nil, hasActual: true)
        XCTAssertEqual(row.alignmentNote, "One lap holds this repetition and the next one (a missed lap press), so no pace for either")
    }

    func testASessionWithNoLapsIsNotAvailableAndKeepsTheReason() {
        let doc = PFReps.parse(json("""
        {"session_id": "s2", "available": false, "reason": "the recording has no laps", "method": "none", "reps": [], "unmatched_laps": [], "planned_reps": 3}
        """))
        XCTAssertEqual([doc.isAvailable ? "yes" : "no", doc.reason ?? ""], ["no", "the recording has no laps"])
    }

    // MARK: Race course and pacing context

    private let eventsDocument = """
    [{"date": "2030-12-16", "name": "HYROX singles", "type": "hyrox", "goal_time": "1:10:00",
      "course_context": {"course_note": "Four 1 km laps, carpet", "pacing_note": "Hold 4:50", "elevation_gain_m": 120, "url": "https://example.org/map",
                         "source": "manual", "updated_at": "2030-03-01T09:00:00+00:00"}},
     {"date": "2030-06-01", "name": "Half marathon", "type": "road"}]
    """

    func testTheCourseNotesOfARaceRead() {
        let context = PFCourse.context(in: json(eventsDocument), date: "2030-12-16", name: "HYROX singles")
        XCTAssertEqual(context, PFCourseContext(courseNote: "Four 1 km laps, carpet", pacingNote: "Hold 4:50", elevationGainM: 120,
                                                url: "https://example.org/map", updatedAt: "2030-03-01T09:00:00+00:00"))
    }

    func testARaceWithoutNotesHasNoContext() {
        XCTAssertNil(PFCourse.context(in: json(eventsDocument), date: "2030-06-01", name: "Half marathon"))
    }

    func testTheRaceIsFoundByDateWhenTheNameHasChanged() {
        XCTAssertEqual(PFCourse.context(in: json(eventsDocument), date: "2030-12-16", name: "Paris singles")?.elevationGainM, 120)
    }

    func testTheEventsMayBeHeldUnderAKey() {
        let wrapped = "{\"events\": \(eventsDocument)}"
        XCTAssertEqual(PFCourse.context(in: json(wrapped), date: "2030-12-16", name: nil)?.pacingNote, "Hold 4:50")
    }

    private func courseDraft(_ change: (inout PFCourseDraft) -> Void = { _ in }) -> PFCourseDraft {
        var form = PFCourseDraft(PFCourse.context(in: json(eventsDocument), date: "2030-12-16", name: nil))
        change(&form)
        return form
    }

    func testTheCourseFormStartsFromTheSavedNotes() {
        XCTAssertEqual(courseDraft().elevationText, "120")
    }

    func testAnUntouchedCourseFormChangesNothing() {
        XCTAssertEqual(courseDraft().changes(from: courseDraft()), [:])
    }

    func testOnlyTheChangedPartGoes() {
        XCTAssertEqual(courseDraft { $0.pacingNote = "Hold 4:45" }.changes(from: courseDraft()), ["pacing_note": "Hold 4:45"])
    }

    func testAClearedPartGoesAsAnEmptyString() {
        XCTAssertEqual(courseDraft { $0.url = "" }.changes(from: courseDraft()), ["course_url": ""])
    }

    func testTheClimbingGoesUnderTheServersFieldName() {
        XCTAssertEqual(courseDraft { $0.elevationText = "150" }.changes(from: courseDraft()), ["course_elevation_gain_m": "150"])
    }

    func testALinkThatIsNotHttpIsRefused() {
        XCTAssertEqual(courseDraft { $0.url = "ftp://example.org/map" }.problem, "The link has to start with http:// or https://.")
    }

    func testClimbingAboveTenThousandMetresIsRefused() {
        XCTAssertEqual(courseDraft { $0.elevationText = "12000" }.problem, "Climbing is a whole number of metres, 0 to 10000.")
    }

    func testClimbingThatIsNotANumberIsRefused() {
        XCTAssertEqual(courseDraft { $0.elevationText = "steep" }.problem, "Climbing is a whole number of metres, 0 to 10000.")
    }

    func testANoteOverFiveHundredCharactersIsRefused() {
        XCTAssertEqual(courseDraft { $0.courseNote = String(repeating: "x", count: 501) }.problem, "The course note is too long (500 characters at most).")
    }

    func testTheCourseUpdateMatchesTheRaceByDateAndName() {
        assertSame(PFJobInputs.raceCourseSet(date: "2030-12-16", name: "HYROX singles", fields: ["course_note": "Carpet"]),
                   ["op": "set", "match": ["date": "2030-12-16", "name": "HYROX singles"], "fields": ["course_note": "Carpet"]])
    }

    func testACourseUpdateWithNoChangeIsNotSent() {
        XCTAssertNil(PFJobInputs.raceCourseSet(date: "2030-12-16", name: nil, fields: [:]))
    }
}
