import XCTest

/// Simulator checks for "Where you stand": the summary on Insights and Today, the scorecard, a metric sheet,
/// a plan, the test-day card and the not-applicable state. Like the other PaceForge UI tests they serve the
/// synthetic PaceForgeFixture.json (made-up values only); `-PaceForgeStandingNotApplicable` swaps in the
/// second state.
final class PaceForgeStandingUITests: XCTestCase {
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

    private func openSegment(_ app: XCUIApplication, _ title: String) throws {
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        let button = segments.buttons[title]
        button.tap()
        // The segment is remembered between launches; a tap that lands while the previous one is restored is lost.
        if !button.isSelected { button.tap() }
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

    private func openScorecard(_ app: XCUIApplication) throws {
        try openSegment(app, "Insights")
        let open = app.buttons["pf-standing-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Insights should lead with the Where you stand card.")
        open.tap()
        XCTAssertTrue(element(app, "pf-standing-screen").waitForExistence(timeout: 10), "The scorecard should open.")
    }

    func testInsightsShowsTheSummaryAndOpensTheScorecard() throws {
        let app = try launch()
        try openSegment(app, "Insights")
        let card = element(app, "pf-standing-insights-card")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Insights should show the Where you stand card.")
        XCTAssertTrue(element(app, "pf-standing-strip").exists, "The card should show the counts as a strip.")
        XCTAssertTrue(element(app, "pf-standing-chip-strongest-grip").exists, "The strongest metrics should show as chips.")
        attach(app, "40 Where you stand on Insights")
        app.buttons["pf-standing-open"].tap()
        XCTAssertTrue(element(app, "pf-standing-screen").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "pf-standing-metric-resting_hr").waitForExistence(timeout: 5),
                      "The scorecard should list the metrics with their band bars.")
        attach(app, "40 Scorecard")
        app.swipeUp()
        attach(app, "40 Scorecard scrolled")
        app.swipeUp()
        attach(app, "40 Scorecard scrolled 2")
    }

    func testMetricRowReadsItsBandForAccessibility() throws {
        let app = try launch()
        try openScorecard(app)
        let row = element(app, "pf-standing-metric-resting_hr")
        XCTAssertTrue(reveal(row, in: app))
        XCTAssertTrue(row.label.contains("Very good, band 4 of 5"), "The row should read its band: \(row.label)")
    }

    func testLowConfidenceAndNotRatedAreMarked() throws {
        let app = try launch()
        try openScorecard(app)
        let vo2 = element(app, "pf-standing-metric-vo2")
        XCTAssertTrue(reveal(vo2, in: app))
        XCTAssertTrue(vo2.label.contains("Low confidence"), "A low-confidence metric should say so.")
        let unrated = element(app, "pf-standing-metric-run_5k")
        XCTAssertTrue(reveal(unrated, in: app))
        XCTAssertTrue(unrated.label.contains("Not rated"), "A metric with no band should read Not rated.")
        attach(app, "40 Low confidence and not rated")
    }

    func testMetricSheetShowsTheNormTableSourceAndTrend() throws {
        let app = try launch()
        try openScorecard(app)
        let row = element(app, "pf-standing-metric-resting_hr")
        XCTAssertTrue(reveal(row, in: app))
        row.tap()
        XCTAssertTrue(element(app, "pf-standing-metric-sheet").waitForExistence(timeout: 10))
        for band in 1...5 {
            XCTAssertTrue(element(app, "pf-standing-norm-\(band)").exists, "The norm table should list band \(band).")
        }
        attach(app, "41 Metric sheet")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-standing-source").waitForExistence(timeout: 5), "The source tag should show.")
        XCTAssertTrue(element(app, "pf-standing-trend").exists, "The trend should show.")
        attach(app, "41 Metric sheet scrolled")
    }

    func testFocusMetricOpensItsPlan() throws {
        let app = try launch()
        try openScorecard(app)
        let button = app.buttons["pf-standing-focus-plan-sleep_regularity"]
        XCTAssertTrue(reveal(button, in: app), "A focus metric with a plan should link to it.")
        button.tap()
        XCTAssertTrue(element(app, "pf-standing-plan-sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "pf-plan-p-sleep").exists, "The plan card should show.")
        attach(app, "42 Plan")
        app.swipeUp()
        attach(app, "42 Plan scrolled")
    }

    func testPlansListOpensAPlan() throws {
        let app = try launch()
        try openScorecard(app)
        let row = app.buttons["pf-standing-plan-p-push"]
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 24), "The Plans list should list every plan.")
        row.tap()
        XCTAssertTrue(element(app, "pf-plan-p-push").waitForExistence(timeout: 10))
    }

    func testTestDayHintsComeFromTheTestText() throws {
        let app = try launch()
        try openScorecard(app)
        let hint = element(app, "pf-test-hint-pushups")
        XCTAssertTrue(reveal(hint, in: app, maxSwipes: 30), "The test-day card should show a Telegram hint.")
        XCTAssertEqual(hint.label, "Log it in Telegram: push-ups 35")
        XCTAssertEqual(element(app, "pf-test-hint-grip").label, "Log it in Telegram: grip 52 kg")
        XCTAssertTrue(element(app, "pf-test-logged-squat").label.contains("Not logged yet"))
        attach(app, "43 Test day")
    }

    func testTodayShowsTheCompactCardAndItOpensTheScorecard() throws {
        let app = try launch()
        try openSegment(app, "Today")
        let card = element(app, "pf-standing-today-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Today should show the compact Where you stand card.")
        attach(app, "44 Where you stand on Today")
        card.tap()
        XCTAssertTrue(element(app, "pf-standing-screen").waitForExistence(timeout: 10))
    }

    func testNotApplicableShowsTheProfileNote() throws {
        let app = try launch(extraArguments: ["-PaceForgeStandingNotApplicable"])
        try openScorecard(app)
        XCTAssertTrue(element(app, "pf-standing-na").waitForExistence(timeout: 5), "A profile without sex and age is the empty state.")
        XCTAssertTrue(element(app, "pf-standing-note").label.localizedCaseInsensitiveContains("norms need sex and age"))
        XCTAssertFalse(element(app, "pf-standing-metric-resting_hr").exists, "No metric is rated in the empty state.")
        attach(app, "45 Not applicable")
    }
}
