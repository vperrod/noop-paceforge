import XCTest
@testable import Strand

/// A road-running prognosis exists only for a road-race goal (the server answers `available: false` for a HYROX goal, so a
/// half-marathon time can never be judged against it), and the Insights HYROX card lists only his own races (made-up numbers
/// here): no predicted finish is built from the race countdown any more.
final class PaceForgeHyroxPrognosisTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private let hyroxGoalPrognosis = """
    {"available": false, "reason": "not a running goal", "goal_type": "HYROX", "effective_vo2max": 50.0}
    """

    private let roadGoalPrognosis = """
    {"available": true, "prognosis_time_sec": 6300, "goal_time_sec": 6000, "goal_verdict": "stretch"}
    """

    private func race(_ label: String, _ date: String, _ seconds: Int) -> String {
        "{\"event_label\": \"\(label)\", \"event_date\": \"\(date)\", \"total_seconds\": \(seconds), \"total_display\": \"t\(seconds)\"}"
    }

    private func hyrox(_ rows: [String]) -> PFJ {
        json("{\"progression\": {\"races\": [\(rows.joined(separator: ","))]}}")
    }

    // MARK: The running prognosis against the goal

    func testAHyroxGoalHasNoRunningPrognosisAgainstIt() {
        XCTAssertNil(PFHyroxPrognosisParse.runningAgainstGoal(json(hyroxGoalPrognosis)))
    }

    func testAnUnavailablePrognosisIsNotShownEvenWithTimesPresent() {
        let stale = json("{\"available\": false, \"prognosis_time_sec\": 6500, \"goal_time_sec\": 3600, \"goal_verdict\": \"unrealistic\"}")
        XCTAssertNil(PFHyroxPrognosisParse.runningAgainstGoal(stale))
    }

    func testARoadGoalKeepsItsPrognosisAndVerdict() throws {
        let running = try XCTUnwrap(PFHyroxPrognosisParse.runningAgainstGoal(json(roadGoalPrognosis)))
        XCTAssertEqual(running.verdict, "stretch")
    }

    func testAMissingPrognosisBlockGivesNothing() {
        XCTAssertNil(PFHyroxPrognosisParse.runningAgainstGoal(PFJ(nil)))
    }

    // MARK: The races behind it

    func testOnlyTheLastSevenRacesAreListedOldestFirst() {
        let rows = (1...9).map { race("R\($0)", "2026-0\($0)-01", 3900 + $0) }
        XCTAssertEqual(PFHyroxPrognosisParse.races(hyrox(rows)).map(\.label), ["R3", "R4", "R5", "R6", "R7", "R8", "R9"])
    }

    func testTheFastestListedRaceIsTheOnlyPersonalBest() {
        let rows = [race("A", "2026-01-01", 4000), race("B", "2026-02-01", 3800), race("C", "2026-03-01", 3900)]
        XCTAssertEqual(PFHyroxPrognosisParse.races(hyrox(rows)).filter(\.isPersonalBest).map(\.label), ["B"])
    }

    func testARaceWithoutATimeIsSkipped() {
        let rows = [race("A", "2026-01-01", 3900), "{\"event_label\": \"DNF\", \"event_date\": \"2026-02-01\"}"]
        XCTAssertEqual(PFHyroxPrognosisParse.races(hyrox(rows)).map(\.label), ["A"])
    }

    func testNoRacesGivesAnEmptyList() {
        XCTAssertEqual(PFHyroxPrognosisParse.races(PFJ(nil)), [])
    }
}
