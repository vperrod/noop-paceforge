import XCTest

/// The unified navigation, Settings > Tools. With the switch on (the default) the tab bar is Today, Plan, Athlete, Insights and More,
/// with Sleep reached from the Rest ring on Today and from a More row; with it off the tabs are the classic ones (Today, Workouts,
/// Sleep, PaceForge, More). The switch is a launch argument here (`-unifiedNav YES` or `NO`); like the other UI tests these run on
/// `--demo-seed` data, and the PaceForge chips on the synthetic fixture (`-PaceForgeFixture`). Not run in CI.
final class UnifiedNavUITests: XCTestCase {
    private func launch(unifiedNav: Bool, fixture: Bool = true) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: ["-theme.appearance", "dark"])
        // The default is on, so "off" has to be asked for.
        if unifiedNav { app.launchArguments.append(contentsOf: ["-unifiedNav", "YES"]) } else { app.useClassicNavigation() }
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

    func testFlagOnShowsTheFiveTabs() throws {
        let app = try launch(unifiedNav: true)
        XCTAssertTrue(app.shellTab("Plan").waitForExistence(timeout: 20), "With the switch on, tab 2 is Plan.")
        XCTAssertTrue(app.shellTab("Athlete").exists, "With the switch on, tab 3 is Athlete.")
        XCTAssertTrue(app.shellTab("Insights").exists, "With the switch on, tab 4 is Insights.")
    }

    func testFlagOnHasNoPaceForgeTrendsSleepOrCalendarTab() throws {
        let app = try launch(unifiedNav: true)
        XCTAssertTrue(app.shellTab("Plan").waitForExistence(timeout: 20))
        XCTAssertFalse(app.shellTab("PaceForge").exists, "With the switch on there is no PaceForge tab.")
        XCTAssertFalse(app.shellTab("Trends").exists, "With the switch on there is no Trends tab.")
        XCTAssertFalse(app.shellTab("Sleep").exists, "With the switch on Sleep is not a tab.")
        XCTAssertFalse(app.shellTab("Calendar").exists, "Calendar is a chip of Plan, not a tab.")
    }

    func testFlagOnKeepsTheCoachButton() throws {
        let app = try launch(unifiedNav: true)
        XCTAssertTrue(element(app, "look-coach").waitForExistence(timeout: 20), "The Coach button stays at the end of the bar.")
    }

    func testFlagOffKeepsTheClassicTabs() throws {
        let app = try launch(unifiedNav: false)
        XCTAssertTrue(app.shellTab("PaceForge").waitForExistence(timeout: 20), "With the switch off, tab 4 is PaceForge.")
        XCTAssertTrue(app.shellTab("Workouts").exists, "With the switch off, tab 2 is Workouts.")
        XCTAssertFalse(app.shellTab("Calendar").exists, "With the switch off there is no Calendar tab.")
        XCTAssertFalse(app.shellTab("Insights").exists, "With the switch off there is no Insights tab.")
    }

    // MARK: Plan

    func testPlanOpensOnThePlanChip() throws {
        let app = try launch(unifiedNav: true)
        open("Plan", host: "calendar-host", in: app)
        XCTAssertTrue(element(app, "calendar-chip-content-plan").waitForExistence(timeout: 30), "Plan opens on its Plan chip.")
    }

    func testCalendarIsTheSecondChipOfPlan() throws {
        let app = try launch(unifiedNav: true)
        open("Plan", host: "calendar-host", in: app)
        choose("calendar", prefix: "calendar", in: app)
        XCTAssertTrue(element(app, "calendar-chip-content-calendar").waitForExistence(timeout: 30), "The Calendar chip should mount.")
        XCTAssertTrue(element(app, "calendar-month").exists, "The Calendar chip draws the month.")
    }

    func testEveryPlanChipMounts() throws {
        let app = try launch(unifiedNav: true)
        open("Plan", host: "calendar-host", in: app)
        for chip in ["workouts", "season", "events", "hyrox"] {
            choose(chip, prefix: "calendar", in: app)
            XCTAssertTrue(element(app, "calendar-chip-content-\(chip)").waitForExistence(timeout: 30), "The \(chip) chip should mount.")
        }
    }

    // MARK: Athlete

    func testAthleteOpensOnTheProfileHeader() throws {
        let app = try launch(unifiedNav: true)
        open("Athlete", host: "athlete-host", in: app)
        XCTAssertTrue(element(app, "athlete-header").waitForExistence(timeout: 30), "Athlete opens on the profile header.")
    }

    // MARK: Sleep

    func testSleepIsAMoreRowNotATab() throws {
        let app = try launch(unifiedNav: true)
        let tab = app.shellTab("More")
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let row = element(app, "more-row-sleep")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "More offers Sleep.")
        row.tap()
        XCTAssertTrue(element(app, "screen-sleep").waitForExistence(timeout: 30), "The Sleep row opens the Sleep screen.")
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

    func testUnifiedCoachShowsOneSharedConversation() throws {
        let app = try launch(unifiedNav: true)
        element(app, "look-coach").tap()
        XCTAssertTrue(element(app, "coach-full-brain").waitForExistence(timeout: 30), "The Coach screen should load the shared PaceForge brain.")
        XCTAssertTrue(element(app, "pf-chat-input").waitForExistence(timeout: 30), "The same screen should offer the shared Coach conversation.")
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
