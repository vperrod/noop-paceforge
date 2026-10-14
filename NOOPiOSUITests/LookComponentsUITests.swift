import XCTest

/// Simulator checks for the dark look: every component in the DEBUG gallery (`--demo-screen looklab`) in dark and in
/// light, the trend controls, Today's dials / monitor tiles / My Day / sticky mini dials, and PaceForge Today's
/// outlook bar and Next best action. Like the other PaceForge UI tests they serve the synthetic
/// PaceForgeFixture.json (made-up values only). Screenshot names start with "Look" so the run's attachments sort together.
final class LookComponentsUITests: XCTestCase {
    private static let sections: [(id: String, name: String)] = [
        ("dials", "01 dials"), ("monitors", "02 monitor tiles and my day"), ("compare", "03 today vs 30 days"),
        ("steps", "04 three-step rows"), ("weekly", "05 weekly bars"), ("stages", "06 typical-range bars"),
        ("trend", "07 trend view"), ("chrome", "08 tab bar and mini dials"),
    ]

    private func launch(screen: String? = nil, appearance: String = "dark", fixture: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
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
        if !button.isSelected { button.tap() }
    }

    // MARK: Gallery

    private func captureGallery(_ appearance: String) throws {
        let app = try launch(screen: "looklab", appearance: appearance)
        XCTAssertTrue(element(app, "look-gallery").waitForExistence(timeout: 30), "The look gallery should open.")
        for section in Self.sections {
            let block = element(app, "look-gallery-\(section.id)")
            XCTAssertTrue(reveal(block, in: app), "The gallery should show the \(section.id) section.")
            attach(app, "Look \(section.name) (\(appearance))")
        }
    }

    func testGalleryInDark() throws { try captureGallery("dark") }

    func testGalleryInLight() throws { try captureGallery("light") }

    // MARK: Trend controls

    func testTrendRangeAndStepperMoveTheWindow() throws {
        let app = try launch(screen: "looklab")
        XCTAssertTrue(reveal(element(app, "look-gallery-trend"), in: app), "The trend section should show.")
        let sixMonths = element(app, "look-trend-range-6M")
        XCTAssertTrue(reveal(sixMonths, in: app), "The trend should offer the 6M range.")
        let label = element(app, "look-trend-range-label")
        let before = label.label
        attach(app, "Look 10 trend 6M")
        element(app, "look-trend-prev").tap()
        XCTAssertNotEqual(label.label, before, "Stepping back should move the date window.")
        attach(app, "Look 11 trend 6M one page back")
        element(app, "look-trend-next").tap()
        XCTAssertEqual(label.label, before, "Stepping forward should return to the first window.")
        element(app, "look-trend-range-W").tap()
        XCTAssertNotEqual(label.label, before, "A week window reads a shorter span.")
        attach(app, "Look 12 trend W")
        element(app, "look-trend-range-Y").tap()
        attach(app, "Look 13 trend Y")
    }

    func testTrendMetricMenuSwitchesTheMetric() throws {
        let app = try launch(screen: "looklab")
        XCTAssertTrue(reveal(element(app, "look-trend-metric-menu"), in: app), "The trend should show its metric menu.")
        element(app, "look-trend-metric-menu").tap()
        let rhr = app.buttons["Resting heart rate"]
        XCTAssertTrue(rhr.waitForExistence(timeout: 10), "The menu should list the other metrics.")
        rhr.tap()
        attach(app, "Look 14 trend resting heart rate")
    }

    // MARK: Today

    func testTodayShowsDialsTilesAndMyDay() throws {
        let app = try launch()
        XCTAssertTrue(element(app, "look-day-title").waitForExistence(timeout: 30), "Today should show the day pill.")
        attach(app, "Look 20 Today top")
        for id in ["look-health-tile", "look-stress-tile", "look-activities-card"] {
            XCTAssertTrue(reveal(element(app, id), in: app), "Today should show \(id).")
        }
        attach(app, "Look 21 Today monitor tiles and My Day")
        XCTAssertTrue(reveal(element(app, "sleep-planner-entry"), in: app), "Today should still show tonight's sleep.")
        attach(app, "Look 22 Today tonight's sleep")
    }

    func testStickyMiniDialsAppearOnceTheDialsScrollAway() throws {
        let app = try launch()
        XCTAssertTrue(element(app, "look-day-title").waitForExistence(timeout: 30), "Today should be up.")
        XCTAssertFalse(element(app, "look-mini-dials").exists, "The mini dials stay hidden while the big dials show.")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(element(app, "look-mini-dials").waitForExistence(timeout: 10), "The mini dials should pin once the dials scroll away.")
        attach(app, "Look 23 Today sticky mini dials")
    }

    // MARK: PaceForge Today

    func testPaceForgeTodayOutlookBarFoldsTheBriefing() throws {
        let app = try launch(fixture: true)
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
        let app = try launch(fixture: true)
        try openSegment(app, "Today")
        attach(app, "Look 32 PaceForge Today top")
        let card = element(app, "pf-next-action-card")
        XCTAssertTrue(reveal(card, in: app), "Today should show the Next best action card.")
        attach(app, "Look 33 PaceForge Next best action")
    }
}
