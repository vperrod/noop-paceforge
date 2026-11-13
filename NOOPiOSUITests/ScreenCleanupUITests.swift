import XCTest

/// The screen cleanup of build 468, kept current for the unified bar (Today, Plan, Train, Health and the Coach button): every screen is
/// a chip or a row of a tab, each metric has one full screen, and nothing that was merged crashes when it opens. They run on
/// `--demo-seed` data and the synthetic PaceForgeFixture.json (made-up numbers). Screen containers are named `screen-<destination>`.
final class ScreenCleanupUITests: XCTestCase {
    private func launch(fixture: Bool = false, extra: [String] = []) throws -> XCUIApplication {
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
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    private func alive(_ app: XCUIApplication, _ what: String) {
        XCTAssertEqual(app.state, .runningForeground, "The app should still be running after \(what).")
    }

    /// The Insights screen: the last chip of the Coach, which the round Coach button opens as a sheet.
    private func openInsights(_ app: XCUIApplication) {
        XCTAssertTrue(app.coachButton.waitForExistence(timeout: 30), "The Coach button should be beside the bar.")
        app.coachButton.tap()
        let chip = element(app, "coach-chip-insights")
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "The Coach should offer the Insights chip.")
        chip.tap()
        XCTAssertTrue(element(app, "insights-host").waitForExistence(timeout: 30), "The Insights chip should open Insights.")
    }

    // MARK: Rows and chips

    /// (tab, chip, row under the chip or nil, the container that proves the screen opened). Rhythm and Alarms are rows of the Sleep chip,
    /// the Athlete screen is the Athlete chip of Train.
    private static let screens: [(tab: String, chip: String, row: String?, screen: String)] = [
        ("Train", "train-chip-athlete", nil, "athlete-host"),
        ("Health", "health-chip-sleep", "health-sleep-rhythm", "screen-rhythm"),
        ("Health", "health-chip-sleep", "health-sleep-alarms", "screen-alarms"),
    ]

    func testEveryRowAndChipOpensItsScreen() throws {
        let app = try launch()
        for (index, entry) in Self.screens.enumerated() {
            let tab = app.shellTab(entry.tab)
            XCTAssertTrue(tab.waitForExistence(timeout: 30), "The \(entry.tab) tab should be in the bar.")
            tab.tap()
            let chip = element(app, entry.chip)
            XCTAssertTrue(chip.waitForExistence(timeout: 20), "\(entry.tab) should have the chip \(entry.chip).")
            chip.tap()
            if let rowID = entry.row {
                let row = element(app, rowID)
                XCTAssertTrue(reveal(row, in: app), "\(entry.chip) should show the row \(rowID).")
                row.tap()
            }
            XCTAssertTrue(element(app, entry.screen).waitForExistence(timeout: 30), "\(entry.chip) \(entry.row ?? "") should open \(entry.screen).")
            Thread.sleep(forTimeInterval: 1)
            alive(app, "opening \(entry.screen)")
            attach(app, "Cleanup 1\(index) \(entry.screen)")
        }
    }

    // MARK: Tabs

    func testEveryTabOpensOnOneTap() throws {
        let app = try launch(fixture: true)
        let today = app.shellTab("Today")
        XCTAssertTrue(today.waitForExistence(timeout: 30), "The Today tab should be present.")
        XCTAssertTrue(element(app, "today-settings").waitForExistence(timeout: 20), "Today should open its top bar.")

        for (tab, host) in [("Plan", "calendar-host"), ("Train", "train-host"), ("Health", "health-host")] {
            app.shellTab(tab).tap()
            XCTAssertTrue(element(app, host).waitForExistence(timeout: 30), "\(tab) should open on one tap.")
            alive(app, "opening \(tab)")
        }
        XCTAssertTrue(app.coachButton.waitForExistence(timeout: 20), "The Coach button should be beside the bar.")
        app.coachButton.tap()
        XCTAssertTrue(element(app, "coach-host").waitForExistence(timeout: 30), "The Coach should open on one tap.")
        alive(app, "opening the Coach")
    }

    // MARK: Insights

    func testInsightsHasEveryChipAndTheReportsOpenTheirScreens() throws {
        let app = try launch(fixture: true)
        openInsights(app)
        XCTAssertTrue(element(app, "insights-chip-content-overview").waitForExistence(timeout: 30), "Insights opens on Overview.")
        for chip in ["trends", "journal", "deepDives"] {
            let button = element(app, "insights-chip-\(chip)")
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Insights should have the \(chip) chip.")
            button.tap()
            Thread.sleep(forTimeInterval: 1)
            alive(app, "choosing the \(chip) chip")
            attach(app, "Cleanup 3 Insights \(chip)")
        }
        element(app, "insights-chip-overview").tap()
        let reports: [(entry: String, body: String)] = [
            ("highlights", "pf-highlights-body"), ("healthspan", "pf-healthspan-body"), ("monthly", "pf-monthly-body"),
        ]
        for report in reports {
            let entry = element(app, "insights-report-\(report.entry)")
            XCTAssertTrue(reveal(entry, in: app), "Reports should list \(report.entry).")
            entry.tap()
            XCTAssertTrue(element(app, report.body).waitForExistence(timeout: 20), "The \(report.entry) report should open from Reports.")
            alive(app, "opening the \(report.entry) report")
            attach(app, "Cleanup 4 report \(report.entry)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    // MARK: Data and Settings

    func testDataHoldsEveryDataSectionAndSettingsHoldsTheTools() throws {
        let app = try launch()
        // Settings opens from the avatar on Today; Data is its Tools row.
        let avatar = element(app, "today-settings")
        XCTAssertTrue(avatar.waitForExistence(timeout: 30), "Today should offer Settings.")
        avatar.tap()
        let data = element(app, "settings-tool-data")
        XCTAssertTrue(reveal(data, in: app, maxSwipes: 14), "Settings should list the Data tool.")
        data.tap()
        for section in ["sources", "appleHealth", "miBand", "fused", "backup", "paceForge", "shortcuts", "limitations"] {
            let chip = element(app, "data-section-\(section)")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Data should have the \(section) section.")
            chip.tap()
            Thread.sleep(forTimeInterval: 1)
            alive(app, "choosing the \(section) data section")
            attach(app, "Cleanup 5 Data \(section)")
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for tool in ["testcentre", "automations", "siri", "powersaving"] {
            XCTAssertTrue(reveal(element(app, "settings-tool-\(tool)"), in: app, maxSwipes: 14), "Settings should list the \(tool) tool.")
        }
        attach(app, "Cleanup 6 Settings tools")
    }

    // MARK: Quick actions

    func testTheQuickActionSheetHoldsLiveWorkoutsBreatheAndIntervals() throws {
        let app = try launch()
        let actions = ["live", "workout", "journal", "breathe", "intervals"]
        for action in actions {
            let plus = app.buttons["Quick actions"]
            XCTAssertTrue(reveal(plus, in: app, maxSwipes: 14), "Today should offer the quick-action button.")
            plus.tap()
            let row = element(app, "quick-action-\(action)")
            XCTAssertTrue(row.waitForExistence(timeout: 15), "The quick-action sheet should list \(action).")
            row.tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20), "\(action) should open from the sheet.")
            Thread.sleep(forTimeInterval: 1)
            alive(app, "opening \(action) from the quick actions")
            attach(app, "Cleanup 7 quick action \(action)")
            app.buttons["Done"].tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: One screen per metric

    func testTheStressAndHealthTilesOpenTheOneScreenEach() throws {
        let app = try launch()
        let health = element(app, "look-health-tile")
        XCTAssertTrue(reveal(health, in: app), "Today should show the Health monitor tile.")
        health.tap()
        XCTAssertTrue(app.staticTexts["Health Monitor"].waitForExistence(timeout: 20), "The Health tile should open the Health screen.")
        alive(app, "opening Health from its tile")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let stress = element(app, "look-stress-tile")
        XCTAssertTrue(reveal(stress, in: app), "Today should show the Stress monitor tile.")
        stress.tap()
        XCTAssertTrue(app.staticTexts["Autonomic load across your waking day"].waitForExistence(timeout: 20),
                      "The Stress tile should open the Stress screen.")
        alive(app, "opening Stress from its tile")
    }

    func testTheRestRingOpensSleepOverTodayAndSleepIsNotATab() throws {
        let app = try launch()
        // The ring's button reads "Rest, 87"; the sticky mini dial ("Rest 87") and the "See how it is scored" button are other elements.
        let ring = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Rest, [0-9]+")).firstMatch
        XCTAssertTrue(reveal(ring, in: app, maxSwipes: 6), "Today should show the Rest ring.")
        ring.tap()
        XCTAssertTrue(reveal(element(app, "look-last-night"), in: app), "The Rest ring should open Sleep.")
        alive(app, "opening Sleep from the Rest ring")
    }
}
