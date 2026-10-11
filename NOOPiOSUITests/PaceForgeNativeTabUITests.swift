import XCTest

final class PaceForgeNativeTabUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBottomBarShowsPaceForgeTab() {
        let app = launch()
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The bottom bar should show a PaceForge tab.")
        XCTAssertFalse(app.tabBars.buttons["Coach"].exists, "NOOP's Coach tab should no longer be in the bottom bar.")
        attach(app, "00 Bottom bar")
    }

    func testEachSegmentRendersAndIsCaptured() {
        let app = launch()
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()

        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 10), "The PaceForge segmented control should be present.")

        // (segment title, text that proves the screen drew, screenshot name)
        let screens: [(String, String, String)] = [
            ("Today", "Should you push today?", "01 Today"),
            ("Coach", "Coach's Take", "02 Coach"),
            ("This week", "Mon 5 Oct", "03 This week"),
            ("Insights", "Fitness, fatigue and form", "04 Insights"),
            ("Body", "Weight trend", "05 Body"),
        ]
        for (title, marker, name) in screens {
            let button = segments.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "The \(title) segment should exist.")
            button.tap()
            XCTAssertTrue(app.staticTexts[marker].waitForExistence(timeout: 10), "\(title) should show \"\(marker)\".")
            XCTAssertTrue(app.staticTexts["pf-preview-label"].exists || app.staticTexts["Preview \u{00B7} data from 11 Oct"].exists,
                          "\(title) should carry the preview label.")
            attach(app, name)
            app.swipeUp()
            attach(app, name + " scrolled")
            app.swipeUp()
            attach(app, name + " scrolled 2")
            app.swipeDown(); app.swipeDown()
        }
    }

    func testWeekSessionExpandsToFullDetail() {
        let app = launch()
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 10))
        segments.buttons["This week"].tap()

        let session = app.buttons["pf-workout-aee4b54b"]
        XCTAssertTrue(session.waitForExistence(timeout: 10), "The race-pace intervals session should be listed.")
        session.tap()
        let breakdown = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Session breakdown")).firstMatch
        XCTAssertTrue(breakdown.waitForExistence(timeout: 5), "Opening a session should show its step breakdown.")
        attach(app, "06 Week session expanded")
        app.swipeUp()
        attach(app, "06 Week session expanded scrolled")
    }
}
