import XCTest
@testable import Strand

/// Daily movement: decoding of movement.json (steps against the usual range, intensity minutes, the last seven days), the chip, the
/// range-bar positions, the week bars and the wording. Every figure is made up.
final class PaceForgeMovementTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private func document(metric: String, available: Bool = true) -> PFJ {
        json("""
        {"version": 1, "as_of": "2030-03-13", "order": ["movement"],
         "items": {"movement": {"id": "movement", "title": "Synthetic", "available": \(available), "metric": \(metric),
           "status": {"label": "typical", "scale": ["low", "typical", "high"], "reason": null},
           "meaning": "Synthetic meaning.", "actions": [], "confidence": "medium", "data_note": "Synthetic note.",
           "source": ["Garmin"]}}}
        """)
    }

    private let metric = """
    {"as_of": "2030-03-13", "in_progress": true,
     "steps": {"today": 9482, "median_30d": 8600, "range_low": 7200, "range_high": 10400, "days_used": 28, "position": "typical"},
     "intensity": {"today": 42, "week_total": 118}, "walking_load": {"value": 3.2}, "strain_today": 6.1,
     "counted_in": ["Walking load"], "not_counted_in": ["Effort"],
     "series_7d": [{"date": "2030-03-11", "steps": 12000}, {"date": "2030-03-12", "steps": 6000}, {"date": "2030-03-13", "steps": null}]}
    """

    private func movement() -> PFMovement? { PFMovementParse.document(document(metric: metric)).value }

    func testStepsTodayAndRangeAreDecoded() throws {
        let m = try XCTUnwrap(movement())
        XCTAssertEqual([m.stepsToday, m.rangeLow ?? 0, m.rangeHigh ?? 0], [9482, 7200, 10400])
    }

    func testPositionOutsideLowTypicalHighIsDropped() throws {
        let odd = metric.replacingOccurrences(of: "\"typical\"}", with: "\"huge\"}")
        XCTAssertNil(PFMovementParse.document(document(metric: odd)).value?.position)
    }

    func testChipSaysDayNotOverWhileTheServerWithholdsALabel() throws {
        var m = try XCTUnwrap(movement())
        m.position = nil
        XCTAssertEqual(PFMovementLogic.chipText(m), "DAY NOT OVER")
    }

    func testUsualTextUsesAnEnDash() throws {
        let m = try XCTUnwrap(movement())
        XCTAssertEqual(PFMovementLogic.usualText(m), "Usual 7,200\u{2013}10,400")
    }

    func testRangeBarKeepsEveryPositionInsideTheBar() throws {
        var m = try XCTUnwrap(movement())
        m.stepsToday = 40000
        let bar = try XCTUnwrap(PFMovementLogic.rangeBar(m))
        XCTAssertTrue([bar.low, bar.high, bar.today].allSatisfy { (0...1).contains($0) })
    }

    func testWeekFractionsDrawAMissingDayAsNoBar() throws {
        let m = try XCTUnwrap(movement())
        XCTAssertEqual(PFMovementLogic.weekFractions(m.series), [1, 0.5, nil])
    }

    func testIntensityTextNamesTodayAndTheWeek() throws {
        let m = try XCTUnwrap(movement())
        XCTAssertEqual(PFMovementLogic.intensityText(m), "42 min today \u{00B7} 118 min in 7 days")
    }

    func testWeekdayLetterComesFromTheDateNotTheTimeZone() {
        XCTAssertEqual(PFMovementDay(date: "2030-03-13", steps: nil, intensityMin: nil, walkingLoad: nil).weekdayName, "Wednesday")
    }

    func testUnavailableItemCarriesTheServersReason() {
        let state = PFMovementParse.document(document(metric: "{}", available: false))
        XCTAssertNil(state.value)
    }

    func testNegativeStepsAreNotAMovement() {
        XCTAssertNil(PFMovementParse.document(document(metric: "{\"steps\": {\"today\": -5}}")).value)
    }
}
