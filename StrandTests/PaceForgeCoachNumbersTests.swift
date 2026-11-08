import XCTest
@testable import Strand

final class PaceForgeCoachNumbersTests: XCTestCase {
    // Synthetic values only: this repository is public.

    // MARK: athlete-numbers

    private let numbersJSON = Data("""
    {"garmin": {"vo2max": {"value": 52.0, "date": "2026-11-03"}, "lt": {"pace_s_per_km": 275, "hr": 171, "date": "2026-11-01"},
                "predictions": {"k5": 1260, "k10": 2640, "half": 5880, "marathon": 12420, "date": "2026-11-03"},
                "training_status": {"value": "productive", "date": "2026-11-04"}},
     "max_hr": {"value": 188, "source": "settings"},
     "paces": [{"name": "easy", "low_s": 330, "high_s": 360, "source": "Garmin LT"},
               {"name": "threshold", "low_s": 270, "high_s": null, "source": null}, {"name": "no_numbers"}]}
    """.utf8)

    private var numbers: PFAthleteNumbers? { PFCoachNumbers.athleteNumbers(numbersJSON) }

    private func row(_ id: String, in n: PFAthleteNumbers?) -> PFNumbersRow? { n?.rows.first { $0.id == id } }

    func testVo2maxRowCarriesGarminAndItsDate() {
        XCTAssertEqual(row("vo2max", in: numbers), PFNumbersRow(id: "vo2max", label: "VO2max", value: "52 ml/kg/min", caption: "Garmin \u{00B7} 3 Nov"))
    }

    func testLactateThresholdPaceIsAMinuteSecondPace() {
        XCTAssertEqual(row("lt-pace", in: numbers)?.value, "4:35 /km")
    }

    func testLactateThresholdHeartRateCarriesItsOwnDate() {
        XCTAssertEqual(row("lt-hr", in: numbers)?.caption, "Garmin \u{00B7} 1 Nov")
    }

    func testTrainingStatusReadsAsWords() {
        XCTAssertEqual(row("status", in: numbers)?.value, "Productive")
    }

    func testFiveKilometrePredictionIsMinutesAndSeconds() {
        XCTAssertEqual(row("pred-k5", in: numbers)?.value, "21:00")
    }

    func testMarathonPredictionIsHoursMinutesSeconds() {
        XCTAssertEqual(row("pred-marathon", in: numbers)?.value, "3:27:00")
    }

    func testPredictionRowIsLabelledByDistance() {
        XCTAssertEqual(row("pred-half", in: numbers)?.label, "Half marathon prediction")
    }

    func testPredictionsAreInRaceOrder() {
        XCTAssertEqual(numbers?.predictions.map(\.id), ["k5", "k10", "half", "marathon"])
    }

    func testMaxHeartRateIsLabelledAsYourSetting() {
        XCTAssertEqual(row("max-hr", in: numbers)?.caption, "your setting")
    }

    func testMaxHeartRateHasNoGarminLabel() {
        XCTAssertFalse(row("max-hr", in: numbers)?.caption.contains("Garmin") == true)
    }

    func testEveryGarminFigureIsLabelledGarmin() {
        XCTAssertTrue((numbers?.rows ?? []).filter { $0.id != "max-hr" }.allSatisfy { $0.caption.hasPrefix("Garmin") })
    }

    func testBandWithBothEndsReadsAsARange() {
        XCTAssertEqual(numbers?.paces.first?.range, "5:30\u{2013}6:00 /km")
    }

    func testBandWithOneEndReadsAsThatPace() {
        XCTAssertEqual(numbers?.paces.last?.range, "4:30 /km")
    }

    func testBandWithNoNumbersIsDropped() {
        XCTAssertEqual(numbers?.paces.count, 2)
    }

    func testBandShowsItsSource() {
        XCTAssertEqual(numbers?.paces.first?.caption, "Source: Garmin LT")
    }

    func testBandWithoutASourceSaysSo() {
        XCTAssertEqual(numbers?.paces.last?.caption, "Source not given")
    }

    func testBandNameReadsAsWords() {
        XCTAssertEqual(numbers?.paces.first?.label, "Easy")
    }

    func testNoVdotOrEffectiveVo2maxLabelEvenWhenTheServerSendsThem() {
        let data = Data(#"{"garmin": {"vo2max": {"value": 50}}, "vdot": 52, "effective_vo2max": {"value": 49}}"#.utf8)
        let text = (PFCoachNumbers.athleteNumbers(data)?.rows ?? []).map { $0.label + $0.value + $0.caption }.joined(separator: " ").lowercased()
        XCTAssertFalse(text.contains("vdot") || text.contains("effective"))
    }

    func testMissingDateLeavesJustGarmin() {
        let n = PFCoachNumbers.athleteNumbers(Data(#"{"garmin": {"vo2max": {"value": 52}}}"#.utf8))
        XCTAssertEqual(n?.rows.first?.caption, "Garmin")
    }

    func testOnlyTheFiguresSentHaveRows() {
        let n = PFCoachNumbers.athleteNumbers(Data(#"{"garmin": {"vo2max": {"value": 52}}}"#.utf8))
        XCTAssertEqual(n?.rows.count, 1)
    }

    func testZeroAndNegativePredictionsAreDropped() {
        let n = PFCoachNumbers.athleteNumbers(Data(#"{"garmin": {"predictions": {"k5": 0, "k10": -5, "half": 5880}}}"#.utf8))
        XCTAssertEqual(n?.predictions.map(\.id), ["half"])
    }

    func testEmptyObjectIsNil() {
        XCTAssertNil(PFCoachNumbers.athleteNumbers(Data("{}".utf8)))
    }

    func testEmptyGarminBlockWithNothingElseIsNil() {
        XCTAssertNil(PFCoachNumbers.athleteNumbers(Data(#"{"garmin": {}}"#.utf8)))
    }

    func testGarbageNumbersAreNil() {
        XCTAssertNil(PFCoachNumbers.athleteNumbers(Data("not json".utf8)))
    }

    func testNoDataNumbersAreNil() {
        XCTAssertNil(PFCoachNumbers.athleteNumbers(nil))
    }

    func testWrongTypesLeaveTheFigureOut() {
        let n = PFCoachNumbers.athleteNumbers(Data(#"{"garmin": {"vo2max": {"value": "high"}, "lt": {"hr": 171}}}"#.utf8))
        XCTAssertEqual(n?.rows.map(\.id), ["lt-hr"])
    }

    // MARK: readiness-decision

    /// The three live documents' shapes with every value replaced (see the file's `_synthetic` note), dates shifted to 2030-03-13.
    private func shape(_ path: String, file: StaticString = #filePath) throws -> Data {
        let url = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appendingPathComponent("LiveShapes/PaceForgeCoachPanelShapes.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let docs = try XCTUnwrap(root["docs"] as? [String: Any])
        return try JSONSerialization.data(withJSONObject: try XCTUnwrap(docs[path]))
    }

    private func liveReadiness() throws -> PFDeviceReadiness {
        try XCTUnwrap(PFDeviceReadinessParse.readiness(try shape("api/readiness-decision")))
    }

    func testLiveShapeGarminMetricsAreInReadingOrder() throws {
        XCTAssertEqual(try liveReadiness().garmin?.metrics.map(\.id), ["hrv", "rhr", "sleep_min", "resp", "skin_temp"])
    }

    func testLiveShapeMetricCarriesLabelUnitStatusAndBaseline() throws {
        let hrv = try XCTUnwrap(try liveReadiness().garmin?.metrics.first)
        XCTAssertEqual([hrv.name, hrv.unit, hrv.status], ["Overnight HRV", "ms", "low"])
        XCTAssertNotNil(hrv.baseline)
    }

    func testLiveShapeUnavailableMetricHasNoValueAndSaysWhy() throws {
        let skin = try XCTUnwrap(try liveReadiness().whoop?.metrics.last)
        XCTAssertEqual([skin.id, skin.value, skin.reason], ["skin_temp", nil, "Synthetic text"])
    }

    func testLiveShapeEachDeviceHasItsOwnScore() throws {
        let r = try liveReadiness()
        XCTAssertEqual([r.garmin?.score?.label, r.whoop?.score?.label], ["Training readiness", "Recovery"])
    }

    func testLiveShapeScoreCarriesItsBand() throws {
        XCTAssertEqual(try liveReadiness().garmin?.score?.band, "yellow")
    }

    func testLiveShapeDeepAndRemAreShownAndNotUsedForDecisions() throws {
        let shown = try XCTUnwrap(try liveReadiness().garmin?.shownOnly)
        XCTAssertEqual(shown.map { [$0.name, String($0.isNotUsedForDecisions)] }, [["Deep sleep", "true"], ["REM sleep", "true"]])
    }

    func testLiveShapeDecisionMetricsAreNotMarkedAsNotUsed() throws {
        XCTAssertEqual(try liveReadiness().garmin?.metrics.contains { $0.isNotUsedForDecisions }, false)
    }

    func testLiveShapeNoteWording() {
        XCTAssertEqual(PFDeviceMetric.notUsedNote, "not used for decisions")
    }

    func testLiveShapeHrvMethodIsTaken() throws {
        XCTAssertEqual(try liveReadiness().whoop?.method, "Synthetic HRV method")
    }

    func testLiveShapePoorFlagsAreRead() throws {
        let r = try liveReadiness()
        XCTAssertEqual([r.garmin?.poor, r.whoop?.poor], [true, false])
    }

    func testLiveShapePoorFlagTextsAreKept() throws {
        XCTAssertEqual(try liveReadiness().garmin?.poorFlags.count, 1)
    }

    func testLiveShapeTrendIsReadPerDevice() throws {
        let r = try liveReadiness()
        XCTAssertEqual([r.garmin?.trend, r.whoop?.trend], [true, false])
    }

    func testLiveShapeOneDevicePoorIsASplit() throws {
        XCTAssertEqual(try liveReadiness().agreement, .split)
    }

    func testLiveShapeLoadIsReadPerDevice() throws {
        let r = try liveReadiness()
        XCTAssertEqual([r.garmin?.load?.line.hasPrefix("Synthetic text: "), r.whoop?.load?.line.hasPrefix("Synthetic text: ")], [true, true])
    }

    func testLiveShapeLoadNoteIsKept() throws {
        XCTAssertEqual(try liveReadiness().loadNote, "Synthetic note")
    }

    func testLiveShapeDecisionIsOnePlainSentence() throws {
        XCTAssertEqual(try liveReadiness().decision?.sentence, "No change to your plan today.")
    }

    func testLiveShapeDecisionRuleReadsInWords() throws {
        XCTAssertEqual(try liveReadiness().decision?.ruleLine, "Rule: one device poor")
    }

    func testLiveShapeDecisionKeepsItsReasonsAndChecks() throws {
        let call = try XCTUnwrap(try liveReadiness().decision)
        XCTAssertEqual([call.reasons.count, call.check.count], [2, 3])
    }

    func testLiveShapeNullRaceGuardIsNotShown() throws {
        XCTAssertNil(try liveReadiness().decision?.raceGuard)
    }

    func testBothDevicesPoorAgree() {
        let json = Data(#"{"devices": {"garmin": {"poor": true}, "whoop": {"poor": true}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.agreement, .agree)
    }

    func testNeitherDevicePoorAgree() {
        let json = Data(#"{"devices": {"garmin": {"poor": false}, "whoop": {"poor": false}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.agreement, .agree)
    }

    func testOnlyWhoopPoorSplits() {
        let json = Data(#"{"devices": {"garmin": {"poor": false}, "whoop": {"poor": true}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.agreement, .split)
    }

    func testOneDeviceAloneHasNoAgreementMark() {
        let json = Data(#"{"devices": {"garmin": {"poor": true}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.agreement)
    }

    func testDeviceThatDoesNotSayPoorHasNoAgreementMark() {
        let json = Data(#"{"devices": {"garmin": {"poor": true}, "whoop": {"label": "WHOOP", "score": {"value": 40}}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.agreement)
    }

    func testMetricWithoutAValueIsSkippedWhenAvailable() {
        let json = Data(#"{"devices": {"garmin": {"metrics": {"hrv": {"available": true, "unit": "ms"}, "rhr": {"available": true, "value": 49}}}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.garmin?.metrics.map(\.id), ["rhr"])
    }

    func testMetricValueReadsWithoutTrailingZero() {
        let json = Data(#"{"devices": {"garmin": {"metrics": {"rhr": {"available": true, "value": 52.0, "unit": "bpm", "baseline": 51.21}}}}}"#.utf8)
        let rhr = PFDeviceReadinessParse.readiness(json)?.garmin?.metrics.first
        XCTAssertEqual([rhr?.value, rhr?.baseline], ["52", "51.2"])
    }

    func testUnavailableScoreIsLeftOut() {
        let json = Data(#"{"devices": {"garmin": {"poor": false, "score": {"available": false, "value": 40}}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.garmin?.score)
    }

    func testIllnessIsOnlyFlaggedWhenPossible() {
        let json = Data(#"{"devices": {"garmin": {"poor": false, "illness": {"evaluable": true, "possible": true}}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.garmin?.illnessPossible, true)
    }

    func testLoadLineWithAGrowingWeekHasAPlusSign() {
        let load = PFDeviceLoad(measure: "Strain", thisWeek: "63", lastWeek: "61", changePct: "2.2", ramp: false)
        XCTAssertEqual(load.line, "Strain: 63 this week, 61 last week (+2.2%)")
    }

    func testLoadLineWithAFallingWeekKeepsItsMinus() {
        let load = PFDeviceLoad(measure: "Load", thisWeek: "699", lastWeek: "723", changePct: "-3.3", ramp: false)
        XCTAssertEqual(load.line, "Load: 699 this week, 723 last week (-3.3%)")
    }

    func testDecisionIsOnePlainSentence() {
        let json = Data(#"{"decision": {"action": "ease", "rule": "hrv_low_two_days", "reasons": ["HRV is low."]}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.decision?.sentence, "Ease today's session.")
    }

    func testTrueRaceGuardReadsOn() {
        let json = Data(#"{"decision": {"action": "go", "race_guard": true}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.decision?.raceGuard, "On")
    }

    func testGoReadsAsTrainingAsPlanned() {
        let json = Data(#"{"decision": {"action": "go"}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.decision?.sentence, "Train as planned today.")
    }

    func testRestReadsAsRest() {
        let json = Data(#"{"decision": {"action": "rest"}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.decision?.sentence, "Rest today.")
    }

    func testUnknownActionStillReadsAsWords() {
        let json = Data(#"{"decision": {"action": "taper_hold"}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.decision?.sentence, "The coach's call today: taper hold.")
    }

    func testRuleAloneStillGivesASentence() {
        let json = Data(#"{"decision": {"rule": "x"}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.decision?.sentence, "No call for today yet.")
    }

    func testMissingWhoopLeavesGarmin() {
        let json = Data(#"{"devices": {"garmin": {"poor": false}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.whoop)
    }

    func testMissingDecisionIsNil() {
        let json = Data(#"{"devices": {"garmin": {"poor": false}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.decision)
    }

    func testEmptyReadinessIsNil() {
        XCTAssertNil(PFDeviceReadinessParse.readiness(Data(#"{"devices": {}}"#.utf8)))
    }

    func testGarbageReadinessIsNil() {
        XCTAssertNil(PFDeviceReadinessParse.readiness(Data("[1, 2]".utf8)))
    }

    func testStatusWordsMapToTones() {
        XCTAssertEqual(["normal", "high", "very low", "red", "yellow", "broken", ""].map { PFStatusTone.of($0) },
                       [.good, .caution, .bad, .bad, .caution, .unknown, .unknown])
    }

    // MARK: live shapes: numbers and season

    func testLiveShapeNumbersRowsAreInReadingOrder() throws {
        let n = try XCTUnwrap(PFCoachNumbers.athleteNumbers(try shape("api/athlete-numbers")))
        XCTAssertEqual(n.rows.map(\.id), ["vo2max", "lt-pace", "lt-hr", "status", "pred-k5", "pred-k10", "pred-half", "pred-marathon", "max-hr"])
    }

    func testLiveShapeVo2maxWithNoDateIsJustLabelledGarmin() throws {
        let n = try XCTUnwrap(PFCoachNumbers.athleteNumbers(try shape("api/athlete-numbers")))
        XCTAssertEqual(n.rows.first?.caption, "Garmin")
    }

    func testLiveShapeThresholdCarriesItsDate() throws {
        let n = try XCTUnwrap(PFCoachNumbers.athleteNumbers(try shape("api/athlete-numbers")))
        XCTAssertEqual(n.rows.first { $0.id == "lt-pace" }?.caption, "Garmin \u{00B7} 21 Feb")
    }

    func testLiveShapeMaxHeartRateIsYourSetting() throws {
        let n = try XCTUnwrap(PFCoachNumbers.athleteNumbers(try shape("api/athlete-numbers")))
        XCTAssertEqual(n.rows.last?.caption, "your setting")
    }

    func testLiveShapeEveryPaceBandHasARangeAndASource() throws {
        let n = try XCTUnwrap(PFCoachNumbers.athleteNumbers(try shape("api/athlete-numbers")))
        XCTAssertEqual(n.paces.map { $0.range != nil && $0.caption == "Source: Synthetic explanation" }, Array(repeating: true, count: 7))
    }

    func testLiveShapeNumbersNeverMentionVdotOrEffectiveVo2max() throws {
        let n = try XCTUnwrap(PFCoachNumbers.athleteNumbers(try shape("api/athlete-numbers")))
        let text = (n.rows.map { $0.label + $0.caption } + n.paces.map { $0.label + $0.caption }).joined(separator: " ").lowercased()
        XCTAssertFalse(text.contains("vdot") || text.contains("effective"))
    }

    // MARK: season-plan

    private let seasonJSON = Data("""
    {"races": [{"date": "2026-12-13", "name": "Half marathon", "priority": "A", "assumed": false},
               {"date": "2026-11-20", "name": "10K tune-up", "priority": "B", "assumed": true},
               {"date": "2026-10-01", "name": "Past race", "priority": "C"}, {"name": "No date"}],
     "blocks": [{"start": "2026-10-05", "end": "2026-11-01", "kind": "base", "aim": "Aerobic volume", "race": null},
                {"start": "2026-11-02", "end": "2026-11-22", "kind": "build", "aim": "Raise threshold", "race": "Half marathon"},
                {"start": "2026-11-23", "end": "2026-12-13", "kind": "taper"}],
     "current_block": "build",
     "week_rules": ["Two quality days a week", {"text": "Long run on Sunday"}, {"rule": "No hard day after a red night"}, 5]}
    """.utf8)

    private let today = "2026-11-09"

    private var season: PFSeasonPlan? { PFSeasonParse.plan(seasonJSON) }

    private func name(_ item: PFSeasonItem) -> String {
        switch item {
        case .race(let race): return race.name
        case .block(let block, _): return block.title
        }
    }

    func testRaceWithoutADateIsDropped() {
        XCTAssertEqual(season?.races.count, 3)
    }

    func testAllBlocksAreKept() {
        XCTAssertEqual(season?.blocks.count, 3)
    }

    func testCurrentBlockIsFoundByItsName() {
        XCTAssertEqual(season?.current(today: today)?.aim, "Raise threshold")
    }

    func testCurrentBlockTitleAndSpan() {
        XCTAssertEqual(season?.current(today: today)?.span, "2\u{2013}22 Nov")
    }

    func testCurrentBlockCanBeTheBlockItself() {
        let json = Data(#"{"current_block": {"start": "2026-11-02", "end": "2026-11-22", "kind": "build", "aim": "X"}, "races": [{"date": "2026-12-13", "name": "R"}]}"#.utf8)
        XCTAssertEqual(PFSeasonParse.plan(json)?.current(today: today)?.aim, "X")
    }

    func testCurrentBlockCanBeAnIndex() {
        let json = Data(#"{"blocks": [{"start": "2026-10-05", "kind": "base"}, {"start": "2026-11-02", "kind": "build"}], "current_block": 1}"#.utf8)
        XCTAssertEqual(PFSeasonParse.plan(json)?.current(today: today)?.kind, "build")
    }

    func testCurrentBlockFallsBackToTheOneHoldingToday() {
        let json = Data(#"{"blocks": [{"start": "2026-10-05", "end": "2026-11-01", "kind": "base"}, {"start": "2026-11-02", "end": "2026-11-22", "kind": "build"}]}"#.utf8)
        XCTAssertEqual(PFSeasonParse.plan(json)?.current(today: today)?.kind, "build")
    }

    func testBlockWithoutAnEndEndsWhereItStarts() {
        let json = Data(#"{"blocks": [{"start": "2026-11-02"}]}"#.utf8)
        XCTAssertEqual(PFSeasonParse.plan(json)?.blocks.first?.end, "2026-11-02")
    }

    func testBlockWithoutAKindIsJustABlock() {
        let json = Data(#"{"blocks": [{"start": "2026-11-02"}]}"#.utf8)
        XCTAssertEqual(PFSeasonParse.plan(json)?.blocks.first?.title, "Block")
    }

    func testTimelineIsInDateOrderWithPastItemsLeftOut() {
        XCTAssertEqual(season.map { PFSeasonParse.timeline($0, today: today).map(name) }, ["Build", "10K tune-up", "Taper", "Half marathon"])
    }

    func testTimelineMarksOnlyTheCurrentBlock() {
        let flags = season.map { PFSeasonParse.timeline($0, today: today) }?.compactMap { item -> Bool? in
            if case .block(_, let isCurrent) = item { return isCurrent }
            return nil
        }
        XCTAssertEqual(flags, [true, false])
    }

    func testAssumedPriorityIsFlagged() {
        XCTAssertEqual(season?.races.first { $0.name == "10K tune-up" }?.assumed, true)
    }

    func testAssumedNoteSaysWhereToSetIt() {
        XCTAssertEqual(PFSeasonRace.assumedNote, "Assumed priority \u{2013} set it in the app")
    }

    func testSetPriorityIsNotFlagged() {
        XCTAssertEqual(season?.races.first { $0.name == "Half marathon" }?.assumed, false)
    }

    func testPriorityLabel() {
        XCTAssertEqual(season?.races.first { $0.name == "Half marathon" }?.priorityLabel, "Priority A")
    }

    func testNumericPriorityReadsAsText() {
        let json = Data(#"{"races": [{"date": "2026-12-13", "name": "R", "priority": 1}]}"#.utf8)
        XCTAssertEqual(PFSeasonParse.plan(json)?.races.first?.priorityLabel, "Priority 1")
    }

    func testMissingPriorityHasNoLabel() {
        let json = Data(#"{"races": [{"date": "2026-12-13", "name": "R"}]}"#.utf8)
        XCTAssertNil(PFSeasonParse.plan(json)?.races.first?.priorityLabel)
    }

    func testWeekRulesAcceptTextAndObjectsAndSkipOthers() {
        XCTAssertEqual(season?.weekRules, ["Two quality days a week", "Long run on Sunday", "No hard day after a red night"])
    }

    func testEmptySeasonIsNil() {
        XCTAssertNil(PFSeasonParse.plan(Data(#"{"races": [], "blocks": []}"#.utf8)))
    }

    func testGarbageSeasonIsNil() {
        XCTAssertNil(PFSeasonParse.plan(Data("nope".utf8)))
    }

    private func liveSeason() throws -> PFSeasonPlan {
        try XCTUnwrap(PFSeasonParse.plan(try shape("api/season-plan")))
    }

    func testLiveShapeSeasonKeepsEveryRaceAndBlock() throws {
        let plan = try liveSeason()
        XCTAssertEqual([plan.races.count, plan.blocks.count], [6, 24])
    }

    func testLiveShapeCurrentBlockIsTheOneTheServerSent() throws {
        let current = try liveSeason().current(today: "2030-03-13")
        XCTAssertEqual([current?.kind, current?.aim], ["taper", "Synthetic aim 1"])
    }

    func testLiveShapeAssumedPrioritiesAreFlagged() throws {
        XCTAssertEqual(try liveSeason().races.map(\.assumed), [false, false, true, true, true, true])
    }

    func testLiveShapeWeekRulesReadTheWhy() throws {
        let rules = try liveSeason().weekRules
        XCTAssertEqual([rules.count, rules.filter { $0 == "Synthetic explanation" }.count], [4, 4])
    }

    func testLiveShapeTimelineLeadsWithTheCurrentBlock() throws {
        let timeline = PFSeasonParse.timeline(try liveSeason(), today: "2030-03-13")
        XCTAssertEqual(timeline.first, .block(try XCTUnwrap(try liveSeason().current(today: "2030-03-13")), isCurrent: true))
    }

    func testLiveShapeTimelineHasNoRaceDayBlocks() throws {
        let kinds = PFSeasonParse.timeline(try liveSeason(), today: "2030-03-13").compactMap { item -> String? in
            if case .block(let block, _) = item { return block.kind }
            return nil
        }
        XCTAssertFalse(kinds.contains("race"))
    }
}
