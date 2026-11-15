import XCTest

/// Simulator checks for the dark look: Today's dials / monitor tiles / sticky mini dials, and the Daily Outlook bar
/// in The call sheet. The component gallery (`--demo-screen looklab`) is gone, and so is the Next best action card on Today
/// (removed with the classic PaceForge Today in 622ffedd; `PFNextActionCard` is no longer mounted anywhere). Like the other PaceForge UI tests they serve the synthetic
/// PaceForgeFixture.json (made-up values only). Screenshot names start with "Look" so the run's attachments sort together.
final class LookComponentsUITests: XCTestCase {
    private func launch(screen: String? = nil, appearance: String = "dark", fixture: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
        app.launchArguments.append(contentsOf: ["-theme.appearance", appearance])
        if fixture {
            app.launchArguments.append("-PaceForgeFixture")
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                    "The synthetic fixture should be bundled with the UI tests.")
            app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
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

    // MARK: The call sheet

    func testOutlookBarInTheCallSheetFoldsTheBriefing() throws {
        let app = try launch(fixture: true)
        let call = element(app, "pf-today-card-the-call")
        XCTAssertTrue(reveal(call, in: app), "Today should show the call.")
        call.tap()
        XCTAssertTrue(element(app, "pf-the-call-sheet").waitForExistence(timeout: 15), "The call should open its sheet.")
        let bar = element(app, "pf-brief-outlook")
        XCTAssertTrue(reveal(bar, in: app), "The sheet should show the Daily Outlook bar.")
        attach(app, "Look 30 The call sheet outlook open")
        bar.tap()
        attach(app, "Look 31 The call sheet outlook closed")
        bar.tap()
        XCTAssertTrue(element(app, "pf-brief-card").exists, "The briefing card stays in place.")
    }
}
