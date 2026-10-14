import XCTest
@testable import Strand

/// Insights v2 (insights-v2.json): decoding the server's real shape, a document with missing keys, `available: false`
/// items, the order of the cards, the status and effort wording, the deep-link ids and the Today card's place in the
/// layout, the "Not today" hash and Hide numbers. The real-shape document is the synthetic one in the UI-test fixture
/// (made-up athlete, made-up race), written in the exact shape the server serves, so the screens and these tests
/// read the same numbers. `PF_FIXTURE_FILE` points at the fixture when the sources are compiled outside the repo
/// tree (the Linux script sets it); otherwise it is found next to this file.
final class PaceForgeInsightsV2Tests: XCTestCase {

    // MARK: Helpers

    private func fixtureRoot(file: StaticString = #filePath) throws -> [String: Any] {
        let fallback = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NOOPiOSUITests/PaceForgeFixture.json")
        let url = ProcessInfo.processInfo.environment["PF_FIXTURE_FILE"].map { URL(fileURLWithPath: $0) } ?? fallback
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureJSON(_ key: String = "data/insights-v2.json") throws -> PFJ {
        PFJ(try XCTUnwrap(try fixtureRoot()[key]))
    }

    private func doc(_ key: String = "data/insights-v2.json") throws -> PFInsightsV2 {
        try XCTUnwrap(PFInsightsV2Parse.document(try fixtureJSON(key)))
    }

    private func item(_ id: String, key: String = "data/insights-v2.json") throws -> PFInsightItem {
        try XCTUnwrap(try doc(key).item(id))
    }

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    /// The synthetic document with `change` applied to it before it is parsed.
    private func changed(_ change: (inout [String: Any]) -> Void) throws -> PFInsightsV2 {
        var root = try XCTUnwrap(try fixtureRoot()["data/insights-v2.json"] as? [String: Any])
        change(&root)
        let data = try JSONSerialization.data(withJSONObject: root)
        return try XCTUnwrap(PFInsightsV2Parse.document(PFJ(data: data)))
    }

    // MARK: The real shape: the document

    func testTheDocumentHasSixItems() throws {
        XCTAssertEqual(try doc().items.count, 6)
    }
    func testTheDocumentReadsItsVersionAndDates() throws {
        let d = try doc()
        XCTAssertEqual([String(d.version ?? 0), d.asOf ?? "", d.generatedAt ?? ""], ["1", "2030-03-13", "2030-03-13T08:00:00+00:00"])
    }
    func testItemsComeInTheServersOrder() throws {
        XCTAssertEqual(try doc().ordered.map { $0.id },
                       ["power_curve", "race_countdown", "weight_goal", "efficiency", "sleep", "next_best_action"])
    }
    func testTheInsightsCardsLeaveOutTheNextBestAction() throws {
        XCTAssertEqual(try doc().insightCards.map { $0.id },
                       ["power_curve", "race_countdown", "weight_goal", "efficiency", "sleep"])
    }
    func testTheTodayCardIsTheNextBestAction() throws {
        XCTAssertEqual(try doc().todayCard?.id, "next_best_action")
    }

    // MARK: The real shape: status, actions, wording

    func testStatusReadsLabelScaleAndThreshold() throws {
        let status = try item("power_curve").status
        XCTAssertEqual([status.label ?? "", status.scale.joined(separator: ","), status.threshold?.isEmpty ?? true ? "empty" : "rule"],
                       ["ahead", "behind,on-track,ahead", "rule"])
    }
    func testConfidenceAndDataNoteAreRead() throws {
        let power = try item("power_curve")
        XCTAssertEqual([power.confidence ?? "", power.confidenceText ?? "", power.dataNote?.isEmpty == false ? "note" : "none"],
                       ["high", "High confidence", "note"])
    }
    func testAnActionReadsItsTextWhyEffortAndImpact() throws {
        let action = try XCTUnwrap(try item("weight_goal").actions.first)
        XCTAssertEqual([action.id, action.effort?.text ?? "", action.impactText ?? "", action.topic ?? "", action.why == nil ? "no why" : "why"],
                       ["weight:deficit", "5 min/day", "Impact 3 of 5", "weight", "why"])
    }
    func testAnActionThatCostsNothingSaysSo() throws {
        let action = try XCTUnwrap(try item("efficiency").actions.first)
        XCTAssertEqual([action.effort?.chipText ?? "", action.effort?.isFree == true ? "free" : "costs"], ["No extra time", "free"])
    }
    func testEffortWithoutALabelIsBuiltFromTheValueAndUnit() {
        XCTAssertEqual(PFInsightEffort(value: 20, unit: "min/week", label: nil).text, "20 min/week")
    }
    func testEffortWithNothingIsUnknown() {
        XCTAssertEqual(PFInsightEffort(value: nil, unit: nil, label: nil).text, "effort unknown")
    }
    func testAnItemHasAtMostThreeActions() throws {
        XCTAssertLessThanOrEqual(try item("weight_goal").actions.count, 3)
    }
    func testStatusChipTextSpellsOutAHyphenatedLabel() {
        XCTAssertEqual(PFInsightStatus(label: "on-track", scale: [], threshold: nil, reason: nil).chipText, "On track")
    }
    func testStatusWithoutALabelReadsNotRated() {
        XCTAssertEqual(PFInsightStatus().chipText, "Not rated")
    }
    func testTheLastStepsOfAThreeStepScaleAreTheGoodEnd() {
        let scale = ["behind", "on-track", "ahead"]
        XCTAssertEqual(["behind", "on-track", "ahead"].map { PFInsightStatus(label: $0, scale: scale, threshold: nil, reason: nil).tone },
                       [.caution, .neutral, .positive])
    }
    func testTheTopTwoStepsOfAFourStepScaleAreTheGoodEnd() {
        let scale = ["needs work", "normal", "good", "very good"]
        XCTAssertEqual(scale.map { PFInsightStatus(label: $0, scale: scale, threshold: nil, reason: nil).tone },
                       [.caution, .neutral, .positive, .positive])
    }
    func testALabelOffTheScaleIsNeutral() {
        XCTAssertEqual(PFInsightStatus(label: "odd", scale: ["a", "b", "c"], threshold: nil, reason: nil).tone, .neutral)
    }
    func testTheNextBestActionIsAPriorityNotAVerdict() throws {
        let next = try item("next_best_action")
        XCTAssertEqual([next.chipText, next.tone == .neutral ? "neutral" : "coloured"], ["Priority medium", "neutral"])
    }

    // MARK: The real shape: power curve and FTP

    func testPowerReadsTheFTPEstimateAndTheFTPInUse() throws {
        let power = try XCTUnwrap(try item("power_curve").power)
        XCTAssertEqual([power.estimateW, power.inUseW], [231, 220])
    }
    func testPowerListsTheThreeFTPFiguresSideBySide() throws {
        let power = try XCTUnwrap(try item("power_curve").power)
        XCTAssertEqual(power.ftpRows.map { $0.id }, ["estimate", "garmin", "in-use"])
    }
    func testGarminsStaleFTPIsFlagged() throws {
        let row = try XCTUnwrap(try item("power_curve").power?.ftpRows.first { $0.id == "garmin" })
        XCTAssertEqual(row.note, "Flagged stale from 2029-06-01")
    }
    func testThePowerCurveHasEighteenPoints() throws {
        XCTAssertEqual(try item("power_curve").power?.curve.count, 18)
    }
    func testACurveDurationWithNoRecentBestKeepsItsAllTimeValue() throws {
        let point = try XCTUnwrap(try item("power_curve").power?.curve.last)
        XCTAssertEqual("\(point.seconds) s, all time \(Int(point.allTime ?? 0)) W, recent \(point.last90.map { String($0) } ?? "none")",
                       "7200 s, all time 208 W, recent none")
    }
    func testThePowerCurveHasSomethingToDraw() throws {
        XCTAssertEqual(try item("power_curve").power?.hasCurve, true)
    }
    func testPowerReadsTheBestEffortsForTheHeadlineDurations() throws {
        let power = try XCTUnwrap(try item("power_curve").power)
        XCTAssertEqual(power.durations.map { $0.label }, ["5 s", "30 s", "1 min", "5 min", "10 min", "20 min", "60 min"])
    }
    func testABestEffortKeepsItsDate() throws {
        let best = try XCTUnwrap(try item("power_curve").power?.evidence)
        XCTAssertEqual("\(Int(best.watts)) W on \(best.date ?? "")", "243 W on 2030-02-20")
    }
    func testThePowerProfileRowsCarryTheirVerdicts() throws {
        XCTAssertEqual(try item("power_curve").power?.profile.map { $0.verdict ?? "" }, ["strong", "typical", "typical"])
    }
    func testAFTPTestThatIsNotDueGivesTheNextDate() throws {
        let power = try XCTUnwrap(try item("power_curve").power)
        XCTAssertEqual([power.retestDue == false ? "not due" : "due", power.retestNextDate ?? ""], ["not due", "2030-04-03"])
    }
    func testPowerLeadsWithTheFTPEstimateAndItsDistanceFromTheFTPInUse() throws {
        XCTAssertEqual(try item("power_curve").headline,
                       PFInsightHeadline(value: "231 W", caption: "FTP estimate, +5 % against the FTP in use"))
    }

    // MARK: The real shape: race countdown

    func testTheRaceCountdownReadsTheDaysAndThePhase() throws {
        let race = try XCTUnwrap(try item("race_countdown").race)
        XCTAssertEqual([String(race.daysTo ?? 0), race.phase ?? "", race.countdownText ?? ""], ["38", "build", "In 38 days"])
    }
    func testTheRaceHasFivePhasesAndTheBuildIsCurrent() throws {
        let race = try XCTUnwrap(try item("race_countdown").race)
        XCTAssertEqual(race.phases.filter { $0.isCurrent }.map { $0.id }, ["build"])
    }
    func testTheFirstPhaseHasNoStartDate() throws {
        XCTAssertNil(try item("race_countdown").race?.phases.first?.from)
    }
    func testTheFinishRangeReadsTheCentralTimeAndTheGoal() throws {
        let finish = try XCTUnwrap(try item("race_countdown").race?.finish)
        XCTAssertEqual([finish.central ?? "", finish.low ?? "", finish.high ?? "", finish.goal ?? ""], ["47:30", "47:30", "48:56", "47:00"])
    }
    func testTheGapToTheGoalIsWorded() throws {
        XCTAssertEqual(try item("race_countdown").race?.finish?.gapText, "0:30 slower than the goal")
    }
    func testAGoalOutsideTheRangeIsReported() throws {
        XCTAssertEqual(try item("race_countdown").race?.finish?.goalInRange, false)
    }
    func testTheFinishBarPutsTheGoalLeftOfTheCentralTime() throws {
        let bar = try XCTUnwrap(try item("race_countdown").race?.finish?.bar)
        XCTAssertLessThan(try XCTUnwrap(bar.goal), bar.central)
    }
    func testTheFinishBarStaysInsideTheBar() throws {
        let bar = try XCTUnwrap(try item("race_countdown").race?.finish?.bar)
        XCTAssertTrue(bar.low >= 0 && bar.high <= 1 && (bar.goal ?? 0) >= 0)
    }
    func testGarminsPredictionsAreLabelled() throws {
        XCTAssertEqual(try item("race_countdown").race?.garminPredictions.map { $0.label }, ["5K", "10K", "Half marathon", "Marathon"])
    }
    func testTheFormCurveHasOnePointForEachDayToTheRace() throws {
        XCTAssertEqual(try item("race_countdown").race?.form.count, 39)
    }
    func testTheTaperReadsItsVerdictAndTheTargetWindow() throws {
        let taper = try XCTUnwrap(try item("race_countdown").race?.taper)
        XCTAssertEqual([taper.verdict ?? "", String(taper.tsbLow ?? 0), String(taper.tsbHigh ?? 0)], ["over-tapered", "5.0", "15.0"])
    }
    func testAnOverTaperIsOneToLookAt() {
        XCTAssertEqual(PFInsightVerdict.taperTone("over-tapered"), .caution)
    }
    func testAnAdequateTaperIsGood() {
        XCTAssertEqual(PFInsightVerdict.taperTone("adequate"), .positive)
    }
    func testTheRaceLeadsWithTheDaysToGo() throws {
        XCTAssertEqual(try item("race_countdown").headline, PFInsightHeadline(value: "38 days", caption: "Synthetic Coastal 10K"))
    }
    func testRaceDayIsToday() {
        var race = PFRaceMetric()
        race.daysTo = 0
        XCTAssertEqual(race.countdownText, "Today")
    }

    // MARK: The real shape: weight goal

    func testWeightReadsTheTrendTheTargetAndTheDistanceToGo() throws {
        let weight = try XCTUnwrap(try item("weight_goal").weight)
        XCTAssertEqual([weight.trendKg, weight.targetKg, weight.kgToGo], [82.49, 78, 4.49])
    }
    func testWeightReadsTheNeededAndTheActualPace() throws {
        let weight = try XCTUnwrap(try item("weight_goal").weight)
        XCTAssertEqual([weight.neededKgPerWeek, weight.actualKgPerWeek], [0.29, 0.27])
    }
    func testWeightHasADailySeriesWithANoiseBand() throws {
        let weight = try XCTUnwrap(try item("weight_goal").weight)
        XCTAssertEqual([weight.series.count, weight.series.filter { $0.bandLowKg != nil && $0.bandHighKg != nil }.count], [30, 30])
    }
    func testTheNeededPathRunsFromTheStartToTheTarget() throws {
        let path = try XCTUnwrap(try item("weight_goal").weight?.neededPath)
        XCTAssertEqual(path.map { $0.weightKg }, [84, 78])
    }
    func testTheProjectedLineEndsOnTheTargetOnTheProjectedDate() throws {
        let line = try XCTUnwrap(try item("weight_goal").weight?.projectedLine)
        XCTAssertEqual([line.last?.date ?? "", String(line.last?.weightKg ?? 0)], ["2030-07-07", "78.0"])
    }
    func testTheScheduleSaysHowLateTheProjectedDateIs() throws {
        let weight = try XCTUnwrap(try item("weight_goal").weight)
        XCTAssertEqual(weight.scheduleText { $0 }, "Projected 2030-07-07 (7 days late)")
    }
    func testTheScheduleSaysHowEarlyAProjectedDateIs() {
        var weight = PFWeightMetric()
        weight.projectedDate = "2030-06-20"
        weight.projectedDaysVsTarget = -1
        XCTAssertEqual(weight.scheduleText { $0 }, "Projected 2030-06-20 (1 day early)")
    }
    func testWithNoProjectedDateTheScheduleSaysSo() {
        var weight = PFWeightMetric()
        weight.kgToGo = 4
        XCTAssertEqual(weight.scheduleText { $0 }, "No date can be projected yet")
    }
    func testBelowTheTargetTheScheduleSaysSo() {
        var weight = PFWeightMetric()
        weight.kgToGo = -0.5
        XCTAssertEqual(weight.scheduleText { $0 }, "At or below the target")
    }
    func testTheTrendSittingNearTheLineIsInsideTheNoise() throws {
        XCTAssertEqual(try item("weight_goal").weight?.pathText, "0.1 kg above the straight line, inside the scale's noise")
    }
    func testWeightHasATrendLine() throws {
        XCTAssertEqual(try item("weight_goal").weight?.hasTrend, true)
    }
    func testWeightIsCoveredByTheBodySwitch() throws {
        XCTAssertEqual(try item("weight_goal").hideKind, .body)
    }
    func testWeightLeadsWithTheTrendAndTheDistanceToGo() throws {
        XCTAssertEqual(try item("weight_goal").headline, PFInsightHeadline(value: "82.5 kg", caption: "4.5 kg to go"))
    }
    func testHidingBodyNumbersTakesTheWeightOutOfTheMeaning() throws {
        let meaning = try XCTUnwrap(try item("weight_goal").meaning)
        XCTAssertFalse(PFRedact.text(meaning, scores: false, body: true).contains("82.5"))
    }

    // MARK: The real shape: efficiency

    func testRunningEfficiencyIsReadableAndImproving() throws {
        let run = try XCTUnwrap(try item("efficiency").efficiency?.running)
        XCTAssertEqual([run.verdict ?? "", run.isReadable ? "readable" : "unreadable"], ["improving", "readable"])
    }
    func testRunningReadsThePaceAtTheReferenceHeartRate() throws {
        let run = try XCTUnwrap(try item("efficiency").efficiency?.running)
        XCTAssertEqual([run.referenceHr, Int(run.paceRecentS ?? 0), Int(run.pacePriorS ?? 0)], [138, 332, 342])
    }
    func testRunningReadsTheDriftAndItsVerdict() throws {
        let run = try XCTUnwrap(try item("efficiency").efficiency?.running)
        XCTAssertEqual("\(run.decouplingPct ?? 0) % \(run.decouplingVerdict ?? "")", "4.2 % good")
    }
    func testBikeEfficiencyWithTooFewRidesIsNotReadable() throws {
        XCTAssertEqual(try item("efficiency").efficiency?.bike.isReadable, false)
    }
    func testTheFourWeekZoneSplitComesFirst() throws {
        XCTAssertEqual(try item("efficiency").efficiency?.zoneSplit?.weeks, 4)
    }
    func testTheZoneSplitIsGradedTooMuchInTheMiddle() throws {
        XCTAssertEqual(try item("efficiency").efficiency?.zoneSplit?.gradeText, "Too much in the middle")
    }
    func testTheZoneSplitSharesAreEasyMiddleHard() throws {
        let shares = try XCTUnwrap(try item("efficiency").efficiency?.zoneSplit?.shares)
        XCTAssertEqual([shares.easy, shares.mid, shares.hard], [68.5, 21, 10.5])
    }
    func testTheEightyTwentyTargetIsEightyPercentEasy() {
        XCTAssertEqual(PFZoneSplit.easyTargetPct, 80)
    }
    func testEfficiencyLeadsWithTheRunningChange() throws {
        XCTAssertEqual(try item("efficiency").headline, PFInsightHeadline(value: "+3.1 %", caption: "Running, improving"))
    }
    func testTrendVerdictsGetTheirOwnWords() {
        XCTAssertEqual(["improving", "steady", "declining", "insufficient_data"].map { PFInsightVerdict.trendText($0) },
                       ["Improving", "Steady", "Declining", "Not enough data"])
    }

    // MARK: The real shape: sleep

    func testSleepReadsTheBedtimeAndWakeSpread() throws {
        let sleep = try XCTUnwrap(try item("sleep").sleep)
        XCTAssertEqual([sleep.bedtimeSdMin, sleep.wakeSdMin], [34, 22])
    }
    func testSleepHasTwentyEightNights() throws {
        XCTAssertEqual(try item("sleep").sleep?.series.count, 28)
    }
    func testSleepReadsTheDebtOverSevenAndFourteenNights() throws {
        let sleep = try XCTUnwrap(try item("sleep").sleep)
        XCTAssertEqual([sleep.debt7?.debtH, sleep.debt14?.debtH], [3.4, 5.1])
    }
    func testSleepReadsTheTargetWindow() throws {
        XCTAssertEqual(try item("sleep").sleep?.targetWindow, ["22:30", "23:00"])
    }
    func testSleepReadsTheRepaymentPlan() throws {
        let sleep = try XCTUnwrap(try item("sleep").sleep)
        XCTAssertEqual([sleep.paybackExtraMinPerNight, sleep.paybackNights], [30, 7])
    }
    func testATravelNightIsMarked() throws {
        XCTAssertEqual(try item("sleep").sleep?.series.filter { $0.isTravel }.count, 2)
    }
    func testSleepDurationsAreNotCoveredByAHideSwitch() throws {
        XCTAssertNil(try item("sleep").hideKind)
    }
    func testSleepLeadsWithTheDebt() throws {
        XCTAssertEqual(try item("sleep").headline, PFInsightHeadline(value: "3.4 h", caption: "owed over 7 nights"))
    }
    func testAnEveningBedtimeIsMeasuredFromSixInTheEvening() {
        XCTAssertEqual(PFSleepClock.sinceEvening("23:10"), 310)
    }
    func testABedtimeAfterMidnightContinuesTheSameScale() {
        XCTAssertEqual(PFSleepClock.sinceEvening("00:30"), 390)
    }
    func testTheEveningScaleConvertsBackToAClock() {
        XCTAssertEqual(PFSleepClock.clock(sinceEvening: 390), "00:30")
    }
    func testMinutesAfterMidnightConvertToAClock() {
        XCTAssertEqual(PFSleepClock.clock(minutesOfDay: 405), "06:45")
    }
    func testTextThatIsNotAClockHasNoMinutes() {
        XCTAssertNil(PFSleepClock.minutes(of: "late"))
    }

    // MARK: The real shape: next best action

    func testTheNextBestActionChoosesOneAction() throws {
        let next = try XCTUnwrap(try item("next_best_action").next)
        XCTAssertEqual(next.chosen?.id, "efficiency:easier-easy-days")
    }
    func testTheNextBestActionItemCarriesTheChosenActionAsItsOnlyAction() throws {
        XCTAssertEqual(try item("next_best_action").actions.map { $0.id }, ["efficiency:easier-easy-days"])
    }
    func testTheNextBestActionListsRunnersUpWithTheirScores() throws {
        let next = try XCTUnwrap(try item("next_best_action").next)
        XCTAssertEqual(next.runnerUps.map { Int($0.score ?? 0) }, [48, 36, 18])
    }
    func testARunnerUpKeepsItsReason() throws {
        let option = try XCTUnwrap(try item("next_best_action").next?.runnerUps.first)
        XCTAssertEqual(option.reason, "impact 4 x ease 4 x relevance 3 = 48")
    }
    func testARunnerUpNamesTheOtherItemsThatPointToIt() throws {
        XCTAssertEqual(try item("next_best_action").next?.runnerUps.first?.alsoSuggestedBy, ["race_countdown"])
    }
    func testTheNextBestActionReadsReadiness() throws {
        let next = try XCTUnwrap(try item("next_best_action").next)
        XCTAssertEqual([next.readinessWord ?? "", next.readinessStrained == false ? "not strained" : "strained"], ["steady", "not strained"])
    }
    func testTheNextBestActionCountsWhatItConsidered() throws {
        let next = try XCTUnwrap(try item("next_best_action").next)
        XCTAssertEqual([next.considered, next.topics], [9, 6])
    }

    // MARK: Missing keys

    func testADocumentWithNoItemsIsNil() {
        XCTAssertNil(PFInsightsV2Parse.document(json(#"{"version": 1, "items": {}}"#)))
    }
    func testAFileOfTheWrongShapeIsNil() {
        XCTAssertNil(PFInsightsV2Parse.document(json("[1, 2]")))
    }
    func testAMissingFileIsNil() {
        XCTAssertNil(PFInsightsV2Parse.document(PFJ(nil)))
    }
    func testAnItemWithOnlyAnIdStillParses() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"{"items": {"sleep": {"id": "sleep"}}}"#)))
        XCTAssertEqual(d.item("sleep")?.title, "Sleep")
    }
    func testAnItemTakesItsIdFromItsKeyWhenItHasNone() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"{"items": {"efficiency": {"title": "Efficiency trends"}}}"#)))
        XCTAssertEqual(d.item("efficiency")?.title, "Efficiency trends")
    }
    func testAnItemWithNoMetricAndNoFlagIsUnavailable() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"{"items": {"sleep": {"id": "sleep"}}}"#)))
        XCTAssertEqual(d.item("sleep")?.available, false)
    }
    func testAnItemWithAMetricAndNoFlagIsAvailable() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"{"items": {"sleep": {"id": "sleep", "metric": {"nights": 20}}}}"#)))
        XCTAssertEqual(d.item("sleep")?.sleep?.nights, 20)
    }
    func testAnActionWithNoTextIsDropped() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"sleep": {"id": "sleep", "available": true, "metric": {"nights": 20},
         "actions": [{"id": "a", "why": "w"}, {"id": "b", "text": "Do b"}]}}}
        """#)))
        XCTAssertEqual(d.item("sleep")?.actions.map { $0.id }, ["b"])
    }
    func testAnActionWithNoEffortStillShows() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"sleep": {"id": "sleep", "available": true, "metric": {"nights": 20}, "actions": [{"id": "b", "text": "Do b"}]}}}
        """#)))
        XCTAssertNil(d.item("sleep")?.actions.first?.effort)
    }
    func testACurveWithShorterValueListsKeepsEveryDuration() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"power_curve": {"id": "power_curve", "available": true,
         "metric": {"curve": {"seconds": [5, 60, 300], "last_90d": [700, 350], "all_time": []}}}}}
        """#)))
        XCTAssertEqual(d.item("power_curve")?.power?.curve.map { $0.last90 == nil ? "none" : "some" }, ["some", "some", "none"])
    }
    func testAFormCurveWithUnevenListsKeepsOnlyTheCompletePoints() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"race_countdown": {"id": "race_countdown", "available": true,
         "metric": {"form_curve": {"dates": ["2030-03-13", "2030-03-14"], "ctl": [50, 51], "atl": [55], "tsb": [-5, -4]}}}}}
        """#)))
        XCTAssertEqual(d.item("race_countdown")?.race?.form.map { $0.date }, ["2030-03-13"])
    }
    func testAFinishWithoutARangeHasNoBar() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"race_countdown": {"id": "race_countdown", "available": true,
         "metric": {"finish": {"central": "47:30", "central_s": 2850}}}}}
        """#)))
        XCTAssertNil(d.item("race_countdown")?.race?.finish?.bar)
    }
    func testAFinishWithNoGoalHasNoGapText() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"race_countdown": {"id": "race_countdown", "available": true,
         "metric": {"finish": {"central": "47:30", "central_s": 2850, "low_s": 2850, "high_s": 2900}}}}}
        """#)))
        XCTAssertNil(d.item("race_countdown")?.race?.finish?.gapText)
    }
    func testAnEventWithNoFinishPredictionKeepsTheCountdown() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"race_countdown": {"id": "race_countdown", "available": true,
         "metric": {"days_to": 12, "finish": null, "form_curve": null, "taper": null}}}}
        """#)))
        XCTAssertEqual(d.item("race_countdown")?.race?.daysTo, 12)
    }
    func testOneWeightReadingIsNotATrend() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"weight_goal": {"id": "weight_goal", "available": true,
         "metric": {"series": [{"date": "2030-03-13", "weight_kg": 83.4, "trend_kg": 83.4}]}}}}
        """#)))
        XCTAssertEqual(d.item("weight_goal")?.weight?.hasTrend, false)
    }
    func testASleepNightWithNoMinutesIsKeptButNotPlotted() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"sleep": {"id": "sleep", "available": true, "metric": {"series": [{"date": "2030-03-13", "hours": 7.2}]}}}}
        """#)))
        XCTAssertEqual(d.item("sleep")?.sleep?.hasNights, false)
    }
    func testNullNumbersReadAsMissing() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"sleep": {"id": "sleep", "available": true, "metric": {"bedtime": {"mean": "23:10", "sd_min": null}, "wake": {"median": "06:40", "sd_min": null}}}}}
        """#)))
        XCTAssertEqual(d.item("sleep")?.sleep?.hasSpread, false)
    }
    func testAnItemWithNoMeaningFallsBackToItsStatusReason() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"sleep": {"id": "sleep", "status": {"label": null, "scale": ["a", "b"], "reason": "Only 9 nights."}}}}
        """#)))
        XCTAssertEqual(d.item("sleep")?.summaryText, "Only 9 nights.")
    }

    // MARK: available: false

    func testAnUnavailablePowerCurveHasNoMetric() throws {
        let power = try item("power_curve", key: "data/insights-v2.sparse.json")
        XCTAssertEqual([power.available ? "available" : "unavailable", power.power == nil ? "no metric" : "metric"], ["unavailable", "no metric"])
    }
    func testAnUnavailableItemStillSaysWhy() throws {
        let power = try item("power_curve", key: "data/insights-v2.sparse.json")
        XCTAssertEqual(power.meaning, "No bike rides with power are on file yet, so there is no power curve.")
    }
    func testAnUnavailableItemOffersNoActions() throws {
        XCTAssertEqual(try item("power_curve", key: "data/insights-v2.sparse.json").actions.count, 0)
    }
    func testAnUnavailableItemIsNotRated() throws {
        XCTAssertEqual(try item("power_curve", key: "data/insights-v2.sparse.json").chipText, "Not rated")
    }
    func testAnUnavailableItemHasNoHeadline() throws {
        XCTAssertNil(try item("power_curve", key: "data/insights-v2.sparse.json").headline)
    }
    func testActionsTheServerSendsOnAnUnavailableItemAreDropped() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"sleep": {"id": "sleep", "available": false, "actions": [{"id": "a", "text": "Do a"}]}}}
        """#)))
        XCTAssertEqual(d.item("sleep")?.actions.count, 0)
    }
    func testAnUnavailableNextBestActionIsNoTodayCard() throws {
        XCTAssertNil(try doc("data/insights-v2.sparse.json").todayCard)
    }
    func testASparseRaceKeepsTheCountdownButNoFinish() throws {
        let race = try XCTUnwrap(try item("race_countdown", key: "data/insights-v2.sparse.json").race)
        XCTAssertEqual([String(race.daysTo ?? 0), race.finish == nil ? "no finish" : "finish"], ["38", "no finish"])
    }
    func testASparseRaceHasNoFormCurveOrTaper() throws {
        let race = try XCTUnwrap(try item("race_countdown", key: "data/insights-v2.sparse.json").race)
        XCTAssertEqual([race.form.count, race.taper == nil ? 0 : 1], [0, 0])
    }
    func testASparseWeightGoalHasNoTrend() throws {
        XCTAssertEqual(try item("weight_goal", key: "data/insights-v2.sparse.json").weight?.hasTrend, false)
    }
    func testASparseWeightGoalExplainsWhyItIsNotRated() throws {
        XCTAssertEqual(try item("weight_goal", key: "data/insights-v2.sparse.json").status.reason,
                       "Not enough weigh-ins to read your own pace yet (needs 4 readings over at least 7 days).")
    }
    func testSparseEfficiencyIsNotReadable() throws {
        let efficiency = try XCTUnwrap(try item("efficiency", key: "data/insights-v2.sparse.json").efficiency)
        XCTAssertEqual([efficiency.running.isReadable, efficiency.bike.isReadable, efficiency.zoneSplit != nil], [false, false, false])
    }
    func testSparseEfficiencyHasNoHeadline() throws {
        XCTAssertNil(try item("efficiency", key: "data/insights-v2.sparse.json").headline)
    }
    func testSparseSleepCannotRateConsistency() throws {
        XCTAssertEqual(try item("sleep", key: "data/insights-v2.sparse.json").sleep?.hasSpread, false)
    }
    func testSparseSleepStillShowsTheDebt() throws {
        XCTAssertEqual(try item("sleep", key: "data/insights-v2.sparse.json").sleep?.debt7?.debtH, 3.4)
    }

    // MARK: Order

    private func ordering(order: String, items: [String]) throws -> [String] {
        let entries = items.map { #""\#($0)": {"id": "\#($0)", "available": true, "metric": {"x": 1}}"# }.joined(separator: ",")
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"{"order": \#(order), "items": {\#(entries)}}"#)))
        return d.ordered.map { $0.id }
    }

    func testTheServersOrderWins() throws {
        XCTAssertEqual(try ordering(order: #"["sleep", "power_curve"]"#, items: PFInsightID.canonical),
                       ["sleep", "power_curve", "race_countdown", "weight_goal", "efficiency", "next_best_action"])
    }
    func testIdsWithNoItemAreSkipped() throws {
        XCTAssertEqual(try ordering(order: #"["efficiency", "weight_goal", "sleep"]"#, items: ["sleep", "efficiency"]), ["efficiency", "sleep"])
    }
    func testRepeatedIdsAreShownOnce() throws {
        XCTAssertEqual(try ordering(order: #"["sleep", "sleep", "efficiency"]"#, items: ["efficiency", "sleep"]), ["sleep", "efficiency"])
    }
    func testWithNoOrderTheItemsFollowTheCanonicalOrder() throws {
        XCTAssertEqual(try ordering(order: "null", items: ["sleep", "power_curve", "efficiency"]), ["power_curve", "efficiency", "sleep"])
    }
    func testAnItemTheAppDoesNotKnowComesLast() throws {
        XCTAssertEqual(try ordering(order: "[]", items: ["sleep", "future_item", "power_curve"]), ["power_curve", "sleep", "future_item"])
    }
    func testAnUnknownItemStillOffersItsMeaningAndActions() throws {
        let d = try XCTUnwrap(PFInsightsV2Parse.document(json(#"""
        {"items": {"future_item": {"id": "future_item", "title": "Hydration", "available": true, "meaning": "Drink.",
         "actions": [{"id": "h", "text": "Drink water"}]}}}
        """#)))
        XCTAssertEqual([d.item("future_item")?.meaning ?? "", d.item("future_item")?.actions.first?.text ?? ""], ["Drink.", "Drink water"])
    }
    func testTheOrderIsStableAcrossRepeatedReads() throws {
        let d = try doc()
        XCTAssertEqual(d.ordered.map { $0.id }, d.ordered.map { $0.id })
    }

    // MARK: Deep links

    func testTheInsightsPathNamesAnItem() {
        XCTAssertEqual(PFInsightID.linkedID(pathComponents: ["/", "insights", "power-curve"]), "power_curve")
    }
    func testAShortPathNamesAnItem() {
        XCTAssertEqual(PFInsightID.linkedID(pathComponents: ["/", "sleep"]), "sleep")
    }
    func testAnAliasNamesAnItem() {
        XCTAssertEqual(PFInsightID.linkedID(pathComponents: ["/", "insights", "weight"]), "weight_goal")
    }
    func testNextNamesTheNextBestAction() {
        XCTAssertEqual(PFInsightID.linkedID(pathComponents: ["/", "next"]), "next_best_action")
    }
    func testCaseAndUnderscoresAreForgiven() {
        XCTAssertEqual(PFInsightID.linkedID(pathComponents: ["/", "Insights", "Race_Countdown"]), "race_countdown")
    }
    func testBareInsightsIsNotAnItem() {
        XCTAssertNil(PFInsightID.linkedID(pathComponents: ["/", "insights"]))
    }
    func testTheStandingLinkIsNotAnItem() {
        XCTAssertNil(PFInsightID.linkedID(pathComponents: ["/", "standing"]))
    }
    func testAnUnknownItemIsNotAnItem() {
        XCTAssertNil(PFInsightID.linkedID(pathComponents: ["/", "insights", "nope"]))
    }
    func testTheSegmentLinksAreNotItems() {
        XCTAssertEqual(["today", "coach", "week", "body"].map { PFInsightID.linkedID(pathComponents: ["/", $0]) == nil }, [true, true, true, true])
    }
    func testAnEmptyPathIsNotAnItem() {
        XCTAssertNil(PFInsightID.linkedID(pathComponents: ["/"]))
    }

    // MARK: Today: layout, hide, hide numbers

    func testTheNextBestActionCardHasItsOwnLayoutId() {
        XCTAssertEqual(PFTodayCard.nextBestAction.rawValue, "next-best-action")
    }
    func testTheNextBestActionCardCanBePinnedToTheTop() {
        let layout = PFTodayOrder.togglingPin("next-best-action", layout: PFTodayLayout())
        XCTAssertEqual(PFTodayOrder.sorted(["today-so-far", "brief", "next-best-action", "feel"], layout: layout).first, "next-best-action")
    }
    func testTheNextBestActionCardCanMoveUpOverTheBrief() {
        let ids = ["today-so-far", "brief", "next-best-action", "feel"]
        let moved = PFTodayOrder.moving("next-best-action", step: -1, ids: ids, visible: Set(ids), layout: PFTodayLayout())
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: moved), ["today-so-far", "next-best-action", "brief", "feel"])
    }
    func testTheNextBestActionCardSitsAfterTheBriefByDefault() {
        let ids = PFTodayCard.defaultOrder.map { $0.rawValue }
        XCTAssertEqual(ids.firstIndex(of: "next-best-action"), (ids.firstIndex(of: "brief") ?? -2) + 1)
    }
    func testHidingTheCardKeepsItHiddenWhileTheAdviceIsTheSame() throws {
        let card = try XCTUnwrap(try doc().todayCard)
        let hidden = PFDismissLogic.dismissing([], key: "next-best-action", text: card.dismissText, mode: .untilChanged,
                                               today: "2030-03-13", now: Date())
        XCTAssertTrue(PFDismissLogic.isHidden(key: "next-best-action", text: card.dismissText, today: "2030-03-13", local: hidden, server: []))
    }
    func testANewScoreForTheSameAdviceDoesNotBringTheCardBack() throws {
        let before = try XCTUnwrap(try doc().todayCard).dismissText
        let rescored = try changed { root in
            var items = root["items"] as? [String: Any] ?? [:]
            var next = items["next_best_action"] as? [String: Any] ?? [:]
            var metric = next["metric"] as? [String: Any] ?? [:]
            var chosen = metric["chosen"] as? [String: Any] ?? [:]
            chosen["score"] = 64
            metric["chosen"] = chosen
            next["metric"] = metric
            items["next_best_action"] = next
            root["items"] = items
        }
        XCTAssertEqual(rescored.todayCard?.dismissText, before)
    }
    func testNewAdviceBringsAHiddenCardBack() throws {
        let card = try XCTUnwrap(try doc().todayCard)
        let hidden = PFDismissLogic.dismissing([], key: "next-best-action", text: card.dismissText, mode: .untilChanged,
                                               today: "2030-03-13", now: Date())
        let other = try changed { root in
            var items = root["items"] as? [String: Any] ?? [:]
            var next = items["next_best_action"] as? [String: Any] ?? [:]
            var actions = next["actions"] as? [[String: Any]] ?? []
            actions[0]["id"] = "sleep:payback"
            actions[0]["text"] = "Repay the sleep debt."
            next["actions"] = actions
            items["next_best_action"] = next
            root["items"] = items
        }
        let text = try XCTUnwrap(other.todayCard).dismissText
        XCTAssertFalse(PFDismissLogic.isHidden(key: "next-best-action", text: text, today: "2030-03-13", local: hidden, server: []))
    }
    func testTheServerCanHideTheCardToo() throws {
        let card = try XCTUnwrap(try doc().todayCard)
        let server = [PFDismissal(key: "next-best-action", until: nil, dismissedAt: nil, textHash: PFFNV.hash(card.dismissText))]
        XCTAssertTrue(PFDismissLogic.isHidden(key: "next-best-action", text: card.dismissText, today: "2030-03-13", local: [], server: server))
    }
    func testHidingBodyNumbersTakesTheKilogramsOutOfAWeightActionsWhy() throws {
        let why = try XCTUnwrap(try item("weight_goal").actions.first?.why)
        XCTAssertFalse(PFRedact.text(why, scores: false, body: true).contains("4.5 kg"))
    }
}
