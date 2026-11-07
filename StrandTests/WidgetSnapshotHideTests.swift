import XCTest
@testable import Strand

/// Settings > Hide numbers on the Home / Lock Screen widgets: the app publishes the two switches with the
/// snapshot, and the widget draws `redactedForDisplay()`, so the scores never reach a face while they are hidden.
final class WidgetSnapshotHideTests: XCTestCase {
    private func snapshot(scoresHidden: Bool?) -> WidgetSnapshot {
        var snap = WidgetSnapshot(recovery: 72, bpm: 58, batteryPct: 84, bonded: true, updated: Date(timeIntervalSince1970: 1_000),
                                  effort: 38, rest: 81, hrv: 64, restingHr: 52, effortDisplay: "38", effortWhoop: false,
                                  effortTargetEffort: 42, effortTargetEffortText: "42",
                                  effortBandLow: 55, effortBandHigh: 70, effortBandText: "55-70", effortToGo: "13-28 to go")
        snap.scoresHidden = scoresHidden
        return snap
    }

    func testHiddenScoresAreTakenOutOfWhatTheWidgetDraws() {
        let out = snapshot(scoresHidden: true).redactedForDisplay()
        XCTAssertEqual([out.recovery, out.effort, out.rest], [nil, nil, nil])
    }

    func testTheEffortTargetGoesWithTheScoresItIsBuiltFrom() {
        let out = snapshot(scoresHidden: true).redactedForDisplay()
        XCTAssertEqual([out.effortDisplay, out.effortTargetEffortText, out.effortBandText, out.effortToGo], [nil, nil, nil, nil])
    }

    func testHeartRateHrvAndBatteryStayWhenScoresAreHidden() {
        let out = snapshot(scoresHidden: true).redactedForDisplay()
        XCTAssertEqual([out.bpm, out.hrv, out.restingHr, out.batteryPct], [58, 64, 52, 84])
    }

    func testTheHiddenFlagSurvivesRedaction() {
        XCTAssertEqual(snapshot(scoresHidden: true).redactedForDisplay().scoresHidden, true)
    }

    func testShownScoresPassThroughUntouched() {
        let snap = snapshot(scoresHidden: false)
        XCTAssertEqual(snap.redactedForDisplay(), snap)
    }

    func testASnapshotFromAnOlderBuildHasNoFlagAndShowsEverything() {
        let snap = snapshot(scoresHidden: nil)
        XCTAssertEqual(snap.redactedForDisplay().recovery, 72)
    }

    func testTheFlagsRoundTripThroughTheStoredJson() throws {
        var snap = snapshot(scoresHidden: true)
        snap.bodyHidden = true
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snap))
        XCTAssertEqual([back.scoresHidden, back.bodyHidden], [true, true])
    }

    func testFlippingASwitchCountsAsAChangeTheWidgetMustRender() {
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: snapshot(scoresHidden: false), to: snapshot(scoresHidden: true)))
    }
}
