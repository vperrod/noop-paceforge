import XCTest

/// The navigation, the only one: five tabs in the floating bar (Today, Plan, Coach, Reports, Body), Plan's three chips, Reports' two chips
/// (with the index of Day, Week, Month and Race), the Coach's four blocks and the six PaceForge cards on Today. Like the other UI tests
/// these run on `--demo-seed` data and the synthetic fixture (`-PaceForgeFixture`). Not run in CI.
final class UnifiedNavUITests: XCTestCase {
    private func launch(fixture: Bool = true, extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: ["-theme.appearance", "dark"])
        app.launchArguments.append(contentsOf: extra)
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

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func open(_ tab: String, host: String, in app: XCUIApplication) {
        let button = app.shellTab(tab)
        XCTAssertTrue(button.waitForExistence(timeout: 20), "The \(tab) tab should be in the bar.")
        button.tap()
        XCTAssertTrue(element(app, host).waitForExistence(timeout: 30), "The \(tab) screen should open.")
    }

    private func choose(_ chip: String, prefix: String, in app: XCUIApplication) {
        let button = element(app, "\(prefix)-chip-\(chip)")
        XCTAssertTrue(button.waitForExistence(timeout: 15), "The \(chip) chip should be in the chip bar.")
        button.tap()
    }

    // MARK: The bar

    func testTheBarHasTheFiveTabsInOrder() throws {
        let app = try launch()
        XCTAssertTrue(app.shellTab("Today").waitForExistence(timeout: 20))
        let order = ["Today", "Plan", "Coach", "Reports", "Body"]
        for title in order { XCTAssertTrue(app.shellTab(title).exists, "The bar has \(title).") }
        let xs = order.map { app.shellTab($0).frame.minX }
        XCTAssertEqual(xs, xs.sorted(), "The bar items should run in the order \(order.joined(separator: ", ")).")
    }

    func testThereIsNoOldTabAndNoCoachButton() throws {
        let app = try launch()
        XCTAssertTrue(app.shellTab("Plan").waitForExistence(timeout: 20))
        for title in ["PaceForge", "My Day", "Athlete", "Sleep", "Insights", "Workouts", "More"] {
            XCTAssertFalse(app.shellTab(title).exists, "\(title) is not a tab.")
        }
        XCTAssertFalse(element(app, "look-coach").exists, "Coach is a tab, so the floating button is gone.")
    }

    // MARK: Today

    func testTodayDrawsThePaceForgeCardsInTheFixedOrder() throws {
        let app = try launch()
        XCTAssertTrue(element(app, "pf-today-cards").waitForExistence(timeout: 30), "Today should draw PaceForge's cards.")
        let ids = ["the-call", "needs-you", "today", "how-you-are", "feel", "this-week"].map { "pf-today-card-\($0)" }
        let shown = ids.filter { element(app, $0).waitForExistence(timeout: 5) }
        XCTAssertTrue(shown.contains("pf-today-card-the-call"), "The call leads.")
        XCTAssertTrue(shown.contains("pf-today-card-this-week"), "The week closes.")
        let ys = shown.map { element(app, $0).frame.minY }
        XCTAssertEqual(ys, ys.sorted(), "The cards should run in the order \(shown.joined(separator: ", ")).")
    }

    func testTheStrapBlocksAreFoldedUnderTheCards() throws {
        let app = try launch()
        XCTAssertTrue(element(app, "today-strap-disclosure").waitForExistence(timeout: 30), "More from the strap is one folded row.")
    }

    // MARK: Plan

    func testPlanOpensOnThisWeek() throws {
        let app = try launch()
        open("Plan", host: "calendar-host", in: app)
        XCTAssertTrue(element(app, "calendar-chip-content-plan").waitForExistence(timeout: 30), "Plan opens on This week.")
    }

    func testPlanHasThreeChipsAndEachMounts() throws {
        let app = try launch()
        open("Plan", host: "calendar-host", in: app)
        for chip in ["calendar", "season"] {
            choose(chip, prefix: "calendar", in: app)
            XCTAssertTrue(element(app, "calendar-chip-content-\(chip)").waitForExistence(timeout: 30), "The \(chip) chip should mount.")
        }
        for gone in ["workouts", "events", "hyrox"] {
            XCTAssertFalse(element(app, "calendar-chip-\(gone)").exists, "\(gone) is a section, not a chip.")
        }
    }

    func testSeasonHasEventsAndHyroxAtTheTop() throws {
        let app = try launch()
        open("Plan", host: "calendar-host", in: app)
        choose("season", prefix: "calendar", in: app)
        XCTAssertTrue(element(app, "calendar-season-events").waitForExistence(timeout: 30), "Season starts with Events.")
        XCTAssertTrue(element(app, "calendar-season-hyrox").waitForExistence(timeout: 30), "Season has the HYROX screen under Events.")
    }

    // MARK: Coach

    func testCoachIsATabWithOneComposer() throws {
        let app = try launch()
        open("Coach", host: "coach-host", in: app)
        XCTAssertTrue(element(app, "coach-full-brain").waitForExistence(timeout: 30), "The Coach screen should load the shared PaceForge brain.")
        XCTAssertTrue(element(app, "pf-composer-mode").waitForExistence(timeout: 30), "One composer with a mode switch.")
        XCTAssertFalse(element(app, "pf-tell-coach").exists, "Tell the coach is not a separate card any more.")
    }

    // MARK: Reports

    func testReportsIndexHasDayWeekMonthAndRace() throws {
        let app = try launch()
        open("Reports", host: "reports-host", in: app)
        for kind in ["daily", "weekly", "monthly", "race"] {
            XCTAssertTrue(element(app, "pf-reports-index-\(kind)").waitForExistence(timeout: 30), "The index has the \(kind) row.")
        }
    }

    func testInsightsIsAChipOfReports() throws {
        let app = try launch()
        open("Reports", host: "reports-host", in: app)
        choose("insights", prefix: "reports", in: app)
        XCTAssertTrue(element(app, "insights-host").waitForExistence(timeout: 30), "Insights opens under Reports.")
    }

    func testReportsEndsWithMyDaySleepAndWorkouts() throws {
        let app = try launch()
        open("Reports", host: "reports-host", in: app)
        for row in ["myday", "sleep", "workouts"] {
            XCTAssertTrue(element(app, "more-row-\(row)").waitForExistence(timeout: 20), "More has the \(row) row.")
        }
    }

    // MARK: Body

    func testBodyHasBothChipsAndTheMoreRows() throws {
        let app = try launch()
        open("Body", host: "body-host", in: app)
        choose("labBook", prefix: "body", in: app)
        XCTAssertTrue(element(app, "body-chip-content-labBook").waitForExistence(timeout: 30), "The Lab Book chip should mount.")
        XCTAssertTrue(element(app, "more-row-athlete").waitForExistence(timeout: 20), "More has Athlete.")
        XCTAssertTrue(element(app, "more-row-settings").exists, "More ends with Settings.")
    }
}
