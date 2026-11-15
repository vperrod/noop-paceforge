import XCTest

/// Build 529, Reports: the list in Plan (P1), the short daily report (P2), the short month report (P3), and the Coach's one row that
/// opens Plan > Reports. Each test serves the merged synthetic fixture and attaches screenshots named with the screen code.
final class Plan529ReportsUITests: XCTestCase {
    private func launch(open target: String? = nil, extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture", "-Plan529ResetSeen"])
        app.launchArguments.append(contentsOf: extra)
        if let target { app.launchArguments.append(contentsOf: ["-Plan529Open", target]) }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
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

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    // MARK: P1 The list

    func testReportsChipListsEveryKindWithItsVerdict() throws {
        let app = try launch()
        app.openChip("Plan", "reports")
        XCTAssertTrue(app.element("reports-row-today:2026-11-15").waitForExistence(timeout: 30), "Today's report should be a row.")
        XCTAssertTrue(app.element("reports-row-week:2026-W46").exists, "A week report should be a row.")
        XCTAssertTrue(app.element("reports-row-month:2026-10").exists, "A month report should be a row.")
        attach(app, "P1 reports top")
        XCTAssertTrue(reveal(app.element("reports-row-race:2026-11-14"), in: app), "A race should be a row.")
        XCTAssertTrue(reveal(app.element("reports-row-workout:24990000002"), in: app), "A workout review should be a row.")
        attach(app, "P1 reports bottom")
    }

    func testANewRowCarriesADotUntilItIsOpened() throws {
        let app = try launch()
        app.openChip("Plan", "reports")
        let row = app.element("reports-row-month:2026-10")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "A month report should be a row.")
        XCTAssertEqual(row.value as? String, "new", "A report never opened should be marked new.")
        row.tap()
        XCTAssertTrue(app.element("plan529-month-report").waitForExistence(timeout: 20), "The row should open the month report.")
        app.element("plan529-sheet-done").tap()
        let seen = NSPredicate(format: "value == nil OR value != %@", "new")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: seen, object: row)], timeout: 15), .completed,
                       "An opened report should lose its dot.")
    }

    func testAWeekRowOpensThatWeekInTheWeekChip() throws {
        let app = try launch()
        app.openChip("Plan", "reports")
        let row = app.element("reports-row-week:2026-W46")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "A week report should be a row.")
        row.tap()
        XCTAssertTrue(app.element("calendar-chip-content-week").waitForExistence(timeout: 20), "A week row should open the Week chip.")
    }

    // MARK: P2 Daily

    func testTheTodayRowOpensTheShortDailyReport() throws {
        let app = try launch()
        app.openChip("Plan", "reports")
        let row = app.element("reports-row-today:2026-11-15")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Today's report should be a row.")
        row.tap()
        XCTAssertTrue(app.element("daily-verdict").waitForExistence(timeout: 20), "The daily report should lead with its verdict.")
        XCTAssertTrue(app.element("report-story").exists, "The story should sit under the verdict.")
        XCTAssertTrue(app.element("report-insight").exists, "The insights should follow the story.")
        XCTAssertTrue(app.element("daily-device-Garmin").exists, "Garmin should have its own block.")
        XCTAssertTrue(app.element("daily-device-WHOOP").exists, "WHOOP should have its own block.")
        attach(app, "P2 daily report top")
        XCTAssertTrue(reveal(app.element("daily-experts"), in: app), "The experts should sit behind one row.")
        XCTAssertTrue(app.element("daily-words").exists, "The glossary should sit behind one row.")
        attach(app, "P2 daily report bottom")
    }

    func testTheExpertsRowOpensTheExistingReadingScreen() throws {
        let app = try launch(open: "daily:2026-11-15")
        app.openTab("Plan")
        let experts = app.element("daily-experts")
        XCTAssertTrue(app.element("daily-verdict").waitForExistence(timeout: 30), "The daily report should open.")
        XCTAssertTrue(reveal(experts, in: app), "The experts should sit behind one row.")
        experts.tap()
        XCTAssertTrue(app.element("pf-reports").waitForExistence(timeout: 20), "The row should open the existing reading screen.")
    }

    func testADailyReportWithoutAShortBlockShowsTheReadingScreen() throws {
        let app = try launch(open: "daily:2026-11-14")
        app.openTab("Plan")
        XCTAssertTrue(app.element("pf-reports").waitForExistence(timeout: 30), "A report with no short block should show the reading screen.")
        XCTAssertFalse(app.element("daily-verdict").exists, "There is no short block to show.")
    }

    // MARK: P3 Month

    func testTheMonthRowOpensTheShortMonthReport() throws {
        let app = try launch(open: "month:2026-10")
        app.openTab("Plan")
        XCTAssertTrue(app.element("month-verdict").waitForExistence(timeout: 30), "The month report should lead with its verdict.")
        XCTAssertTrue(app.element("report-story").exists, "The story should sit under the verdict.")
        XCTAssertTrue(app.element("month-held-slipped").exists, "It should say what held and what slipped.")
        attach(app, "P3 month report top")
        XCTAssertTrue(reveal(app.element("month-trend"), in: app), "It should draw the trend.")
        XCTAssertTrue(reveal(app.element("month-detail"), in: app), "The detail should sit behind one row.")
        attach(app, "P3 month report bottom")
    }

    // MARK: Coach

    func testCoachReadHasOneReportsRowThatOpensPlanReports() throws {
        let app = try launch()
        app.openCoach("read")
        XCTAssertFalse(app.element("coach-chip-reports").exists, "The Coach has no Reports chip any more.")
        let row = app.element("coach-reports-row")
        XCTAssertTrue(reveal(row, in: app), "The Read chip should hold one Reports row.")
        row.tap()
        XCTAssertTrue(app.element("calendar-chip-content-reports").waitForExistence(timeout: 30), "The row should open Plan > Reports.")
        attach(app, "P1 opened from the Coach")
    }

    func testInsightsLinksToTheWeekReportAndTheMonthReport() throws {
        let app = try launch()
        app.openCoach("insights")
        // Longer reports come before the week review on Overview, so they are met first when scrolling down.
        XCTAssertTrue(reveal(app.element("insights-report-monthly"), in: app), "Insights should link to the monthly report.")
        XCTAssertTrue(app.element("insights-report-monthly-scores").exists, "The monthly scores should stay reachable.")
        XCTAssertTrue(reveal(app.element("insights-week-report"), in: app), "Insights should link to last week's report.")
    }
}
