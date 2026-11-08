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

    private let readinessJSON = Data("""
    {"date": "2026-11-09",
     "devices": {
       "garmin": {"method": "HRV status", "metrics": {"hrv": {"value": 54, "unit": "ms", "status": "normal", "baseline": 58},
                                                      "rhr": {"value": 49, "unit": "bpm", "status": "high"},
                                                      "deep_sleep": {"value": 62, "unit": "min", "status": "ok"}}},
       "whoop": {"recovery": {"value": 71, "unit": "%", "status": "green", "baseline": {"mean": 64}},
                 "rem_sleep": {"value": 80, "unit": "min"}, "method": "strap HRV", "status": "green"}},
     "decision": {"action": "ease", "rule": "hrv_low_two_days", "reasons": ["HRV is below your baseline."], "question": null,
                  "confidence": "medium", "race_guard": false},
     "load": {"garmin": {"acute": {"value": 410, "status": "ok"}}, "whoop": {}}, "hr_traces": []}
    """.utf8)

    private var readiness: PFDeviceReadiness? { PFDeviceReadinessParse.readiness(readinessJSON) }

    func testGarminMetricsAreInReadingOrder() {
        XCTAssertEqual(readiness?.garmin?.metrics.map(\.id), ["hrv", "rhr", "deep_sleep"])
    }

    func testMetricCarriesValueUnitStatusAndBaseline() {
        XCTAssertEqual(readiness?.garmin?.metrics.first,
                       PFDeviceMetric(id: "hrv", name: "HRV", value: "54", unit: "ms", status: "normal", baseline: "58"))
    }

    func testBaselineReadsFromAnObject() {
        XCTAssertEqual(readiness?.whoop?.metrics.first?.baseline, "64")
    }

    func testWhoopBlockKeepsItsMetricsApartFromItsOwnFields() {
        XCTAssertEqual(readiness?.whoop?.metrics.map(\.id), ["recovery", "rem_sleep"])
    }

    func testMethodIsTakenFromTheDeviceBlock() {
        XCTAssertEqual(readiness?.garmin?.method, "HRV status")
    }

    func testLoadMetricsAreKeptPerDevice() {
        XCTAssertEqual(readiness?.garmin?.load.first?.value, "410")
    }

    func testDeviceStatusIsTakenWhenSent() {
        XCTAssertEqual(readiness?.whoop?.status, "green")
    }

    func testDeepSleepIsNotUsedForDecisions() {
        XCTAssertEqual(readiness?.garmin?.metrics.last?.isNotUsedForDecisions, true)
    }

    func testRemSleepIsNotUsedForDecisions() {
        XCTAssertEqual(readiness?.whoop?.metrics.last?.isNotUsedForDecisions, true)
    }

    func testHrvIsUsedForDecisions() {
        XCTAssertEqual(readiness?.garmin?.metrics.first?.isNotUsedForDecisions, false)
    }

    func testWordContainingRemIsNotTakenForRemSleep() {
        XCTAssertFalse(PFDeviceMetric(id: "remaining_days", name: "Remaining", value: "3", unit: nil, status: nil, baseline: nil).isNotUsedForDecisions)
    }

    func testNoteWordingForSleepStages() {
        XCTAssertEqual(PFDeviceMetric.notUsedNote, "not used for decisions")
    }

    func testDeviceWithoutItsOwnStatusTakesTheWorstDecisionMetric() {
        XCTAssertEqual(readiness?.garmin?.tone, .caution)
    }

    func testDeepSleepDoesNotMoveTheDeviceTone() {
        let json = Data(#"{"devices": {"garmin": {"hrv": {"value": 54, "status": "ok"}, "deep_sleep": {"value": 20, "status": "poor"}}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.garmin?.tone, .good)
    }

    func testDevicesOnDifferentColoursSplit() {
        XCTAssertEqual(readiness?.agreement, .split)
    }

    func testDevicesOnTheSameColourAgree() {
        let json = Data(#"{"devices": {"garmin": {"status": "ok"}, "whoop": {"status": "green"}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.agreement, .agree)
    }

    func testOneDeviceAloneHasNoAgreementMark() {
        let json = Data(#"{"devices": {"garmin": {"status": "ok"}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.agreement)
    }

    func testDecisionIsOnePlainSentenceWithItsReason() {
        XCTAssertEqual(readiness?.decision?.sentence, "Ease today's session: HRV is below your baseline.")
    }

    func testDecisionRuleReadsInWords() {
        XCTAssertEqual(readiness?.decision?.ruleLine, "Rule: hrv low two days")
    }

    func testDecisionKeepsItsConfidence() {
        XCTAssertEqual(readiness?.decision?.confidence, "medium")
    }

    func testFalseRaceGuardIsNotShown() {
        XCTAssertNil(readiness?.decision?.raceGuard)
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

    func testListFormMetricsAreRead() {
        let json = Data(#"{"devices": {"whoop": {"metrics": [{"name": "recovery", "value": 70, "status": "green"}, {"value": 1}]}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.whoop?.metrics.map(\.id), ["recovery", "metric-1"])
    }

    func testBareValueIsAMetricWithoutAStatus() {
        let json = Data(#"{"devices": {"garmin": {"hrv": 54, "status": "ok"}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.garmin?.metrics.first?.value, "54")
    }

    func testEntryWithNeitherValueNorStatusIsSkipped() {
        let json = Data(#"{"devices": {"garmin": {"hrv": {"unit": "ms"}, "rhr": {"value": 49}}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.garmin?.metrics.map(\.id), ["rhr"])
    }

    func testMissingWhoopLeavesGarminAndNoAgreement() {
        let json = Data(#"{"devices": {"garmin": {"metrics": {"hrv": {"value": 54}}}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.whoop)
    }

    func testMissingDecisionIsNil() {
        let json = Data(#"{"devices": {"garmin": {"metrics": {"hrv": {"value": 54}}}}}"#.utf8)
        XCTAssertNil(PFDeviceReadinessParse.readiness(json)?.decision)
    }

    func testMethodFallsBackToTheDocumentLevel() {
        let json = Data(#"{"method": "two devices", "devices": {"garmin": {"hrv": {"value": 54}}}}"#.utf8)
        XCTAssertEqual(PFDeviceReadinessParse.readiness(json)?.garmin?.method, "two devices")
    }

    func testEmptyReadinessIsNil() {
        XCTAssertNil(PFDeviceReadinessParse.readiness(Data(#"{"devices": {}}"#.utf8)))
    }

    func testGarbageReadinessIsNil() {
        XCTAssertNil(PFDeviceReadinessParse.readiness(Data("[1, 2]".utf8)))
    }

    func testStatusWordsMapToTones() {
        XCTAssertEqual(["normal", "high", "very low", "red", "broken", ""].map { PFStatusTone.of($0) },
                       [.good, .caution, .bad, .bad, .unknown, .unknown])
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
}
