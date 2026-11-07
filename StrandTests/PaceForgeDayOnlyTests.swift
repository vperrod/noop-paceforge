import XCTest
@testable import Strand

/// Which parts of Today a day-only wearer (the watch is worn by day, never overnight) sees. Only an explicit `day_only: true` from the
/// server changes anything; an unknown answer keeps every screen as it is. All values are made up.
final class PaceForgeDayOnlyTests: XCTestCase {
    private func capabilities(_ text: String) -> PFCapabilities? {
        PFReportParse.capabilities(PFJ(data: Data(text.utf8)))
    }

    func testDayOnlyTrueHidesTheOvernightParts() {
        XCTAssertEqual(capabilities(#"{"day_only": true, "wears_overnight": false}"#)?.showsOvernight, false)
    }

    func testDayOnlyFalseKeepsTheOvernightParts() {
        XCTAssertEqual(capabilities(#"{"day_only": false, "wears_overnight": true}"#)?.showsOvernight, true)
    }

    func testAFlagTheFileDoesNotCarryKeepsTheOvernightParts() {
        XCTAssertEqual(capabilities(#"{"has_sleep": false, "has_hrv": false}"#)?.showsOvernight, true)
    }

    func testNoSleepDataAloneDoesNotHideAnything() {
        XCTAssertEqual(capabilities(#"{"day_only": false, "has_sleep": false, "has_hrv": false, "has_readiness": false}"#)?.showsOvernight, true)
    }

    func testAMissingFileReadsAsNoCapabilities() {
        XCTAssertNil(capabilities("{}"))
    }

    func testDayOnlyDoesNotTakeTheReportsAway() {
        XCTAssertEqual(PFCapabilities(reportsScheduled: true, reportReview: true, dayOnly: true).showsReports, true)
    }

    func testAnUnknownDayOnlyFlagKeepsTheOvernightParts() {
        XCTAssertTrue(PFCapabilities().showsOvernight)
    }
}
