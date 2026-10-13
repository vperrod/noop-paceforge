import XCTest
@testable import Strand

/// Garmin's own recovery HR on the heart-rate-recovery card. The two documents are the shapes the server files
/// today (`hrr_garmin`); the absent case is a session saved before the watch finished its 2-minute countdown.
final class PaceForgeHRRGarminTests: XCTestCase {
    private func garmin(_ text: String) -> PFHRRGarmin? { PFHRRGarmin.parse(PFJ(data: Data(text.utf8))) }

    private let first = #"{"drop_bpm":46,"hr_2min":103,"stop_bpm":149,"source":"garmin_recovery_hr"}"#
    private let second = #"{"drop_bpm":32,"hr_2min":116,"stop_bpm":148,"source":"garmin_recovery_hr"}"#

    func testTheFirstRealDocumentReadsItsThreeNumbers() {
        XCTAssertEqual(garmin(first), PFHRRGarmin(dropBpm: 46, hr2min: 103, stopBpm: 149))
    }

    func testTheSecondRealDocumentReadsItsThreeNumbers() {
        XCTAssertEqual(garmin(second), PFHRRGarmin(dropBpm: 32, hr2min: 116, stopBpm: 148))
    }

    func testTheHeadlineStatesTheDropOverTwoMinutes() {
        XCTAssertEqual(garmin(first)?.headline, "Garmin recovery heart rate: -46 bpm in 2 minutes")
    }

    func testTheDetailLineGivesTheStopAndTheTwoMinuteReading() {
        XCTAssertEqual(garmin(first)?.detail, "149 at the stop, 103 two minutes later")
    }

    func testTheSecondDetailLineGivesItsOwnReadings() {
        XCTAssertEqual(garmin(second)?.detail, "148 at the stop, 116 two minutes later")
    }

    func testADropAloneKeepsTheHeadlineAndHasNoDetailLine() {
        let g = garmin(#"{"drop_bpm":32,"hr_2min":null,"stop_bpm":null,"source":"garmin_recovery_hr"}"#)
        XCTAssertEqual(g?.headline, "Garmin recovery heart rate: -32 bpm in 2 minutes")
        XCTAssertNil(g?.detail)
    }

    func testMissingKeysDecodeAsNoDetailInsteadOfFailing() {
        XCTAssertEqual(garmin(#"{"drop_bpm":40}"#), PFHRRGarmin(dropBpm: 40, hr2min: nil, stopBpm: nil))
    }

    func testOnlyOneOfTheTwoReadingsGivesNoDetailLine() {
        XCTAssertNil(garmin(#"{"drop_bpm":40,"stop_bpm":150}"#)?.detail)
    }

    func testARiseInHeartRateShowsAPlusSign() {
        XCTAssertEqual(garmin(#"{"drop_bpm":-3}"#)?.headline, "Garmin recovery heart rate: +3 bpm in 2 minutes")
    }

    func testNoDropShowsZeroWithoutASign() {
        XCTAssertEqual(garmin(#"{"drop_bpm":0}"#)?.headline, "Garmin recovery heart rate: 0 bpm in 2 minutes")
    }

    func testAnAbsentDocumentIsNil() {
        XCTAssertNil(PFHRRGarmin.parse(PFJ(data: Data(#"{"hrr1":{"kind":"post"}}"#.utf8))["hrr_garmin"]))
    }

    func testANullDocumentIsNil() {
        XCTAssertNil(PFHRRGarmin.parse(PFJ(data: Data(#"{"hrr_garmin":null}"#.utf8))["hrr_garmin"]))
    }

    func testADocumentWithoutADropIsNil() {
        XCTAssertNil(garmin(#"{"hr_2min":103,"stop_bpm":149}"#))
    }

    func testADropOfTheWrongTypeIsNil() {
        XCTAssertNil(garmin(#"{"drop_bpm":"46"}"#))
    }

    func testTheTipTellsWhatToDoWhenGarminRecordedNothing() {
        XCTAssertEqual(PFHRRGarmin.tip, "To get Garmin's recovery HR: after the last Stop wait 2 minutes before Save.")
    }
}
