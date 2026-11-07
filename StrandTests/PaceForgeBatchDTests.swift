import XCTest
@testable import Strand

/// The batch D documents: sleep settle, sleep tiles, stage shares, weekly stress load and active hours. Every figure is made up; the key
/// names are the server's.
final class PaceForgeBatchDTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    // MARK: Sleep settle

    private let settle = """
    {"generated_at": "2030-03-13T07:40:00", "source": "WHOOP strap via NOOP",
     "nights": [{"date": "2030-03-12", "onset": "2030-03-11T23:10", "lowest_bpm": 48.2, "lowest_after_onset_min": 200, "lowest_at": "2030-03-12T02:30",
                 "settle_after_onset_min": 55, "within_bpm": 3.0, "coverage_pct": 91.0, "quality": "ok", "line": "Heart rate settled 55 min after you fell asleep; lowest 48 bpm, 3 h 20 min in"},
                {"date": "2030-03-13", "onset": "2030-03-12T23:30", "lowest_bpm": 47.0, "lowest_after_onset_min": 180, "lowest_at": "2030-03-13T02:30",
                 "settle_after_onset_min": 40, "within_bpm": 3.0, "coverage_pct": 93.0, "quality": "ok", "line": "Night line."}],
     "status": {"state": "in_band", "settle_min": 40, "baseline_min": 48, "band_low_min": 30, "band_high_min": 66, "nights_used": 20,
                "line": "Heart rate settled 40 min after you fell asleep, about your usual (48 min)", "gloss": "Settle time gloss.", "source": "WHOOP strap via NOOP"}}
    """

    func testTheSettleSentenceIsTheStatusLineOnceItCanCompare() throws {
        let s = try XCTUnwrap(PFBatchDParse.sleepSettle(json(settle)))
        XCTAssertEqual(s.latest?.date, "2030-03-13")
        XCTAssertEqual(s.latest?.settleAfterOnsetMin, 40)
        XCTAssertEqual(s.status?.state, "in_band")
        XCTAssertEqual(s.sentence, "Heart rate settled 40 min after you fell asleep, about your usual (48 min)")
        XCTAssertEqual(s.source, "WHOOP strap via NOOP")
    }

    func testWhileCalibratingTheSentenceIsTheNightsOwnLine() throws {
        let calibrating = settle.replacingOccurrences(of: "\"line\": \"Heart rate settled 40 min after you fell asleep, about your usual (48 min)\"", with: "\"line\": null")
        let s = try XCTUnwrap(PFBatchDParse.sleepSettle(json(calibrating)))
        XCTAssertEqual(s.sentence, "Night line.")
    }

    func testNoNightsOrNoFileMeansNoSettleLine() {
        XCTAssertNil(PFBatchDParse.sleepSettle(json("{\"nights\": [], \"status\": {\"state\": \"calibrating\"}}")))
        XCTAssertNil(PFBatchDParse.sleepSettle(PFJ(nil)))
    }

    // MARK: Sleep tiles

    private let tiles = """
    {"generated_at": "2030-03-13T07:40:00", "source": "PaceForge (Garmin)",
     "gloss": {"duration": "Duration gloss.", "efficiency": "Efficiency gloss.", "restorative": "Restorative gloss.", "consistency": "Consistency gloss."},
     "nights": [{"date": "2030-03-12", "tiles": {"duration": {"value": 80.0, "unit": "% of need", "text": "old", "standing": "usual"}}},
                {"date": "2030-03-13", "tiles": {
                  "duration": {"value": 91.2, "unit": "% of need", "text": "7 h 20 min asleep, 91% of your 8 h 00 min need", "usual": 88.0, "band_low": 80.0, "band_high": 96.0, "standing": "usual", "baseline_nights": 28, "source": "PaceForge (Garmin)"},
                  "efficiency": {"value": 93.0, "unit": "%", "text": "93% of your time in bed asleep", "usual": 90.0, "band_low": 87.0, "band_high": 93.0, "standing": "usual", "baseline_nights": 28},
                  "restorative": {"value": 41.0, "unit": "% of sleep", "text": "41% of your sleep was deep or REM", "usual": 35.0, "band_low": 30.0, "band_high": 40.0, "standing": "better", "baseline_nights": 28},
                  "consistency": {"value": null, "unit": "min", "text": null, "usual": null, "band_low": null, "band_high": null, "standing": "unavailable", "baseline_nights": 0}}}]}
    """

    func testTheLatestNightsTilesComeInTheCardsOrderWithTheirGloss() throws {
        let t = try XCTUnwrap(PFBatchDParse.sleepTiles(json(tiles)))
        XCTAssertEqual(t.date, "2030-03-13")
        XCTAssertEqual(t.tiles.map { $0.key }, ["duration", "efficiency", "restorative"])
        XCTAssertEqual(t.tiles[2].standing, "better")
        XCTAssertEqual(t.tiles[0].bandHigh, 96.0)
        XCTAssertEqual(t.tiles[1].gloss, "Efficiency gloss.")
    }

    func testAnUnavailableTileIsLeftOut() throws {
        let t = try XCTUnwrap(PFBatchDParse.sleepTiles(json(tiles)))
        XCTAssertNil(t.tiles.first { $0.key == "consistency" })
    }

    func testANightWithNoUsableTileGivesNothing() {
        let none = "{\"nights\": [{\"date\": \"2030-03-13\", \"tiles\": {\"duration\": {\"value\": null, \"standing\": \"unavailable\"}}}]}"
        XCTAssertNil(PFBatchDParse.sleepTiles(json(none)))
    }

    func testStandingWords() {
        XCTAssertEqual(PFBatchDLogic.standingWord("better"), "Better than usual")
        XCTAssertEqual(PFBatchDLogic.standingWord("calibrating"), "Calibrating")
        XCTAssertNil(PFBatchDLogic.standingWord("unavailable"))
    }

    // MARK: Stage shares

    private let shares = """
    {"source": "Garmin", "caveat": "Stages timed from a wrist are estimates.", "gloss": "A stage share is the portion of your sleep.",
     "nights": [{"date": "2030-03-13", "shares": {
        "deep": {"pct": 12.0, "usual_pct": 18.0, "deviation_pts": -6.0, "large": true, "direction": "lower"},
        "rem": {"pct": 22.0, "usual_pct": 21.0, "deviation_pts": 1.0, "large": false, "direction": null},
        "light": {"pct": 66.0, "usual_pct": null, "deviation_pts": null, "large": false, "direction": null}},
       "line": "Deep sleep was 6 points lower than your usual (12% against 18%). A wrist is a weak judge of sleep stages, so take it as a hint."}]}
    """

    func testStageSharesKeepTheirOrderCaveatAndLargeDeviation() throws {
        let s = try XCTUnwrap(PFBatchDParse.stageShares(json(shares)))
        XCTAssertEqual(s.shares.map { $0.key }, ["deep", "rem", "light"])
        XCTAssertEqual(s.caveat, "Stages timed from a wrist are estimates.")
        XCTAssertEqual(PFBatchDLogic.stageWord(s.shares[0]), "Lower than usual")
        XCTAssertNil(PFBatchDLogic.stageWord(s.shares[1]))
        XCTAssertNil(s.shares[2].usualPct)
        XCTAssertNotNil(s.line)
    }

    func testANightWithNoSharesGivesNothing() {
        XCTAssertNil(PFBatchDParse.stageShares(json("{\"nights\": [{\"date\": \"2030-03-13\", \"shares\": {}}]}")))
    }

    // MARK: Weekly stress load

    private let stress = """
    {"source": "Garmin", "gloss": "Stress here is Garmin's all-day stress level.", "available": true, "reason": null, "own_high_level": 58,
     "norm": {"high_hours_per_day": 2.1, "restful_min_per_day": 95.0, "days": 40},
     "weeks": [{"week_start": "2030-02-25", "days": 7, "complete": true, "high_hours": 14.0, "high_hours_per_day": 2.0, "restful_min": 650, "restful_min_per_day": 92.9},
               {"week_start": "2030-03-04", "days": 7, "complete": true, "high_hours": 17.5, "high_hours_per_day": 2.5, "restful_min": 600, "restful_min_per_day": 85.7},
               {"week_start": "2030-03-11", "days": 3, "complete": false, "high_hours": 9.0, "high_hours_per_day": 3.0, "restful_min": 240, "restful_min_per_day": 80.0}],
     "trend": {"high_hours": "rising", "restful_min": "falling"}, "line": "Week of 2030-03-11: 3.0 h a day above your high-stress level."}
    """

    func testTheStressWeeksNormAndTrendsAreDecoded() throws {
        let load = try XCTUnwrap(PFBatchDParse.stressLoad(json(stress)))
        XCTAssertEqual(load.weeks.count, 3)
        XCTAssertFalse(load.weeks[2].complete)
        XCTAssertEqual(load.normHighHoursPerDay, 2.1)
        XCTAssertEqual(PFBatchDLogic.trendWord(load.highTrend), "Rising")
        XCTAssertEqual(PFBatchDLogic.trendWord(load.restfulTrend), "Falling")
        XCTAssertEqual(PFBatchDLogic.trendWord("unknown"), nil)
    }

    func testAnUnavailableStressLoadLeavesTheCardOut() {
        let off = "{\"available\": false, \"reason\": \"Not enough stress readings yet.\", \"weeks\": []}"
        XCTAssertNil(PFBatchDParse.stressLoad(json(off)))
        XCTAssertNil(PFBatchDParse.stressLoad(PFJ(nil)))
    }

    func testFractionKeepsABarInsideTheTrackAndRefusesNoMaximum() {
        XCTAssertEqual(PFBatchDLogic.fraction(2.5, of: 5), 0.5)
        XCTAssertEqual(PFBatchDLogic.fraction(9, of: 5), 1)
        XCTAssertNil(PFBatchDLogic.fraction(1, of: 0))
    }

    // MARK: Active hours

    private let active = """
    {"source": "Garmin", "gloss": "An active hour is a clock hour in which you took at least 250 steps.", "hour_steps": 250, "available": true, "reason": null,
     "days": [{"date": "2030-03-12", "active_hours": 9, "steps": 8000}],
     "metric": {"as_of": "2030-03-12", "active_hours": 9, "median_30d": 10.0, "band_low": 8.0, "band_high": 12.0, "days_used": 28, "status": "typical"},
     "line": "On Tuesday 12 Mar you were active in 9 different hours of the day, about your usual (10)."}
    """

    func testActiveHoursKeepTheMetricAndTheLine() throws {
        let a = try XCTUnwrap(PFBatchDParse.activeHours(json(active)))
        XCTAssertEqual(a.activeHours, 9)
        XCTAssertEqual(a.median, 10.0)
        XCTAssertEqual(a.hourSteps, 250)
        XCTAssertEqual(PFBatchDLogic.activeStatusWord(a.status), "About your usual")
    }

    func testCalibratingActiveHoursHaveNoLineButStillShowTheCount() throws {
        let calibrating = active.replacingOccurrences(of: "\"median_30d\": 10.0", with: "\"median_30d\": null")
            .replacingOccurrences(of: "\"status\": \"typical\"", with: "\"status\": \"calibrating\"")
            .replacingOccurrences(of: "\"line\": \"On Tuesday 12 Mar you were active in 9 different hours of the day, about your usual (10).\"", with: "\"line\": null")
        let a = try XCTUnwrap(PFBatchDParse.activeHours(json(calibrating)))
        XCTAssertNil(a.median)
        XCTAssertNil(a.line)
        XCTAssertEqual(PFBatchDLogic.activeStatusWord(a.status), "Calibrating")
    }

    func testUnavailableActiveHoursLeaveTheLineOut() {
        XCTAssertNil(PFBatchDParse.activeHours(json("{\"available\": false, \"reason\": \"No finished day.\", \"metric\": null}")))
    }

    func testThePathsAreTheServersDocuments() {
        XCTAssertEqual(PFBatchDParse.all.count, 5)
        XCTAssertFalse(PFBatchDParse.all.contains { $0.contains("shadow") })
    }
}
