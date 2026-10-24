import XCTest

/// The screen cleanup of build 468: every screen is at most two taps from a tab (More lists 11 rows, all visible at rest), each metric
/// has one full screen, and nothing that was merged crashes when it opens. They run on `--demo-seed` data and the synthetic
/// PaceForgeFixture.json (made-up numbers). Screen containers are named `screen-<destination>` and More rows `more-row-<name>`.
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

    /// Tap 1: the More tab (a re-tap pops whatever it had open back to the list).
    private func openMore(_ app: XCUIApplication) {
        let more = app.shellTab("More")
        XCTAssertTrue(more.waitForExistence(timeout: 30), "The More tab should be present.")
        more.tap()
    }

    // MARK: More

    /// (More row, the screen container it opens). The container id is `screen-` plus the destination's raw value.
    private static let moreRows: [(row: String, screen: String)] = [
        ("insights", "insights"), ("explore", "explore"), ("compare", "compare"),
        ("liftlog", "liftLog"), ("health", "health"), ("stress", "stress"), ("labbook", "labBook"), ("rhythm", "rhythm"),
        ("alarms", "alarms"), ("data", "data"), ("settings", "settings"),
    ]

    func testMoreListsAtMostTwelveRowsAndNothingIsCollapsed() throws {
        let app = try launch()
        openMore(app)
        XCTAssertTrue(element(app, "more-row-insights").waitForExistence(timeout: 20), "More should list its rows.")
        var found = Set<String>()
        for _ in 0..<4 {
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "more-row-"))
            for index in 0..<rows.count { found.insert(rows.element(boundBy: index).identifier) }
            app.swipeUp()
        }
        attach(app, "Cleanup 01 More")
        XCTAssertLessThanOrEqual(found.count, 12, "More should list 12 rows or fewer, found \(found.sorted()).")
        XCTAssertEqual(found, Set(Self.moreRows.map { "more-row-\($0.row)" }), "More should list exactly the eleven rows.")
        XCTAssertFalse(app.buttons["Body"].exists, "No group header should hide rows behind a disclosure.")
        alive(app, "listing More")
    }

    func testEveryMoreRowOpensItsScreenInTwoTaps() throws {
        let app = try launch()
        for (index, entry) in Self.moreRows.enumerated() {
            openMore(app)
            let row = element(app, "more-row-\(entry.row)")
            XCTAssertTrue(reveal(row, in: app), "More should show the \(entry.row) row.")
            row.tap()
            XCTAssertTrue(element(app, "screen-\(entry.screen)").waitForExistence(timeout: 30),
                          "The \(entry.row) row should open its screen on the second tap.")
            Thread.sleep(forTimeInterval: 1)
            alive(app, "opening \(entry.row)")
            attach(app, "Cleanup 1\(index) \(entry.row)")
        }
    }

    // MARK: Tabs

    func testEveryTabAndTheCoachButtonOpenOnOneTap() throws {
        let app = try launch(fixture: true)
        let today = app.shellTab("Today")
        XCTAssertTrue(today.waitForExistence(timeout: 30), "The Today tab should be present.")
        XCTAssertTrue(element(app, "today-settings").waitForExistence(timeout: 20), "Today should open its top bar.")

        app.shellTab("Workouts").tap()
        XCTAssertTrue(app.staticTexts["Workouts"].waitForExistence(timeout: 20), "Workouts should open on one tap.")
        alive(app, "opening Workouts")
        app.shellTab("Sleep").tap()
        XCTAssertTrue(reveal(element(app, "look-last-night"), in: app), "Sleep should open on one tap.")
        alive(app, "opening Sleep")
        app.shellTab("PaceForge").tap()
        XCTAssertTrue(app.segmentedControls["pf-segments"].waitForExistence(timeout: 20), "PaceForge should open on one tap.")
        alive(app, "opening PaceForge")
        openMore(app)
        XCTAssertTrue(element(app, "more-row-insights").waitForExistence(timeout: 20), "More should open on one tap.")

        let coach = element(app, "look-coach")
        XCTAssertTrue(coach.exists, "The centre button should be NOOP Coach.")
        XCTAssertEqual(coach.label, "NOOP Coach", "The Coach button is the single Coach entry point.")
        coach.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20), "The Coach button should open Coach in one tap.")
        alive(app, "opening Coach")
    }

    func testPaceForgeSegmentsAreTwoTapsAndInsightsIsTheSameScreenWithTraining() throws {
        let app = try launch(fixture: true)
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 20), "The PaceForge segments should load from the fixture.")
        for title in ["Today", "Coach", "This week", "Insights", "Body"] {
            let button = segments.buttons[title]
            for _ in 0..<3 where !button.isSelected { button.tap(); Thread.sleep(forTimeInterval: 1) }
            XCTAssertTrue(button.isSelected, "\(title) should open on the second tap.")
            alive(app, "opening PaceForge \(title)")
        }
        segments.buttons["Insights"].tap()
        XCTAssertTrue(element(app, "insights-section-training").waitForExistence(timeout: 15),
                      "PaceForge's Insights is the Insights screen, with Training as its first section.")
        XCTAssertTrue(element(app, "insights-section-reports").exists, "It carries the same Reports section as Insights in More.")
        attach(app, "Cleanup 20 PaceForge Insights sections")
    }

    // MARK: Insights

    func testInsightsHasEverySectionAndTheReportsOpenTheirScreens() throws {
        let app = try launch(fixture: true)
        openMore(app)
        let row = element(app, "more-row-insights")
        XCTAssertTrue(reveal(row, in: app), "More should show Insights.")
        row.tap()
        XCTAssertTrue(element(app, "screen-insights").waitForExistence(timeout: 30), "Insights should open on the second tap.")
        XCTAssertTrue(element(app, "look-journal-flow").waitForExistence(timeout: 30), "Insights opens on its Journal section.")
        for section in ["journal", "moves", "intelligence", "reports"] {
            let chip = element(app, "insights-section-\(section)")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Insights should have the \(section) section.")
            chip.tap()
            Thread.sleep(forTimeInterval: 1)
            alive(app, "choosing the \(section) section")
            attach(app, "Cleanup 3 Insights \(section)")
        }
        let reports: [(entry: String, body: String)] = [
            ("highlights", "pf-highlights-body"), ("healthspan", "pf-healthspan-body"),
            ("monthly", "pf-monthly-body"), ("impact", "pf-impact-body"),
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
        openMore(app)
        let data = element(app, "more-row-data")
        XCTAssertTrue(reveal(data, in: app), "More should show Data.")
        data.tap()
        XCTAssertTrue(element(app, "screen-data").waitForExistence(timeout: 30), "Data should open on the second tap.")
        for section in ["sources", "appleHealth", "miBand", "fused", "backup", "paceForge", "shortcuts", "limitations"] {
            let chip = element(app, "data-section-\(section)")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Data should have the \(section) section.")
            chip.tap()
            Thread.sleep(forTimeInterval: 1)
            alive(app, "choosing the \(section) data section")
            attach(app, "Cleanup 5 Data \(section)")
        }
        openMore(app)
        let settings = element(app, "more-row-settings")
        XCTAssertTrue(reveal(settings, in: app), "More should show Settings.")
        settings.tap()
        XCTAssertTrue(element(app, "screen-settings").waitForExistence(timeout: 30), "Settings should open on the second tap.")
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

    func testTheRestDetailLinksToTheSleepTabNotASecondSleepScreen() throws {
        let app = try launch()
        // The ring's button reads "Rest, 87"; the sticky mini dial ("Rest 87") and the "See how it is scored" button are other elements.
        let ring = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Rest, [0-9]+")).firstMatch
        XCTAssertTrue(reveal(ring, in: app, maxSwipes: 6), "Today should show the Rest ring.")
        ring.tap()
        XCTAssertTrue(element(app, "look-score-detail-rest").waitForExistence(timeout: 30), "The Rest ring should open the Rest detail.")
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Explore your sleep insights")).firstMatch  // the label ends with an arrow
        XCTAssertTrue(reveal(link, in: app), "The Rest insight card should link to sleep.")
        link.tap()
        XCTAssertTrue(reveal(element(app, "look-last-night"), in: app), "The link should land on the Sleep tab.")
        XCTAssertTrue(app.shellTab("Sleep").isSelected, "The Sleep tab should be the selected tab, not a screen over Today.")
        alive(app, "following the Rest detail's sleep link")
    }
}
