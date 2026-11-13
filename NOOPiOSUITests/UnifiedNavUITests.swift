import XCTest

/// The navigation, the only one: four tabs in the floating bar (Today, Plan, Train, Health) and the Coach button beside it, Plan's four
/// chips, Train's six, Health's seven, the Coach sheet and the six PaceForge cards on Today. Like the other UI tests
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

    func testTheBarHasTheFourTabsInOrder() throws {
        let app = try launch()
        XCTAssertTrue(app.shellTab("Today").waitForExistence(timeout: 20))
        let order = ["Today", "Plan", "Train", "Health"]
        for title in order { XCTAssertTrue(app.shellTab(title).exists, "The bar has \(title).") }
        let xs = order.map { app.shellTab($0).frame.minX }
        XCTAssertEqual(xs, xs.sorted(), "The bar items should run in the order \(order.joined(separator: ", ")).")
    }

    func testThereIsNoOldTabAndTheCoachIsAButton() throws {
        let app = try launch()
        XCTAssertTrue(app.shellTab("Plan").waitForExistence(timeout: 20))
        for title in ["Coach", "Reports", "Body", "PaceForge", "My Day", "Athlete", "Sleep", "Insights", "Workouts", "More"] {
            XCTAssertFalse(app.shellTab(title).exists, "\(title) is not a tab.")
        }
        XCTAssertTrue(app.coachButton.exists, "The Coach button sits beside the bar.")
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

    func testTheRingsLeadTodayAboveTheCards() throws {
        let app = try launch()
        let rings = element(app, "today-six-rings")
        XCTAssertTrue(rings.waitForExistence(timeout: 30), "The rings lead Today.")
        XCTAssertLessThan(rings.frame.minY, element(app, "pf-today-card-today").frame.minY, "The rings sit above the cards.")
    }

    // MARK: Plan

    func testPlanThisWeekChipMounts() throws {
        let app = try launch()
        open("Plan", host: "calendar-host", in: app)
        // The tab reopens on the chip it was left on, so the chip is chosen rather than assumed.
        choose("thisWeek", prefix: "calendar", in: app)
        XCTAssertTrue(element(app, "calendar-chip-content-plan").waitForExistence(timeout: 30), "This week should mount.")
    }

    func testPlanHasFourChipsAndEachMounts() throws {
        let app = try launch()
        open("Plan", host: "calendar-host", in: app)
        for chip in ["nextWeek", "calendar", "season"] {
            choose(chip, prefix: "calendar", in: app)
            XCTAssertTrue(element(app, "calendar-chip-content-\(chip)").waitForExistence(timeout: 30), "The \(chip) chip should mount.")
        }
        for gone in ["workouts", "events", "hyrox"] {
            XCTAssertFalse(element(app, "calendar-chip-\(gone)").exists, "\(gone) is not a Plan chip.")
        }
    }

    func testSeasonHasEventsAndNoHyrox() throws {
        let app = try launch()
        open("Plan", host: "calendar-host", in: app)
        choose("season", prefix: "calendar", in: app)
        XCTAssertTrue(element(app, "calendar-season-events").waitForExistence(timeout: 30), "Season has Events.")
        XCTAssertFalse(element(app, "calendar-season-hyrox").exists, "HYROX moved to Train.")
    }

    // MARK: Train

    func testTrainHasSixChipsAndEachMounts() throws {
        let app = try launch()
        open("Train", host: "train-host", in: app)
        for chip in ["hyrox", "running", "strength", "bike", "workouts", "athlete"] {
            choose(chip, prefix: "train", in: app)
            XCTAssertTrue(element(app, "train-chip-content-\(chip)").waitForExistence(timeout: 30), "The \(chip) chip should mount.")
        }
    }

    // MARK: Health

    func testHealthHasSevenChipsAndEachMounts() throws {
        let app = try launch()
        open("Health", host: "health-host", in: app)
        for chip in ["day", "sleep", "recovery", "body", "vitals", "journal", "trends"] {
            choose(chip, prefix: "health", in: app)
            XCTAssertTrue(element(app, "health-chip-content-\(chip)").waitForExistence(timeout: 30), "The \(chip) chip should mount.")
        }
    }

    // MARK: Coach

    func testCoachOpensAsASheetOverTheScreenOnShow() throws {
        let app = try launch()
        open("Plan", host: "calendar-host", in: app)
        XCTAssertTrue(app.coachButton.waitForExistence(timeout: 20), "The Coach button should be beside the bar.")
        app.coachButton.tap()
        XCTAssertTrue(element(app, "coach-host").waitForExistence(timeout: 30), "The Coach sheet should open.")
        XCTAssertTrue(element(app, "coach-full-brain").waitForExistence(timeout: 30), "The Coach should load the shared PaceForge brain.")
        choose("ask", prefix: "coach", in: app)
        XCTAssertTrue(element(app, "pf-composer-mode").waitForExistence(timeout: 30), "One composer with a mode switch on the Ask chip.")
        XCTAssertFalse(element(app, "pf-tell-coach").exists, "Tell the coach is not a separate card any more.")
    }
}
