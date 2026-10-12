import XCTest
@testable import Strand

/// Hiding a PaceForge card: the FNV-1a hash matches the server's, "hide until it changes" keeps a card hidden
/// only while its text hashes the same, a snooze ends on the day it names, and the phone's list and the
/// server's dismissed.json are united. All values are made up.
final class PaceForgeDismissTests: XCTestCase {
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    // MARK: Hash

    func testHashOfNothingIsTheOffsetBasis() {
        XCTAssertEqual(PFFNV.hash(""), "811c9dc5")
    }

    func testHashOfA() {
        XCTAssertEqual(PFFNV.hash("a"), "e40c292c")
    }

    func testHashOfFoobar() {
        XCTAssertEqual(PFFNV.hash("foobar"), "bf9cf968")
    }

    func testHashIsOverUtf8Bytes() {
        // U+00E9 is the two bytes C3 A9; hashing the code unit instead would give another value.
        XCTAssertEqual(PFFNV.hash("\u{00E9}"), "1e9de8c1")
    }

    func testHashIsAlwaysEightHexDigits() {
        XCTAssertEqual(PFFNV.hash("x").count, 8)
    }

    // MARK: Hide until it changes

    func testHiddenCardStaysHiddenWhileItsTextIsTheSame() {
        let items = PFDismissLogic.dismissing([], key: "brief", text: "Easy day", mode: .untilChanged, today: "2030-03-13", now: now)
        XCTAssertTrue(PFDismissLogic.isHidden(key: "brief", text: "Easy day", today: "2030-03-20", local: items, server: []))
    }

    func testHiddenCardReturnsWhenItsTextChanges() {
        let items = PFDismissLogic.dismissing([], key: "brief", text: "Easy day", mode: .untilChanged, today: "2030-03-13", now: now)
        XCTAssertFalse(PFDismissLogic.isHidden(key: "brief", text: "Hard day", today: "2030-03-13", local: items, server: []))
    }

    func testCardWithTheSameTextAfterAChangeIsHiddenAgain() {
        let items = PFDismissLogic.dismissing([], key: "brief", text: "Easy day", mode: .untilChanged, today: "2030-03-13", now: now)
        XCTAssertTrue(PFDismissLogic.isHidden(key: "brief", text: "Easy day", today: "2030-03-14", local: items, server: []))
    }

    func testHidingOneCardDoesNotHideAnother() {
        let items = PFDismissLogic.dismissing([], key: "brief", text: "x", mode: .untilChanged, today: "2030-03-13", now: now)
        XCTAssertFalse(PFDismissLogic.isHidden(key: "feel", text: "x", today: "2030-03-13", local: items, server: []))
    }

    func testHidingAgainReplacesTheEarlierEntry() {
        var items = PFDismissLogic.dismissing([], key: "brief", text: "one", mode: .untilChanged, today: "2030-03-13", now: now)
        items = PFDismissLogic.dismissing(items, key: "brief", text: "two", mode: .untilChanged, today: "2030-03-13", now: now)
        XCTAssertEqual(items.count, 1)
    }

    // MARK: Snooze

    func testSnoozedCardIsHiddenForTheRestOfTheDay() {
        let items = PFDismissLogic.dismissing([], key: "feel", text: "x", mode: .untilTomorrow, today: "2030-03-13", now: now)
        XCTAssertTrue(PFDismissLogic.isHidden(key: "feel", text: "changed", today: "2030-03-13", local: items, server: []))
    }

    func testSnoozedCardReturnsTomorrowEvenWithTheSameText() {
        let items = PFDismissLogic.dismissing([], key: "feel", text: "x", mode: .untilTomorrow, today: "2030-03-13", now: now)
        XCTAssertFalse(PFDismissLogic.isHidden(key: "feel", text: "x", today: "2030-03-14", local: items, server: []))
    }

    func testTomorrowCrossesTheMonthEnd() {
        XCTAssertEqual(PFDismissLogic.tomorrow(after: "2030-03-31"), "2030-04-01")
    }

    func testTomorrowCrossesTheYearEnd() {
        XCTAssertEqual(PFDismissLogic.tomorrow(after: "2030-12-31"), "2031-01-01")
    }

    func testTomorrowKnowsALeapDay() {
        XCTAssertEqual(PFDismissLogic.tomorrow(after: "2032-02-28"), "2032-02-29")
    }

    func testExpiredSnoozesArePrunedAndOtherEntriesKept() {
        let items = [PFDismissal(key: "a", until: "2030-03-13", dismissedAt: nil, textHash: nil),
                     PFDismissal(key: "b", until: nil, dismissedAt: nil, textHash: "abc"),
                     PFDismissal(key: "c", until: "2030-03-14", dismissedAt: nil, textHash: nil)]
        XCTAssertEqual(PFDismissLogic.pruned(items, today: "2030-03-13").map(\.key), ["b", "c"])
    }

    // MARK: Union with the server's list

    func testAServerDismissalHidesTheCardToo() {
        let server = [PFDismissal(key: "alerts", until: nil, dismissedAt: nil, textHash: PFFNV.hash("Open alert"))]
        XCTAssertTrue(PFDismissLogic.isHidden(key: "alerts", text: "Open alert", today: "2030-03-13", local: [], server: server))
    }

    func testAServerDismissalWithAnotherHashHidesNothing() {
        let server = [PFDismissal(key: "alerts", until: nil, dismissedAt: nil, textHash: PFFNV.hash("Old alert"))]
        XCTAssertFalse(PFDismissLogic.isHidden(key: "alerts", text: "New alert", today: "2030-03-13", local: [], server: server))
    }

    func testAServerSnoozeHidesUntilItsDay() {
        let server = [PFDismissal(key: "feel", until: "2030-03-15", dismissedAt: nil, textHash: nil)]
        XCTAssertTrue(PFDismissLogic.isHidden(key: "feel", text: "x", today: "2030-03-14", local: [], server: server))
    }

    func testEitherListHidesTheCard() {
        let local = PFDismissLogic.dismissing([], key: "feel", text: "x", mode: .untilChanged, today: "2030-03-13", now: now)
        let server = [PFDismissal(key: "feel", until: nil, dismissedAt: nil, textHash: PFFNV.hash("other"))]
        XCTAssertEqual(PFDismissLogic.hiddenBy(key: "feel", text: "x", today: "2030-03-13", local: local, server: server), .local)
    }

    func testTheServerListIsNamedWhenOnlyItHidesTheCard() {
        let server = [PFDismissal(key: "feel", until: nil, dismissedAt: nil, textHash: PFFNV.hash("x"))]
        XCTAssertEqual(PFDismissLogic.hiddenBy(key: "feel", text: "x", today: "2030-03-13", local: [], server: server), .server)
    }

    func testAnEntryWithNeitherDayNorHashHidesNothing() {
        let server = [PFDismissal(key: "feel", until: nil, dismissedAt: nil, textHash: nil)]
        XCTAssertFalse(PFDismissLogic.isHidden(key: "feel", text: "x", today: "2030-03-13", local: [], server: server))
    }

    // MARK: Restore

    func testRestoringRemovesOnlyThatCard() {
        var items = PFDismissLogic.dismissing([], key: "a", text: "x", mode: .untilChanged, today: "2030-03-13", now: now)
        items = PFDismissLogic.dismissing(items, key: "b", text: "x", mode: .untilChanged, today: "2030-03-13", now: now)
        XCTAssertEqual(PFDismissLogic.restoring(items, key: "a").map(\.key), ["b"])
    }

    func testRestoredCardShowsAgain() {
        var items = PFDismissLogic.dismissing([], key: "a", text: "x", mode: .untilChanged, today: "2030-03-13", now: now)
        items = PFDismissLogic.restoring(items, key: "a")
        XCTAssertFalse(PFDismissLogic.isHidden(key: "a", text: "x", today: "2030-03-13", local: items, server: []))
    }

    // MARK: Server file and storage

    func testServerFileReadsKeyUntilStampAndHash() {
        let doc = json(#"{"items":[{"key":"brief","until":null,"dismissed_at":"2030-03-12T07:00:00","text_hash":"e40c292c"},{"key":"feel","until":"2030-03-14"}]}"#)
        let items = PFDismissStorage.parseServer(doc)
        XCTAssertEqual(items, [PFDismissal(key: "brief", until: nil, dismissedAt: "2030-03-12T07:00:00", textHash: "e40c292c"),
                               PFDismissal(key: "feel", until: "2030-03-14", dismissedAt: nil, textHash: nil)])
    }

    func testMissingServerFileIsNoDismissals() {
        XCTAssertEqual(PFDismissStorage.parseServer(PFJ(nil)), [])
    }

    func testLocalListSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "pf-dismiss-roundtrip")!
        defaults.removePersistentDomain(forName: "pf-dismiss-roundtrip")
        let items = PFDismissLogic.dismissing([], key: "brief", text: "x", mode: .untilChanged, today: "2030-03-13", now: now)
        PFDismissStorage.save(items, defaults: defaults)
        XCTAssertEqual(PFDismissStorage.load(defaults: defaults, today: "2030-03-13"), items)
    }

    func testLoadingDropsExpiredSnoozes() {
        let defaults = UserDefaults(suiteName: "pf-dismiss-prune")!
        defaults.removePersistentDomain(forName: "pf-dismiss-prune")
        PFDismissStorage.save(PFDismissLogic.dismissing([], key: "feel", text: "x", mode: .untilTomorrow, today: "2030-03-13", now: now),
                              defaults: defaults)
        XCTAssertEqual(PFDismissStorage.load(defaults: defaults, today: "2030-03-14"), [])
    }
}
