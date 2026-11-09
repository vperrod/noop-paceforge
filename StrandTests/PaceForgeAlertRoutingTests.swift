import XCTest
@testable import Strand

/// Where a tapped PaceForge notification lands, which Needs you items are announced and how an alert's activity is read from its key.
/// All values are made up.
final class PaceForgeAlertRoutingTests: XCTestCase {
    private func item(_ id: String, _ kind: PFNeedsItem.Kind) -> PFNeedsItem {
        PFNeedsItem(id: id, kind: kind, title: "Title")
    }

    // MARK: Route from a notification

    func testNeedsYouNotificationOpensTheCard() {
        let info = PFAlertRoute.userInfo(kind: PFAlertRoute.needsYouKind, id: "rpe:91", activityID: "91")
        XCTAssertEqual(PFAlertRoute(userInfo: info), .needsYou)
    }

    func testAlertWithAnActivityOpensItsResults() {
        let info = PFAlertRoute.userInfo(kind: PFAlertRoute.alertKind, id: "a1", activityID: "91")
        XCTAssertEqual(PFAlertRoute(userInfo: info), .activity("91"))
    }

    func testAlertWithoutAnActivityOpensTheCard() {
        let info = PFAlertRoute.userInfo(kind: PFAlertRoute.alertKind, id: "a1")
        XCTAssertEqual(PFAlertRoute(userInfo: info), .needsYou)
    }

    func testAlertWithAnEmptyActivityOpensTheCard() {
        let info = PFAlertRoute.userInfo(kind: PFAlertRoute.alertKind, id: "a1", activityID: "")
        XCTAssertEqual(PFAlertRoute(userInfo: info), .needsYou)
    }

    func testNotificationWithoutUserInfoHasNoRoute() {
        XCTAssertNil(PFAlertRoute(userInfo: [:]))
    }

    func testNotificationOfAnotherKindHasNoRoute() {
        XCTAssertNil(PFAlertRoute(userInfo: [PFAlertRoute.kindKey: "brief"]))
    }

    func testUserInfoCarriesTheKeyTheSharedPresenterChecks() {
        XCTAssertEqual(PFAlertRoute.kindKey, "pf.kind")
    }

    // MARK: Activity of an alert

    func testLoadSpikeKeyNamesItsActivity() {
        XCTAssertEqual(PFAlertRoute.activityID(kind: "load_spike", key: "load_spike:9000000001"), "9000000001")
    }

    func testHeartRateRecoveryFlagKeyNamesItsActivity() {
        XCTAssertEqual(PFAlertRoute.activityID(kind: "hrr2_flag", key: "hrr2_flag:77"), "77")
    }

    func testDailyAlertKindHasNoActivity() {
        XCTAssertNil(PFAlertRoute.activityID(kind: "hrv_below", key: "hrv_below:2030-03-13"))
    }

    func testKeyOfAnotherKindHasNoActivity() {
        XCTAssertNil(PFAlertRoute.activityID(kind: "load_spike", key: "hrr2_flag:77"))
    }

    func testKeyWithoutAnIdHasNoActivity() {
        XCTAssertNil(PFAlertRoute.activityID(kind: "load_spike", key: "load_spike:"))
    }

    func testMissingKeyHasNoActivity() {
        XCTAssertNil(PFAlertRoute.activityID(kind: "load_spike", key: nil))
    }

    func testBuilderReadsTheActivityOfALoadSpikeAlert() {
        let doc = PFJ(data: Data("""
        {"alerts":[{"id":"a1","key":"load_spike:9000000001","kind":"load_spike","severity":"watch","title":"Big session","status":"open"}]}
        """.utf8))
        XCTAssertEqual(PFBuilder.alerts(doc).first?.activityID, "9000000001")
    }

    // MARK: Which Needs you items are announced

    func testAnItemNotSeenBeforeIsAnnounced() {
        XCTAssertEqual(PFNeedsNotify.fresh([item("rpe:91", .rpe)], seen: []).map { $0.id }, ["rpe:91"])
    }

    func testAnItemSeenBeforeIsNotAnnouncedAgain() {
        XCTAssertEqual(PFNeedsNotify.fresh([item("rpe:91", .rpe)], seen: ["rpe:91"]), [])
    }

    func testTheFeelCheckInIsNotAnnounced() {
        XCTAssertEqual(PFNeedsNotify.fresh([item("feel:2030-03-13", .feel)], seen: []), [])
    }

    func testEveryOtherKindIsAnnounced() {
        let items = [item("treadmill_pace:1", .treadmillPace), item("rpe:2", .rpe), item("proposal:3", .proposal), item("question:4", .question)]
        XCTAssertEqual(PFNeedsNotify.fresh(items, seen: []).count, 4)
    }

    func testRememberedIdsKeepTheNewest200() {
        let old = (0..<199).map { "old\($0)" }
        let kept = PFNeedsNotify.remembering(old, adding: [item("new1", .rpe), item("new2", .rpe)])
        XCTAssertEqual(kept.count, 200)
    }

    func testRememberedIdsDropTheOldestFirst() {
        let old = (0..<199).map { "old\($0)" }
        let kept = PFNeedsNotify.remembering(old, adding: [item("new1", .rpe), item("new2", .rpe)])
        XCTAssertEqual(kept.first, "old1")
    }

    func testRememberedIdsEndWithTheNewOnes() {
        XCTAssertEqual(PFNeedsNotify.remembering(["a"], adding: [item("b", .rpe)]), ["a", "b"])
    }

    func testRememberedIdsKeepTheOrderTheyWereAdded() {
        XCTAssertEqual(PFNeedsNotify.remembering([], adding: [item("c", .rpe), item("a", .rpe), item("b", .rpe)]), ["c", "a", "b"])
    }

    // MARK: First run

    func testTheFirstRunRecordsTheOpenItemsOfAnnouncedKinds() {
        let items = [item("rpe:1", .rpe), item("feel:2030-03-13", .feel), item("question:2", .question)]
        XCTAssertEqual(PFNeedsNotify.firstRun(items), ["rpe:1", "question:2"])
    }

    func testNothingOpenAtTheFirstRunRecordsNothing() {
        XCTAssertEqual(PFNeedsNotify.firstRun([]), [])
    }

    func testAnItemOpenAtTheFirstRunIsNotAnnouncedLater() {
        let items = [item("rpe:1", .rpe)]
        XCTAssertEqual(PFNeedsNotify.fresh(items, seen: Set(PFNeedsNotify.firstRun(items))), [])
    }

    func testAnItemThatAppearsAfterTheFirstRunIsAnnounced() {
        let recorded = PFNeedsNotify.firstRun([item("rpe:1", .rpe)])
        XCTAssertEqual(PFNeedsNotify.fresh([item("rpe:1", .rpe), item("proposal:2", .proposal)], seen: Set(recorded)).map { $0.id }, ["proposal:2"])
    }

    func testAnItemNotRememberedStaysAnnounceable() {
        // Alerts off or no permission: the caller does not remember what it did not announce, so the next run still announces it.
        let stored = ["rpe:1"]
        XCTAssertEqual(PFNeedsNotify.fresh([item("proposal:2", .proposal)], seen: Set(stored)).map { $0.id }, ["proposal:2"])
    }

    // MARK: A tapped activity waiting for the snapshot

    private let tapped = Date(timeIntervalSince1970: 1_900_000_000)

    func testATappedActivityIsHeldWithinTheMinute() {
        XCTAssertFalse(PFWantedActivity(id: "91", tappedAt: tapped).isExpired(now: tapped.addingTimeInterval(59)))
    }

    func testATappedActivityExpiresAfterTheMinute() {
        XCTAssertTrue(PFWantedActivity(id: "91", tappedAt: tapped).isExpired(now: tapped.addingTimeInterval(60)))
    }

    func testTheHoldIsOneMinute() {
        XCTAssertEqual(PFWantedActivity.holdSeconds, 60)
    }
}
