import XCTest

/// Simulator checks for "Not today": the corner menu on the PaceForge Today cards, hiding a card until it
/// changes or until tomorrow, the Hidden cards row that brings one back, and a card hidden in PaceForge itself
/// (`-PaceForgeServerDismissed`). The fixture starts with nothing hidden on every launch. All values are made up.
final class PaceForgeDismissUITests: XCTestCase {
    private func launch(extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
        app.launchArguments.append("-PaceForgeFixture")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func label(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    private func openToday(_ app: XCUIApplication) throws {
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15))
        segments.buttons["Today"].tap()
        XCTAssertTrue(label(app, "Daily briefing").waitForExistence(timeout: 10))
    }

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    func testEveryCardOffersBothModes() throws {
        let app = try launch()
        try openToday(app)
        let corner = element(app, "pf-dismiss-brief")
        XCTAssertTrue(corner.waitForExistence(timeout: 10), "The briefing should have the Not today corner.")
        corner.tap()
        XCTAssertTrue(app.buttons["Hide until it changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Snooze until tomorrow"].exists)
        attach(app, "60 Not today menu")
        app.buttons["Hide until it changes"].tap()
    }

    func testHideUntilItChangesRemovesTheCardAndTheHiddenRowRestoresIt() throws {
        let app = try launch()
        try openToday(app)
        XCTAssertTrue(element(app, "pf-brief-card").exists)
        element(app, "pf-dismiss-brief").tap()
        app.buttons["Hide until it changes"].tap()
        XCTAssertFalse(element(app, "pf-brief-card").waitForExistence(timeout: 3), "The hidden briefing should be gone.")
        attach(app, "61 Briefing hidden")
        let row = element(app, "pf-hidden-cards")
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 24), "Today should end with a Hidden cards row.")
        attach(app, "61 Hidden cards row")
        row.tap()
        XCTAssertTrue(element(app, "pf-hidden-sheet").waitForExistence(timeout: 10))
        attach(app, "61 Hidden cards sheet")
        let restore = app.buttons["pf-restore-brief"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        // Restoring the last hidden card removes the Hidden cards row, which closes its sheet by itself, so
        // Done is tapped only if the sheet is still up.
        let done = app.buttons["pf-hidden-done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
        XCTAssertTrue(label(app, "Daily briefing").waitForExistence(timeout: 10), "Showing it again should bring the briefing back.")
    }

    func testSnoozeUntilTomorrowRemovesTheCard() throws {
        let app = try launch()
        try openToday(app)
        let corner = element(app, "pf-dismiss-feel")
        XCTAssertTrue(reveal(corner, in: app, maxSwipes: 20))
        corner.tap()
        app.buttons["Snooze until tomorrow"].tap()
        XCTAssertFalse(element(app, "pf-feel-card").waitForExistence(timeout: 3), "The snoozed card should be gone.")
        attach(app, "62 Feel card snoozed")
    }

    func testCardHiddenInPaceForgeStaysHiddenAndCannotBeRestoredHere() throws {
        let app = try launch(extraArguments: ["-PaceForgeServerDismissed"])
        try openToday(app)
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(label(app, "Next race").exists, "A card hidden in dismissed.json should not show.")
        let row = element(app, "pf-hidden-cards")
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 24))
        row.tap()
        XCTAssertTrue(element(app, "pf-hidden-server-next-race").waitForExistence(timeout: 10),
                      "The Hidden cards list should say it is hidden in PaceForge.")
        XCTAssertFalse(app.buttons["pf-restore-next-race"].exists, "The app is read-only toward PaceForge.")
        attach(app, "63 Hidden in PaceForge")
    }
}
