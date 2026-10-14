import XCTest
@testable import Strand

/// daily-intel.json: decoding the served shape, the keys that may be missing, `available: false`, the verdict wording,
/// the Health monitor tile text, the bedtime from a wake time, the range band, the evening switch and the metric map.
/// Every value is made up.
final class PaceForgeDailyIntelTests: XCTestCase {

    // MARK: Fixtures

    private static let full = """
    {"version":1,"generated_at":"2030-03-13T19:05:00+00:00","as_of":"2030-03-13",
     "order":["todays_call","sleep_need_tonight","health_monitor","what_moved_it","day_in_review"],
     "items":{
      "todays_call":{"id":"todays_call","title":"Today's call","available":true,
       "metric":{"as_of":"2030-03-13",
        "charge":{"score":72,"band":"green","source":"NOOP","label":"Charge","carried_from":null},
        "readiness":{"score":41.4,"band":"yellow","source":"PaceForge","label":"Readiness","reason":"synthetic"},
        "agreement":"mixed","disagreement":{"input":"hrv","text":"Your strap reads HRV above its usual while your watch reads it below."},
        "effort_target":{"low":52,"high":71,"charge_band":"green","scale":"0-100","basis":"rule",
         "progress":{"status":"to_go","effort":30,"low":52,"high":71,"to_go_low":22,"to_go_high":41,"above_by":0,"text":"Effort 30 of 52\\u201371: 22\\u201341 to go"},
         "effort_now":{"value":30.4,"scale":"0-100","source":"NOOP (strap)"}},
        "planned":[{"name":"Synthetic tempo run","type":"tempo","sport":"run","minutes":50,"hard":true,"done":false}],
        "lead_session":null,
        "tomorrow_session":{"name":"Synthetic easy run","type":"easy_run","sport":"run","minutes":40,"hard":false,"done":false},
        "load":{"acwr":1.1,"flag":"ok","high":false},"call":"keep","verdict":"Synthetic verdict."},
       "status":{"label":"keep","scale":["ease","keep","go"],"threshold":"synthetic","reason":null},
       "meaning":"Synthetic meaning.",
       "actions":[{"id":"keep_plan","text":"Do the tempo run as planned.","why":"Charge is green.","effort":{"value":0,"unit":"min","label":"no extra time"},"impact":3,"topic":"training","tags":["suggestion"]}],
       "confidence":"medium","data_note":"Not averaged.","source":["NOOP","PaceForge"]},
      "sleep_need_tonight":{"id":"sleep_need_tonight","title":"Sleep need tonight","available":true,
       "metric":{"as_of":"2030-03-13","phase":"evening","need_min":505,"need_text":"8 h 25",
        "breakdown":[
         {"key":"baseline","label":"Baseline","minutes":460,"detail":"synthetic"},
         {"key":"effort","label":"Effort","minutes":30,"detail":"30 of 100 (NOOP (strap)), today so far"},
         {"key":"debt","label":"Sleep debt","minutes":25,"detail":"approximate"},
         {"key":"naps","label":"Naps","minutes":-10,"detail":"1 nap today (NOOP)"}],
        "baseline_min":460,"effort":{"value":30,"scale":"0-100","value_21":6.3,"source":"NOOP (strap)","basis":"today so far"},
        "tiers":[
         {"id":"getBy","title":"Get by","percent":70,"sleep_min":354,"time_in_bed_min":365,"bedtime":"00:25"},
         {"id":"perform","title":"Perform","percent":85,"sleep_min":429,"time_in_bed_min":442,"bedtime":"23:08"},
         {"id":"peak","title":"Peak","percent":100,"sleep_min":505,"time_in_bed_min":520,"bedtime":"21:50"}],
        "recommended":"perform","recommended_time_in_bed_min":442,"wake":{"time":"06:30","basis":"your typical wake time (NOOP)","nights":9}},
       "status":{"label":"raised","scale":["baseline","raised","high"],"threshold":"x","reason":null},
       "meaning":"Synthetic.","actions":[],"confidence":"medium","data_note":"x","source":["NOOP"]},
      "health_monitor":{"id":"health_monitor","title":"Health monitor","available":true,
       "metric":{"as_of":"2030-03-13","window_days":30,"vitals":[
         {"key":"hrv","label":"HRV","unit":"ms","source":"NOOP","available":true,"day":"2030-03-13","value":44,"n":28,
          "typical":{"center":46,"low":40,"high":52,"sd":6},"illness_direction":false,"z":-0.3,"status":"within","word":"WITHIN RANGE"},
         {"key":"resting_hr","label":"Resting heart rate","unit":"bpm","source":"NOOP","available":true,"day":"2030-03-13","value":58,"n":28,
          "typical":{"center":54,"low":51,"high":57,"sd":3},"illness_direction":true,"z":1.3,"status":"elevated","word":"ELEVATED"},
         {"key":"resp","label":"Respiratory rate","unit":"br/min","source":"Garmin","available":true,"day":"2030-03-13","value":19.2,"n":23,
          "typical":{"center":15,"low":13.5,"high":16.5,"sd":1.5},"illness_direction":true,"z":2.8,"status":"elevated","word":"VERY ELEVATED"},
         {"key":"skin_temp","label":"Skin temperature","unit":"\\u00b0C vs usual","source":"NOOP","available":true,"day":"2030-03-13","value":0.2,"n":28,
          "typical":{"center":0.1,"low":-0.2,"high":0.4,"sd":0.3},"illness_direction":false,"z":0.3,"status":"within","word":"WITHIN RANGE"},
         {"key":"spo2","label":"Blood oxygen","unit":"%","source":"Garmin","available":false,"n":2,"reason":"2 nights in the last 30 days; 14 are needed"}],
        "tile":{"state":"alert","text":"VERY ELEVATED \\u00b7 Respiratory rate","count":"2/4 metrics within range","within":2,"total":4},
        "alert":{"kind":"health_monitor","key":"health_monitor","severity":"watch","title":"Several vitals are out of your range","push":true,
         "body":"Resting heart rate and breathing are above your usual.",
         "vitals":[{"key":"resting_hr","label":"Resting heart rate"},{"key":"resp","label":"Respiratory rate"}],
         "what_to_do":["Take today easy.","Drink water and go to bed early.","If you feel unwell, rest."]}},
       "status":{"label":"alert","scale":["within range","attention","alert"],"threshold":"x","reason":null},
       "meaning":"Resting heart rate and breathing are above your usual.","actions":[],"confidence":"medium","data_note":"x","source":["NOOP","Garmin"]},
      "what_moved_it":{"id":"what_moved_it","title":"What moved it","available":true,
       "metric":{"as_of":"2030-03-13","window_days":90,"metrics":[
         {"key":"hrv","label":"HRV","unit":"ms","source":"NOOP","state":"ok","reason":null,
          "change_7d":{"days":7,"current":44.0,"previous":45.0,"delta":-1.0,"pct":-2.2,"n_current":7,"n_previous":7},
          "change_30d":{"days":30,"current":43.0,"previous":50.1,"delta":-7.1,"pct":-14.2,"n_current":30,"n_previous":30},
          "moved":true,"moved_over_days":30,"direction":"down","assessment":"worse",
          "links":[{"behaviour":"late_session","label":"a late session","lag_days":1,"source":"NOOP","binary":true,"r":-0.31,"n":60,"strength":"weak","sentence":"HRV runs lower after a late session (weak, r -0.31, n 60)"}],
          "action":{"id":"hrv_rule","text":"Give it two easy days.","why":"HRV is down.","effort":{"value":0,"unit":"min","label":"no extra time"},"impact":2,"topic":"recovery","tags":["suggestion"]}},
         {"key":"sleep_hours","label":"Sleep hours","unit":"h","source":"Garmin","state":"ok","reason":null,
          "change_7d":{"days":7,"current":6.4,"previous":6.4,"delta":0.0,"pct":0.0,"n_current":7,"n_previous":7},
          "change_30d":{"days":30,"current":6.6,"previous":6.8,"delta":-0.2,"pct":-2.7,"n_current":30,"n_previous":29},
          "moved":false,"moved_over_days":null,"direction":null,"assessment":null,"links":[],"action":null},
         {"key":"weight","label":"Weight","unit":"kg","source":"Garmin","state":"not enough data","reason":"Needs 14 weigh-ins in 30 days",
          "change_7d":null,"change_30d":null,"moved":false,"moved_over_days":null,"direction":null,"assessment":null,"links":[],"action":null}]},
       "status":{"label":"shifting","scale":["steady","shifting","moving"],"threshold":"x","reason":null},
       "meaning":"HRV down.","actions":[],"confidence":"medium","data_note":"x","source":["NOOP","Garmin"]},
      "day_in_review":{"id":"day_in_review","title":"Day in review","available":true,
       "metric":{"as_of":"2030-03-13",
        "effort":{"status":"to_go","effort":30,"low":52,"high":71,"to_go_low":22,"to_go_high":41,"above_by":0,"text":"Effort 30 of 52\\u201371","source":"NOOP","scale":"0-100"},
        "target_met":false,"sessions_today":[{"name":"Synthetic tempo run","type":"tempo","sport":"run","minutes":50,"hard":true,"done":true}],
        "tonight":{"need_min":505,"need_text":"8 h 25","bedtime":"23:08","tier":"Perform","time_in_bed_min":442,"wake":"06:30"},
        "tomorrow_session":{"name":"Synthetic easy run","type":"easy_run","sport":"run","minutes":40,"hard":false,"done":false},
        "sentence":"Effort finished 22 short of your range."},
       "status":{"label":"below range","scale":["below range","in range","above range","no target"],"threshold":"x","reason":null},
       "meaning":"Effort finished 22 short of your range.",
       "actions":[{"id":"bed_by","text":"Be in bed by 23:08.","why":"Tonight needs 8 h 25.","effort":{"value":0,"unit":"min","label":"no extra time"},"impact":4,"topic":"sleep","tags":["suggestion"]}],
       "confidence":"high","data_note":"x","source":["NOOP"]}
     }}
    """

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    /// A daily-intel document of the synthetic UI-test fixture (`PF_FIXTURE_FILE` when compiled outside the repo tree).
    private func fixtureDocument(_ key: String, file: StaticString = #filePath) throws -> PFDailyIntel {
        let fallback = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NOOPiOSUITests/PaceForgeFixture.json")
        let url = ProcessInfo.processInfo.environment["PF_FIXTURE_FILE"].map { URL(fileURLWithPath: $0) } ?? fallback
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(PFDailyIntelParse.document(PFJ(try XCTUnwrap(root[key]))))
    }

    private func document(_ text: String = PaceForgeDailyIntelTests.full) throws -> PFDailyIntel {
        try XCTUnwrap(PFDailyIntelParse.document(json(text)))
    }

    /// The full document with one item replaced by an unavailable one.
    private func documentWithout(_ id: String) throws -> PFDailyIntel {
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(Self.full.utf8)) as? [String: Any])
        var items = try XCTUnwrap(root["items"] as? [String: Any])
        items[id] = ["id": id, "title": "Unavailable", "available": false, "metric": [String: Any](), "actions": [Any](),
                     "meaning": "No data yet.", "source": [Any]()] as [String: Any]
        root["items"] = items
        let data = try JSONSerialization.data(withJSONObject: root)
        return try XCTUnwrap(PFDailyIntelParse.document(PFJ(data: data)))
    }

    // MARK: Decoding

    func testTheServedShapeDecodesAllFiveItems() throws {
        let intel = try document()
        XCTAssertEqual(intel.items.keys.sorted(), PFIntelID.canonical.sorted())
    }
    func testTheDocumentKeepsItsDayAndOrder() throws {
        let intel = try document()
        XCTAssertEqual(intel.asOf, "2030-03-13")
        XCTAssertEqual(intel.order.first, "todays_call")
    }
    func testTheCallKeepsNoopChargeAndPaceForgeReadinessSeparate() throws {
        let call = try XCTUnwrap(try document().call)
        XCTAssertEqual([call.charge?.source, call.readiness?.source].compactMap { $0 }, ["NOOP", "PaceForge"])
        XCTAssertEqual(call.charge?.rounded, 72)
        XCTAssertEqual(call.readiness?.rounded, 41)
    }
    func testTheCallCaptionsNameWhoseScoreItIs() throws {
        let call = try XCTUnwrap(try document().call)
        XCTAssertEqual(call.charge?.caption, "NOOP Charge")
        XCTAssertEqual(call.readiness?.caption, "PaceForge Readiness")
    }
    func testTheDisagreementSentenceIsKept() throws {
        let call = try XCTUnwrap(try document().call)
        XCTAssertEqual(call.disagreement?.input, "hrv")
    }
    func testTheEffortTargetArcIsTheRangeOnTheDial() throws {
        let target = try XCTUnwrap(try document().call?.effortTarget)
        XCTAssertEqual(target.arc?.start ?? -1, 0.52, accuracy: 0.0001)
        XCTAssertEqual(target.arc?.end ?? -1, 0.71, accuracy: 0.0001)
    }
    func testTheEffortSoFarIsAFractionOfTheDial() throws {
        let target = try XCTUnwrap(try document().call?.effortTarget)
        XCTAssertEqual(target.effortFraction ?? -1, 0.304, accuracy: 0.0001)
    }
    func testTheTargetRangeReadsAsTwoNumbers() throws {
        let target = try XCTUnwrap(try document().call?.effortTarget)
        XCTAssertEqual(target.rangeText, "52\u{2013}71")
    }
    func testThePlannedSessionAndTomorrowAreListed() throws {
        let call = try XCTUnwrap(try document().call)
        XCTAssertEqual(call.plannedSession?.lineText, "Synthetic tempo run \u{00B7} 50 min \u{00B7} hard")
        XCTAssertEqual(call.tomorrowSession?.name, "Synthetic easy run")
    }
    func testTheActionsComeThroughTheSharedItemParser() throws {
        let item = try XCTUnwrap(try document().callItem)
        XCTAssertEqual(item.base.actions.map { $0.id }, ["keep_plan"])
    }
    func testTheSourcesAreKeptPerItem() throws {
        let item = try XCTUnwrap(try document().callItem)
        XCTAssertEqual(item.sources, ["NOOP", "PaceForge"])
    }

    // MARK: The UI-test fixture

    func testTheFixtureIsTodaysFileOnTheFixturesDay() throws {
        XCTAssertTrue(try fixtureDocument("data/daily-intel.json").isCurrent(for: "2030-03-13"))
    }
    func testTheFixtureHealthMonitorIsWithinRange() throws {
        XCTAssertEqual(try XCTUnwrap(try fixtureDocument("data/daily-intel.json").health).tile.text, "WITHIN RANGE \u{00B7} 4/4 metrics")
    }
    func testTheFixtureAlertVariantIsTheRedTile() throws {
        let tile = try XCTUnwrap(try fixtureDocument("data/daily-intel.alert.json").health).tile
        XCTAssertEqual([tile.text, "\(tile.isRed)"], ["VERY ELEVATED \u{00B7} Respiratory rate", "true"])
    }
    func testTheFixtureUnavailableVariantHasNoTypedItems() throws {
        let intel = try fixtureDocument("data/daily-intel.unavailable.json")
        XCTAssertNil(intel.call)
        XCTAssertNil(intel.sleepNeed)
        XCTAssertNil(intel.health)
        XCTAssertNil(intel.moved)
        XCTAssertNil(intel.review)
    }
    func testTheFixtureUnavailableVariantSaysWhy() throws {
        let intel = try fixtureDocument("data/daily-intel.unavailable.json")
        XCTAssertEqual(intel.unavailableReason("todays_call"), "Not enough data yet for this item (synthetic fixture).")
    }

    // MARK: Missing keys and unavailable items

    func testAFileOfTheWrongShapeIsNoDocument() {
        XCTAssertNil(PFDailyIntelParse.document(json("[1, 2]")))
    }
    func testAMissingFileIsNoDocument() {
        XCTAssertNil(PFDailyIntelParse.document(PFJ(nil)))
    }
    func testAFileWithNoItemsIsNoDocument() {
        XCTAssertNil(PFDailyIntelParse.document(json(#"{"version":1,"items":{}}"#)))
    }
    func testAnItemWithOnlyAnIdAndAnAvailableFlagStillDecodes() throws {
        let intel = try document(#"{"as_of":"2030-03-13","items":{"todays_call":{"id":"todays_call","available":true,"metric":{"call":"go"}}}}"#)
        XCTAssertEqual(intel.call?.call, .go)
    }
    func testACallWithNoScoresAndNoTargetStillSaysItsVerdict() throws {
        let intel = try document(#"{"as_of":"2030-03-13","items":{"todays_call":{"id":"todays_call","available":true,"metric":{"call":"ease"}}}}"#)
        XCTAssertNil(intel.call?.charge)
        XCTAssertNil(intel.call?.effortTarget)
    }
    func testACallWithNothingInItIsNoCard() throws {
        let intel = try document(#"{"as_of":"2030-03-13","items":{"todays_call":{"id":"todays_call","available":true,"metric":{"as_of":"2030-03-13"}}}}"#)
        XCTAssertNil(intel.call)
    }
    func testAnUnavailableItemHasNoTypedMetric() throws {
        XCTAssertNil(try documentWithout("todays_call").call)
    }
    func testAnUnavailableItemKeepsTheServersReason() throws {
        XCTAssertEqual(try documentWithout("todays_call").unavailableReason("todays_call"), "No data yet.")
    }
    func testAnAvailableItemHasNoUnavailableReason() throws {
        XCTAssertNil(try document().unavailableReason("todays_call"))
    }
    func testOneUnavailableItemDoesNotTouchTheOthers() throws {
        XCTAssertNotNil(try documentWithout("todays_call").health)
    }
    func testAnUnavailableDayReviewHasNoReview() throws {
        XCTAssertNil(try documentWithout("day_in_review").review)
    }

    // MARK: Which day the file is for

    func testTheFileIsCurrentOnItsOwnDay() throws {
        XCTAssertTrue(try document().isCurrent(for: "2030-03-13"))
    }
    func testTheFileIsNotCurrentTheNextDay() throws {
        XCTAssertFalse(try document().isCurrent(for: "2030-03-14"))
    }

    // MARK: Verdict wording

    func testGoKeepAndEaseMapToTheirChips() {
        XCTAssertEqual(["go", "keep", "ease"].map { PFCallVerdict(label: $0).chipText }, ["GO", "KEEP", "EASE"])
    }
    func testTheVerdictLabelIsReadCaseInsensitively() {
        XCTAssertEqual(PFCallVerdict(label: " Ease "), .ease)
    }
    func testAnUnknownOrMissingVerdictIsNoCall() {
        XCTAssertEqual([PFCallVerdict(label: nil), PFCallVerdict(label: "maybe")], [.unknown, .unknown])
    }
    func testEaseIsTheCautionToneAndGoTheGoodOne() {
        XCTAssertEqual([PFCallVerdict.ease, PFCallVerdict.keep, PFCallVerdict.go].map { $0.tone }, [.caution, .neutral, .positive])
    }
    func testEveryVerdictHasSpokenWords() {
        XCTAssertEqual([PFCallVerdict.go, .keep, .ease, .unknown].map { $0.spokenText },
                       ["Go", "Keep the plan", "Ease today", "No call yet"])
    }

    // MARK: Health monitor tile

    func testAnAlertShowsTheWorstVitalInRed() throws {
        let tile = try XCTUnwrap(try document().health).tile
        XCTAssertEqual(tile.text, "VERY ELEVATED \u{00B7} Respiratory rate")
        XCTAssertTrue(tile.isRed)
    }
    func testTheAlertStateIsKept() throws {
        XCTAssertEqual(try XCTUnwrap(try document().health).tile.state, .alert)
    }
    func testTheWorstVitalIsTheOneFurthestFromItsRange() throws {
        XCTAssertEqual(try XCTUnwrap(try document().health).worst?.key, "resp")
    }
    func testWithinRangeShowsTheCountOfMetrics() throws {
        var health = try XCTUnwrap(try document().health)
        health.vitals = health.vitals.filter { $0.status == "within" }
        health.alert = nil
        health.tileState = "within_range"
        health.within = nil
        health.total = nil
        XCTAssertEqual(health.tile.text, "WITHIN RANGE \u{00B7} 2/2 metrics")
    }
    func testWithinRangeIsNotRed() throws {
        var health = try XCTUnwrap(try document().health)
        health.vitals = health.vitals.filter { $0.status == "within" }
        health.alert = nil
        health.tileState = "within_range"
        XCTAssertFalse(health.tile.isRed)
    }
    func testOneElevatedVitalWithoutAnAlertIsAttentionNotRed() throws {
        var health = try XCTUnwrap(try document().health)
        health.alert = nil
        health.tileState = "attention"
        health.vitals = health.vitals.filter { $0.key != "resp" }
        XCTAssertEqual(health.tile.state, .attention)
        XCTAssertFalse(health.tile.isRed)
    }
    func testOneVeryElevatedVitalIsRedEvenWithoutAnAlert() throws {
        var health = try XCTUnwrap(try document().health)
        health.alert = nil
        health.tileState = "attention"
        XCTAssertTrue(health.tile.isRed)
    }
    func testAnUnavailableVitalIsNotCountedAsInsideItsRange() throws {
        let health = try XCTUnwrap(try document().health)
        XCTAssertEqual(health.available.count, 4)
    }
    func testTheServersTileTextIsUsedWhenThereAreNoVitalRows() {
        let health = PFHealthMonitor(vitals: [], tileState: "attention", tileText: "ELEVATED \u{00B7} Skin temperature", within: 3, total: 4)
        XCTAssertEqual(health.tile.text, "ELEVATED \u{00B7} Skin temperature")
    }
    func testTheAlertCarriesWhatToDo() throws {
        let alert = try XCTUnwrap(try document().health?.alert)
        XCTAssertEqual(alert.whatToDo.count, 3)
    }

    // MARK: A vital's row

    func testTheStrapAndTheWatchAreLabelledApart() throws {
        let health = try XCTUnwrap(try document().health)
        XCTAssertEqual(health.vitals.map { $0.sourceLabel }, ["NOOP strap", "NOOP strap", "Garmin", "NOOP strap", "Garmin"])
    }
    func testSkinTemperatureIsAnUnitlessSignedDifference() throws {
        let vital = try XCTUnwrap(try document().health?.vitals.first { $0.key == "skin_temp" })
        XCTAssertEqual(vital.valueText, "+0.2")
        XCTAssertEqual(vital.unitText, "\u{00B0}C")
    }
    func testTheTypicalRangeReadsWithItsUnit() throws {
        let vital = try XCTUnwrap(try document().health?.vitals.first { $0.key == "hrv" })
        XCTAssertEqual(vital.rangeText, "40\u{2013}52 ms")
    }
    func testAVitalWithoutEnoughNightsHasNoValueOrBand() throws {
        let vital = try XCTUnwrap(try document().health?.vitals.first { $0.key == "spo2" })
        XCTAssertNil(vital.band)
        XCTAssertNil(vital.valueText)
    }
    func testAValueInsideTheRangeSitsInsideTheBand() throws {
        let band = try XCTUnwrap(PFRangeBand.make(value: 44, low: 40, high: 52))
        XCTAssertTrue(band.markerIsInside)
        XCTAssertTrue(band.marker > band.low && band.marker < band.high)
    }
    func testAValueAboveTheRangeSitsRightOfTheBand() throws {
        let band = try XCTUnwrap(PFRangeBand.make(value: 19.2, low: 13.5, high: 16.5))
        XCTAssertFalse(band.markerIsInside)
        XCTAssertTrue(band.marker > band.high)
    }
    func testTheBandPositionsStayOnTheBar() throws {
        let band = try XCTUnwrap(PFRangeBand.make(value: 90, low: 40, high: 52))
        XCTAssertTrue([band.low, band.high, band.marker].allSatisfy { $0 >= 0 && $0 <= 1 })
    }
    func testAReversedRangeIsNoBand() {
        XCTAssertNil(PFRangeBand.make(value: 5, low: 10, high: 2))
    }

    // MARK: Sleep need

    func testTheRowsAddUpToTonightsNeed() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        XCTAssertEqual(need.rows.reduce(0) { $0 + $1.minutes }, need.needMin)
    }
    func testTheThreeGoalTiersAreTheSeventyEightyFiveAndHundredPercent() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        XCTAssertEqual(need.tiers.map { $0.percent }, [70, 85, 100])
    }
    func testWithoutAWakeTimeOnThePhoneTheServersBedtimeIsUsed() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        let perform = try XCTUnwrap(need.tier("perform"))
        XCTAssertEqual(need.bedtimeText(perform, userWake: nil), "23:08")
    }
    func testAWakeTimeOnThePhoneMovesTheBedtime() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        let perform = try XCTUnwrap(need.tier("perform"))
        // 07:00 wake minus 7 h 22 in bed.
        XCTAssertEqual(need.bedtimeText(perform, userWake: 7 * 60), "23:38")
    }
    func testABedtimeAcrossMidnightWraps() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        let peak = try XCTUnwrap(need.tier("peak"))
        // 05:00 wake minus 8 h 40 in bed.
        XCTAssertEqual(need.bedtimeText(peak, userWake: 5 * 60), "20:20")
    }
    func testTheWakeTimeInUseIsTheUsersElseTheServers() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        XCTAssertEqual([need.wakeMinutes(userWake: nil), need.wakeMinutes(userWake: 420)], [390, 420])
    }
    func testAWakeTimeOutsideADayIsIgnored() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        XCTAssertEqual(need.wakeMinutes(userWake: 2000), 390)
    }
    func testTheRecommendedTierIsPerform() throws {
        XCTAssertEqual(try XCTUnwrap(try document().sleepNeed).recommendedTier?.id, "perform")
    }
    func testTheNightPlanUsesTheServersWakeAndBedtimeWithoutAPhoneWake() throws {
        let plan = try XCTUnwrap(try XCTUnwrap(try document().sleepNeed).nightPlan(tierID: "perform", userWake: nil))
        XCTAssertEqual([plan.bedtimeText, plan.wakeText], ["23:08", "06:30"])
        XCTAssertFalse(plan.usesPhoneWake)
    }
    func testTheNightPlanFollowsTheWakeTimeSetOnThePhone() throws {
        let plan = try XCTUnwrap(try XCTUnwrap(try document().sleepNeed).nightPlan(tierID: "perform", userWake: 7 * 60))
        XCTAssertEqual([plan.bedtimeText, plan.wakeText], ["23:38", "07:00"])
        XCTAssertTrue(plan.usesPhoneWake)
    }
    func testTheTimeToFallAsleepIsWhatTheEfficiencyLeaves() throws {
        let plan = try XCTUnwrap(try XCTUnwrap(try document().sleepNeed).nightPlan(tierID: "peak", userWake: nil))
        XCTAssertEqual(plan.latencyMin, 15)
    }
    func testAnUnknownGoalHasNoNightPlan() throws {
        XCTAssertNil(try XCTUnwrap(try document().sleepNeed).nightPlan(tierID: "max", userWake: nil))
    }
    func testTheNightPlanDatesTheBedtimeBeforeTheNextWakeUp() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let plan = try XCTUnwrap(try XCTUnwrap(try document().sleepNeed).nightPlan(tierID: "perform", userWake: nil))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 3, day: 13, hour: 20, minute: 0)))
        let dates = try XCTUnwrap(plan.dates(after: evening, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.day, .hour, .minute], from: dates.wake), DateComponents(day: 14, hour: 6, minute: 30))
        XCTAssertEqual(dates.wake.timeIntervalSince(dates.bedtime), 442 * 60, accuracy: 0.5)
    }
    func testTheEfficiencyIsNamedWhenTheServerSendsIt() throws {
        var need = try XCTUnwrap(try document().sleepNeed)
        need.efficiency = 0.93
        XCTAssertEqual(need.efficiencyText, "time in bed = sleep \u{00F7} your typical sleep efficiency (93 %)")
    }
    func testNapsAreSignedSoTheTableAddsUp() {
        XCTAssertEqual([PFSleepNeed.signedHoursMinutes(-10), PFSleepNeed.signedHoursMinutes(30), PFSleepNeed.signedHoursMinutes(0)],
                       ["\u{2212}0:10", "+0:30", "0:00"])
    }
    func testHoursAndMinutesPadTheMinutes() {
        XCTAssertEqual(PFSleepNeed.hoursMinutes(505), "8:25")
    }
    func testTheEffortRowSaysTodaysWhenItUsesTodaysEffort() throws {
        let need = try XCTUnwrap(try document().sleepNeed)
        let row = try XCTUnwrap(need.rows.first { $0.key == "effort" })
        XCTAssertEqual(need.label(of: row), "Today's effort")
    }
    func testTheEffortRowSaysYesterdaysBeforeTodayIsScored() throws {
        var need = try XCTUnwrap(try document().sleepNeed)
        need.effortBasis = "yesterday, today is not scored yet"
        let row = try XCTUnwrap(need.rows.first { $0.key == "effort" })
        XCTAssertEqual(need.label(of: row), "Yesterday's effort")
    }
    func testAnUnavailableSleepNeedLeavesThePlannerOnItsOwnNumbers() throws {
        XCTAssertNil(try documentWithout("sleep_need_tonight").sleepNeed)
    }

    // MARK: What moved it

    func testAMovedMetricNamesTheDirectionAndSize() throws {
        let hrv = try XCTUnwrap(try document().moved?.metric("hrv"))
        XCTAssertEqual(hrv.headline, "Down 7.1 ms over 30 days")
    }
    func testAMovedMetricIsMarkedWorseOrBetter() throws {
        XCTAssertEqual(try XCTUnwrap(try document().moved?.metric("hrv")).chipText, "WORSE")
    }
    func testAMetricThatDidNotMoveIsSteady() throws {
        let sleep = try XCTUnwrap(try document().moved?.metric("sleep_hours"))
        XCTAssertEqual(sleep.headline, "Steady over 30 days")
        XCTAssertEqual(sleep.chipText, "STEADY")
    }
    func testAMetricWithoutEnoughDataSaysWhy() throws {
        let weight = try XCTUnwrap(try document().moved?.metric("weight"))
        XCTAssertEqual(weight.headline, "Needs 14 weigh-ins in 30 days")
        XCTAssertEqual(weight.chipText, "NOT ENOUGH DATA")
    }
    func testWhatLinedUpComesWithItsOwnSentence() throws {
        let hrv = try XCTUnwrap(try document().moved?.metric("hrv"))
        XCTAssertEqual(hrv.links.first?.sentence, "HRV runs lower after a late session (weak, r -0.31, n 60)")
    }
    func testTheActionOfAMovedMetricComesThrough() throws {
        XCTAssertEqual(try XCTUnwrap(try document().moved?.metric("hrv")).action?.id, "hrv_rule")
    }
    func testAMetricTheServerDoesNotMentionHasNoSection() throws {
        XCTAssertNil(try document().moved?.metric("effort"))
    }
    func testNoopCatalogKeysMapToTheServersMetrics() {
        XCTAssertEqual(["recovery", "strain", "hrv", "rhr", "sleep_total_min", "weight"].map { PFMovedMetricMap.intelKey(forCatalogKey: $0) },
                       ["charge", "effort", "hrv", "resting_hr", "sleep_hours", "weight"])
    }
    func testATrendMetricIdWithASourcePrefixMapsToo() {
        XCTAssertEqual(PFMovedMetricMap.intelKey(forMetricID: "my-whoop:recovery"), "charge")
    }
    func testAMetricNobodyTracksIsNotMapped() {
        XCTAssertNil(PFMovedMetricMap.intelKey(forMetricID: "my-whoop:stress"))
    }

    // MARK: Day in review and the evening switch

    func testTheReviewSaysTheTargetWasNotMet() throws {
        let review = try XCTUnwrap(try document().review)
        XCTAssertEqual(review.outcomeText, "TARGET NOT MET")
        XCTAssertEqual(review.effortText, "30 of 52\u{2013}71")
    }
    func testTheReviewKeepsTonightAndTomorrow() throws {
        let review = try XCTUnwrap(try document().review)
        XCTAssertEqual(review.tonight?.bedtime, "23:08")
        XCTAssertEqual(review.tomorrow?.name, "Synthetic easy run")
    }
    func testAMetTargetReadsAsMet() throws {
        var review = try XCTUnwrap(try document().review)
        review.targetMet = true
        XCTAssertEqual(review.outcomeText, "TARGET MET")
    }
    func testAPassedTargetSaysSo() throws {
        var review = try XCTUnwrap(try document().review)
        review.targetMet = true
        review.effort?.status = "above"
        XCTAssertEqual(review.outcomeText, "TARGET PASSED")
    }
    func testADayWithoutATargetSaysSo() throws {
        var review = try XCTUnwrap(try document().review)
        review.targetMet = nil
        XCTAssertEqual(review.outcomeText, "NO TARGET TODAY")
    }
    func testTheEveningStartsAtSixInTheEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2030, month: 3, day: 13, hour: hour, minute: minute)) ?? Date()
        }
        XCTAssertEqual([at(5, 59), at(17, 59), at(18, 0), at(23, 30)].map { PFEvening.isEvening($0, calendar: calendar) },
                       [false, false, true, true])
    }
}
