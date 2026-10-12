import XCTest

/// Simulator checks for the Effort target and the Sleep Planner. Both are driven by made-up readings
/// (`-EffortTargetFixture`, `-SleepPlannerFixture`, DEBUG builds only) so every state can be captured with
/// no strap and no history; nothing here is real data. The widget faces are drawn by the debug gallery.
final class PlannerUITests: XCTestCase {

    private func launch(effort: String? = nil, sleep: String? = nil, widgetGallery: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let effort { app.launchArguments += ["-EffortTargetFixture", effort] }
        if let sleep { app.launchArguments += ["-SleepPlannerFixture", sleep] }
        if widgetGallery {
            app.launchArguments += ["-PaceForgeFixture", "-PaceForgeWidgetGallery"]
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                    "The synthetic PaceForge fixture should be bundled with the UI tests.")
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

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls Today until the element exists.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !element.exists { app.swipeUp() }
    }

    // MARK: Effort target

    private func effortText(_ app: XCUIApplication) -> XCUIElement {
        let text = element(app, "effort-target-text")
        XCTAssertTrue(text.waitForExistence(timeout: 30), "Today should show the Effort target card.")
        reveal(text, in: app)
        return text
    }

    func testEffortTargetShowsHowMuchIsToGo() throws {
        let app = try launch(effort: "toGo")
        XCTAssertEqual(effortText(app).label, "Effort 42 of 67\u{2013}86: 25\u{2013}44 to go")
        XCTAssertEqual(element(app, "effort-target-state").label, "Balanced")
        attach(app, "30 Effort target to go")
    }

    func testEffortTargetSaysWhenYouAreInRange() throws {
        let app = try launch(effort: "inRange")
        XCTAssertEqual(effortText(app).label, "Effort 75 of 67\u{2013}86: In your range")
        attach(app, "30 Effort target in range")
    }

    func testEffortTargetSaysHowFarAboveTheRangeYouAre() throws {
        let app = try launch(effort: "above")
        XCTAssertEqual(effortText(app).label, "Effort 95 of 67\u{2013}86: Above range by 9")
        XCTAssertEqual(element(app, "effort-target-state").label, "Building")
        attach(app, "30 Effort target above")
    }

    func testEffortTargetNamesTheDaysStillNeededWhileCalibrating() throws {
        let app = try launch(effort: "calibrating")
        _ = effortText(app)
        let note = element(app, "effort-target-calibration")
        XCTAssertTrue(note.exists, "Too little history should say how many days are still needed.")
        XCTAssertTrue(note.label.contains("4 more days"))
        XCTAssertFalse(element(app, "effort-target-state").exists, "No Training State word without the history for one.")
        attach(app, "30 Effort target calibrating")
    }

    func testEffortTargetWithoutChargeGuessesNoTarget() throws {
        let app = try launch(effort: "noTarget")
        XCTAssertEqual(effortText(app).label, "Target appears once today's Charge is scored")
        attach(app, "30 Effort target no charge")
    }

    func testEffortTargetHowItWorksSheetOpens() throws {
        let app = try launch(effort: "toGo")
        _ = effortText(app)
        let info = element(app, "effort-target-info")
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()
        XCTAssertTrue(element(app, "effort-target-info-sheet").waitForExistence(timeout: 10), "The ⓘ should open the How it works sheet.")
        attach(app, "31 Effort target how it works")
    }

    // MARK: Sleep Planner

    private func openPlanner(_ app: XCUIApplication) {
        let entry = element(app, "sleep-planner-entry")
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "Today should show the Sleep Planner card.")
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(element(app, "sleep-planner-bedtime").waitForExistence(timeout: 20), "The planner should show tonight's bedtime.")
    }

    func testSleepPlannerBreaksTonightsNeedIntoParts() throws {
        let app = try launch(sleep: "ready")
        openPlanner(app)
        XCTAssertTrue(element(app, "sleep-planner-bedtime").label.hasPrefix("Bed by"))
        // 8 h baseline + 45 min effort + 25 min debt - 30 min nap.
        XCTAssertEqual(element(app, "sleep-planner-need-total").label, "8 h 40 min")
        attach(app, "32 Sleep planner")
        app.swipeUp()
        attach(app, "32 Sleep planner scrolled")
        app.swipeUp()
        attach(app, "32 Sleep planner scrolled 2")
    }

    func testChoosingAGoalMovesTheBedtime() throws {
        let app = try launch(sleep: "ready")
        openPlanner(app)
        let before = element(app, "sleep-planner-bedtime").label
        element(app, "sleep-planner-preset-peak").tap()
        XCTAssertNotEqual(element(app, "sleep-planner-bedtime").label, before, "Peak sleeps longer than Perform, so bed is earlier.")
        attach(app, "33 Sleep planner peak")
    }

    func testSleepPlannerCalibratingNamesTheNightsStillNeeded() throws {
        let app = try launch(sleep: "calibrating")
        openPlanner(app)
        let note = element(app, "sleep-planner-calibration")
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("Needs 4 more nights"))
        attach(app, "34 Sleep planner calibrating")
    }

    func testSleepPlannerAlarmModeIsHonestAboutTheLimit() throws {
        let app = try launch(sleep: "ready")
        openPlanner(app)
        let copy = element(app, "sleep-planner-alarm-copy")
        for _ in 0..<8 where !copy.exists { app.swipeUp() }
        XCTAssertTrue(copy.exists)
        XCTAssertTrue(copy.label.contains("cannot watch your sleep live"))
        attach(app, "35 Sleep planner alarm mode")
    }

    // MARK: Widget gallery

    func testEffortTargetWidgetIsInTheGallery() throws {
        let app = try launch(widgetGallery: true)
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let caption = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Effort target, small")).firstMatch
        XCTAssertTrue(app.staticTexts["Widget gallery"].waitForExistence(timeout: 20))
        for _ in 0..<10 where !caption.exists { app.swipeUp() }
        XCTAssertTrue(caption.exists, "The Effort target widget should be drawn in the debug gallery.")
        attach(app, "36 Effort target widget")
        app.swipeUp()
        attach(app, "36 Effort target widget lock screen")
    }
}
