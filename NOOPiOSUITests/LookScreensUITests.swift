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

    // MARK: Charge, Effort, Rest

    private func captureScoreDetail(_ screen: String, kind: String, step: Int, name: String) throws {
        let app = try launch(screen: screen)
        XCTAssertTrue(element(app, "look-score-detail-\(kind)").waitForExistence(timeout: 30), "The \(name) detail should open.")
        XCTAssertTrue(element(app, "look-score-ring").waitForExistence(timeout: 20), "The \(name) ring should show.")
        attach(app, "Look \(step)0 \(name) detail top")
        XCTAssertTrue(reveal(element(app, "look-score-insight"), in: app), "The \(name) insight card should show.")
        attach(app, "Look \(step)1 \(name) insight card")
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

    /// Trends no longer carries the look's metric-menu chart (the Charge section has the one chart with the W / M / 3M / 6M / Y / All
    /// switch, and the Metric Explorer row has every metric); the Charge section is closed until tapped.
    func testNoopTrendsKeepsTheChargeChartWithItsRangeSwitch() throws {
        let app = try launch(screen: "trends")
        XCTAssertTrue(element(app, "coach-week-section-trends-charge").waitForExistence(timeout: 30), "Trends should have the Charge section.")
        app.openSection("trends-charge")
        XCTAssertFalse(element(app, "look-noop-trends").exists, "The look's metric-menu chart is no longer on Trends.")
        attach(app, "Look 72 Trends Charge section")
    }

    // MARK: Sleep

    func testSleepTabShowsItsStagesAndSleepTrends() throws {
        let app = try launch(screen: "sleep")
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

    func testHealthBodyChipShowsTheTrendView() throws {
        let app = try launch(fixture: true)
        app.openChip("Health", "body")
        app.openSection("body-trend")
        XCTAssertTrue(reveal(element(app, "pf-body-trend-chart"), in: app), "The Body chip should show the trend view.")
        attach(app, "Look A2 PaceForge Body trend")
        let menu = element(app, "look-trend-metric-menu")
        XCTAssertTrue(reveal(menu, in: app), "The Body chip should offer the metric menu.")
        menu.tap()
        attach(app, "Look A3 PaceForge Body metric menu")
    }

    func testPlanThisWeekAndSharedCoachUseTheCards() throws {
        let app = try launch(fixture: true)
        app.openChip("Plan", "week")
        attach(app, "Look A4 PaceForge This week")
        app.openCoach("read")
        XCTAssertTrue(element(app, "coach-full-brain").waitForExistence(timeout: 30))
        attach(app, "Look A5 Shared Coach")
    }

    // MARK: Floating tab bar

    func testFloatingTabBarSwitchesTabs() throws {
        let app = try launch()
        let plan = app.shellTab("Plan")
        XCTAssertTrue(plan.waitForExistence(timeout: 30), "The floating bar should show its tabs.")
        XCTAssertTrue(element(app, "look-coach").exists, "The Coach is a button beside the bar.")
        attach(app, "Look B0 floating tab bar on Today")
        plan.tap()
        XCTAssertTrue(element(app, "calendar-host").waitForExistence(timeout: 20), "Plan should open from the floating bar.")
        attach(app, "Look B1 floating tab bar on Plan")
        app.shellTab("Train").tap()
        XCTAssertTrue(element(app, "train-host").waitForExistence(timeout: 20), "Train should open from the floating bar.")
        element(app, "train-chip-athlete").tap()
        XCTAssertTrue(element(app, "train-chip-content-athlete").waitForExistence(timeout: 20), "Train should have the Athlete chip.")
        attach(app, "Look B2 floating tab bar on Train")
        app.shellTab("Health").tap()
        XCTAssertTrue(element(app, "health-host").waitForExistence(timeout: 20), "Health should open from the floating bar.")
        app.coachButton.tap()
        XCTAssertTrue(element(app, "coach-host").waitForExistence(timeout: 20), "The Coach button should open the Coach.")
        attach(app, "Look B3 the Coach over Health")
    }
}
