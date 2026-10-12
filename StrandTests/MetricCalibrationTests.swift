import XCTest
@testable import Strand

/// The "N nights to go" copy on the HRV and Vital Signs sheets counts down from the engine's own
/// thresholds (4 valid nights to seed a baseline, 14 to trust it) and goes quiet once they are met.
final class MetricCalibrationTests: XCTestCase {
    func testNoNightsYetCountsDownToTheSeed() {
        XCTAssertEqual(MetricCalibration.hrvLine(nights: 0, seed: 4, trust: 14),
                       "4 nights to go before Charge can use your HRV baseline. It is fully trusted after 14 nights.")
    }

    func testOneNightShortOfTheSeedIsSingular() {
        XCTAssertTrue(MetricCalibration.hrvLine(nights: 3, seed: 4, trust: 14)?.hasPrefix("1 night to go ") == true)
    }

    func testBetweenSeedAndTrustTheBaselineIsProvisional() {
        XCTAssertEqual(MetricCalibration.hrvLine(nights: 9, seed: 4, trust: 14),
                       "Your baseline is provisional: 5 nights to go until it is fully trusted.")
    }

    func testATrustedBaselineHasNoCalibrationLine() {
        XCTAssertNil(MetricCalibration.hrvLine(nights: 14, seed: 4, trust: 14))
    }

    func testVitalsCountDownToTheTrustThreshold() {
        XCTAssertTrue(MetricCalibration.vitalsLine(nights: 10, trust: 14)?.hasPrefix("4 nights to go until in range") == true)
    }

    func testVitalsGoQuietOnceTheBaselineIsTrusted() {
        XCTAssertNil(MetricCalibration.vitalsLine(nights: 20, trust: 14))
    }

    func testStressHasNoMinimumToCountDownTo() {
        XCTAssertNil(MetricCalibration.line(for: .stress, hrvNights: 0))
    }

    func testTheDefaultsFollowTheEnginesConstants() {
        XCTAssertNotNil(MetricCalibration.hrvLine(nights: 0))
    }
}
