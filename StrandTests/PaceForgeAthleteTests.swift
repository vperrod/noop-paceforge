import XCTest
@testable import Strand

/// The Athlete tab's data: the change over four weeks, the fitness.json extras and the three finding groups. Every number is
/// made up.
final class PaceForgeAthleteTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private func points(_ rows: [(String, Double)]) -> [PFAthletePoint] {
        rows.map { PFAthletePoint(date: $0.0, value: $0.1) }
    }

    private func snapshot() -> PFSnapshot {
        PFSnapshot(today: PFToday(), coach: PFCoach(), weeks: [], insights: PFInsights(ctl: 40, atl: 50, tsb: -10))
    }

    private func metric(_ id: String, _ label: String, band: Int?, planId: String? = nil) -> PFStandingMetric {
        var m = PFStandingMetric(id: id, label: label)
        m.value = 10
        m.band = band
        m.planId = planId
        return m
    }

    private func standing(_ metrics: [PFStandingMetric], strongest: [String], focus: [String]) -> PFStanding {
        var summary = PFStandingSummary()
        summary.strongest = strongest
        summary.focus = focus
        var out = PFStanding()
        out.domains = [PFStandingDomain(id: "d", title: "D", metrics: metrics)]
        out.summary = summary
        return out
    }

    // MARK: Change over four weeks

    func testARiseWhereHigherIsBetterIsFavourable() {
        let series = points([("2030-01-01", 50), ("2030-01-29", 52)])
        let change = PFAthleteMath.change(series: series, higherIsBetter: true)
        XCTAssertEqual(change, PFAthleteChange(delta: 2, direction: .up, window: "4 wk", isFavourable: true))
    }

    func testAFallWhereLowerIsBetterIsFavourable() {
        let series = points([("2030-01-01", 82), ("2030-01-29", 80)])
        XCTAssertEqual(PFAthleteMath.change(series: series, higherIsBetter: false)?.isFavourable, true)
    }

    func testAHistoryShorterThanFourWeeksHasNoChange() {
        let series = points([("2030-01-15", 50), ("2030-01-29", 52)])
        XCTAssertNil(PFAthleteMath.change(series: series, higherIsBetter: true))
    }

    func testAMoveInsideTheNoiseBandIsFlat() {
        let series = points([("2030-01-01", 82.0), ("2030-01-29", 82.4)])
        XCTAssertEqual(PFAthleteMath.change(series: series, higherIsBetter: false, noise: 0.5)?.direction, .flat)
    }

    func testAMoveOfOnePercentOrLessIsFlatWithoutANoiseBand() {
        let series = points([("2030-01-01", 100), ("2030-01-29", 100.9)])
        XCTAssertEqual(PFAthleteMath.change(series: series, higherIsBetter: true)?.direction, .flat)
    }

    func testAMetricWithNoBetterDirectionIsNeverFavourable() {
        let series = points([("2030-01-01", -10), ("2030-01-29", 5)])
        XCTAssertNil(PFAthleteMath.change(series: series, higherIsBetter: nil)?.isFavourable)
    }

    func testTheChangeReadsFromTheValueAtOrBeforeTheCutoffNotTheFirstPoint() {
        let series = points([("2029-12-01", 40), ("2030-01-01", 50), ("2030-01-20", 51), ("2030-01-29", 52)])
        XCTAssertEqual(PFAthleteMath.change(series: series, higherIsBetter: true)?.delta, 2)
    }

    func testTheStandingTrendBecomesAThirtyDayChange() {
        let trend = PFStandingTrend(direction: "down", change: -1.2, windowDays: 30, improving: true)
        XCTAssertEqual(PFAthleteMath.change(from: trend),
                       PFAthleteChange(delta: -1.2, direction: .down, window: "30 d", isFavourable: true))
    }

    func testTheChangeTextNamesTheWindow() {
        var tile = PFAthleteMetric(id: "x", label: "X", unit: "", value: 1, valueText: "1", source: "s", what: "w")
        tile.decimals = 1
        tile.change = PFAthleteChange(delta: 1.26, direction: .up, window: "4 wk", isFavourable: true)
        XCTAssertEqual(tile.changeText, "+1.3 vs 4 wk")
    }

    func testALastPointOlderThanTwoWeeksGivesNoChange() {
        let series = points([("2029-11-01", 50), ("2029-12-15", 52)])
        XCTAssertNil(PFAthleteMath.change(series: series, today: "2030-01-29", higherIsBetter: true))
    }

    func testTheCutoffCountsFromTodayNotFromTheLastPoint() {
        let series = points([("2030-01-01", 50), ("2030-01-20", 52), ("2030-01-26", 53)])
        XCTAssertEqual(PFAthleteMath.change(series: series, today: "2030-01-29", higherIsBetter: true)?.delta, 3)
    }

    func testAStaleSeriesDrawsNoSparkline() {
        var tile = PFAthleteMetric(id: "x", label: "X", unit: "", value: 1, valueText: "1", source: "s", what: "w")
        tile.series = points([("2029-11-01", 1), ("2029-11-10", 2)])
        tile.anchorDate = "2030-01-29"
        XCTAssertEqual(tile.sparkValues, [])
    }

    func testAFreshSeriesDrawsItsLastFourWeeks() {
        var tile = PFAthleteMetric(id: "x", label: "X", unit: "", value: 1, valueText: "1", source: "s", what: "w")
        tile.series = points([("2029-12-01", 1), ("2030-01-10", 2), ("2030-01-25", 3)])
        tile.anchorDate = "2030-01-29"
        XCTAssertEqual(tile.sparkValues, [2, 3])
    }

    func testTheFtpStepHasNoArrowAndSaysSince() {
        var snap = snapshot()
        snap.todayISO = "2030-01-29"
        snap.athleteFitness = PFAthleteFitness(ftpHistory: points([("2029-10-01", 230), ("2030-01-10", 240)]), ftp: 240, autoFtp: 250)
        let tile = PFAthleteBuild.make(snap).tile("ftp")
        XCTAssertNil(tile?.change)
        XCTAssertEqual(tile?.datedText, "since 10 Jan")
    }

    func testTheFtpOnFileWinsOverTheEstimateFromRides() {
        var snap = snapshot()
        snap.athleteFitness = PFAthleteFitness(ftpHistory: points([("2029-10-01", 230)]), ftp: 240, autoFtp: 250)
        XCTAssertEqual(PFAthleteBuild.make(snap).tile("ftp")?.value, 240)
    }

    func testTheEstimateFromRidesIsLabelledAsSuch() {
        var snap = snapshot()
        snap.athleteFitness = PFAthleteFitness(autoFtp: 250)
        XCTAssertEqual(PFAthleteBuild.make(snap).tile("ftp")?.source, "PaceForge \u{00B7} from your rides")
    }

    func testTheFtpOnFileIsParsed() {
        XCTAssertEqual(PFAthleteParse.fitness(json("{\"bike\": {\"ftp\": 245, \"auto_ftp\": 250}}"))?.ftp, 245)
    }

    func testMaxHrNamesItsSource() {
        let notes = [PFAthleteBuild.make(snapshot()).facts.first { $0.label == "Max HR" }?.note,
                     PFAthleteBuild.make(snapshot(), maxHr: 185).facts.first { $0.label == "Max HR" }?.note]
        XCTAssertEqual(notes, ["auto", "NOOP setting"])
    }

    // MARK: fitness.json extras

    func testTheEffectiveVo2maxSeriesReadsTheSmoothedValueOldestFirst() {
        let doc = json("""
        {"running": {"effective_vo2max": {"available": true, "current": 51.2, "series": [
          {"date": "2030-01-10", "value": 50.0, "ewma": 50.5}, {"date": "2030-01-02", "value": 49.0, "ewma": 50.0}]}}}
        """)
        XCTAssertEqual(PFAthleteParse.fitness(doc)?.effectiveVo2, points([("2030-01-02", 50.0), ("2030-01-10", 50.5)]))
    }

    func testTheFtpHistoryAndTheAutomaticEstimateAreRead() {
        let doc = json("""
        {"bike": {"auto_ftp": 240, "ftp_history": [{"date": "2030-01-01", "ftp": 230, "source": "manual"}]}}
        """)
        XCTAssertEqual(PFAthleteParse.fitness(doc)?.ftpHistory, points([("2030-01-01", 230)]))
    }

    func testAnUnavailableCriticalSpeedIsLeftOut() {
        let doc = json("{\"running\": {\"critical_speed\": {\"available\": false, \"cs_pace_sec_per_km\": 300}}}")
        XCTAssertNil(PFAthleteParse.fitness(doc)?.criticalPaceSecPerKm)
    }

    func testTheRankedLimitersAreReadInOrder() {
        let doc = json("""
        {"coach_input": {"ranked_limiters": [
          {"name": "Aerobic base", "area": "endurance", "evidence": "Easy runs drift", "time_impact": 0.8},
          {"name": "Wall balls", "area": "strength", "evidence": "Fade late", "time_impact": 0.5}]}}
        """)
        XCTAssertEqual(PFAthleteParse.fitness(doc)?.limiters.map { $0.name }, ["Aerobic base", "Wall balls"])
    }

    func testAMissingFitnessDocumentGivesNothing() {
        XCTAssertNil(PFAthleteParse.fitness(PFJ(nil)))
    }

    // MARK: The three groups

    func testAStrengthMustBeInTheMiddleBandOrAbove() {
        let st = standing([metric("a", "A", band: 4), metric("b", "B", band: 2)], strongest: ["a", "b"], focus: [])
        var snap = snapshot()
        snap.standing = st
        XCTAssertEqual(PFAthleteBuild.make(snap).strengths.map { $0.title }, ["A"])
    }

    func testTheFocusMetricsAreTheWeaknessesWithTheirPlan() {
        let st = standing([metric("c", "C", band: 1, planId: "plan-c")], strongest: [], focus: ["c"])
        var snap = snapshot()
        snap.standing = st
        XCTAssertEqual(PFAthleteBuild.make(snap).weaknesses.first?.planId, "plan-c")
    }

    func testALimiterTakesTheCoachsRecommendationOnlyInTheCoachField() {
        var snap = snapshot()
        snap.athleteFitness = PFAthleteFitness(limiters: [PFAthleteLimiter(name: "Aerobic base", area: "endurance", evidence: "Easy runs drift")])
        snap.coach.take = PFTake(headline: "h", readinessScore: nil, readinessBand: nil,
                                 limiters: [PFLimiter(name: "aerobic base", area: "endurance", evidence: "e", recommendation: "More easy volume")],
                                 weekActions: nil)
        let area = PFAthleteBuild.make(snap).areas.first
        XCTAssertEqual(area?.coachWhy, "More easy volume")
    }

    func testTheRuleReasonOfALimiterIsItsEvidenceNotTheCoachText() {
        var snap = snapshot()
        snap.athleteFitness = PFAthleteFitness(limiters: [PFAthleteLimiter(name: "Aerobic base", area: "endurance", evidence: "Easy runs drift")])
        snap.coach.take = PFTake(headline: "h", readinessScore: nil, readinessBand: nil,
                                 limiters: [PFLimiter(name: "Aerobic base", area: "endurance", evidence: "e", recommendation: "More easy volume")],
                                 weekActions: nil)
        XCTAssertEqual(PFAthleteBuild.make(snap).areas.first?.ruleWhy, "Easy runs drift")
    }

    func testAnEmptySnapshotHasNoTilesAndAHeaderOfDashes() {
        let athlete = PFAthleteBuild.make(snapshot())
        XCTAssertEqual(athlete.facts.map { $0.text }, Array(repeating: "\u{2014}", count: 8))
    }
}
