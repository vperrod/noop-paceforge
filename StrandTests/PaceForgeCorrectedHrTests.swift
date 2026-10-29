import XCTest
@testable import Strand

/// The heart rate of an activity PaceForge corrected (the wrist sensor locked onto cadence): `avg_hr` / `max_hr` are then the corrected
/// figures, `avg_hr_raw` / `max_hr_raw` the ones the watch recorded and `hr_quality` says what was ignored. All values are made up.
final class PaceForgeCorrectedHrTests: XCTestCase {
    private func activity(_ text: String) -> PFActivity? {
        PFBuilder.activity(PFJ(data: Data(text.utf8)))
    }

    private let corrected = """
    {"activity_id": 91, "name": "Easy run", "activity_type": "running", "avg_hr": 125, "max_hr": 146,
     "avg_hr_raw": 133, "max_hr_raw": 158, "hr_quality": "Wrist HR locked to cadence for 9 minutes."}
    """

    func testACorrectedActivityIsMarked() {
        XCTAssertEqual(activity(corrected)?.hasCorrectedHr, true)
    }

    func testTheCorrectedFiguresStayTheActivitysHeartRate() {
        XCTAssertEqual(activity(corrected)?.avgHr, 125)
    }

    func testTheRecordedFiguresAreKeptBesideThem() {
        let recorded = activity(corrected)?.recordedHr
        XCTAssertEqual([recorded?.avg, recorded?.peak], [133, 158])
    }

    func testAnUncorrectedActivityIsNotMarked() {
        XCTAssertEqual(activity(#"{"activity_id": 92, "avg_hr": 140, "max_hr": 160}"#)?.hasCorrectedHr, false)
    }

    func testAnUncorrectedActivityHasNoRecordedLine() {
        XCTAssertNil(activity(#"{"activity_id": 92, "avg_hr": 140, "max_hr": 160}"#)?.recordedHr)
    }

    func testACorrectionWithoutARecordedAverageHasNoRecordedLine() {
        let text = #"{"activity_id": 93, "avg_hr": 125, "max_hr": 146, "avg_hr_raw": null, "max_hr_raw": 158, "hr_quality": "Wrist HR locked to cadence."}"#
        XCTAssertNil(activity(text)?.recordedHr)
    }
}
