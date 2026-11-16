import XCTest

/// The Sunday review block decodes in the shape the server writes (`week_review.py`), and a part it sends in a shape this build does not
/// know never takes the rest of the block (or the week document that carries it) down. Synthetic values.
final class PFWeekReviewDoc530Tests: XCTestCase {
    private func decode(_ json: String) throws -> PFWeekReviewDoc530 {
        try PFPlan529Decoder.make().decode(PFWeekReviewDoc530.self, from: Data(json.utf8))
    }

    func testServerShapeDecodes() throws {
        let doc = try decode("""
        {"training_days": [{"dow": "M", "minutes": 28, "effort": "easy"}, {"dow": "T", "minutes": 0, "effort": null}],
         "hours": {"this_label": "3 h 25", "this_h": 3.42, "usual_weeks": 4, "usual_label": "6 h 16", "usual_h": 6.27, "pct_vs_usual": -45,
                   "planned_done": {"done": 4, "planned": 4}},
         "race_losses": [{"date": "2030-02-27", "name": "Singles", "against": "plan", "losses": [{"station": "Wall Balls", "seconds": 45}]}],
         "sleep": {"source": "Garmin", "hours": [8.12, null], "labels": ["8:07", null], "need_h": 7.67, "short_nights": 5, "avg_label": "6 h 56"},
         "hrv_rhr": [{"source": "Garmin", "hrv": [47, null], "rhr": [50, 51], "hrv_usual": 36}],
         "readings": {"training": "Done.", "hrv_rhr": "Together."},
         "ahead": {"week": "2030-W10", "headline": "Recover.", "calendar": [{"phase": "recover", "days": 9, "from": "2030-03-04", "to": "2030-03-12"}],
                   "next_race": {"name": "Paris", "date": "2030-04-03", "goal": "1:03:00"}, "mix": [{"type": "classes", "minutes": 180}],
                   "calendar_reading": "Recovery part."}}
        """)
        XCTAssertEqual(doc.hours?.plannedDone?.planned, 4)
        XCTAssertEqual(doc.raceLosses?.first?.losses?.first?.seconds, 45)
        XCTAssertEqual(doc.sleep?.hours?.compactMap { $0 }, [8.12])
        XCTAssertEqual(doc.hrvRhr?.first?.hrvUsual, 36)
        XCTAssertNil(doc.hrvRhr?.first?.rhrUsual)
        XCTAssertEqual(doc.readings?.hrvRhr, "Together.")
        XCTAssertEqual(doc.ahead?.nextRace?.goal, "1:03:00")
        XCTAssertEqual(doc.ahead?.calendar?.first?.days, 9)
    }

    func testAFieldOfAnUnknownShapeReadsAsNilAndKeepsItsNeighbours() throws {
        let doc = try decode(#"{"hours": {"this_label": "3 h 25", "planned_done": "4 of 4"}, "sleep": "none", "readings": {"training": "Done."}}"#)
        XCTAssertEqual(doc.hours?.thisLabel, "3 h 25")
        XCTAssertNil(doc.hours?.plannedDone)
        XCTAssertNil(doc.sleep)
        XCTAssertEqual(doc.readings?.training, "Done.")
    }

    func testAnEntryThatCannotBeReadIsLeftOutOfItsList() throws {
        let doc = try decode(#"{"training_days": [{"dow": "M", "minutes": 28}, "broken", {"dow": "W", "minutes": 68}]}"#)
        XCTAssertEqual(doc.trainingDays?.compactMap { $0.dow }, ["M", "W"])
    }

    func testTheWeekDocumentSurvivesAReviewBlockOfTheWrongShape() throws {
        let json = #"{"week": "2030-W09", "state": "finished", "report": {"verdict": "Done.", "review": [1, 2]}}"#
        let week = try PFPlan529Decoder.make().decode(PFPlanWeekDoc.self, from: Data(json.utf8))
        XCTAssertEqual(week.report?.verdict, "Done.")
    }
}
