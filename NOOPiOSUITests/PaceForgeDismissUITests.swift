import XCTest

/// Simulator checks for "Not today": the corner menu on the cards of Today (the call, how you feel), hiding a card until it
/// changes or until tomorrow, the Hidden cards row that closes Today and brings one back, and a card hidden in PaceForge itself
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

    private func openToday(_ app: XCUIApplication) {
        app.openTab("Today")
        XCTAssertTrue(element(app, "pf-today-card-the-call").waitForExistence(timeout: 30), "Today should lead with the call.")
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

    /// Scrolls until the element is on screen and clear of the floating tab bar, read from its frame. The call now sits under the
    /// two dial rows and the day graph, so on first launch its corner is below the bar, where a tap lands on the bar or the card.
    @discardableResult
    private func revealClearOfBar(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        func isClear() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            return !frame.isEmpty && frame.midY > 120 && frame.midY < app.frame.height * 0.85
        }
        for _ in 0..<maxSwipes {
            if isClear() { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return isClear()
    }

    func testTheCallOffersBothModes() throws {
        let app = try launch()
        openToday(app)
        let corner = element(app, "pf-dismiss-the-call")
        XCTAssertTrue(revealClearOfBar(corner, in: app), "The call should have the Not today corner.")
        corner.tap()
        XCTAssertTrue(app.buttons["Hide until it changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Snooze until tomorrow"].exists)
        attach(app, "60 Not today menu")
        app.buttons["Hide until it changes"].tap()
    }

    func testHideUntilItChangesRemovesTheCallAndTheHiddenRowRestoresIt() throws {
        let app = try launch()
        openToday(app)
        let corner = element(app, "pf-dismiss-the-call")
        XCTAssertTrue(revealClearOfBar(corner, in: app), "The call should have the Not today corner.")
        corner.tap()
        app.buttons["Hide until it changes"].tap()
        XCTAssertFalse(element(app, "pf-today-card-the-call").waitForExistence(timeout: 3), "The hidden call should be gone.")
        attach(app, "61 Call hidden")
        let row = element(app, "pf-hidden-cards")
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 24), "Today should end with a Hidden cards row.")
        attach(app, "61 Hidden cards row")
        row.tap()
        XCTAssertTrue(element(app, "pf-hidden-sheet").waitForExistence(timeout: 10))
        attach(app, "61 Hidden cards sheet")
        let restore = app.buttons["pf-restore-the-call"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        // Restoring the last hidden card removes the Hidden cards row, which closes its sheet by itself, so
        // Done is tapped only if the sheet is still up.
        let done = app.buttons["pf-hidden-done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
        // The sheet was opened from the bottom of Today; the call is at the top.
        let call = element(app, "pf-today-card-the-call")
        for _ in 0..<24 where !call.exists { app.swipeDown() }
        XCTAssertTrue(call.waitForExistence(timeout: 10), "Showing it again should bring the call back.")
    }

    func testSnoozeUntilTomorrowRemovesTheFeelCard() throws {
        let app = try launch()
        openToday(app)
        let corner = element(app, "pf-dismiss-feel")
        XCTAssertTrue(reveal(corner, in: app, maxSwipes: 20))
        corner.tap()
        app.buttons["Snooze until tomorrow"].tap()
        XCTAssertFalse(element(app, "pf-feel-card").waitForExistence(timeout: 3), "The snoozed card should be gone.")
        attach(app, "62 Feel card snoozed")
    }

    func testCardHiddenInPaceForgeCannotBeRestoredHere() throws {
        let app = try launch(extraArguments: ["-PaceForgeServerDismissed"])
        openToday(app)
        let row = element(app, "pf-hidden-cards")
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 24))
        row.tap()
        XCTAssertTrue(element(app, "pf-hidden-server-next-race").waitForExistence(timeout: 10),
                      "The Hidden cards list should say it is hidden in PaceForge.")
        XCTAssertFalse(app.buttons["pf-restore-next-race"].exists, "The app is read-only toward PaceForge.")
        attach(app, "63 Hidden in PaceForge")
    }
}
