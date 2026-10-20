import XCTest

/// The New navigation (beta), Settings > Tools. With the switch on at launch the tab bar is Today, Calendar, Day, Insights and More;
/// with it off the tabs are the ones build 480 has. The switch is a launch argument here (`-unifiedNav YES`); like the other UI tests
/// these run on `--demo-seed` data, and the PaceForge chips on the synthetic fixture (`-PaceForgeFixture`). Not run in CI.
final class UnifiedNavUITests: XCTestCase {
    private func launch(unifiedNav: Bool, fixture: Bool = true) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: ["-theme.appearance", "dark"])
        if unifiedNav { app.launchArguments.append(contentsOf: ["-unifiedNav", "YES"]) }
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

    // MARK: The switch

    func testFlagOnShowsTheFiveNewTabs() throws {
        let app = try launch(unifiedNav: true)
        XCTAssertTrue(app.shellTab("Calendar").waitForExistence(timeout: 20), "With the switch on, tab 2 is Calendar.")
        XCTAssertTrue(app.shellTab("Day").exists, "With the switch on, Day is a tab.")
        XCTAssertTrue(app.shellTab("Insights").exists, "With the switch on, tab 4 is Insights.")
    }

    func testFlagOnHasNoPaceForgeTrendsOrSleepTab() throws {
        let app = try launch(unifiedNav: true)
        XCTAssertTrue(app.shellTab("Calendar").waitForExistence(timeout: 20))
        XCTAssertFalse(app.shellTab("PaceForge").exists, "With the switch on there is no PaceForge tab.")
        XCTAssertFalse(app.shellTab("Trends").exists, "With the switch on there is no Trends tab.")
        XCTAssertFalse(app.shellTab("Sleep").exists, "With the switch on there is no Sleep tab.")
    }

    func testFlagOnKeepsTheCoachButton() throws {
        let app = try launch(unifiedNav: true)
        XCTAssertTrue(element(app, "look-coach").waitForExistence(timeout: 20), "The Coach button stays at the end of the bar.")
    }

    func testFlagOffKeepsTheBuild480Tabs() throws {
        let app = try launch(unifiedNav: false)
        XCTAssertTrue(app.shellTab("PaceForge").waitForExistence(timeout: 20), "With the switch off, tab 4 is PaceForge.")
        XCTAssertTrue(app.shellTab("Trends").exists, "With the switch off, tab 2 is Trends.")
        XCTAssertFalse(app.shellTab("Calendar").exists, "With the switch off there is no Calendar tab.")
        XCTAssertFalse(app.shellTab("Insights").exists, "With the switch off there is no Insights tab.")
    }

    // MARK: Calendar

    func testCalendarOpensOnTheCalendarChip() throws {
        let app = try launch(unifiedNav: true)
        open("Calendar", host: "calendar-host", in: app)
        XCTAssertTrue(element(app, "calendar-chip-content-calendar").waitForExistence(timeout: 30), "Calendar opens on its Calendar chip.")
        XCTAssertTrue(element(app, "calendar-month").exists, "The Calendar chip draws the month.")
    }

    func testEveryCalendarChipMounts() throws {
        let app = try launch(unifiedNav: true)
        open("Calendar", host: "calendar-host", in: app)
        for chip in ["plan", "season", "events", "hyrox"] {
            choose(chip, prefix: "calendar", in: app)
            XCTAssertTrue(element(app, "calendar-chip-content-\(chip)").waitForExistence(timeout: 30), "The \(chip) chip should mount.")
        }
    }

    // MARK: Insights

    func testInsightsOpensOnOverview() throws {
        let app = try launch(unifiedNav: true)
        open("Insights", host: "insights-host", in: app)
        XCTAssertTrue(element(app, "insights-chip-content-overview").waitForExistence(timeout: 30), "Insights opens on Overview.")
    }

    func testEveryInsightsChipMounts() throws {
        let app = try launch(unifiedNav: true)
        open("Insights", host: "insights-host", in: app)
        for chip in ["trends", "reports", "journal", "deepDives"] {
            choose(chip, prefix: "insights", in: app)
            XCTAssertTrue(element(app, "insights-chip-content-\(chip)").waitForExistence(timeout: 30), "The \(chip) chip should mount.")
        }
    }

    func testReportsChipOffersTheMonthlyReport() throws {
        let app = try launch(unifiedNav: true)
        open("Insights", host: "insights-host", in: app)
        choose("reports", prefix: "insights", in: app)
        XCTAssertTrue(element(app, "insights-report-monthly").waitForExistence(timeout: 20), "Reports offers the Monthly report.")
    }

    // MARK: Coach

    func testCoachButtonOpensTheUnifiedCoach() throws {
        let app = try launch(unifiedNav: true)
        let button = element(app, "look-coach")
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(element(app, "coach-host").waitForExistence(timeout: 30), "The Coach button opens the one Coach screen.")
    }

    func testCoachHasBothChips() throws {
        let app = try launch(unifiedNav: true)
        element(app, "look-coach").tap()
        XCTAssertTrue(element(app, "coach-chip-coach").waitForExistence(timeout: 30), "The Coach chip should be there.")
        choose("chat", prefix: "coach", in: app)
        XCTAssertTrue(element(app, "coach-chip-content-chat").waitForExistence(timeout: 30), "The NOOP chat chip should mount.")
    }

    // MARK: More

    func testMoreOffersBodyAndNotTheMovedRows() throws {
        let app = try launch(unifiedNav: true)
        let tab = app.shellTab("More")
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(element(app, "more-row-body").waitForExistence(timeout: 20), "More offers Body.")
        XCTAssertFalse(element(app, "more-row-insights").exists, "Insights moved to its tab.")
        XCTAssertFalse(element(app, "more-row-compare").exists, "Compare moved to the Insights tab.")
        XCTAssertFalse(element(app, "more-row-labbook").exists, "The Lab Book moved into Body.")
    }

    func testBodyHasBothChips() throws {
        let app = try launch(unifiedNav: true)
        app.shellTab("More").tap()
        let row = element(app, "more-row-body")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(element(app, "body-host").waitForExistence(timeout: 30), "Body should open.")
        choose("labBook", prefix: "body", in: app)
        XCTAssertTrue(element(app, "body-chip-content-labBook").waitForExistence(timeout: 30), "The Lab Book chip should mount.")
    }

    func testFlagOffMoreKeepsTheOldRows() throws {
        let app = try launch(unifiedNav: false, fixture: false)
        let tab = app.shellTab("More")
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(element(app, "more-row-insights").waitForExistence(timeout: 20), "With the switch off, More keeps Insights.")
        XCTAssertTrue(element(app, "more-row-labbook").exists, "With the switch off, More keeps the Lab Book.")
        XCTAssertFalse(element(app, "more-row-body").exists, "With the switch off there is no Body row.")
    }
}
