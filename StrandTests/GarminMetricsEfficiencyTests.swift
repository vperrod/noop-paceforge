import XCTest
@testable import Strand

/// PaceForge's Garmin metrics carry sleep efficiency as a fraction; anything else is read as no efficiency.
final class GarminMetricsEfficiencyTests: XCTestCase {

    func testAFractionIsRead() {
        XCTAssertEqual(SelfHostedPushClient.garminSleepEfficiency(["efficiency": NSNumber(value: 0.91)]), 0.91)
    }

    func testAMissingKeyGivesNoEfficiency() {
        XCTAssertNil(SelfHostedPushClient.garminSleepEfficiency(["sleepSeconds": NSNumber(value: 27_000)]))
    }

    func testAPercentIsRejected() {
        XCTAssertNil(SelfHostedPushClient.garminSleepEfficiency(["efficiency": NSNumber(value: 91)]))
    }

    func testANegativeValueIsRejected() {
        XCTAssertNil(SelfHostedPushClient.garminSleepEfficiency(["efficiency": NSNumber(value: -0.1)]))
    }

    func testANonFiniteValueIsRejected() {
        XCTAssertNil(SelfHostedPushClient.garminSleepEfficiency(["efficiency": NSNumber(value: Double.nan)]))
    }
}
