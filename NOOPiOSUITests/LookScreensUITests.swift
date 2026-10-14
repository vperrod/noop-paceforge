import XCTest

/// Simulator checks for the look applied to the real screens: the Charge, Effort and Rest details, the Sleep tab's
/// last-night block, the Sleep Planner, the trend view on NOOP Trends and a metric detail, PaceForge's trends, and
/// the floating tab bar. Screenshot names start with "Look 4" to "Look 9" so the later run's attachments sort in
/// screen order. Like the other UI tests they run on `--demo-seed` data and the synthetic PaceForgeFixture.json
/// (made-up values only).
final class LookScreensUITests: XCTestCase {
    private func launch(screen: String? = nil, appearance: String = "dark", fixture: Bool = false,
                        extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
        app.launchArguments.append(contentsOf: ["-theme.appearance", appearance])
        app.launchArguments.append(contentsOf: extra)
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

    private func openSegment(_ app: XCUIApplication, _ title: String) throws {
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        let button = segments.buttons[title]
        if !button.isSelected { button.tap() }
    }

    // MARK: Charge, Effort, Rest

    private func captureScoreDetail(_ screen: String, kind: String, step: Int, name: String) throws {
        let app = try launch(screen: screen)
        XCTAssertTrue(element(app, "look-score-detail-\(kind)").waitForExistence(timeout: 30), "The \(name) detail should open.")
        XCTAssertTrue(element(app, "look-score-ring").waitForExistence(timeout: 20), "The \(name) ring should show.")
        attach(app, "Look \(step)0 \(name) detail top")
        XCTAssertTrue(reveal(element(app, "look-score-insight"), in: app), "The \(name) insight card should show.")
        attach(app, "Look \(step)1 \(name) insight card")
        XCTAssertTrue(reveal(element(app, "look-week-card"), in: app), "The \(name) weekly bars should show.")
        attach(app, "Look \(step)2 \(name) weekly bars")
        XCTAssertTrue(reveal(element(app, "look-metric-trend"), in: app), "The \(name) trend view should show.")
        attach(app, "Look \(step)3 \(name) trend")
        let sevenDay = element(app, "look-trend-seven-day")
        if reveal(sevenDay, in: app) {
            sevenDay.tap()
            attach(app, "Look \(step)4 \(name) trend with the 7-day average")
        }
    }

    func testChargeDetail() throws { try captureScoreDetail("lookcharge", kind: "charge", step: 4, name: "Charge") }

    func testEffortDetail() throws { try captureScoreDetail("lookeffort", kind: "effort", step: 5, name: "Effort") }

    func testRestDetail() throws { try captureScoreDetail("lookrest", kind: "rest", step: 6, name: "Rest") }

    func testScoreDetailInfoSheetOpens() throws {
        let app = try launch(screen: "lookcharge")
        let info = element(app, "look-detail-info")
        XCTAssertTrue(info.waitForExistence(timeout: 30), "The detail should offer its info button.")
        info.tap()
        XCTAssertTrue(app.staticTexts["What is Charge?"].waitForExistence(timeout: 10), "The info sheet should explain Charge.")
        attach(app, "Look 47 Charge info sheet")
    }

    func testChargeDetailInLight() throws {
        let app = try launch(screen: "lookcharge", appearance: "light")
        XCTAssertTrue(element(app, "look-score-detail-charge").waitForExistence(timeout: 30), "The Charge detail should open in light.")
        attach(app, "Look 48 Charge detail top (light)")
    }

    // MARK: Metric detail and NOOP Trends

    func testMetricDetailUsesTheTrendView() throws {
        let app = try launch(screen: "lookhrv")
        XCTAssertTrue(reveal(element(app, "look-metric-trend"), in: app), "A metric detail should show the trend view.")
        element(app, "look-trend-range-6M").tap()
        attach(app, "Look 70 metric detail trend 6M")
        element(app, "look-trend-range-Y").tap()
        attach(app, "Look 71 metric detail trend Y")
    }

    func testNoopTrendsOffersTheMetricMenuAndTheSevenDayAverage() throws {
        let app = try launch(screen: "trends")
        let trends = element(app, "look-noop-trends")
        XCTAssertTrue(trends.waitForExistence(timeout: 30), "Trends should show the look's trend view.")
        XCTAssertTrue(reveal(element(app, "look-trend-metric-menu"), in: app), "Trends should show the metric menu.")
        attach(app, "Look 72 Trends trend view")
        element(app, "look-trend-metric-menu").tap()
        let hrv = app.buttons["Heart Rate Variability"]
        XCTAssertTrue(hrv.waitForExistence(timeout: 10), "The menu should list heart rate variability.")
        hrv.tap()
        attach(app, "Look 73 Trends heart rate variability")
        let sevenDay = element(app, "look-trend-seven-day")
        XCTAssertTrue(reveal(sevenDay, in: app), "Trends should offer the 7-day average.")
        sevenDay.tap()
        attach(app, "Look 74 Trends with the 7-day average")
    }

    // MARK: Sleep

    func testSleepTabShowsLastNightAndSleepTrends() throws {
        let app = try launch(screen: "sleep")
        XCTAssertTrue(reveal(element(app, "look-last-night"), in: app), "The Sleep tab should show last night's sleep.")
        attach(app, "Look 80 Sleep last night")
        XCTAssertTrue(reveal(element(app, "look-last-night-hours"), in: app), "Last night should show the hours against the prior 30 days.")
        attach(app, "Look 81 Sleep hours and stages")
        XCTAssertTrue(reveal(element(app, "look-sleep-trends"), in: app), "The Sleep tab should show its trends.")
        attach(app, "Look 82 Sleep trends")
    }

    func testSleepPlannerInTheLook() throws {
        let app = try launch(screen: "lookplanner", extra: ["-SleepPlannerFixture", "ready"])
        XCTAssertTrue(element(app, "sleep-planner-bedtime").waitForExistence(timeout: 30), "The planner should show tonight's bedtime.")
        XCTAssertTrue(element(app, "sleep-planner-bedtime").label.hasPrefix("Bed by"))
        attach(app, "Look 90 Sleep planner top")
        XCTAssertTrue(reveal(element(app, "look-time-in-bed"), in: app), "The planner should show the time in bed.")
        attach(app, "Look 91 Sleep planner time in bed")
        let before = element(app, "sleep-planner-bedtime").label
        let peak = element(app, "sleep-planner-preset-peak")
        XCTAssertTrue(reveal(peak, in: app) || peak.exists, "The planner should offer the Peak goal.")
        peak.tap()
        XCTAssertNotEqual(element(app, "sleep-planner-bedtime").label, before, "Peak sleeps longer, so bed is earlier.")
        XCTAssertTrue(reveal(element(app, "sleep-planner-follow"), in: app), "The wind-down panel should show its toggle.")
        attach(app, "Look 92 Sleep planner wind-down")
        XCTAssertTrue(reveal(element(app, "sleep-planner-need-total"), in: app), "The planner should show the sleep-need table.")
        attach(app, "Look 93 Sleep planner sleep need")
    }

    // MARK: PaceForge

    func testPaceForgeInsightsShowsTheLoadTrend() throws {
        let app = try launch(fixture: true)
        try openSegment(app, "Insights")
        XCTAssertTrue(reveal(element(app, "pf-load-trend"), in: app), "Insights should show the load trend view.")
        attach(app, "Look A0 PaceForge Insights load trend")
        element(app, "look-trend-range-6M").tap()
        attach(app, "Look A1 PaceForge Insights load trend 6M")
    }

    func testPaceForgeBodyShowsTheTrendView() throws {
        let app = try launch(fixture: true)
        try openSegment(app, "Body")
        XCTAssertTrue(reveal(element(app, "pf-body-trend-chart"), in: app), "Body should show the trend view.")
        attach(app, "Look A2 PaceForge Body trend")
        let menu = element(app, "look-trend-metric-menu")
        XCTAssertTrue(reveal(menu, in: app), "Body should offer the metric menu.")
        menu.tap()
        attach(app, "Look A3 PaceForge Body metric menu")
    }

    func testPaceForgeThisWeekAndCoachUseTheCards() throws {
        let app = try launch(fixture: true)
        try openSegment(app, "This week")
        attach(app, "Look A4 PaceForge This week")
        try openSegment(app, "Coach")
        attach(app, "Look A5 PaceForge Coach")
    }

    // MARK: Floating tab bar

    func testFloatingTabBarSwitchesTabs() throws {
        let app = try launch()
        let trends = app.shellTab("Trends")
        XCTAssertTrue(trends.waitForExistence(timeout: 30), "The floating bar should show its tabs.")
        XCTAssertTrue(element(app, "look-coach").exists, "The floating bar should carry the coach button.")
        attach(app, "Look B0 floating tab bar on Today")
        trends.tap()
        XCTAssertTrue(element(app, "look-noop-trends").waitForExistence(timeout: 30), "Trends should open from the floating bar.")
        attach(app, "Look B1 floating tab bar on Trends")
        app.shellTab("Sleep").tap()
        XCTAssertTrue(reveal(element(app, "look-last-night"), in: app), "Sleep should open from the floating bar.")
        attach(app, "Look B2 floating tab bar on Sleep")
        app.shellTab("More").tap()
        attach(app, "Look B3 floating tab bar on More")
    }
}
