import XCTest
@testable import Strand

/// A failed Apple Health steps read costs only steps: the other metrics still sync, the stored step counts are
/// written back unchanged, and the failure is on record so the next sync (and Today) can act on it.
final class AppleSyncLedgerTests: XCTestCase {

    private func ledger(failing labels: [String]) -> AppleSyncLedger {
        var l = AppleSyncLedger()
        for label in ["restingHeartRate", "stepCount", "vo2Max"] { l.record(label, failed: labels.contains(label)) }
        return l
    }

    func testAFailedStepsReadDoesNotBlockTheOtherMetrics() {
        XCTAssertEqual(ledger(failing: ["stepCount"]).blockingFailures, [])
    }

    func testAFailedStepsReadIsRecorded() {
        XCTAssertTrue(ledger(failing: ["stepCount"]).stepsFailed)
    }

    func testAFailedStepsReadIsListedAmongTheFailures() {
        XCTAssertEqual(ledger(failing: ["stepCount"]).allFailures, ["stepCount"])
    }

    func testAFailedOtherMetricStillBlocksTheWrite() {
        XCTAssertEqual(ledger(failing: ["vo2Max"]).blockingFailures, ["vo2Max"])
    }

    func testStepsAndAnotherMetricFailingBlocksOnlyOnTheOther() {
        XCTAssertEqual(ledger(failing: ["stepCount", "restingHeartRate"]).blockingFailures, ["restingHeartRate"])
    }

    func testACleanPassHasNoFailures() {
        XCTAssertEqual(ledger(failing: []).allFailures, [])
    }

    func testACleanPassDoesNotReportStepsFailed() {
        XCTAssertFalse(ledger(failing: []).stepsFailed)
    }

    func testFailedStepsReadKeepsTheStoredCount() {
        XCTAssertEqual(AppleSyncLedger.stepsForWrite(stepsFailed: true, fresh: nil, stored: 8_300), 8_300)
    }

    func testFailedStepsReadWithNothingStoredStaysEmpty() {
        XCTAssertNil(AppleSyncLedger.stepsForWrite(stepsFailed: true, fresh: nil, stored: nil))
    }

    func testGoodStepsReadReplacesTheStoredCount() {
        XCTAssertEqual(AppleSyncLedger.stepsForWrite(stepsFailed: false, fresh: 9_100, stored: 8_300), 9_100)
    }

    func testGoodStepsReadMayRecordAnEmptyDay() {
        XCTAssertNil(AppleSyncLedger.stepsForWrite(stepsFailed: false, fresh: nil, stored: 8_300))
    }
}
