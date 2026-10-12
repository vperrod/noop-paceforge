import XCTest
@testable import Strand

/// Hide scores: which tiles each switch covers, and what a hidden value reads. All values are made up.
final class HideScoresTests: XCTestCase {

    func testTheScoreSwitchCoversCharge() {
        XCTAssertTrue(HideScoresPrefs.hides(key: "recovery", scores: true, body: false))
    }

    func testTheScoreSwitchCoversEffortAndRest() {
        XCTAssertEqual(["strain", "sleep_performance"].map { HideScoresPrefs.hides(key: $0, scores: true, body: false) }, [true, true])
    }

    func testTheScoreSwitchDoesNotCoverWeight() {
        XCTAssertFalse(HideScoresPrefs.hides(key: "weight", scores: true, body: false))
    }

    func testTheBodySwitchCoversWeightAndBodyFat() {
        XCTAssertEqual(["weight", "body_fat"].map { HideScoresPrefs.hides(key: $0, scores: false, body: true) }, [true, true])
    }

    func testTheBodySwitchDoesNotCoverCharge() {
        XCTAssertFalse(HideScoresPrefs.hides(key: "recovery", scores: false, body: true))
    }

    func testWithBothOffNothingIsHidden() {
        XCTAssertEqual(["recovery", "weight", "hrv"].map { HideScoresPrefs.hides(key: $0, scores: false, body: false) },
                       [false, false, false])
    }

    func testOtherMetricsAreNeverHidden() {
        XCTAssertFalse(HideScoresPrefs.hides(key: "hrv", scores: true, body: true))
    }

    func testATileWithNoKeyIsNeverHidden() {
        XCTAssertFalse(HideScoresPrefs.hides(key: nil, scores: true, body: true))
    }

    func testAHiddenValueReadsHidden() {
        XCTAssertEqual(HideScoresPrefs.shown("82", hidden: true), "Hidden")
    }

    func testAVisibleValueIsUnchanged() {
        XCTAssertEqual(HideScoresPrefs.shown("82", hidden: false), "82")
    }

    func testTheSwitchesAreReadFromTheirOwnKeys() {
        let defaults = UserDefaults(suiteName: "hide-scores-test")!
        defaults.removePersistentDomain(forName: "hide-scores-test")
        defaults.set(true, forKey: HideScoresPrefs.bodyKey)
        XCTAssertEqual([HideScoresPrefs.isOn(.scores, defaults: defaults), HideScoresPrefs.isOn(.body, defaults: defaults)], [false, true])
    }
}
