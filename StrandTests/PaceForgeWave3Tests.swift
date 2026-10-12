import XCTest
@testable import Strand

/// PaceForge's wave-3 documents decode leniently (every field optional, ints and doubles both fine), a
/// missing file hides its section, and the neutral wording and formats the screens depend on are exact.
/// All values are made up.
final class PaceForgeWave3Tests: XCTestCase {
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    // MARK: Race week

    private let raceWeekDoc = """
    {"generated_at":"2030-03-13T06:00:00","date":"2030-03-13","race_week":{
      "event":{"name":"Demo Half","date":"2030-03-18","goal_time":"1:45:00","priority":"A","location":"Nowhere","type":"half"},
      "days_to":5,"phase":"taper","volume_target_pct":60,"week_volume_cut_pct":40,"notes":["Keep it easy.","Sleep early."],
      "carb_load":{"g_per_kg_per_day":[8,10],"grams_per_day":640,"weight_kg":80,"tips":["Low fibre."],"label":"Carb load","note":"From Saturday."},
      "checklist":[{"id":"shoes","when":"Thursday","text":"Lay out shoes"},{"id":"gel","when":"Friday","text":"Buy gels"}],
      "race_morning":[{"t_minus_min":45,"text":"Warm-up jog"},{"t_minus_min":180,"text":"Breakfast"}],
      "suppresses_alerts":true,"recovery":{"day":null,"of_days":null,"suggestion":null}}}
    """

    func testRaceWeekReadsThePhaseDaysAndVolume() {
        let week = PFWave3Parse.raceWeek(json(raceWeekDoc), brief: PFJ(nil))
        XCTAssertEqual(week?.summaryLine, "Taper \u{00B7} 5 days to go \u{00B7} volume 60 %")
    }

    func testRaceWeekOrdersTheRaceMorningEarliestFirst() {
        let week = PFWave3Parse.raceWeek(json(raceWeekDoc), brief: PFJ(nil))
        XCTAssertEqual(week?.raceMorning.map(\.tMinusMin), [180, 45])
    }

    func testRaceMorningStepsReadAsTimeBefore() {
        XCTAssertEqual(PFRaceWeek.MorningStep(tMinusMin: 210, text: "x").whenText, "3 h 30 min before")
    }

    func testCarbLoadLineNamesTheRangeAndTheGrams() {
        let week = PFWave3Parse.raceWeek(json(raceWeekDoc), brief: PFJ(nil))
        XCTAssertEqual(week?.carbLoad?.line, "8\u{2013}10 g/kg a day, about 640 g a day at 80 kg")
    }

    func testRaceWeekIsAbsentWhenTheServerSaysNull() {
        let doc = json(#"{"date":"2030-03-13","race_week":null}"#)
        XCTAssertNil(PFWave3Parse.raceWeek(doc, brief: json(#"{"race_week":{"event":"Demo","phase":"taper","days_to":3}}"#)))
    }

    func testRaceWeekFallsBackToTheBriefSummaryWhenTheDocumentIsNotServed() {
        let brief = json(#"{"date":"2030-03-13","race_week":{"event":"Demo Half","date":"2030-03-18","phase":"taper","days_to":5,"volume_target_pct":60,"notes":["a","b"]}}"#)
        XCTAssertEqual(PFWave3Parse.raceWeek(PFJ(nil), brief: brief)?.isSummaryOnly, true)
    }

    func testTheDayAfterTheRaceHasNoCountdown() {
        let week = PFRaceWeek(date: nil, event: PFRaceWeek.Event(name: "x"), daysTo: -1, phase: "recovery")
        XCTAssertNil(week.daysText)
    }

    func testChecklistTicksAreKeptPerDay() {
        let defaults = UserDefaults(suiteName: "pf-wave3-ticks")!
        defaults.removePersistentDomain(forName: "pf-wave3-ticks")
        PFRaceWeekChecklist.toggle("shoes", date: "2030-03-13", defaults: defaults)
        XCTAssertEqual(PFRaceWeekChecklist.checked(date: "2030-03-14", defaults: defaults), [])
    }

    func testTickingTwiceUnticks() {
        let defaults = UserDefaults(suiteName: "pf-wave3-untick")!
        defaults.removePersistentDomain(forName: "pf-wave3-untick")
        PFRaceWeekChecklist.toggle("shoes", date: "2030-03-13", defaults: defaults)
        PFRaceWeekChecklist.toggle("shoes", date: "2030-03-13", defaults: defaults)
        XCTAssertEqual(PFRaceWeekChecklist.checked(date: "2030-03-13", defaults: defaults), [])
    }

    // MARK: Race simulations

    private let analysisDoc = """
    {"has_data":true,"count":2,"unmapped":[{"activity_id":1},{"activity_id":2}],
     "goal":{"event":"Demo Games","date":"2030-05-01","goal_seconds":4800,"goal_display":"1:20:00","basis":"Made up."},
     "fresh_run":{"pace_sec":270,"display":"4:30","n_runs":3,"basis":"Made up."},
     "latest":{"id":"sim-2","date":"2030-03-10","complete":true,"total_seconds":5000,"total_display":"1:23:20","notes":null,
       "run_fade_pct":6.5,"compromised_pct":4.2,"compromised_runs":[{"run":2,"seconds":300,"pct_slower":7.1}],
       "max_dev_pct":6.5,"within_band":false,"pacing_note":"Outside the band."},
     "segments":[{"name":"Run 1","display":"4:40","kind":"run","sim_seconds":280,"goal_seconds":270,"delta_goal_s":10,"prev_seconds":285,"delta_prev_s":-5},
                 {"name":"Ski erg","display":"4:10","kind":"station","sim_seconds":250,"goal_seconds":240,"delta_goal_s":10,"prev_seconds":null,"delta_prev_s":null}],
     "weakest":[{"station":"Sled push","display":"3:00","sim_seconds":180,"goal_seconds":150,"over_s":30,"over_pct":20,"suggestion":"More sled work."}]}
    """

    func testSimulationsReadTheLatestTotalAndTheGoal() {
        let sims = PFWave3Parse.hyroxSims(analysis: json(analysisDoc), sims: PFJ(nil))
        XCTAssertEqual(sims?.totalVsGoalS, 200)
    }

    func testSimulationsCountUnmappedGarminSessions() {
        XCTAssertEqual(PFWave3Parse.hyroxSims(analysis: json(analysisDoc), sims: PFJ(nil))?.unmappedCount, 2)
    }

    func testSimulationsKeepTheRunAndStationKinds() {
        let sims = PFWave3Parse.hyroxSims(analysis: json(analysisDoc), sims: PFJ(nil))
        XCTAssertEqual(sims?.segments.map(\.isRun), [true, false])
    }

    func testSimulationsAreAbsentWhenNeitherDocumentIsServed() {
        XCTAssertNil(PFWave3Parse.hyroxSims(analysis: PFJ(nil), sims: PFJ(nil)))
    }

    func testAServedEmptyAnalysisIsAnEmptyStateNotAbsence() {
        let sims = PFWave3Parse.hyroxSims(analysis: json(#"{"has_data":false,"count":0,"unmapped":[]}"#), sims: json(#"{"sims":[]}"#))
        XCTAssertEqual(sims?.hasData, false)
    }

    func testTheSimsListFillsTheLatestWhenTheAnalysisHasNone() {
        let sims = PFWave3Parse.hyroxSims(analysis: PFJ(nil), sims: json(#"{"sims":[{"id":"a","date":"2030-03-01","total_seconds":5100,"total_display":"1:25:00","segments":[]},{"id":"b","date":"2030-03-08","total_seconds":5000,"total_display":"1:23:20","segments":[{"name":"Run 1","kind":"run","display":"4:40","seconds":280}]}]}"#))
        XCTAssertEqual(sims?.latest?.id, "b")
    }

    func testSimDeltasAreSignedMinutesAndSeconds() {
        XCTAssertEqual(PFSimFormat.signed(-5), "\u{2212}0:05")
    }

    func testSimClockPassesAnHour() {
        XCTAssertEqual(PFSimFormat.clock(4_000), "1:06:40")
    }

    // MARK: Easy mode

    func testEasyModeReadsTheDayAndTheReturnDate() {
        let doc = json(#"{"mode":{"level":2,"label":"Easy week","summary":"Quality sessions swapped.","started":"2030-03-12","until":"2030-03-18","day":2,"of_days":7,"days_left":5,"returns_on":"2030-03-19","changed_sessions":["s-1","s-2"],"restorable":true},"pending":[],"levels":[{"level":1,"label":"Light","summary":"x"}],"days":{"min":2,"max":14,"default":7},"history":[]}"#)
        XCTAssertEqual(PFWave3Parse.easyMode(doc, stateMode: PFJ(nil))?.mode?.dayText, "Day 2 of 7")
    }

    func testEasyModeNamesTheChangedSessions() {
        let doc = json(#"{"mode":{"level":2,"label":"Easy week","changed_sessions":["s-1",{"session_id":"s-2"}]},"pending":[]}"#)
        XCTAssertEqual(PFWave3Parse.easyMode(doc, stateMode: PFJ(nil))?.mode?.changedSessionIds, ["s-1", "s-2"])
    }

    func testEasyModeAcceptsAChangedSessionsCount() {
        let doc = json(#"{"mode":{"level":1,"label":"Light","changed_sessions":3},"pending":[]}"#)
        XCTAssertEqual(PFWave3Parse.easyMode(doc, stateMode: PFJ(nil))?.mode?.changedCount, 3)
    }

    func testEasyModePendingProposalsKeepTheirTitle() {
        let doc = json(#"{"mode":null,"pending":[{"proposal_id":"p1","level":2,"days":5,"until":"2030-03-18","title":"Easy for 5 days"}]}"#)
        XCTAssertEqual(PFWave3Parse.easyMode(doc, stateMode: PFJ(nil))?.pending.first?.title, "Easy for 5 days")
    }

    func testAServedEasyModeWithNothingActiveIsIdle() {
        XCTAssertEqual(PFWave3Parse.easyMode(json(#"{"mode":null,"pending":[]}"#), stateMode: PFJ(nil))?.isIdle, true)
    }

    func testEasyModeIsAbsentOnAServerThatHasNeither() {
        XCTAssertNil(PFWave3Parse.easyMode(PFJ(nil), stateMode: PFJ(nil)))
    }

    func testEasyModeFallsBackToTheStateMode() {
        let mode = json(#"{"level":3,"label":"Rest","started":"2030-03-12","until":"2030-03-14","day":1,"of_days":3,"pending":0}"#)
        XCTAssertEqual(PFWave3Parse.easyMode(PFJ(nil), stateMode: mode)?.mode?.label, "Rest")
    }

    // MARK: Muscle check and tape

    func testMuscleCheckReadsACalibratingFlag() {
        let doc = json(#"{"has_data":true,"stale":false,"lean":{"current_trend_kg":62.1,"noise_kg":0.4,"readings":4},"flag":{"raised":false,"status":"calibrating","rule":"Needs 8 readings."}}"#)
        XCTAssertEqual(PFWave3Parse.muscleCheck(doc)?.isCalibrating, true)
    }

    func testMuscleCheckKeepsTheSplitWindowsInOrderWithTheirQuality() {
        let doc = json(#"{"has_data":true,"split":{"28d":{"days":28,"weight_kg":-0.8,"lean_kg":-0.1,"fat_kg":-0.7,"lean_share_pct":12,"quality":"noisy"},"14d":{"days":14,"weight_kg":-0.4,"lean_kg":0,"fat_kg":-0.4,"lean_share_pct":0,"quality":"estimate"}}}"#)
        XCTAssertEqual(PFWave3Parse.muscleCheck(doc)?.splits.map(\.quality), ["estimate", "noisy"])
    }

    func testMuscleCheckReadsTheAdviceLines() {
        let doc = json(#"{"has_data":true,"advice":[{"id":"protein","severity":"info","text":"Keep protein up."}]}"#)
        XCTAssertEqual(PFWave3Parse.muscleCheck(doc)?.advice.map(\.text), ["Keep protein up."])
    }

    func testMuscleCheckProteinAsARange() {
        XCTAssertEqual(PFWave3Parse.muscleCheck(json(#"{"has_data":true,"protein_g":[125,155]}"#))?.proteinText, "125\u{2013}155 g")
    }

    func testTapeKeepsSitesInTheirFixedOrder() {
        let doc = json(#"{"readings":[],"trend":{"thigh":{"latest":55},"waist":{"latest":82,"change_28d_cm":-1.2,"enough":true}}}"#)
        XCTAssertEqual(PFWave3Parse.tape(doc)?.sites.map(\.key), ["waist", "thigh"])
    }

    func testTapeReadsTheWaistToHipRatio() {
        let doc = json(#"{"readings":[],"trend":{},"waist_to_hip":{"ratio":0.85,"waist":82,"hips":96.5,"date":"2030-03-12"}}"#)
        XCTAssertEqual(PFWave3Parse.tape(doc)?.waistToHip?.ratio, 0.85)
    }

    func testTapeWithNoReadingsHasNoData() {
        XCTAssertEqual(PFWave3Parse.tape(json(#"{"readings":[],"trend":{},"waist_to_hip":null}"#))?.hasData, false)
    }

    func testSignedFiguresUseAMinusSignAndNoColourWord() {
        XCTAssertEqual(PFNumber.signed(-1.24), "\u{2212}1.2")
    }

    func testAFigureThatRoundsToNothingHasNoSign() {
        XCTAssertEqual(PFNumber.signed(-0.04), "0.0")
    }

    // MARK: Heat

    func testHeatChipNamesTheTemperatureLevelAndPaceCost() {
        let heat = PFWave3Parse.heat(json(#"{"temp_c":24.4,"feels_c":27.2,"humidity":70,"level":"hot","pace_cost_pct":3,"source":"weather"}"#))
        XCTAssertEqual(heat?.chipText, "24\u{00B0} (feels 27\u{00B0}) \u{00B7} hot \u{00B7} pace +3 %")
    }

    func testAMildDayIsNotHot() {
        XCTAssertEqual(PFWave3Parse.heat(json(#"{"temp_c":12,"level":"mild","pace_cost_pct":0}"#))?.isHot, false)
    }

    func testAPaceCostMakesADayHotWhateverTheLevelSays() {
        XCTAssertEqual(PFWave3Parse.heat(json(#"{"temp_c":20,"level":"unknown","pace_cost_pct":2}"#))?.isHot, true)
    }

    func testNullHeatIsAbsent() {
        XCTAssertNil(PFWave3Parse.heat(json("null")))
    }

    // MARK: Estimate labels

    func testSegmentalMetaIsAnEstimateOnlyWhenTheServerSaysSo() {
        XCTAssertEqual(PFWave3Parse.segmentalMeta(json(#"{"estimate":true,"method":"share","clamp_pct":5,"note":"n","share_right":0.51}"#))?.estimate, true)
    }

    func testSegmentalMetaIsAbsentWhenTheServerSendsNone() {
        XCTAssertNil(PFWave3Parse.segmentalMeta(PFJ(nil)))
    }

    // MARK: Privacy

    func testTheServerDefaultAppliesWhenThereIsNoOverride() {
        XCTAssertFalse(PFPrivacy.hidesBody(server: false, override: nil))
    }

    func testTheOverrideBeatsTheServer() {
        XCTAssertTrue(PFPrivacy.hidesBody(server: false, override: true))
    }

    func testBodyIsHiddenWhenNeitherSaysAnything() {
        XCTAssertTrue(PFPrivacy.hidesBody(server: nil, override: nil))
    }

    func testPrivacyIsReadFromTheStatesSettings() {
        XCTAssertEqual(PFWave3Parse.hidesBodyOnLockScreen(json(#"{"settings":{"privacy":{"hide_body_on_lock_screen":false}}}"#)), false)
    }

    // MARK: Intraday

    private let intradayDoc = """
    {"date":"2030-03-13","body_battery":[[1899590400000,40],[1899594000000,55]],"stress":[[1899590400000,30],[1899594000000,-1]],
     "steps":null,"hr":null,"source":"garmin","fetched_at":"2030-03-13T08:00:00","final":false,"tz":"UTC",
     "latest":{"body_battery":{"time":1899594000000,"level":55},"stress":null},
     "last_recharge":{"time":1899594000000,"start":1899583200000,"from":22,"to":55,"minutes":120}}
    """

    func testIntradayConvertsMillisecondsToSeconds() {
        XCTAssertEqual(PFWave3Parse.intraday(json(intradayDoc))?.energy.first?.ts, 1_899_590_400)
    }

    func testIntradayDropsGarminsNoReadingStress() {
        XCTAssertEqual(PFWave3Parse.intraday(json(intradayDoc))?.stress.count, 1)
    }

    func testIntradayReadsTheLastRecharge() {
        XCTAssertEqual(PFWave3Parse.intraday(json(intradayDoc))?.lastRecharge?.minutes, 120)
    }

    func testIntradayWithNothingInItIsAbsent() {
        XCTAssertNil(PFWave3Parse.intraday(json(#"{"date":"2030-03-13","body_battery":[],"stress":[],"steps":null,"hr":null,"final":true}"#)))
    }

    // MARK: Day events

    private let dayEventsDoc = """
    {"generated_at":"x","tz":"UTC","today":"2030-03-13","days":["2030-03-13"],"events":[
      {"id":"e1","kind":"planned","date":"2030-03-13","start":"2030-03-13T07:30:00+00:00","end":null,"all_day":false,"title":"Synthetic intervals","sources":[],"matched_activity_id":null,"matched_session_id":"s-wed","state":"planned","session_id":"s-wed","workout_type":"intervals","duration_min":55},
      {"id":"e2","kind":"planned","date":"2030-03-13","start":"2030-03-13","end":null,"all_day":true,"title":"Synthetic mobility","state":"planned","session_id":"s-wed2","duration_min":30},
      {"id":"e3","kind":"weighIn","date":"2030-03-13","start":"2030-03-13T06:45:00+00:00","all_day":false,"title":"Weigh-in","weight_kg":78.7,"body_fat_pct":17.8},
      {"id":"e4","kind":"note","date":"2030-03-13","start":"2030-03-13","all_day":true,"title":"Niggle","niggle":{"id":"n1","site":"calf","side":"left","severity":2,"movements":["running"],"resolved":false}}]}
    """

    func testDayEventsGiveATimedPlannedSessionItsSlot() {
        XCTAssertEqual(PFWave3Parse.dayEvents(json(dayEventsDoc)).first?.startTs, 1_899_617_400)
    }

    func testAnAllDayPlannedSessionHasNoSlot() {
        XCTAssertNil(PFWave3Parse.dayEvents(json(dayEventsDoc))[1].startTs)
    }

    func testDayEventsReadAWeighInTimeAndWeight() {
        XCTAssertEqual(PFWave3Parse.dayEvents(json(dayEventsDoc))[2].weightKg, 78.7)
    }

    func testDayEventsReadANiggleNote() {
        XCTAssertEqual(PFWave3Parse.dayEvents(json(dayEventsDoc))[3].niggleSite, "calf")
    }

    func testABareDateIsNotATime() {
        XCTAssertNil(PFStamp.parse("2030-03-13"))
    }
}

/// The bundled text behind the (i) buttons of the wave-3 cards.
final class PaceForgeLocalExplainerTests: XCTestCase {
    func testEveryWave3CardHasABundledExplainer() {
        let ids = [PFLocalExplainers.raceWeek, PFLocalExplainers.raceSims, PFLocalExplainers.easyMode,
                   PFLocalExplainers.muscleCheck, PFLocalExplainers.tape, PFLocalExplainers.heat]
        XCTAssertEqual(ids.filter { PFLocalExplainers.fallback[$0]?.plain != nil }.count, ids.count)
    }

    func testTheExplainerIdsAreDistinct() {
        XCTAssertEqual(PFLocalExplainers.fallback.count, 6)
    }
}
