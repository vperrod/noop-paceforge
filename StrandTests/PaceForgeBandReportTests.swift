import XCTest
@testable import Strand

/// The band-report numbers PaceForge serves: Recovery two ways and the verdict lines, Load Focus, the weekly target range, muscular
/// load, the strap's HRV, the Healthspan inputs and the graded health watch. Every figure is made up; the key names are the server's.
final class PaceForgeBandReportTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    // MARK: Recovery two ways and the verdict lines

    private let daily = """
    {"recovery": {"score": 72, "body_signals": {"value": 3.3, "z": 1.0, "state": "settled", "line": "Body signals: nervous system settled",
                  "inputs": ["hrv", "rhr"], "source": "PaceForge (Garmin)", "gloss": "Body signals gloss."},
                  "sleep_signal": {"value": -2.1, "z": -0.64, "state": "behind", "line": "Sleep: a little worse than your usual",
                  "source": "PaceForge (Garmin)", "gloss": "Sleep gloss."}},
     "lines": {"recovery": {"verdict": "Ready: well recovered, a hard day is fine", "driver": "Mostly lifted by heart rate variability.",
                            "calibrating": null, "source": "PaceForge (Garmin)"},
               "sleep": {"verdict": "Sufficient: close to a full night", "driver": null, "calibrating": "calibrating: night 3 of 7"},
               "strain": {"verdict": "Moderate: building toward today's target of 8-12", "driver": "No session logged yet today.",
                          "calibrating": null}}}
    """

    func testBothSignalsAndAllThreeLinesAreDecoded() throws {
        let readout = try XCTUnwrap(PFBandParse.readout(daily: json(daily)))
        XCTAssertEqual(readout.bodySignals?.value, 3.3)
        XCTAssertEqual(readout.sleepSignal?.state, "behind")
        XCTAssertEqual(readout.recovery?.verdict, "Ready: well recovered, a hard day is fine")
        XCTAssertEqual(readout.sleep?.calibrating, "calibrating: night 3 of 7")
        XCTAssertEqual(readout.strain?.driver, "No session logged yet today.")
        XCTAssertEqual(readout.source, "PaceForge (Garmin)")
    }

    func testAWatchWornByDayOnlyKeepsNothingOvernight() throws {
        let readout = try XCTUnwrap(PFBandParse.readout(daily: json(daily)))
        let dayOnly = try XCTUnwrap(readout.visible(overnight: false))
        XCTAssertNil(dayOnly.bodySignals)
        XCTAssertNil(dayOnly.sleepSignal)
        XCTAssertNil(dayOnly.recovery)
        XCTAssertNil(dayOnly.sleep)
        XCTAssertEqual(dayOnly.strain?.verdict, "Moderate: building toward today's target of 8-12")
    }

    func testDayOnlyWithNoStrainLineLeavesNothing() throws {
        let overnightOnly = """
        {"recovery": {"body_signals": {"value": 1.0, "line": "Body signals: nervous system settled"}},
         "lines": {"recovery": {"verdict": "Ready: well recovered, a hard day is fine"}}}
        """
        let readout = try XCTUnwrap(PFBandParse.readout(daily: json(overnightOnly)))
        XCTAssertNil(readout.visible(overnight: false))
    }

    func testAnOlderServerWithNeitherKeyGivesNoReadout() {
        XCTAssertNil(PFBandParse.readout(daily: json("{\"recovery\": {\"score\": 72}}")))
    }

    func testTheGuardedFallbackBlockGivesNoReadout() {
        XCTAssertNil(PFBandParse.readout(daily: json("{\"lines\": {\"available\": false}}")))
    }

    func testASignalWithoutANumberOrALineIsDropped() throws {
        let odd = """
        {"recovery": {"body_signals": {"value": null, "line": "x"}, "sleep_signal": {"value": 1.0}},
         "lines": {"strain": {"verdict": "Easy: well under target"}}}
        """
        let readout = try XCTUnwrap(PFBandParse.readout(daily: json(odd)))
        XCTAssertNil(readout.bodySignals)
        XCTAssertNil(readout.sleepSignal)
    }

    // MARK: Load Focus

    private let loadFocus = """
    {"available": true, "label": "Garmin Load Focus", "note": "Reference only.", "as_of": "2030-03-13", "phrase": "Balanced",
     "buckets": [{"key": "low_aerobic", "label": "Low aerobic", "value": 410, "min": 300, "max": 520, "status": "in_range"},
                 {"key": "high_aerobic", "label": "High aerobic", "value": 120, "min": 250, "max": 480, "status": "under"},
                 {"key": "anaerobic", "label": "Anaerobic", "value": 90, "min": null, "max": null, "status": null}],
     "verdict": "High aerobic is under range: add threshold or tempo work"}
    """

    func testLoadFocusBucketsKeepTheirRangeAndStatus() throws {
        let focus = try XCTUnwrap(PFBandParse.loadFocus(load: json("{\"load_focus_panel\": \(loadFocus)}")))
        XCTAssertEqual(focus.buckets.map { $0.key }, ["low_aerobic", "high_aerobic", "anaerobic"])
        XCTAssertEqual(focus.buckets[1].status, "under")
        XCTAssertNil(focus.buckets[2].min)
        XCTAssertEqual(focus.verdict, "High aerobic is under range: add threshold or tempo work")
    }

    func testAnUnavailableLoadFocusLeavesTheCardOut() {
        XCTAssertNil(PFBandParse.loadFocus(load: json("{\"load_focus_panel\": {\"available\": false}}")))
        XCTAssertNil(PFBandParse.loadFocus(load: json("{}")))
    }

    func testALoadFocusKnownOnlyByItsPhraseStillShowsTheVerdict() throws {
        let phraseOnly = "{\"load_focus_panel\": {\"available\": true, \"buckets\": [], \"verdict\": \"Garmin's own wording: Balanced.\"}}"
        let focus = try XCTUnwrap(PFBandParse.loadFocus(load: json(phraseOnly)))
        XCTAssertTrue(focus.buckets.isEmpty)
        XCTAssertEqual(focus.verdict, "Garmin's own wording: Balanced.")
    }

    func testABarKeepsAValueAboveItsRangeInsideTheTrack() throws {
        let bar = try XCTUnwrap(PFBandLogic.bar(value: 600, low: 300, high: 520))
        XCTAssertEqual(bar.value, 600 / 690.0, accuracy: 0.0001)
        XCTAssertEqual(bar.high, 520 / 690.0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(bar.value, 1)
    }

    func testABarWithNoRangeStillPlacesTheValue() throws {
        let bar = try XCTUnwrap(PFBandLogic.bar(value: 90, low: nil, high: nil))
        XCTAssertEqual(bar.low, 0)
        XCTAssertEqual(bar.high, 90 / (90 * 1.15), accuracy: 0.0001)
    }

    func testABarForANegativeValueIsRefused() {
        XCTAssertNil(PFBandLogic.bar(value: -1, low: 0, high: 10))
    }

    // MARK: Weekly target

    private let weekTarget = """
    {"available": true, "source": "PaceForge load", "note": "A guide, not a limit.", "range_factors": [0.8, 1.3],
     "weeks": [{"week": "2030-W11", "start": "2030-03-11", "state": "current", "kind": "normal", "event": null, "chronic": 300,
                "actual": 180, "expected": 290, "days_left": 3, "low": 240, "high": 390, "status": "under", "planned_check": "in_range",
                "planned_delta": 0, "line": "This week: 180 so far."},
               {"week": "2030-W12", "start": "2030-03-18", "state": "next", "kind": "taper", "event": "Dublin", "chronic": 310,
                "actual": null, "expected": 150, "days_left": 7, "low": 149, "high": 242, "status": null, "planned_check": "under",
                "planned_delta": 1, "line": "Taper week for Dublin."}]}
    """

    func testBothWeeksOfTheTargetAreDecoded() throws {
        let target = try XCTUnwrap(PFBandParse.weekTarget(projection: json("{\"week_target\": \(weekTarget)}")))
        XCTAssertEqual(target.weeks.map { $0.state }, ["current", "next"])
        XCTAssertEqual(target.weeks[0].status, "under")
        XCTAssertEqual(target.weeks[1].kind, "taper")
        XCTAssertNil(target.weeks[1].actual)
        XCTAssertEqual(target.weeks[1].event, "Dublin")
    }

    func testACalibratingOrAbsentTargetLeavesTheCardOut() {
        let calibrating = "{\"week_target\": {\"available\": false, \"reason\": \"calibrating\", \"have_days\": 12, \"need_days\": 28}}"
        XCTAssertNil(PFBandParse.weekTarget(projection: json(calibrating)))
        XCTAssertNil(PFBandParse.weekTarget(projection: json("{\"week_target\": null}")))
        XCTAssertNil(PFBandParse.weekTarget(projection: json("{}")))
    }

    // MARK: Muscular load

    private let muscular = """
    {"available": true, "source": "PaceForge muscular load", "note": "Working sets per group.", "calibrating": true,
     "top": ["legs", "pull", "upper", "core"],
     "groups": {"legs": {"label": "Legs", "acute_sets": 14, "chronic_weekly_sets": 10, "ratio": 1.4, "status": "above", "line": "Legs: 14 sets."},
                "pull": {"label": "Pull", "acute_sets": 9, "chronic_weekly_sets": null, "ratio": null, "status": null, "line": "Pull: 9 sets."},
                "upper": {"label": "Upper (push)", "acute_sets": 6, "chronic_weekly_sets": 6, "ratio": 1.0, "status": "steady", "line": "Upper: 6 sets."}},
     "total": {"label": "All strength work", "acute_sets": 29, "chronic_weekly_sets": 20, "ratio": 1.45, "status": "above", "line": "All: 29."},
     "weekly": [{"week_ending": "2030-03-06", "sets": 18}, {"week_ending": "2030-03-13", "sets": 29}]}
    """

    func testTheTopThreeGroupsAreKeptInTheServersOrder() throws {
        let load = try XCTUnwrap(PFBandParse.muscularLoad(strength: json("{\"muscular_load\": \(muscular)}")))
        XCTAssertEqual(load.top.map { $0.key }, ["legs", "pull", "upper"])
        XCTAssertEqual(load.top[0].status, "above")
        XCTAssertNil(load.top[1].ratio)
        XCTAssertTrue(load.calibrating)
        XCTAssertEqual(load.weekly.map { $0.sets }, [18, 29])
        XCTAssertEqual(load.total?.acuteSets, 29)
    }

    func testATopGroupWithNoEntryIsSkipped() throws {
        let odd = "{\"muscular_load\": {\"available\": true, \"top\": [\"legs\", \"core\"], \"groups\": {\"legs\": {\"acute_sets\": 4}}}}"
        let load = try XCTUnwrap(PFBandParse.muscularLoad(strength: json(odd)))
        XCTAssertEqual(load.top.map { $0.key }, ["legs"])
    }

    func testUnavailableMuscularLoadIsHidden() {
        XCTAssertNil(PFBandParse.muscularLoad(strength: json("{\"muscular_load\": {\"available\": false}}")))
        XCTAssertNil(PFBandParse.muscularLoad(strength: json("{}")))
    }

    // MARK: Strap HRV

    private let strapDoc = """
    {"generated_at": "2030-03-13T07:40:00", "source": "WHOOP strap, read by NOOP",
     "nights": [{"date": "2030-03-11", "ln_rmssd": 4.0, "rmssd_ms": 54.6, "sdnn_ms": 70.1, "n_beats": 21000, "clean_pct": 97.1, "window": "whole_night", "quality": "ok"},
                {"date": "2030-03-12", "ln_rmssd": 3.9, "rmssd_ms": 49.4, "sdnn_ms": 60.0, "n_beats": 900, "clean_pct": 90.0, "window": "whole_night", "quality": "short"},
                {"date": "2030-03-13", "ln_rmssd": 4.1, "rmssd_ms": 60.3, "sdnn_ms": 72.0, "n_beats": 22000, "clean_pct": 98.0, "window": "whole_night", "quality": "ok"}],
     "status": {"state": "in_band", "mean7": 57.0, "baseline60": 55.0, "band_low": 48.0, "band_high": 63.0, "nights_used": 6, "cv7": 0.08},
     "complete": true, "unusable": []}
    """

    func testTheStrapStatusAndNightsAreDecoded() throws {
        let hrv = try XCTUnwrap(PFBandParse.strapHRV(json(strapDoc)))
        XCTAssertEqual(hrv.state, "in_band")
        XCTAssertEqual(hrv.mean7, 57.0)
        XCTAssertEqual(hrv.nightsUsed, 6)
        XCTAssertEqual(hrv.nights.count, 3)
        XCTAssertEqual(PFBandLogic.lastFullNight(hrv)?.date, "2030-03-13")
    }

    func testAFileWithNoNightsMeansNoStrapDataYet() {
        XCTAssertNil(PFBandParse.strapHRV(json("{\"nights\": [], \"status\": {\"state\": \"calibrating\"}}")))
        XCTAssertNil(PFBandParse.strapHRV(PFJ(nil)))
    }

    func testTheLastFullNightSkipsAShortOne() throws {
        var hrv = try XCTUnwrap(PFBandParse.strapHRV(json(strapDoc)))
        hrv.nights.removeLast()
        XCTAssertEqual(PFBandLogic.lastFullNight(hrv)?.date, "2030-03-11")
    }

    func testTheStrapBarPlacesTheAverageInsideTheBand() throws {
        let hrv = try XCTUnwrap(PFBandParse.strapHRV(json(strapDoc)))
        let bar = try XCTUnwrap(PFBandLogic.strapBar(hrv))
        XCTAssertLessThan(bar.low, bar.value)
        XCTAssertLessThan(bar.value, bar.high)
    }

    func testCalibratingStrapHasNoBar() throws {
        var hrv = try XCTUnwrap(PFBandParse.strapHRV(json(strapDoc)))
        hrv.bandLow = nil
        XCTAssertNil(PFBandLogic.strapBar(hrv))
        XCTAssertEqual(PFBandLogic.strapStateWord("calibrating"), "Calibrating")
        XCTAssertEqual(PFBandLogic.strapStateWord("in_band"), "In your range")
    }

    // MARK: Healthspan inputs

    private let inputPanel = """
    {"present": 3, "total": 4, "needed": 2, "enough": true, "status_text": "3 of 4 inputs have data; at least 2 are needed",
     "inputs": [{"key": "vo2max", "label": "VO2max", "present": false, "value_text": null, "target_text": "47", "status": "unknown", "years": null,
                 "source": "Garmin", "gloss": "Fitness.", "fix": "Record a few runs with heart rate."},
                {"key": "resting_hr", "label": "Resting heart rate", "present": true, "value_text": "52 bpm", "target_text": "55", "status": "good",
                 "years": -1.2, "source": "WHOOP strap", "gloss": "Heart.", "fix": null},
                {"key": "steps", "label": "Steps", "present": true, "value_text": "6,100", "target_text": "8,000", "status": "short",
                 "years": 0.4, "source": "Garmin", "gloss": "Walking.", "fix": null},
                {"key": "sleep_duration", "label": "Sleep duration", "present": true, "value_text": "7h", "target_text": "7-9h", "status": "good",
                 "years": -0.1, "source": "Garmin", "gloss": "Sleep.", "fix": null}],
     "holding_back": {"key": "vo2max", "label": "VO2max", "half_width_years": 2.5, "reason": "VO2max has no data, which widens the range."}}
    """

    func testTheInputPanelListsPresentAndMissingInputsAndTheTopMovers() throws {
        let panel = try XCTUnwrap(PFBandParse.inputPanel(json(inputPanel)))
        XCTAssertEqual(panel.present, 3)
        XCTAssertEqual(panel.missing.map { $0.key }, ["vo2max"])
        XCTAssertEqual(panel.missing.first?.fix, "Record a few runs with heart rate.")
        XCTAssertEqual(panel.movers.map { $0.key }, ["resting_hr", "steps", "sleep_duration"])
        XCTAssertEqual(panel.holdingBack, "VO2max has no data, which widens the range.")
    }

    func testAnAbsentInputPanelIsNil() {
        XCTAssertNil(PFBandParse.inputPanel(json("{}")))
        XCTAssertNil(PFBandParse.inputPanel(json("{\"inputs\": []}")))
    }

    func testTheHealthspanDocumentCarriesItsInputPanel() throws {
        let metric = "{\"body_age\": {\"low\": 34.0, \"high\": 38.0, \"mid\": 36.0}, \"input_panel\": \(inputPanel)}"
        let healthspan = try XCTUnwrap(PFIntelDocsParse.healthspan(json(metric)))
        XCTAssertEqual(healthspan.inputPanel?.total, 4)
    }

    func testAnOlderHealthspanHasNoInputPanel() throws {
        let healthspan = try XCTUnwrap(PFIntelDocsParse.healthspan(json("{\"body_age\": {\"low\": 34.0, \"high\": 38.0}}")))
        XCTAssertNil(healthspan.inputPanel)
    }

    // MARK: Graded health watch

    private let graded = """
    {"level": "watch", "text": "Keep an eye on it.", "basis": "Vitals outside median +/- 1.4826 x MAD.", "cap_reason": null,
     "metrics": [{"key": "resting_hr", "label": "Resting heart rate", "status": "elevated", "z": 1.8, "counts": true,
                  "text": "resting heart rate 6 bpm above your usual, usual 50-56"},
                 {"key": "spo2", "label": "Blood oxygen", "status": "low", "z": -1.5, "counts": false, "text": "blood oxygen 2 % below your usual"}]}
    """

    func testTheGradedWatchKeepsItsLevelAndEachVitalInWords() throws {
        let watch = try XCTUnwrap(PFBandParse.graded(json(graded)))
        XCTAssertEqual(watch.level, "watch")
        XCTAssertEqual(watch.metrics.map { $0.key }, ["resting_hr", "spo2"])
        XCTAssertEqual(watch.metrics[0].text, "resting heart rate 6 bpm above your usual, usual 50-56")
    }

    func testALevelTheAppDoesNotKnowIsDropped() {
        XCTAssertNil(PFBandParse.graded(json("{\"level\": \"panic\", \"metrics\": []}")))
        XCTAssertNil(PFBandParse.graded(json("{}")))
    }

    func testTheHealthMonitorCarriesTheGradedWatch() throws {
        let metric = """
        {"vitals": [{"key": "hrv", "label": "HRV", "available": true, "value": 50, "typical": {"low": 40, "high": 60, "center": 50}, "z": 0.1}],
         "graded": \(graded)}
        """
        let health = try XCTUnwrap(PFDailyIntelParse.health(json(metric)))
        XCTAssertEqual(health.graded?.level, "watch")
    }

    func testAnOlderHealthMonitorHasNoGradedWatch() throws {
        let metric = "{\"vitals\": [{\"key\": \"hrv\", \"label\": \"HRV\", \"available\": true, \"value\": 50}]}"
        let health = try XCTUnwrap(PFDailyIntelParse.health(json(metric)))
        XCTAssertNil(health.graded)
    }

    // MARK: The snapshot

    func testTheSnapshotInsightsCarryLoadFocusTargetAndMuscularLoad() throws {
        var raw = PFRawBundle()
        raw.state = json("{\"generated_at\": \"2030-03-13T08:00:00\"}")
        raw.fitness = json("{\"load\": {\"load_focus_panel\": \(loadFocus)}, \"strength\": {\"muscular_load\": \(muscular)}}")
        raw.projection = json("{\"week_target\": \(weekTarget)}")
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
        XCTAssertEqual(snapshot.insights.loadFocus?.buckets.count, 3)
        XCTAssertEqual(snapshot.insights.weekTarget?.weeks.count, 2)
        XCTAssertEqual(snapshot.insights.muscular?.top.count, 3)
    }

    func testTheSnapshotOfAnOlderServerHasNoneOfThem() throws {
        var raw = PFRawBundle()
        raw.state = json("{\"generated_at\": \"2030-03-13T08:00:00\"}")
        raw.fitness = json("{\"load\": {}}")
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
        XCTAssertNil(snapshot.insights.loadFocus)
        XCTAssertNil(snapshot.insights.weekTarget)
        XCTAssertNil(snapshot.insights.muscular)
    }
}
