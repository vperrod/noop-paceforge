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

    func testNoPostStopDataKeepsItsKindAndTheServersReason() {
        let h = hrr(#"{"kind":"no_post_stop_data","bpm":null,"stop_bpm":148,"peak_bpm":163,"reason":"Garmin stopped recording at the stop; keep the activity recording for 2 minutes after your last effort to measure recovery"}"#)
        XCTAssertEqual(h?.kind, PFHRR1.noPostStopData)
        XCTAssertEqual(h?.reason, "Garmin stopped recording at the stop; keep the activity recording for 2 minutes after your last effort to measure recovery")
    }

    func testNoPostStopDataIsNeverScoredAndHasNoDrop() {
        let h = hrr(#"{"kind":"no_post_stop_data","bpm":null,"stop_bpm":148,"peak_bpm":163}"#)
        XCTAssertEqual(h?.isScored, false)
        XCTAssertNil(h?.bpm)
    }

    func testNoPostStopDataIsNotCollapsedIntoNotMeasurable() {
        XCTAssertNotEqual(hrr(#"{"kind":"no_post_stop_data","stop_bpm":148}"#)?.kind, PFHRR1.notMeasurable)
    }

    func testAnOlderServerWithoutAReasonStillHasTheFallbackLine() {
        XCTAssertTrue(PFHRR1.noPostStopLine.hasPrefix("Garmin stopped recording at the stop"))
    }
}
