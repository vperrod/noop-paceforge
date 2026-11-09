import XCTest
@testable import Strand

/// The HYROX screen's documents and wording, and what the phone no longer shows (a predicted finish, the top 3, a field figure).
/// Synthetic values only: every date, city and time below is made up, because this repository is public.
final class PaceForgeHyroxTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    // MARK: Documents

    private let planDoc = Data("""
    {"events": [{"id": "2030-04-20", "name": "HYROX Testville", "date": "2030-04-20", "days_out": 38, "goal_time": "1:10:00",
                 "format": "singles", "division": "open", "priority": "A"},
                {"id": "2030-06-01", "name": "HYROX Sampleton", "date": "2030-06-01", "days_out": 80, "goal_time": "",
                 "format": "singles", "division": "open", "priority": "B"}],
     "event": {"id": "2030-04-20", "name": "HYROX Testville", "date": "2030-04-20", "days_out": 38, "goal_time": "1:10:00",
               "format": "singles", "division": "open", "priority": "A"},
     "available": true, "reason": null, "venue": "Testville", "races_on_file": 3, "lap_profile": true,
     "format": {"discipline": "hyrox", "format": "singles", "division": "open", "category": "open"}, "goal_s": 4200,
     "runs": [{"key": "Running_1", "name": "Run 1", "target_s": 300, "ceiling_s": 290, "band_s": [285, 315]},
              {"key": "Running_2", "name": "Run 2", "target_s": 310, "ceiling_s": 300, "band_s": [295, 325]},
              {"key": "Running_8", "name": "Run 8", "target_s": 330, "ceiling_s": null, "band_s": null}],
     "stations": [{"key": "SkiErg_1000m", "name": "SkiErg", "realistic_s": 240, "stretch_s": 225, "bad_s": 255, "spread_s": 30,
                   "bias_s": -4, "save_s": 15, "swing": false},
                  {"key": "Sled_Push_50m", "name": "Sled Push", "realistic_s": 200, "stretch_s": 180, "bad_s": 230, "spread_s": 50,
                   "bias_s": 6, "save_s": 20, "swing": true}],
     "roxzone": {"key": "Roxzone_Time", "name": "Roxzone", "realistic_s": 400, "stretch_s": 380, "bad_s": 430, "spread_s": 50,
                 "bias_s": 0, "save_s": 0, "swing": false},
     "base": {"Running_1": 300, "SkiErg_1000m": 240, "Running_2": 310, "Sled_Push_50m": 200, "Running_8": 330, "Roxzone_Time": 400},
     "swing": ["Sled Push"], "available_s": 35, "garmin_10k": {"seconds": 3000.0, "date": "2030-03-30"},
     "your_plan": {"plan": {"Running_1": 290, "SkiErg_1000m": 245, "Running_2": 310, "Sled_Push_50m": 200, "Running_8": 330,
                            "Roxzone_Time": 400}, "locked": ["Running_2"], "updated": "2030-04-01T09:00:00"},
     "pack": {"updated": 1900000000.0, "sections": [{"title": "Goal & Plan A/B", "md": "Goal text"}, {"title": "Warm-up", "md": "Warm text"},
              {"title": "Kit list", "md": "Kit"}, {"title": "Mental cues", "md": "Cues"}, {"title": "If it goes wrong", "md": "Fix"}]}}
    """.utf8)

    private var plan: PFHyroxPlan? { PFHyroxParse.plan(planDoc) }

    private let resultsDoc = Data("""
    {"races": [{"id": "2030-03-10-testville", "date": "2030-03-10", "city": "Testville", "division": "open", "total_s": 4400,
                "total_display": "1:13:20", "runs_s": 2000, "stations_s": 1700, "roxzone_s": 400,
                "laps": [250, 250, 250, 250, 250, 250, 250, null],
                "stations": [{"key": "SkiErg_1000m", "name": "SkiErg", "s": 230}, {"key": "Sled_Push_50m", "name": "Sled Push", "s": 190}],
                "flags": ["Uneven laps: a lap far shorter than the rest"], "artefact": true},
               {"id": "2029-11-02-sampleton", "date": "2029-11-02", "city": "Sampleton", "division": "open", "total_s": 4600,
                "total_display": null, "runs_s": null, "stations_s": null, "roxzone_s": null, "laps": [], "stations": [],
                "flags": [], "artefact": false}],
     "performance": {
       "stations": [{"key": "SkiErg_1000m", "name": "SkiErg", "best_s": 225, "median_s": 235, "last_s": 230, "swing_s": 15,
                     "change_s": -5, "races": 3, "series": [{"date": "2029-01-01", "s": 240}, {"date": "2029-11-02", "s": 235}, {"date": "2030-03-10", "s": 230}]},
                    {"key": "Sled_Push_50m", "name": "Sled Push", "best_s": 180, "median_s": 190, "last_s": 200, "swing_s": 20,
                     "change_s": null, "races": 1, "series": [{"date": "2030-03-10", "s": 200}]}],
       "roxzone": {"best_s": 380, "median_s": 400, "last_s": 410, "swing_s": 30, "change_s": 10, "races": 3,
                   "series": [{"date": "2030-03-10", "s": 410}]},
       "runs": {"lap_clean_races": 2, "of": 3, "band_pct": 4.5, "first_three_vs_laps_4_7_pct": -2.5, "run8_vs_laps_4_7_pct": 6.0,
                "per_race": [{"date": "2030-03-10", "city": "Testville", "spread_pct": 3.2, "run8_vs_steady_pct": 5.0}]},
       "where_the_time_is": {"race": "Testville 2030-03-10", "rows": [{"name": "Sled Push", "over_best_s": 20}, {"name": "SkiErg", "over_best_s": 5}],
                             "total_s": 25}}}
    """.utf8)

    private var results: PFHyroxResults? { PFHyroxParse.results(resultsDoc) }

    // MARK: Paths

    func testTheRacePlanOfOneRaceCarriesItsDateAsAQuery() {
        XCTAssertEqual(PFHyroxDoc.racePlanPath(event: "2030-04-20"), "api/hyrox/race-plan?event=2030-04-20")
    }

    func testTheRacePlanOfTheNextRaceHasNoQuery() {
        XCTAssertEqual(PFHyroxDoc.racePlanPath(event: nil), "api/hyrox/race-plan")
    }

    // MARK: Next race

    func testThePickerListsTheUpcomingRacesAndThePlanNamesTheNextOne() {
        XCTAssertEqual(plan?.events.map(\.pickerLabel), ["Testville \u{00B7} 20 Apr", "Sampleton \u{00B7} 1 Jun"])
    }

    func testTheNextRaceIsTheEventTheServerNames() {
        XCTAssertEqual(plan?.event?.id, "2030-04-20")
    }

    func testTheCountdownReadsTheDaysToGo() {
        XCTAssertEqual([plan?.event?.countdownValue, plan?.event?.countdownUnit], ["38", "days"])
    }

    func testTheCountdownOnRaceDayReadsToday() {
        let today = PFHyroxEvent(id: "a", name: "HYROX Testville", date: "2030-04-20", daysOut: 0, goalTime: nil, format: nil, division: nil, priority: nil)
        XCTAssertEqual(today.countdownValue, "Today")
    }

    func testTheRaceFactsListDayGoalFormatAndPriority() {
        XCTAssertEqual(plan?.event?.facts, ["Sat 20 Apr", "goal 1:10:00", "singles open", "priority A"])
    }

    func testARunKeepsItsCeilingAndItsSteadyBand() {
        XCTAssertEqual([plan?.runs[0].ceilingS, plan?.runs[0].bandLowS, plan?.runs[0].bandHighS], [290, 285, 315])
    }

    func testTheBandReadsAsARange() {
        XCTAssertEqual(plan?.runs[0].bandText, "4:45\u{2013}5:15")
    }

    func testALapWithoutACeilingOrBandReadsAsNone() {
        XCTAssertNil(plan?.runs[2].bandText)
    }

    func testAStationCarriesItsThreeLevelsAndWhetherItSwings() {
        let sled = plan?.stations[1]
        XCTAssertEqual([sled?.realisticS, sled?.stretchS, sled?.badS, sled?.spreadS, sled?.biasS], [200, 180, 230, 50, 6])
    }

    func testOnlyTheSwingingStationIsMarkedAsSwinging() {
        XCTAssertEqual(plan?.stationsWithSwing.map(\.name), ["Sled Push"])
    }

    func testTheRoxzoneIsParsedLikeAStation() {
        XCTAssertEqual(plan?.roxzone?.realisticS, 400)
    }

    func testTheGarminTenKilometreCrossCheckReadsItsTimeDateAndPace() {
        XCTAssertEqual(plan?.garmin10K?.line,
                       "Running-fitness cross-check: Garmin's 10K prediction is 50:00 (Garmin, 30 Mar) (= 5:00/km).")
    }

    func testWhereTheTimeIsListsTheStationsWhereHisBestIsFasterWidestFirst() {
        XCTAssertEqual(plan.flatMap(PFHyroxFormat.timeToFindLine),
                       "Where the time is (your best against your Testville split): Sled Push 20 s, SkiErg 15 s = 35 s.")
    }

    func testTheLevelsHintNamesTheVenueSplitAndTheRacesOnFile() {
        XCTAssertTrue(PFHyroxFormat.levelsHint(venue: "Testville", racesOnFile: 3).hasPrefix("Realistic is your Testville split,"))
    }

    func testAVenueWithUnevenLapsSaysARunIsALapTime() {
        XCTAssertEqual(PFHyroxFormat.runsHint(venue: "Testville", lapProfile: true),
                       "Testville is this venue's profile: its laps are uneven, so a run is a lap time, not a pace per km.")
    }

    func testEvenLapsSayARunIsOneKilometre() {
        XCTAssertEqual(PFHyroxFormat.runsHint(venue: nil, lapProfile: false), "Targets are your own times; a run is one even km.")
    }

    func testThePackShowsGoalWarmUpCuesAndIfItGoesWrongFirst() {
        XCTAssertEqual(plan?.pack?.main.map(\.title), ["Goal & Plan A/B", "Warm-up", "Mental cues", "If it goes wrong"])
    }

    func testThePackFoldsTheOtherSections() {
        XCTAssertEqual(plan?.pack?.rest.map(\.title), ["Kit list"])
    }

    // MARK: No race, no pacing, no answer

    private let noRaceDoc = Data("{\"events\": [], \"event\": null, \"available\": false, \"reason\": \"no upcoming HYROX race on file\"}".utf8)

    func testNoUpcomingRaceIsAPlanWithNoEvent() throws {
        XCTAssertNil(try XCTUnwrap(PFHyroxParse.plan(noRaceDoc)).event)
    }

    func testNoUpcomingRaceKeepsItsReason() throws {
        XCTAssertEqual(try XCTUnwrap(PFHyroxParse.plan(noRaceDoc)).reason, "no upcoming HYROX race on file")
    }

    func testARaceWithoutPacingIsNotAvailableAndSaysWhy() throws {
        let doc = Data("""
        {"events": [{"id": "2030-04-20", "name": "HYROX Testville", "date": "2030-04-20", "days_out": 38}],
         "event": {"id": "2030-04-20", "name": "HYROX Testville", "date": "2030-04-20", "days_out": 38},
         "available": false, "reason": "no HYROX results on file to build the paces from"}
        """.utf8)
        let parsed = try XCTUnwrap(PFHyroxParse.plan(doc))
        XCTAssertEqual([parsed.available, parsed.stations.isEmpty], [false, true])
    }

    func testAnAnswerThatIsNotAnObjectIsNotAPlan() {
        XCTAssertNil(PFHyroxParse.plan(Data("[]".utf8)))
    }

    func testNothingAtAllIsNotAPlan() {
        XCTAssertNil(PFHyroxParse.plan(nil))
    }

    // MARK: Your plan

    func testASavedPlanThatNamesTheSameSegmentsFits() {
        XCTAssertEqual(plan?.savedPlanFits, true)
    }

    func testASavedPlanMissingASegmentIsOutOfDate() throws {
        var parsed = try XCTUnwrap(plan)
        parsed.yourPlan = PFHyroxSavedPlan(values: ["Running_1": 290], locked: [], updated: nil)
        XCTAssertTrue(parsed.savedPlanIsStale)
    }

    func testNoSavedPlanIsNotOutOfDate() throws {
        var parsed = try XCTUnwrap(plan)
        parsed.yourPlan = nil
        XCTAssertFalse(parsed.savedPlanIsStale)
    }

    func testThePlanRowsRunInRaceOrderBesideRealistic() {
        XCTAssertEqual(plan?.planRows.map(\.key), ["Running_1", "SkiErg_1000m", "Running_2", "Sled_Push_50m", "Running_8", "Roxzone_Time"])
    }

    func testAPlanRowStatesTheChangeAgainstRealistic() {
        XCTAssertEqual(plan?.planRows.map(\.deltaS), [-10, 5, 0, 0, 0, 0])
    }

    func testThePlanTotalAddsUpEverySegment() {
        XCTAssertEqual(plan?.planTotalS, 1775)
    }

    func testRealisticTotalAddsUpEverySegment() {
        XCTAssertEqual(plan?.realisticTotalS, 1780)
    }

    func testTheLockedSegmentsAreMarked() {
        XCTAssertEqual(plan?.planRows.filter(\.isLocked).map(\.key), ["Running_2"])
    }

    // MARK: Results

    func testResultsListEveryRaceNewestFirstAsTheServerSentThem() {
        XCTAssertEqual(results?.races.map(\.title), ["Testville", "Sampleton"])
    }

    func testARaceReadsItsFinishAsTheServerPrintedIt() {
        XCTAssertEqual(results?.races[0].finishText, "1:13:20")
    }

    func testARaceWithoutAPrintedFinishReadsItFromSeconds() {
        XCTAssertEqual(results?.races[1].finishText, "1:16:40")
    }

    func testTheRaceSummaryLineNamesRunsStationsAndRoxzone() {
        XCTAssertEqual(results?.races[0].summaryLine, "Runs 33:20 \u{00B7} Stations 28:20 \u{00B7} Roxzone 6:40")
    }

    func testAMissingSplitReadsAsADash() {
        XCTAssertEqual(results?.races[1].summaryLine, "Runs \u{2013} \u{00B7} Stations \u{2013} \u{00B7} Roxzone \u{2013}")
    }

    func testARaceHasEightLaps() {
        XCTAssertEqual(results?.races[0].laps.count, 8)
    }

    func testALapTheTimingDidNotRecordIsNil() throws {
        let race = try XCTUnwrap(results?.races[0])
        XCTAssertNil(race.laps[7])
    }

    func testARaceKeepsItsStationsInOrder() {
        XCTAssertEqual(results?.races[0].stations.map(\.name), ["SkiErg", "Sled Push"])
    }

    func testARaceWithTimingFlagsIsAnArtefact() {
        XCTAssertEqual(results?.races.map(\.artefact), [true, false])
    }

    func testTheRaceSubtitleNamesTheDayAndTheDivision() {
        XCTAssertEqual(results?.races[0].subtitle, "Sun 10 Mar \u{00B7} open")
    }

    func testTheBestFinishIsTheFastestRaceOnFile() {
        XCTAssertEqual(results?.bestFinish, "1:13:20")
    }

    func testResultsThatAreNotAnObjectAreNotResults() {
        XCTAssertNil(PFHyroxParse.results(Data("[]".utf8)))
    }

    // MARK: Performance

    func testAStationSeriesKeepsBestMedianLastAndSwing() {
        let ski = results?.stations[0]
        XCTAssertEqual([ski?.bestS, ski?.medianS, ski?.lastS, ski?.swingS], [225, 235, 230, 15])
    }

    func testAStationSeriesRunsOldestToNewest() {
        XCTAssertEqual(results?.stations[0].points, [240, 235, 230])
    }

    func testTheLastRaceAgainstUsualIsSigned() throws {
        let ski = try XCTUnwrap(results?.stations[0])
        XCTAssertEqual(PFHyroxFormat.againstUsual(ski), "\u{2212}5 s vs usual")
    }

    func testAFirstRaceHasNoChangeAgainstUsual() throws {
        let sled = try XCTUnwrap(results?.stations[1])
        XCTAssertNil(PFHyroxFormat.againstUsual(sled))
    }

    func testTheRoxzoneSeriesIsNamedRoxzone() {
        XCTAssertEqual(results?.roxzone?.name, "Roxzone")
    }

    func testTheLapNoteSaysWhatTheRunsDoAcrossTheCleanRaces() {
        XCTAssertEqual(results?.runs.map(PFHyroxFormat.lapNote),
                       "Across your 2 lap-clean races (of 3): laps 2 to 7 stay within 4.5 % of the median lap; "
                       + "your first three laps average 2.5 % faster than laps 4 to 7; Run 8 is 6 % slower than laps 4 to 7.")
    }

    func testWithoutACleanRaceTheLapNoteSaysSo() {
        let none = PFHyroxRunStats(lapCleanRaces: 0, of: 2, bandPct: nil, firstThreePct: nil, run8Pct: nil, perRace: [])
        XCTAssertEqual(PFHyroxFormat.lapNote(none), "No race with usable lap times yet (laps cut short by the timing mats are left out).")
    }

    func testThePerRaceRunFadeIsSigned() {
        XCTAssertEqual(PFHyroxFormat.percent(3.2), "+3.2 %")
    }

    func testWhereTheTimeIsNamesTheRaceTheStationsAndTheTotal() {
        XCTAssertEqual(results?.timeLoss?.line,
                       "In Testville 2030-03-10 you were over your own best by Sled Push 20 s, SkiErg 5 s = 25 s.")
    }

    func testNoStationOverItsBestGivesNoLine() {
        XCTAssertNil(PFHyroxTimeLoss(race: "Testville", rows: [], totalS: 0).line)
    }

    // MARK: Wording

    func testASecondsFigureReadsAsMinutesAndSeconds() {
        XCTAssertEqual(PFHyroxFormat.clock(272), "4:32")
    }

    func testAMissingOrZeroTimeReadsAsADash() {
        XCTAssertEqual([PFHyroxFormat.clock(nil), PFHyroxFormat.clock(0)], ["\u{2013}", "\u{2013}"])
    }

    func testAChangeIsSignedWithAProperMinus() {
        XCTAssertEqual([PFHyroxFormat.signed(5), PFHyroxFormat.signed(-3), PFHyroxFormat.signed(0)], ["+5 s", "\u{2212}3 s", "\u{00B1}0 s"])
    }

    // MARK: Training for HYROX

    private func session(_ id: String, _ date: String, _ name: String, kind: String?) -> PFWorkout {
        PFWorkout(id: id, date: date, status: "planned", name: name, kind: kind)
    }

    private func week(_ sessions: [PFWorkout]) -> PFWeek {
        PFWeek(key: "w", start: "2030-03-11", end: "2030-03-24",
               days: sessions.map { PFDay(date: $0.date, dow: "", workouts: [$0]) })
    }

    func testStrengthAndHyroxSessionsAreHyroxTraining() {
        XCTAssertEqual([session("a", "d", "Legs", kind: "strength"), session("b", "d", "Sim", kind: "hyrox_simulation")].map(PFHyroxTraining.isHyroxSession),
                       [true, true])
    }

    func testACompromisedRunIsHyroxTrainingByName() {
        XCTAssertTrue(PFHyroxTraining.isHyroxSession(session("a", "d", "Compromised run", kind: "tempo")))
    }

    func testAnEasyRunIsNotHyroxTraining() {
        XCTAssertFalse(PFHyroxTraining.isHyroxSession(session("a", "d", "Easy run", kind: "easy_run")))
    }

    func testTheSessionKindsReadInWords() {
        let kinds = [session("a", "d", "x", kind: "hyrox_simulation"), session("b", "d", "x", kind: "hyrox_station_day"),
                     session("c", "d", "x", kind: "strength"), session("d", "d", "Brick", kind: "tempo"), session("e", "d", "Sled", kind: nil)]
        XCTAssertEqual(kinds.map(PFHyroxTraining.kindLabel), ["Race simulation", "Station day", "Strength", "Compromised run", "Stations and runs"])
    }

    func testTrainingCoversThisWeekAndNextWeekOnly() {
        let sessions = [session("before", "2030-03-10", "Sled", kind: "strength"), session("mine", "2030-03-12", "Legs", kind: "strength"),
                        session("easy", "2030-03-13", "Easy run", kind: "easy_run"), session("next", "2030-03-19", "Sled push", kind: nil),
                        session("late", "2030-03-26", "Sled pull", kind: nil)]
        let found = PFHyroxTraining.sessions(weeks: [week(sessions)], today: "2030-03-13")
        XCTAssertEqual([found.thisWeek.map(\.id), found.nextWeek.map(\.id)], [["mine"], ["next"]])
    }

    func testTrainingNamesTheMondayOfThisWeek() {
        XCTAssertEqual(PFHyroxTraining.sessions(weeks: [], today: "2030-03-13").monday, "2030-03-11")
    }

    // MARK: Advisory

    private func proposal(_ id: String, _ title: String, _ description: String) -> PFPendingProposal {
        PFPendingProposal(id: id, title: title, description: description, why: nil, day: nil, changes: [])
    }

    func testOnlyProposalsAboutTheRacesAreKept() {
        let all = [proposal("a", "Move the sled day to Thursday", ""), proposal("b", "Add an easy run on Friday", "Short and flat")]
        XCTAssertEqual(PFHyroxAdvice.proposals(all).map(\.id), ["a"])
    }

    func testTheRacesCityCountsAsAboutTheRaces() {
        let all = [proposal("a", "Travel day", "Plan for Testville weekend")]
        XCTAssertEqual(PFHyroxAdvice.proposals(all, extra: ["Testville"]).map(\.id), ["a"])
    }

    func testWithoutTheCityThatProposalIsNotAboutTheRaces() {
        XCTAssertTrue(PFHyroxAdvice.proposals([proposal("a", "Travel day", "Plan for Testville weekend")]).isEmpty)
    }

    func testOnlyBriefLinesAboutTheRacesAreKept() {
        let brief = PFDailyBrief(headline: "Steady day", outlook: ["Taper starts Monday", "Sleep before 23:00"])
        XCTAssertEqual(PFHyroxAdvice.briefLines(brief), ["Taper starts Monday"])
    }

    private let raceWeekDoc = """
    {"date": "2030-04-15", "race_week": {"event": {"name": "HYROX Testville", "date": "2030-04-20"}, "days_to": 5, "phase": "taper",
     "notes": ["Keep it easy."]}}
    """

    func testRaceWeekNotesShowForAHyroxRaceStillToCome() {
        let week = PFWave3Parse.raceWeek(json(raceWeekDoc), brief: PFJ(nil))
        XCTAssertEqual(PFHyroxAdvice.raceWeek(week)?.notes, ["Keep it easy."])
    }

    func testRaceWeekNotesAreLeftOutForARoadRace() {
        let road = raceWeekDoc.replacingOccurrences(of: "HYROX Testville", with: "Sample Half")
        XCTAssertNil(PFHyroxAdvice.raceWeek(PFWave3Parse.raceWeek(json(road), brief: PFJ(nil))))
    }

    // MARK: Season

    private func season(_ text: String) -> PFSeasonPlan? { PFSeasonParse.plan(Data(text.utf8)) }

    private let seasonDoc = """
    {"races": [{"date": "2030-04-20", "name": "HYROX Testville", "priority": "A"},
               {"date": "2030-05-04", "name": "Sample Half", "priority": "B"},
               {"date": "2030-06-01", "name": "HYROX Sampleton", "priority": "C", "assumed": true}],
     "blocks": [{"start": "2030-03-01", "end": "2030-04-06", "kind": "build", "race": "HYROX Testville"},
                {"start": "2030-04-07", "end": "2030-04-19", "kind": "taper", "race": "HYROX Testville"},
                {"start": "2030-05-20", "end": "2030-06-10", "kind": "build", "race": "Sample Half"}]}
    """

    func testTheSeasonListsOnlyTheHyroxRaces() {
        XCTAssertEqual(PFHyroxSeason.rows(season(seasonDoc), today: "2030-03-13").map(\.name), ["HYROX Testville", "HYROX Sampleton"])
    }

    func testARaceWithATaperNamesTheTaperWindow() {
        XCTAssertEqual(PFHyroxSeason.rows(season(seasonDoc), today: "2030-03-13")[0].taperText, "Taper 7 Apr to 19 Apr.")
    }

    func testARaceInsideAnotherBlockSaysSo() {
        XCTAssertEqual(PFHyroxSeason.rows(season(seasonDoc), today: "2030-03-13")[1].taperText,
                       "No taper of its own: it falls in the build of Sample Half (20 May to 10 Jun).")
    }

    func testTheSeasonRowCountsTheDaysAway() {
        XCTAssertEqual(PFHyroxSeason.rows(season(seasonDoc), today: "2030-03-13")[0].awayText, "38 days away")
    }

    func testARaceAlreadyRunIsDone() {
        XCTAssertEqual(PFHyroxSeason.rows(season(seasonDoc), today: "2030-04-21")[0].awayText, "Done")
    }

    func testAnAssumedPriorityIsKept() {
        XCTAssertEqual(PFHyroxSeason.rows(season(seasonDoc), today: "2030-03-13").map(\.assumed), [false, true])
    }

    func testNoSeasonPlanGivesNoRows() {
        XCTAssertTrue(PFHyroxSeason.rows(nil, today: "2030-03-13").isEmpty)
    }

    // MARK: The Coach race plans

    func testAnEventNamedHyroxIsAHyroxRace() {
        XCTAssertTrue(PFHyroxEventKind.isHyrox(name: "Testville Games", type: "HYROX"))
    }

    func testARoadEventIsNotAHyroxRace() {
        XCTAssertFalse(PFHyroxEventKind.isHyrox(name: "Sample Half", type: "Half Marathon"))
    }

    // MARK: What the phone no longer shows

    private let hyroxAnalysis = """
    {"prediction": {"predicted_display": "1:01:00", "basis": "made up", "trend": "improving"},
     "priorities": [{"display": "Sled Push", "train_priority": true, "athlete_display": "3:20", "top3_avg_display": "2:50", "gap_seconds": 30}],
     "progression": {"races": [{"event_label": "Sampleton 2029", "event_date": "2029-11-02", "total_seconds": 4600, "total_display": "1:16:40", "rank": "30th"},
                               {"event_label": "Testville 2030", "event_date": "2030-03-10", "total_seconds": 4400, "total_display": "1:13:20", "rank": "12th"}]}}
    """

    private func snapshot() throws -> PFSnapshot {
        var raw = PFRawBundle()
        raw.state = json("{\"generated_at\": \"2030-03-13T08:00:00\"}")
        raw.fitness = json("{\"load\": {}}")
        raw.hyrox = json(hyroxAnalysis)
        return try XCTUnwrap(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
    }

    func testTheSnapshotKeepsOnlyHisOwnRacesFromTheHyroxAnalysis() throws {
        XCTAssertEqual(try snapshot().insights.hyroxRaces.map(\.display), ["1:16:40", "1:13:20"])
    }

    func testTheFastestRaceIsMarkedAsTheBest() throws {
        XCTAssertEqual(try snapshot().insights.hyroxRaces.filter(\.isPersonalBest).map(\.display), ["1:13:20"])
    }

    func testTheAthleteTabListsNoStationAgainstTheTopThree() throws {
        let athlete = PFAthleteBuild.make(try snapshot(), maxHr: nil)
        XCTAssertTrue(athlete.areas.allSatisfy { !$0.id.hasPrefix("station-") })
    }

    func testTheAthleteTabOffersTheHyroxScreenWithTheBestRace() throws {
        let athlete = PFAthleteBuild.make(try snapshot(), maxHr: nil)
        XCTAssertEqual(athlete.hyroxBest, "1:13:20")
    }

    private func raceItem(finish: String, discipline: String) -> PFJ {
        json("""
        {"id": "race_countdown", "title": "Race countdown", "available": true,
         "status": {"label": "behind", "scale": ["behind", "on-track", "ahead"], "threshold": "predicted finish within 3 % of the goal time"},
         "meaning": "HYROX Testville is in 38 days. Predicted finish 1:12:00 (range 1:10:00 to 1:14:00) against a goal of 1:10:00: 2 min slower.",
         "data_note": "The HYROX finish comes from your own race splits.",
         "metric": {"event": {"name": "HYROX Testville", "date": "2030-04-20", "type": "HYROX", "goal_time": "1:10:00"}, "days_to": 38, "phase": "build",
                    "phases": [], "finish": {"discipline": "\(discipline)", "central_s": 4320, "low_s": 4200, "high_s": 4440, "central": "\(finish)",
                    "goal_s": 4200, "goal": "1:10:00", "gap_to_goal_s": 120, "goal_in_range": true, "method": "made up"},
                    "garmin_predictions": [{"distance": "10K", "seconds": 3000, "display": "50:00", "pace_s_per_km": 300}],
                    "taper": {"verdict": "adequate", "reason": "Form lands inside the target window."}}}
        """)
    }

    func testAHyroxRaceCountdownKeepsNoPredictedFinish() throws {
        let item = try XCTUnwrap(PFInsightsV2Parse.item(raceItem(finish: "1:12:00", discipline: "hyrox"), key: "race_countdown"))
        XCTAssertNil(item.race?.finish)
    }

    func testAHyroxRaceCountdownDropsTheRatingAndThePredictedSentence() throws {
        let item = try XCTUnwrap(PFInsightsV2Parse.item(raceItem(finish: "1:12:00", discipline: "hyrox"), key: "race_countdown"))
        XCTAssertEqual([item.status.label, item.meaning], [nil, "HYROX Testville is in 38 days. Form lands inside the target window."])
    }

    func testAHyroxRaceCountdownKeepsTheGarminPredictionsAsAFact() throws {
        let item = try XCTUnwrap(PFInsightsV2Parse.item(raceItem(finish: "1:12:00", discipline: "hyrox"), key: "race_countdown"))
        XCTAssertEqual(item.race?.garminPredictions.map(\.display), ["50:00"])
    }

    func testARoadRaceCountdownKeepsItsGarminBasedFinish() throws {
        let item = try XCTUnwrap(PFInsightsV2Parse.item(raceItem(finish: "47:30", discipline: "run"), key: "race_countdown"))
        XCTAssertEqual(item.race?.finish?.central, "47:30")
    }

    private let simAnalysis = """
    {"has_data": true, "count": 1, "goal": {"event": "Testville", "date": "2030-04-20", "goal_seconds": 4800, "goal_display": "1:20:00",
      "basis": "the field-average profile scaled to the goal"},
     "latest": {"id": "s1", "date": "2030-03-01", "complete": true, "total_seconds": 4900, "total_display": "1:21:40", "within_band": false,
      "pacing_note": "run pacing spread wider than the 5 % top finishers hold"}, "segments": [], "weakest": []}
    """

    func testASimulationGoalIsNotExplainedAgainstTheFieldAverage() {
        XCTAssertNil(PFWave3Parse.hyroxSims(analysis: json(simAnalysis), sims: PFJ(nil))?.goal?.basis)
    }

    func testASimulationPacingNoteIsNotComparedWithTopFinishers() {
        XCTAssertNil(PFWave3Parse.hyroxSims(analysis: json(simAnalysis), sims: PFJ(nil))?.latest?.pacingNote)
    }

    func testAGoalBasisFromHisOwnRaceIsKept() {
        XCTAssertEqual(PFHyroxSims.withoutFieldComparison("your Testville race profile scaled to the goal"),
                       "your Testville race profile scaled to the goal")
    }
}
