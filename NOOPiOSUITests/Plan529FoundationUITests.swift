import XCTest

/// Build 529 foundation: the merged fixture, and the Plan section's destinations. `-Plan529Open <target>` (DEBUG) opens a destination
/// through `PFDeepLink529` once the Plan tab is up; each destination shows its title until the stream that owns it replaces the file.
final class Plan529FoundationUITests: XCTestCase {
    private func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                      "The synthetic fixture should be bundled with the UI tests.")
    }

    private func launch(open target: String? = nil) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture"])
        if let target { app.launchArguments.append(contentsOf: ["-Plan529Open", target]) }
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: fixtureURL()))
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

    private func merged() throws -> [String: Any] {
        let json = try Fixtures529.merged(Data(contentsOf: fixtureURL()))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testMergedFixtureKeepsTheBigFixtureDay() throws {
        XCTAssertEqual(try merged()["today"] as? String, "2030-03-13")
    }

    func testMergedFixtureServesTheWeekIndex() throws {
        XCTAssertNotNil(try merged()["data/plan-week/index.json"] as? [String: Any])
    }

    func testMergedFixtureAddsTheShortBlockToTheDailyReport() throws {
        let report = try XCTUnwrap(try merged()["data/reports/daily/2026-11-15.json"] as? [String: Any])
        XCTAssertNotNil(report["short"] as? [String: Any])
    }

    func testSessionSheetOpensOverThePlanTab() throws {
        let app = try launch(open: "session:2026-W47:c10def6f")
        app.openTab("Plan")
        XCTAssertTrue(app.element("plan529-session").waitForExistence(timeout: 30), "The session sheet should open.")
        attach(app, "Plan529 01 session sheet")
        app.element("plan529-sheet-done").tap()
        XCTAssertTrue(app.element("plan529-session").waitForNonExistence(timeout: 30), "Done should close the sheet over the Plan tab.")
        XCTAssertTrue(app.element("calendar-host").exists, "Done should return to the Plan tab.")
    }

    func testInboxOpensOverThePlanTab() throws {
        let app = try launch(open: "inbox")
        app.openTab("Plan")
        XCTAssertTrue(app.element("plan529-inbox").waitForExistence(timeout: 30), "The inbox should open.")
    }

    func testDeepLinkToTheSeasonChipLandsOnSeason() throws {
        let app = try launch(open: "chip:season")
        app.openTab("Plan")
        XCTAssertTrue(app.element("calendar-chip-content-season").waitForExistence(timeout: 30), "The Season chip should mount.")
        attach(app, "Plan529 02 season chip")
    }

    func testReportsChipListsTheReports() throws {
        let app = try launch()
        app.openChip("Plan", "reports")
        XCTAssertTrue(app.element("reports-row-today:2026-11-15").waitForExistence(timeout: 30), "The Reports chip should list the reports.")
        attach(app, "Plan529 03 reports chip")
    }
}
