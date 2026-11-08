import XCTest
@testable import Strand

/// The Athlete tab's second layer (build 501): profile.json, analytics.json and benchmarks.json, and the tiles, facts and cards built
/// from them. Every number is made up.
final class PaceForgeAthleteProfileTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private func snapshot() -> PFSnapshot {
        PFSnapshot(today: PFToday(), coach: PFCoach(), weeks: [], insights: PFInsights(ctl: 40, atl: 50, tsb: -10))
    }

    private let profileText = """
    {"profile_date": "2030-01-29T07:00:00", "vo2_max": 52.4, "resting_hr": 50, "max_hr": 177,
     "lactate_threshold_hr": 165.0, "lactate_threshold_speed": 3.8, "lactate_threshold_date": "2030-01-15",
     "endurance_score": 6700.0, "endurance_date": "2030-01-29", "training_status": "PRODUCTIVE_2", "training_status_date": "2030-01-29",
     "race_predictions_date": "2030-01-29",
     "race_predictions": [{"distance": "MARATHON", "predicted_seconds": 13000}, {"distance": "5K", "predicted_seconds": 1200},
                          {"distance": "HALF_MARATHON", "predicted_seconds": 5800}, {"distance": "10K", "predicted_seconds": 2600}],
     "hr_zones": [{"zone": 2, "low_bpm": 112, "high_bpm": 130}, {"zone": 1, "low_bpm": 94, "high_bpm": 111}],
     "hr_zone_sets": [{"sport": "DEFAULT", "max": 190, "lt": 160}, {"sport": "RUNNING", "max": 187, "lt": 165}],
     "personal_records": [{"distance": "5K", "time_seconds": 1190, "record_date": "2029-11-02"}]}
    """

    private func profile() -> PFAthleteProfile { PFAthleteParse.profile(json(profileText)) }

    private func snapshot(with profile: PFAthleteProfile?, analytics: PFAthleteAnalytics? = nil,
                          benchmarks: [PFAthleteRecord] = []) -> PFSnapshot {
        var snap = snapshot()
        snap.todayISO = "2030-01-29"
        snap.athleteDocs = PFAthleteDocs(profile: profile, analytics: analytics, benchmarks: benchmarks)
        return snap
    }

    // MARK: profile.json

    func testTheThresholdSpeedInMetresPerSecondBecomesAPace() throws {
        let pace = try XCTUnwrap(profile().ltPaceSecPerKm)
        XCTAssertEqual(pace, 1000 / 3.8, accuracy: 0.001)
    }

    func testTheThresholdSpeedInCentimetresPerSecondBecomesTheSamePace() throws {
        let pace = try XCTUnwrap(PFAthleteParse.thresholdPace(rawSpeed: 380))
        XCTAssertEqual(pace, 1000 / 3.8, accuracy: 0.001)
    }

    func testAThresholdSpeedInNoKnownUnitIsNotShown() {
        XCTAssertNil(PFAthleteParse.thresholdPace(rawSpeed: 50))
    }

    func testTheThresholdHeartRateIsRead() {
        XCTAssertEqual(profile().ltHr, 165)
    }

    func testTheDayTheThresholdWasMeasuredIsRead() {
        XCTAssertEqual(profile().ltDate, "2030-01-15")
    }

    func testTheProfileDateKeepsOnlyTheDay() {
        XCTAssertEqual(profile().date, "2030-01-29")
    }

    func testTheConfiguredMaximumComesFromTheRunningZoneSet() {
        XCTAssertEqual(profile().zoneMaxHr, 187)
    }

    func testTheDefaultZoneSetStandsInWhenThereIsNoRunningOne() {
        let p = PFAthleteParse.profile(json("{\"hr_zone_sets\": [{\"sport\": \"DEFAULT\", \"max\": 190}]}"))
        XCTAssertEqual(p.zoneMaxHr, 190)
    }

    func testTheHighestPeakSeenIsKeptApartFromTheConfiguredMaximum() {
        XCTAssertEqual(profile().maxHrSeen, 177)
    }

    func testTheZonesAreInZoneOrder() {
        XCTAssertEqual(profile().zones.map { $0.zone }, [1, 2])
    }

    func testALaterDuplicateOfAZoneNumberIsDropped() {
        let p = PFAthleteParse.profile(json("""
        {"hr_zones": [{"zone": 3, "low_bpm": 131, "high_bpm": 149}, {"zone": 3, "low_bpm": 1, "high_bpm": 2}, {"zone": 1, "low_bpm": 94, "high_bpm": 111}]}
        """))
        XCTAssertEqual(p.zones, [PFAthleteZone(zone: 1, low: 94, high: 111), PFAthleteZone(zone: 3, low: 131, high: 149)])
    }

    func testAZoneWithItsCeilingBelowItsFloorIsDropped() {
        let p = PFAthleteParse.profile(json("{\"hr_zones\": [{\"zone\": 1, \"low_bpm\": 120, \"high_bpm\": 100}]}"))
        XCTAssertEqual(p.zones, [])
    }

    func testRacePredictionsKeepTheFourDistancesInTheLabelsTheTabUses() {
        XCTAssertEqual(profile().racePredictions.map { $0.label }.sorted(), ["10K", "5K", "Half", "Marathon"])
    }

    func testAPredictionHasItsPaceWorkedOutWhenTheFileGivesNone() throws {
        let five = try XCTUnwrap(profile().racePredictions.first { $0.id == "5k" })
        XCTAssertEqual(try XCTUnwrap(five.paceSecPerKm), 240, accuracy: 0.001)
    }

    func testAOneKilometreForecastIsLeftOut() {
        let p = PFAthleteParse.profile(json("{\"race_predictions\": [{\"distance\": \"1km\", \"predicted_seconds\": 190}]}"))
        XCTAssertEqual(p.racePredictions, [])
    }

    func testTheTrainingStatusLosesItsCapsAndItsNumber() {
        XCTAssertEqual(profile().trainingStatus, "Productive")
    }

    func testTheEnduranceScoreIsRead() {
        XCTAssertEqual(profile().enduranceScore, 6700)
    }

    func testTheDayOfTheEnduranceScoreIsRead() {
        XCTAssertEqual(profile().enduranceDate, "2030-01-29")
    }

    func testAGarminRecordReadsAsATime() {
        XCTAssertEqual(profile().personalRecords.first?.text, "19:50")
    }

    func testAGarminRecordKeepsItsDay() {
        XCTAssertEqual(profile().personalRecords.first?.date, "2029-11-02")
    }

    func testAZeroOrMissingFigureReadsAsMissing() {
        let p = PFAthleteParse.profile(json("{\"vo2_max\": 0, \"endurance_score\": null}"))
        XCTAssertEqual([p.vo2Max, p.enduranceScore].compactMap { $0 }, [])
    }

    // MARK: analytics.json and benchmarks.json

    func testAnalyticsKeepsTheConfidenceOfEachDistance() {
        let a = PFAthleteParse.analytics(json("""
        {"race_predictions": {"vdot": 52.0, "predictions": [
          {"distance": "1km", "predicted_seconds": 190, "pace_sec_per_km": 190, "confidence": "Moderate"},
          {"distance": "Half Marathon", "predicted_seconds": 5800, "pace_sec_per_km": 275, "confidence": "High"}]}}
        """))
        XCTAssertEqual(a.predictions.map { "\($0.label) \($0.confidence ?? "-")" }, ["Half High"])
    }

    func testTheVdotComesFromTheRacePredictionsBlockFirst() {
        let a = PFAthleteParse.analytics(json("{\"race_predictions\": {\"vdot\": 52.0}, \"snapshot\": {\"vdot\": 50.0}}"))
        XCTAssertEqual(a.vdot, 52)
    }

    func testBenchmarksLeaveOutBodyweightAndFtpWhichHaveTilesOfTheirOwn() {
        let rows = PFAthleteParse.benchmarks(json("""
        {"wall_balls_max": 40, "row_500m_sec": 118, "bodyweight_kg": 80, "ftp_watts": 250, "history": {}}
        """))
        XCTAssertEqual(rows.map { $0.id }, ["bench-row_500m_sec", "bench-wall_balls_max"])
    }

    func testABenchmarkInSecondsReadsAsATime() {
        let rows = PFAthleteParse.benchmarks(json("{\"row_500m_sec\": 118}"))
        XCTAssertEqual(rows.first?.text, "1:58")
    }

    func testABenchmarkWithAnUnknownUnitIsLeftOut() {
        XCTAssertEqual(PFAthleteParse.benchmarks(json("{\"mystery\": 5}")), [])
    }

    func testABenchmarkTheAthleteTypedSaysSoAndHasNoDateWhenTheFileHasNone() {
        let rows = PFAthleteParse.benchmarks(json("""
        {"wall_balls_max": 40, "history": {"wall_balls_max": [{"date": "", "value": 40, "source": "manual"}]}}
        """))
        XCTAssertEqual(rows.first.map { "\($0.source) \($0.date ?? "no date")" }, "entered by you no date")
    }

    func testNoneOfTheThreeDocumentsGivesNothing() {
        XCTAssertNil(PFAthleteParse.documents(profile: PFJ(nil), analytics: PFJ(nil), benchmarks: PFJ(nil)))
    }

    func testAProfileAloneIsEnough() {
        XCTAssertNotNil(PFAthleteParse.documents(profile: json(profileText), analytics: PFJ(nil), benchmarks: PFJ(nil))?.profile)
    }

    // MARK: Tiles

    func testTheLactateThresholdTileShowsThePaceWithTheHeartRateUnderIt() {
        let tile = PFAthleteBuild.make(snapshot(with: profile())).tile("lt_pace")
        XCTAssertEqual([tile?.valueText, tile?.secondary], ["4:23", "Heart rate 165 bpm"])
    }

    func testTheLactateThresholdTileSaysWhenItWasMeasured() {
        XCTAssertEqual(PFAthleteBuild.make(snapshot(with: profile())).tile("lt_pace")?.datedText, "as of 15 Jan")
    }

    func testAThresholdWithNoDateSaysDateUnknownOnTheTile() {
        var p = profile()
        p.ltDate = nil
        XCTAssertEqual(PFAthleteBuild.make(snapshot(with: p)).tile("lt_pace")?.datedText, "Date unknown")
    }

    func testAThresholdWithNoDateSaysDateUnknownOnThePage() {
        var p = profile()
        p.ltDate = nil
        let row = PFAthleteBuild.make(snapshot(with: p)).tile("lt_pace")?.rows.first { $0.label == "Lactate threshold pace" }
        XCTAssertEqual(row?.note, "Garmin watch, date unknown")
    }

    func testTheLactateThresholdTileDrawsNoArrow() {
        XCTAssertNil(PFAthleteBuild.make(snapshot(with: profile())).tile("lt_pace")?.change)
    }

    func testWithoutAProfileTheThresholdTileIsTheCriticalSpeed() {
        var snap = snapshot()
        snap.athleteFitness = PFAthleteFitness(criticalPaceSecPerKm: 270)
        let tile = PFAthleteBuild.make(snap).tile("lt_pace")
        XCTAssertEqual(tile?.label, "Threshold pace")
    }

    func testTheEnduranceScoreTileHasADate() {
        let tile = PFAthleteBuild.make(snapshot(with: profile())).tile("endurance")
        XCTAssertEqual([tile?.valueText, tile?.datedText], ["6700", "as of 29 Jan"])
    }

    func testTheEnduranceScoreTileDrawsNoArrow() {
        XCTAssertNil(PFAthleteBuild.make(snapshot(with: profile())).tile("endurance")?.change)
    }

    func testTheTrainingStatusTileIsTheWatchsWord() {
        XCTAssertEqual(PFAthleteBuild.make(snapshot(with: profile())).tile("training_status")?.valueText, "Productive")
    }

    func testTheTrainingStatusTileHasNoNumber() {
        XCTAssertNil(PFAthleteBuild.make(snapshot(with: profile())).tile("training_status")?.value)
    }

    func testWithNoStandingDocumentTheVo2maxTileComesFromTheGarminProfile() {
        let tile = PFAthleteBuild.make(snapshot(with: profile())).tile("vo2max")
        XCTAssertEqual([tile?.valueText, tile?.datedText], ["52.4", "as of 29 Jan"])
    }

    func testTheVo2maxAndThresholdPagesShowOnlyGarminFigures() {
        var snap = snapshot(with: profile())
        snap.athleteFitness = PFAthleteFitness()
        let rows = PFAthleteBuild.make(snap).tile("vo2max")?.rows.map { $0.label }
        XCTAssertEqual(rows, ["VO2max, Garmin", "Lactate threshold pace", "Lactate threshold heart rate"])
    }

    func testThereIsNoVo2maxTileFromTheRuns() {
        var snap = snapshot(with: profile())
        snap.athleteFitness = PFAthleteFitness()
        XCTAssertNil(PFAthleteBuild.make(snap).tile("vo2max_runs"))
    }

    func testTheVo2maxTileIsLabelledGarmin() {
        XCTAssertEqual(PFAthleteBuild.make(snapshot(with: profile())).tile("vo2max")?.source, "Garmin")
    }

    func testTheThresholdTileOpensTheSameFigures() {
        let athlete = PFAthleteBuild.make(snapshot(with: profile()))
        XCTAssertEqual(athlete.tile("lt_pace")?.rows, athlete.tile("vo2max")?.rows)
    }

    func testEachFigureOnThePageNamesItsSourceAndDate() {
        let row = PFAthleteBuild.make(snapshot(with: profile())).tile("lt_pace")?.rows.first { $0.label == "Lactate threshold pace" }
        XCTAssertEqual(row?.note, "Garmin watch, measured 15 Jan")
    }

    // MARK: Header facts

    func testTheMaxHrFactNamesTheGarminZonesWhenTheAthleteSetNone() {
        let fact = PFAthleteBuild.make(snapshot(with: profile())).facts.first { $0.label == "Max HR" }
        XCTAssertEqual([fact?.text, fact?.note], ["187 bpm", "Garmin zones"])
    }

    func testANoopMaxHrSettingStillWins() {
        let fact = PFAthleteBuild.make(snapshot(with: profile()), maxHr: 185).facts.first { $0.label == "Max HR" }
        XCTAssertEqual([fact?.text, fact?.note], ["185 bpm", "NOOP setting"])
    }

    func testWithoutAZoneSetTheHighestPeakSeenIsLabelledThatWay() {
        var p = profile()
        p.zoneMaxHr = nil
        let fact = PFAthleteBuild.make(snapshot(with: p)).facts.first { $0.label == "Max HR" }
        XCTAssertEqual([fact?.text, fact?.note], ["177 bpm", "highest seen"])
    }

    func testTheLtHrFactReadsTheProfile() {
        XCTAssertEqual(PFAthleteBuild.make(snapshot(with: profile())).facts.first { $0.label == "LT HR" }?.text, "165 bpm")
    }

    func testWithoutAProfileTheLtHrFactIsADash() {
        XCTAssertEqual(PFAthleteBuild.make(snapshot()).facts.first { $0.label == "LT HR" }?.text, "\u{2014}")
    }

    func testACriticalSpeedBehindTheLtPaceFactIsLabelledThatWay() {
        var snap = snapshot()
        snap.athleteFitness = PFAthleteFitness(criticalPaceSecPerKm: 270)
        XCTAssertEqual(PFAthleteBuild.make(snap).facts.first { $0.label == "LT pace" }?.note, "critical speed")
    }

    // MARK: Cards

    func testThePredictionsAreInRaceOrder() {
        let predictions = PFAthleteBuild.make(snapshot(with: profile())).predictions
        XCTAssertEqual(predictions?.garmin.map { $0.label }, ["5K", "10K", "Half", "Marathon"])
    }

    func testThePredictionsCarryTheDateOfTheForecast() {
        XCTAssertEqual(PFAthleteBuild.make(snapshot(with: profile())).predictions?.garminDate, "2030-01-29")
    }

    func testPaceForgesOwnForecastStaysSeparateFromGarmins() {
        let analytics = PFAthleteAnalytics(vdot: 52, predictions: [
            PFAthletePrediction(id: "5k", label: "5K", seconds: 1190, paceSecPerKm: 238, confidence: "High")])
        let predictions = PFAthleteBuild.make(snapshot(with: profile(), analytics: analytics)).predictions
        XCTAssertEqual([predictions?.garmin.count, predictions?.model.count], [4, 1])
    }

    func testThereIsNoPredictionsCardWithoutAForecast() {
        XCTAssertNil(PFAthleteBuild.make(snapshot(with: PFAthleteProfile())).predictions)
    }

    func testTheZonesCardCarriesTheMaximumTheThresholdAndThePeakSeen() {
        let zones = PFAthleteBuild.make(snapshot(with: profile())).zones
        XCTAssertEqual([zones?.maxHr, zones?.ltHr, zones?.maxHrSeen], [187, 165, 177])
    }

    func testTheZonesCardCarriesTheDateOfTheProfile() {
        XCTAssertEqual(PFAthleteBuild.make(snapshot(with: profile())).zones?.date, "2030-01-29")
    }

    func testThereIsNoZonesCardWithoutZones() {
        XCTAssertNil(PFAthleteBuild.make(snapshot(with: PFAthleteProfile())).zones)
    }

    func testRecordsJoinTheGarminOnesAndTheFiledBenchmarks() {
        let bench = [PFAthleteRecord(id: "bench-row", label: "Row 500 m", text: "1:58", date: nil, source: "entered by you")]
        let records = PFAthleteBuild.make(snapshot(with: profile(), benchmarks: bench)).records
        XCTAssertEqual(records.map { $0.label }, ["5K", "Row 500 m"])
    }

    func testAProfileAloneMakesTheTabNonEmpty() {
        XCTAssertFalse(PFAthleteBuild.make(snapshot(with: profile())).isEmpty)
    }

    func testNoDocumentsLeavesTheTabAsItWas() {
        XCTAssertTrue(PFAthleteBuild.make(snapshot()).isEmpty)
    }

    // MARK: The builder and the document list

    private func rawBundle(profileText: String? = nil) -> PFRawBundle {
        var raw = PFRawBundle()
        raw.state = json("{}")
        raw.fitness = json("{}")
        if let profileText { raw.profile = json(profileText) }
        return raw
    }

    func testTheBuilderReadsTheProfileIntoTheSnapshot() throws {
        let snap = try XCTUnwrap(PFBuilder.snapshot(from: rawBundle(profileText: profileText), today: "2030-01-29"))
        XCTAssertEqual(snap.athleteDocs?.profile?.vo2Max, 52.4)
    }

    func testABuildWithoutTheThreeDocumentsHasNoAthleteDocs() throws {
        let snap = try XCTUnwrap(PFBuilder.snapshot(from: rawBundle(), today: "2030-01-29"))
        XCTAssertNil(snap.athleteDocs)
    }

    func testAChangedProfileRebuildsOnlyTheAthleteDocsOfAnEarlierSnapshot() throws {
        let first = try XCTUnwrap(PFBuilder.snapshot(from: rawBundle(), today: "2030-01-29"))
        let second = try XCTUnwrap(PFBuilder.snapshot(from: rawBundle(profileText: profileText), today: "2030-01-29",
                                                      previous: first, changed: [PFDocs.profile]))
        XCTAssertEqual(second.athleteDocs?.profile?.vo2Max, 52.4)
    }

    func testAChangedProfileAsksForTheProfileDocumentToBeParsed() throws {
        let first = try XCTUnwrap(PFBuilder.snapshot(from: rawBundle(), today: "2030-01-29"))
        let needed = PFBuilder.documents(needed: "2030-01-29", previous: first, changed: [PFDocs.profile])
        XCTAssertTrue(needed.contains(PFDocs.profile))
    }

    func testTheSavedCopyOfTheProfileIsReadBackOffline() throws {
        let raw = try XCTUnwrap(PFRawBundle.cached(read: { $0 == PFDocs.profile ? Data(self.profileText.utf8) : Data("{}".utf8) }))
        XCTAssertTrue(raw.profile.exists)
    }

    func testTheWidgetSummaryDoesNotRebuildForTheAthleteDocuments() {
        XCTAssertTrue(Set([PFDocs.profile, PFDocs.analytics, PFDocs.benchmarks]).isDisjoint(with: PFDocs.summaryInputs))
    }

    func testTheThreeDocumentsAreInTheListThatIsFetched() {
        let paths = Set(PFDocs.all.map { $0.path })
        XCTAssertTrue(Set([PFDocs.profile, PFDocs.analytics, PFDocs.benchmarks]).isSubset(of: paths))
    }
}
