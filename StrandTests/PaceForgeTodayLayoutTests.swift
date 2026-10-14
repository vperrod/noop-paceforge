import XCTest
@testable import Strand

/// The order of the Today cards: the web page's rule (pinned first, then the saved order, then the cards the order
/// does not name in their default places), moving and pinning on the phone, and the phone's arrangement winning over
/// the server's. All values are made up.
final class PaceForgeTodayLayoutTests: XCTestCase {
    private let ids = ["a", "b", "c", "d", "e"]
    private func layout(_ order: [String] = [], _ pinned: [String] = []) -> PFTodayLayout {
        PFTodayLayout(order: order, pinned: pinned)
    }
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    // MARK: Sorting

    func testNoLayoutKeepsTheDefaultOrder() {
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: layout()), ids)
    }
    func testTheSavedOrderIsApplied() {
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: layout(["e", "d", "c", "b", "a"])), ["e", "d", "c", "b", "a"])
    }
    func testPinnedCardsComeFirst() {
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: layout([], ["d", "b"])), ["b", "d", "a", "c", "e"])
    }
    func testPinnedCardsFollowTheSavedOrderAmongThemselves() {
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: layout(["d", "b"], ["b", "d"])), ["d", "b", "a", "c", "e"])
    }
    func testCardsTheOrderDoesNotNameKeepTheirDefaultPlacesAfterTheNamedOnes() {
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: layout(["c"])), ["c", "a", "b", "d", "e"])
    }
    func testIdsInTheLayoutThatAreNotOnScreenAreIgnored() {
        XCTAssertEqual(PFTodayOrder.sorted(["a", "b"], layout: layout(["x", "b", "y", "a"], ["z"])), ["b", "a"])
    }
    func testRepeatedCallsGiveTheSameAnswer() {
        let l = layout(["b"], ["e"])
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: l), PFTodayOrder.sorted(ids, layout: l))
    }

    // MARK: Moving

    func testMovingDownSwapsWithTheNextCard() {
        let moved = PFTodayOrder.moving("b", step: 1, ids: ids, visible: Set(ids), layout: layout())
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: moved), ["a", "c", "b", "d", "e"])
    }
    func testMovingUpSwapsWithThePreviousCard() {
        let moved = PFTodayOrder.moving("b", step: -1, ids: ids, visible: Set(ids), layout: layout())
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: moved), ["b", "a", "c", "d", "e"])
    }
    func testMovingSkipsCardsThatAreHidden() {
        let moved = PFTodayOrder.moving("b", step: 1, ids: ids, visible: ["a", "b", "d", "e"], layout: layout())
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: moved), ["a", "d", "c", "b", "e"])
    }
    func testTheTopCardCannotMoveUp() {
        XCTAssertFalse(PFTodayOrder.canMove("a", step: -1, ids: ids, visible: Set(ids), layout: layout()))
    }
    func testTheBottomCardCannotMoveDown() {
        XCTAssertFalse(PFTodayOrder.canMove("e", step: 1, ids: ids, visible: Set(ids), layout: layout()))
    }
    func testAMiddleCardCanMoveBothWays() {
        XCTAssertTrue(PFTodayOrder.canMove("c", step: -1, ids: ids, visible: Set(ids), layout: layout())
                      && PFTodayOrder.canMove("c", step: 1, ids: ids, visible: Set(ids), layout: layout()))
    }
    func testAnUnpinnedCardDoesNotMoveAboveAPinnedOne() {
        XCTAssertFalse(PFTodayOrder.canMove("a", step: -1, ids: ids, visible: Set(ids), layout: layout([], ["c"])))
    }
    func testAPinnedCardStaysAmongThePinned() {
        XCTAssertFalse(PFTodayOrder.canMove("c", step: 1, ids: ids, visible: Set(ids), layout: layout([], ["c"])))
    }
    func testAMoveThatCannotHappenLeavesTheLayoutAlone() {
        let start = layout(["b", "a"], ["c"])
        XCTAssertEqual(PFTodayOrder.moving("c", step: -1, ids: ids, visible: Set(ids), layout: start), start)
    }
    func testAnUnknownCardDoesNotMove() {
        XCTAssertFalse(PFTodayOrder.canMove("zzz", step: 1, ids: ids, visible: Set(ids), layout: layout()))
    }
    func testNamesOffScreenAreKeptAfterTheOnesOnScreen() {
        let moved = PFTodayOrder.moving("b", step: 1, ids: ["a", "b", "c"], visible: ["a", "b", "c"],
                                        layout: layout(["x", "a", "b", "c", "y"]))
        XCTAssertEqual(moved.order, ["a", "c", "b", "x", "y"])
    }
    func testMovingKeepsThePins() {
        let moved = PFTodayOrder.moving("b", step: 1, ids: ids, visible: Set(ids), layout: layout([], ["e"]))
        XCTAssertEqual(moved.pinned, ["e"])
    }

    // MARK: Pinning

    func testPinningAddsTheCard() {
        XCTAssertEqual(PFTodayOrder.togglingPin("c", layout: layout([], ["a"])).pinned, ["a", "c"])
    }
    func testPinningAPinnedCardUnpinsIt() {
        XCTAssertEqual(PFTodayOrder.togglingPin("a", layout: layout([], ["a", "c"])).pinned, ["c"])
    }
    func testPinningDoesNotTouchTheOrder() {
        XCTAssertEqual(PFTodayOrder.togglingPin("c", layout: layout(["b", "a"])).order, ["b", "a"])
    }

    // MARK: Which layout is in force

    func testThePhonesOwnArrangementWins() {
        let effective = PFTodayOrder.effective(local: layout(["b"]), server: layout(["a"], ["c"]))
        XCTAssertEqual(effective, layout(["b"]))
    }
    func testWithoutAPhoneArrangementTheServersApplies() {
        XCTAssertEqual(PFTodayOrder.effective(local: nil, server: layout(["a"], ["c"])), layout(["a"], ["c"]))
    }
    func testAnEmptyPhoneArrangementStillWinsOverTheServers() {
        XCTAssertEqual(PFTodayOrder.effective(local: layout(), server: layout(["a"], ["c"])), layout())
    }

    // MARK: The server's file

    func testServerFileIsRead() {
        XCTAssertEqual(PFTodayOrder.parseServer(json(#"{"order": ["brief", "daily"], "pinned": ["session"]}"#)),
                       layout(["brief", "daily"], ["session"]))
    }
    func testServerFileDropsNonStringsAndRepeats() {
        XCTAssertEqual(PFTodayOrder.parseServer(json(#"{"order": ["a", 5, "a", null, "b"], "pinned": "a"}"#)), layout(["a", "b"]))
    }
    func testMissingServerFileIsAnEmptyLayout() {
        XCTAssertTrue(PFTodayOrder.parseServer(PFJ(nil)).isEmpty)
    }
    func testServerFileOfTheWrongShapeIsAnEmptyLayout() {
        XCTAssertTrue(PFTodayOrder.parseServer(json("[1, 2]")).isEmpty)
    }

    // MARK: The cards

    func testTheAppsCardsUseTheWebPagesIdsWhereTheWebHasTheSameCard() {
        let webIds: Set<String> = ["daily", "feel", "easy", "race-week", "brief", "session"]
        XCTAssertTrue(webIds.isSubset(of: Set(PFTodayCard.allCases.map { $0.rawValue })))
    }
    func testTodaysCallHasItsOwnLayoutIdSoItCanBePinnedAndMoved() {
        let ids = ["todays-call", "today-so-far", "brief"]
        let moved = PFTodayOrder.moving("todays-call", step: 1, ids: ids, visible: Set(ids), layout: PFTodayLayout())
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: moved), ["today-so-far", "todays-call", "brief"])
    }
    func testNoTwoCardsShareAnId() {
        XCTAssertEqual(Set(PFTodayCard.allCases.map { $0.rawValue }).count, PFTodayCard.allCases.count)
    }
    func testTheDefaultOrderIsTheOneTheScreenHadWithTodaysCallOnTopAndNextBestActionAfterTheBrief() {
        XCTAssertEqual(PFTodayCard.defaultOrder.map { $0.rawValue },
                       ["todays-call", "day-in-review", "today-so-far", "race-week", "brief", "next-best-action", "easy", "feel", "alerts", "daily",
                        "what-changed", "readiness", "standing", "session", "next-race"])
    }
    func testAWebLayoutOrdersTheCardsItNamesAndLeavesTheAppsOwnWhereTheyWere() {
        let present = ["today-so-far", "brief", "feel", "daily", "session"]
        let web = layout(["session", "daily", "brief", "feel"])
        XCTAssertEqual(PFTodayOrder.sorted(present, layout: web), ["session", "daily", "brief", "feel", "today-so-far"])
    }

    // MARK: Storage

    func testTheLayoutSurvivesTheDefaults() {
        let name = "noop.paceforge.todayLayout.tests"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        PFTodayLayoutStorage.save(layout(["b", "a"], ["a"]), defaults: defaults)
        XCTAssertEqual(PFTodayLayoutStorage.load(defaults: defaults), layout(["b", "a"], ["a"]))
    }
    func testSavingNothingClearsTheArrangement() {
        let name = "noop.paceforge.todayLayout.tests.clear"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        PFTodayLayoutStorage.save(layout(["b"]), defaults: defaults)
        PFTodayLayoutStorage.save(nil, defaults: defaults)
        XCTAssertNil(PFTodayLayoutStorage.load(defaults: defaults))
    }
    func testNothingSavedLoadsAsNoArrangement() {
        let name = "noop.paceforge.todayLayout.tests.empty"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertNil(PFTodayLayoutStorage.load(defaults: defaults))
    }
}
