import XCTest
@testable import Strand

/// The hidden score keys must stay the keys the hero rings and their Key-Metrics tiles use.
final class HideScoresKeysTests: XCTestCase {
    func testTheScoreKeysAreTheHeroRingKeys() {
        XCTAssertEqual(HideScoresPrefs.scoreMetricKeys, Set(HeroRingMetric.all))
    }
}
