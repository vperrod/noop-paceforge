import XCTest

/// Simulator checks for the dark look: Today's dials / monitor tiles / sticky mini dials, and PaceForge Today's
/// outlook bar and Next best action (those two need porting to the unified Today, see `useClassicNavigation`). The component
/// gallery (`--demo-screen looklab`) is gone. Like the other PaceForge UI tests they serve the synthetic
/// PaceForgeFixture.json (made-up values only). Screenshot names start with "Look" so the run's attachments sort together.
final class LookComponentsUITests: XCTestCase {
    private func launch(screen: String? = nil, appearance: String = "dark", fixture: Bool = false, classic: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        if classic { try app.useClassicNavigation() }
        app.launchArguments.append("--demo-seed")
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
        app.launchArguments.append(contentsOf: ["-theme.appearance", appearance])
        if fixture {
            app.launchArguments.append("-PaceForgeFixture")
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                    "The synthetic fixture should be bundled with the UI tests.")
            app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }
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

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    private func openSegment(_ app: XCUIApplication, _ title: String) throws {
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        let button = segments.buttons[title]
        // The segment is remembered between launches; a tap that lands while the previous one is restored is lost.
        // A tap that lands while the remembered segment is still being restored is lost; look again before moving on.
        for _ in 0..<3 where !button.isSelected { button.tap(); Thread.sleep(forTimeInterval: 1) }
    }

    // MARK: Today

    func testTodayShowsDialsAndTiles() throws {
        let app = try launch()
        XCTAssertTrue(element(app, "look-day-title").waitForExistence(timeout: 30), "Today should show the day pill.")
        attach(app, "Look 20 Today top")
        for id in ["look-health-tile", "look-stress-tile"] {
            XCTAssertTrue(reveal(element(app, id), in: app), "Today should show \(id).")
        }
        attach(app, "Look 21 Today monitor tiles")
        XCTAssertFalse(element(app, "look-activities-card").exists, "My Day is a tab, not a section of Today.")
        XCTAssertFalse(element(app, "sleep-planner-entry").exists, "Tonight's sleep is on the Sleep screen, not on Today.")
    }

    func testStickyMiniDialsAppearOnceTheDialsScrollAway() throws {
        let app = try launch()
        XCTAssertTrue(element(app, "look-day-title").waitForExistence(timeout: 30), "Today should be up.")
        XCTAssertFalse(element(app, "look-mini-dials").exists, "The mini dials stay hidden while the big dials show.")
        app.swipeUp()
        app.swipeUp()
        attach(app, "Look 23 Today after two swipes")
        XCTAssertTrue(element(app, "look-mini-dials").waitForExistence(timeout: 10), "The mini dials should pin once the dials scroll away.")
        attach(app, "Look 23 Today sticky mini dials")
    }

    // MARK: PaceForge Today

    func testPaceForgeTodayOutlookBarFoldsTheBriefing() throws {
        let app = try launch(fixture: true, classic: true)
        try openSegment(app, "Today")
        let bar = element(app, "pf-brief-outlook")
        XCTAssertTrue(reveal(bar, in: app), "Today should show the Daily Outlook bar.")
        attach(app, "Look 30 PaceForge Today outlook open")
        bar.tap()
        attach(app, "Look 31 PaceForge Today outlook closed")
        bar.tap()
        XCTAssertTrue(element(app, "pf-brief-card").exists, "The briefing card stays in place.")
    }

    func testPaceForgeTodayDialsAndNextBestAction() throws {
        let app = try launch(fixture: true, classic: true)
        try openSegment(app, "Today")
        attach(app, "Look 32 PaceForge Today top")
        let card = element(app, "pf-next-action-card")
        XCTAssertTrue(reveal(card, in: app), "Today should show the Next best action card.")
        attach(app, "Look 33 PaceForge Next best action")
    }
}
