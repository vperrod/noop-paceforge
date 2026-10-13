import XCTest
@testable import Strand

/// The heart-rate-recovery card: a cool-down is explained instead of scored. All values are made up.
final class PaceForgeHRR1Tests: XCTestCase {
    private func hrr(_ text: String) -> PFHRR1? { PFBuilder.hrr1(PFJ(data: Data(text.utf8))) }

    func testWalkingKindIsANotScoredCoolDown() {
        XCTAssertEqual(hrr(#"{"kind":"walking","bpm":2,"stop_bpm":138,"peak_bpm":167}"#)?.isNotScoredCoolDown, true)
    }

    func testRisingAfterTheStopIsANotScoredCoolDownEvenForAPostKind() {
        XCTAssertEqual(hrr(#"{"kind":"post","bpm":9,"rising_after_stop":true}"#)?.isNotScoredCoolDown, true)
    }

    func testARealStopIsNotACoolDown() {
        XCTAssertEqual(hrr(#"{"kind":"post","bpm":23,"stop_bpm":152}"#)?.isNotScoredCoolDown, false)
    }

    func testTheNotScoredLineSaysWhy() {
        XCTAssertEqual(PFHRR1.notScoredLine,
                       "Not scored: heart rate was still high at the stop or rose in the last seconds (cool-down)")
    }
}
