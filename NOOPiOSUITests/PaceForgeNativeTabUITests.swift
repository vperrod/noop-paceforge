import XCTest

/// Simulator checks for the native PaceForge tab. There is no server in CI, so the fixture tests launch
/// with `-PaceForgeFixture` and serve the synthetic PaceForgeFixture.json (made-up values only).
final class PaceForgeNativeTabUITests: XCTestCase {
    private func launch(fixture: Bool, widgetGallery: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if fixture {
            app.launchArguments.append("-PaceForgeFixture")
            if widgetGallery { app.launchArguments.append("-PaceForgeWidgetGallery") }
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                    "The synthetic fixture should be bundled with the UI tests.")
            app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Overline labels are rendered upper-case, so match the text case-insensitively.
    private func label(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    private func openPaceForge(_ app: XCUIApplication) throws -> XCUIElement {
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        return segments
    }

    func testBottomBarShowsPaceForgeTab() throws {
        let app = try launch(fixture: false)
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The bottom bar should show a PaceForge tab.")
        XCTAssertFalse(app.tabBars.buttons["Coach"].exists, "NOOP's Coach tab should no longer be in the bottom bar.")
        attach(app, "00 Bottom bar")
    }

    func testNotSetUpStateWithoutSyncSettings() throws {
        let app = try launch(fixture: false)
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(label(app, "PaceForge sync not set up").waitForExistence(timeout: 10),
                      "Without an endpoint and token the tab should say sync is not set up.")
        attach(app, "00b Not set up")
    }

    func testEachSegmentRendersAndIsCaptured() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)

        // (segment title, text that proves the screen drew, screenshot name)
        let screens: [(String, String, String)] = [
            ("Today", "Your body today", "01 Today"),
            ("Coach", "Coach's Take", "02 Coach"),
            ("This week", "Mon 11 Mar", "03 This week"),
            ("Insights", "Fitness, fatigue and form", "04 Insights"),
            ("Body", "Body breakdown", "05 Body"),
        ]
        for (title, marker, name) in screens {
            let button = segments.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "The \(title) segment should exist.")
            button.tap()
            XCTAssertTrue(label(app, marker).waitForExistence(timeout: 10), "\(title) should show \"\(marker)\".")
            attach(app, name)
            app.swipeUp()
            attach(app, name + " scrolled")
            app.swipeUp()
            attach(app, name + " scrolled 2")
            app.swipeUp()
            attach(app, name + " scrolled 3")
            for _ in 0..<4 { app.swipeDown() }
        }
    }

    func testTodayShowsTheBriefingAndNoVerdictCard() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        segments.buttons["Today"].tap()
        XCTAssertTrue(label(app, "Daily briefing").waitForExistence(timeout: 10), "Today should lead with the daily briefing.")
        XCTAssertFalse(label(app, "Should you push today?").exists, "The verdict card should be gone.")
        XCTAssertFalse(label(app, "Coach's morning read").exists, "The morning-read card should be gone.")
    }

    func testCompletedSessionOpensItsResults() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        segments.buttons["This week"].tap()

        let done = app.buttons["pf-workout-s-mon"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The completed easy run should be listed.")
        done.tap()
        XCTAssertTrue(label(app, "Coach analysis").waitForExistence(timeout: 15),
                      "A completed session should open its results with the coach's analysis.")
        attach(app, "06 Session results")
        for index in 1...4 {
            app.swipeUp()
            attach(app, "06 Session results scrolled \(index)")
        }
        app.buttons["Done"].tap()
    }

    func testBodyProgressCardIsCaptured() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        segments.buttons["Body"].tap()
        XCTAssertTrue(label(app, "Progress").waitForExistence(timeout: 10), "Body should lead with the Progress card.")
        XCTAssertTrue(label(app, "Needs readings").exists, "A goal without a pace should say it needs more readings.")
        attach(app, "09 Body progress")
        app.swipeUp()
        attach(app, "09 Body progress scrolled")
    }

    func testTodayShowsPartialBriefAlertsAndReadiness() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        segments.buttons["Today"].tap()
        XCTAssertTrue(label(app, "Waiting for: scale").waitForExistence(timeout: 10),
                      "A partial brief should say what it is waiting for.")
        XCTAssertTrue(label(app, "Updated 08:12").exists, "An updated brief should show when.")
        attach(app, "10 Today brief")
        XCTAssertTrue(label(app, "Alerts").waitForExistence(timeout: 5), "Open alerts should be listed on Today.")
        XCTAssertTrue(label(app, "Why my readiness is this").exists, "The three readiness reads should be on Today.")
        app.swipeUp()
        attach(app, "10 Today alerts and readiness")
        app.swipeUp()
        attach(app, "10 Today readiness")
    }

    func testSessionResultsShowHeartRateRecovery() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        segments.buttons["This week"].tap()
        let done = app.buttons["pf-workout-s-mon"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(label(app, "Heart rate recovery").waitForExistence(timeout: 15),
                      "A session with a first-minute recovery should show it in its results.")
        attach(app, "11 Session heart rate recovery")
        app.swipeUp()
        attach(app, "11 Session heart rate recovery scrolled")
        app.buttons["Done"].tap()
    }

    func testPlannedSessionStillExpandsToPlanDetail() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        segments.buttons["This week"].tap()

        let planned = app.buttons["pf-workout-s-wed"]
        XCTAssertTrue(planned.waitForExistence(timeout: 10), "The planned intervals session should be listed.")
        planned.tap()
        XCTAssertTrue(label(app, "Session breakdown").waitForExistence(timeout: 5),
                      "Opening a planned session should show its step breakdown.")
        attach(app, "07 Planned session expanded")
    }

    func testWidgetGalleryIsCaptured() throws {
        let app = try launch(fixture: true, widgetGallery: true)
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(label(app, "Widget gallery").waitForExistence(timeout: 15), "The widget gallery should draw from the fixture.")
        attach(app, "08 Widgets large")
        for index in 1...4 {
            app.swipeUp()
            attach(app, "08 Widgets scrolled \(index)")
        }
    }
}
