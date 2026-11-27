import XCTest

/// Opens every awards screen on made-up history (`-AwardsFixture`, DEBUG builds only) and attaches a picture of each. Data is the
/// synthetic PaceForgeFixture.json (day 2030-03-13); nothing here is real.
final class AwardsUITests: XCTestCase {
    private func launch(_ variant: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "-theme.appearance", "dark", "-AwardsFixture", variant, "-PaceForgeFixture"]
        if variant == "celebrate" { app.launchArguments.append("-ConfettiStill") }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"))
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
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

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 20) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let element = app.element(id)
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(id) should be on the screen.")
        reveal(element, in: app)
        element.tap()
    }

    private func openHighlights(_ app: XCUIApplication) {
        let chip = app.element("look-streak-chip")
        XCTAssertTrue(chip.waitForExistence(timeout: 60), "Today should carry the streak chip.")
        chip.tap()
        XCTAssertTrue(app.element("awards-streak").waitForExistence(timeout: 30), "Highlights should open with the awards.")
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.element("award-row-greenDays").waitForExistence(timeout: 20))
    }

    func testAwardsInHighlightsAndOneAwardsSteps() throws {
        let app = try launch("normal")
        openHighlights(app)
        XCTAssertFalse(app.element("award-celebration-title").exists, "Steps already reached are not celebrated.")
        attach(app, "Awards 01 Highlights")
        tap("award-row-greenDays", in: app)
        XCTAssertTrue(app.element("award-step-25").waitForExistence(timeout: 20))
        XCTAssertEqual(app.element("award-step-10").label, "10: Earned")
        XCTAssertEqual(app.element("award-step-25").label, "25: 4 to go")
        attach(app, "Awards 02 One award")
        back(app)
        tap("award-row-activities", in: app)
        XCTAssertTrue(app.element("award-detail").waitForExistence(timeout: 20))
        attach(app, "Awards 02b Activities award")
    }

    func testAChallengeIsSetByTheUserAndShowsItsProgress() throws {
        let app = try launch("normal")
        openHighlights(app)
        tap("awards-challenges", in: app)
        let start = app.element("challenge-start")
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        XCTAssertFalse(start.isEnabled, "Nothing is chosen for you.")
        attach(app, "Awards 04 New challenge")
        tap("challenge-kind-Green days", in: app)
        tap("challenge-target", in: app)
        app.element("challenge-target").typeText("10")
        tap("challenge-end", in: app)
        XCTAssertTrue(app.element("timing-picker-set").waitForExistence(timeout: 10))
        // A later day of the fixture's month, so the card reads as a span; the day number as a whole word.
        let later = app.datePickers.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*\\b28\\b.*")).firstMatch
        if later.waitForExistence(timeout: 5) { later.tap() }
        app.element("timing-picker-set").tap()
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(app.element("challenge-card").waitForExistence(timeout: 10), "The challenge should be listed.")
        attach(app, "Awards 05 Running challenge")
    }

    func testAStepNewlyReachedIsCelebratedOnce() throws {
        let app = try launch("celebrate")
        let title = app.element("award-celebration-title")
        XCTAssertTrue(title.waitForExistence(timeout: 60), "A step newly reached should be celebrated.")
        XCTAssertEqual(title.label, "25 green days")
        attach(app, "Awards 03 Celebration")
        app.element("award-celebration-done").tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), "Done closes it.")
    }
}
