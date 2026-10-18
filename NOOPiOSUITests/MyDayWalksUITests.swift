import XCTest

/// Simulator checks for the walk-or-workout suggestions on My Day. Driven by the made-up day
/// `-MyDayFixture walks` (DEBUG builds only): five calm walks, one hard stretch and one stretch a recorded run
/// already covers. Nothing here is real data.
final class MyDayWalksUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "-MyDayFixture", "walks"]
        app.launch()
        dumpHierarchyOnFailure(app)
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func elements(_ app: XCUIApplication, prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func labelContaining(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Today tab, My Day card, then scrolled down to the walk header of the timeline.
    private func openTimeline(_ app: XCUIApplication) {
        let card = element(app, "myday-entry")
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Today should show the My Day card under the rings.")
        card.tap()
        XCTAssertTrue(element(app, "myday-strip").waitForExistence(timeout: 20), "My Day should draw its 24 h strip.")
        let header = element(app, "myday-dismiss-walks")
        for _ in 0..<8 where !header.exists { app.swipeUp() }
        XCTAssertTrue(header.exists, "The timeline header should offer to dismiss the walks.")
    }

    func testCalmStretchesAreOfferedAsWalksAndTheRestStaysAWorkout() {
        let app = launch()
        openTimeline(app)
        attach(app, "30 My Day walks")
        XCTAssertTrue(labelContaining(app, "Looks like a walk").exists, "A calm stretch should read as a walk.")
        XCTAssertTrue(labelContaining(app, "Looks like a workout").exists, "The hard stretch should stay a workout.")
        XCTAssertTrue(app.buttons["Save as walk"].exists, "A walk is saved as a walk.")
    }

    func testAStretchARecordedRunCoversIsMarkedAlreadyRecordedWithNoSaveButton() {
        let app = launch()
        openTimeline(app)
        for _ in 0..<8 where elements(app, prefix: "myday-recorded-").count == 0 { app.swipeDown() }
        XCTAssertGreaterThan(elements(app, prefix: "myday-recorded-").count, 0, "The covered stretch should say Already recorded.")
        // Seven suggestions, one of them recorded: six can be saved.
        XCTAssertEqual(elements(app, prefix: "myday-save-").count, 6)
        attach(app, "31 My Day already recorded")
    }

    func testTheSaveButtonOffersEveryWorkoutType() {
        let app = launch()
        openTimeline(app)
        let chooser = elements(app, prefix: "myday-type-").matching(NSPredicate(format: "identifier MATCHES %@", "myday-type-detected.*")).firstMatch
        XCTAssertTrue(chooser.waitForExistence(timeout: 5), "A suggestion should carry a type chooser next to Save.")
        chooser.tap()
        for type in ["walk", "run", "cycle", "strength", "hiit", "yoga", "hike", "swim", "other"] {
            XCTAssertTrue(elements(app, prefix: "myday-type-\(type)-").firstMatch.waitForExistence(timeout: 5),
                          "The type menu should offer \(type).")
        }
        attach(app, "32 My Day type menu")
    }

    func testDismissAllWalksClearsThemAndKeepsTheWorkout() {
        let app = launch()
        openTimeline(app)
        element(app, "myday-dismiss-walks").tap()
        // The rows go at once, but the 24 h strip's own labels follow the reload that stores the dismissal: wait for them to go.
        let walk = labelContaining(app, "Looks like a walk")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: walk)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 20), .completed, "No walk should be left.")
        XCTAssertTrue(labelContaining(app, "Looks like a workout").exists, "The hard stretch stays.")
        XCTAssertFalse(element(app, "myday-dismiss-walks").exists, "The header action goes with the walks.")
        attach(app, "33 My Day walks dismissed")
    }
}
