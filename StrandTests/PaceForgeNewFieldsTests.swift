import XCTest
@testable import Strand

/// The detail, fitness and profile fields the server added on 2026-10-28/29. Shapes follow the server's emitting functions; every number is made up.
final class PaceForgeNewFieldsTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    func testRunExplainerReadsTheTextKeys() {
        let j = json(#"{"looks_like": "easy_run", "purpose": "Aerobic base.", "feel": "Chatty.", "body": "Mitochondria.", "energy": "Fat.", "shape": "Even.", "payoff": "Base."}"#)
        let e = PFRunExplainer.parse(j)
        XCTAssertEqual(e?.looksLike, "easy_run")
        XCTAssertEqual(e?.payoff, "Base.")
    }

    func testRunExplainerWithoutTextIsNil() {
        XCTAssertNil(PFRunExplainer.parse(json(#"{"looks_like": "easy_run"}"#)))
    }

    func testLtSplitReadsBandsAndThreshold() {
        let s = PFLtSplit.parse(json(#"{"lt_hr": 165.0, "below_s": 600, "at_s": 120, "above_s": 30, "lt_pace_sec_per_km": 263, "lt_date": "2030-01-15"}"#))
        XCTAssertEqual(s?.totalS, 750)
        XCTAssertEqual(s?.ltPaceSecPerKm, 263)
    }

    func testEffortRankChipWordBands() {
        let words = [90, 60, 35, 10].map { PFEffortRank(pct: $0).chipWord }
        XCTAssertEqual(words, ["among your hardest", "harder than usual", "typical for you", "lighter than usual"])
    }

    func testEffortRankReadsClassCorrectionAndNullRecovery() {
        let r = PFEffortRank.parse(json(#"{"pct": 72, "n": 31, "days": 90, "trimp": 80.5, "raw_trimp": 60.0, "class_factor": 1.34, "anaerobic_te": 1.2, "recovery": null}"#))
        XCTAssertEqual(r?.classFactor, 1.34)
        XCTAssertNil(r?.recovery)
    }

    func testEffortRankWithoutPctIsNil() {
        XCTAssertNil(PFEffortRank.parse(json(#"{"n": 31}"#)))
    }

    func testZoneSetsReadFloorsAndSkipOlderShape() {
        let sets = PFZoneSet.parseAll(json(#"[{"sport": "RUNNING", "floors": [94, 112, 131, 150, 168], "max": 187, "lt": 165, "resting": 50}, {"sport": "DEFAULT", "max": 190}]"#))
        XCTAssertEqual(sets.map(\.floors), [[94, 112, 131, 150, 168], []])
    }

    func testProfileAlertDecodesLikeAnyLiveAlert() {
        let text = #"{"alerts": [{"id": "a1", "kind": "live_lt_stale", "severity": "info", "title": "Lactate threshold not re-measured", "status": "open", "metrics": {"push": false, "reading": "165 bpm, measured 2029-12-01", "source": "Garmin lactate threshold", "plan_effect": "None."}}]}"#
        let alerts = PFBuilder.alertHistory(json(text))
        XCTAssertEqual(alerts.first?.live?.planEffect, "None.")
    }
}
