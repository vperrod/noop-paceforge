import XCTest

/// Simulator checks for detected walks on My Day. Driven by the made-up day `-MyDayFixture walks` (DEBUG builds
/// only), which shows the day after the walks saved themselves: three calm walks of 15 minutes or more are
/// Walking workouts; two shorter calm ones, one hard stretch and one stretch a recorded run already covers stay
/// plain rows with no button. Nothing here is real data.
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

    private func walkingRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Walking"))
    }

    /// Today tab, My Day card, then scrolled down to the saved walks in the timeline.
    private func openTimeline(_ app: XCUIApplication) {
        let card = element(app, "myday-entry")
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Today should show the My Day card under the rings.")
        card.tap()
        XCTAssertTrue(element(app, "myday-strip").waitForExistence(timeout: 20), "My Day should draw its 24 h strip.")
        for _ in 0..<8 where walkingRows(app).count == 0 { app.swipeUp() }
        XCTAssertGreaterThan(walkingRows(app).count, 0, "The saved walks should be in the timeline.")
    }

    func testDetectedWalksAreWalkingWorkoutsWithNoSavePrompt() {
        let app = launch()
        openTimeline(app)
        attach(app, "30 My Day walks")
        XCTAssertGreaterThanOrEqual(walkingRows(app).count, 3, "The three walks of 15 minutes or more are saved as Walking.")
        XCTAssertEqual(elements(app, prefix: "myday-save-").count, 0, "Nothing asks to be saved.")
        XCTAssertFalse(app.buttons["Save as walk"].exists, "No Save as walk button.")
        XCTAssertFalse(app.buttons["Save as workout"].exists, "No Save as workout button.")
        XCTAssertFalse(app.buttons["Dismiss"].exists, "No Dismiss button.")
        XCTAssertFalse(labelContaining(app, "Looks like a walk").exists, "Nothing hedges a walk any more.")
    }

    func testAShortCalmStretchAndAHardOneAreJustShown() {
        let app = launch()
        openTimeline(app)
        for _ in 0..<8 where !labelContaining(app, "Looks like a workout").exists { app.swipeDown() }
        XCTAssertTrue(labelContaining(app, "Looks like a workout").exists, "The hard stretch is shown as a workout.")
        let walk = app.staticTexts.matching(NSPredicate(format: "label == %@", "Walk")).firstMatch
        for _ in 0..<8 where !walk.exists { app.swipeUp() }
        XCTAssertTrue(walk.exists, "A calm stretch under 15 minutes is shown as a Walk.")
        XCTAssertEqual(elements(app, prefix: "myday-type-").count, 0, "No type button next to a stretch.")
        attach(app, "31 My Day short walk and workout")
    }

    func testAStretchARecordedRunCoversIsMarkedAlreadyRecordedWithNoSaveButton() {
        let app = launch()
        openTimeline(app)
        for _ in 0..<8 where elements(app, prefix: "myday-recorded-").count == 0 { app.swipeDown() }
        XCTAssertGreaterThan(elements(app, prefix: "myday-recorded-").count, 0, "The covered stretch should say Already recorded.")
        XCTAssertEqual(elements(app, prefix: "myday-save-").count, 0)
        attach(app, "32 My Day already recorded")
    }

    func testLongPressOnASavedWalkOffersChangeTypeAndDelete() {
        let app = launch()
        openTimeline(app)
        let walk = walkingRows(app).firstMatch
        walk.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Change type"].waitForExistence(timeout: 5), "A saved walk can be given another type.")
        XCTAssertTrue(app.buttons["Delete"].exists, "A wrongly detected walk can be deleted.")
        attach(app, "33 My Day walk menu")
    }
}
