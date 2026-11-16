import XCTest

/// Build 529, A2: the inbox behind the bell on Today. It runs on `--demo-seed` data and the synthetic fixtures (`Fixtures529/inbox.json`
/// serves `data/inbox.json`; the big fixture's `data/alerts.json` stands in for the earlier alert history). `-Plan529InboxUnread` starts
/// with nothing read, where a phone takes the first document it reads as its baseline. Screenshot names start with "A2".
final class Plan529InboxUITests: XCTestCase {
    private func launch(extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture", "-Plan529InboxUnread"])
        app.launchArguments.append(contentsOf: extra)
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
    private func openInbox(_ app: XCUIApplication) -> XCUIElement {
        let bell = app.element("today-alerts")
        XCTAssertTrue(bell.waitForExistence(timeout: 30), "Today should carry the bell.")
        bell.tap()
        let inbox = app.element("plan529-inbox")
        XCTAssertTrue(inbox.waitForExistence(timeout: 20), "The bell should open the inbox.")
        return inbox
    }

    private func row(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.element("plan529-inbox-row-\(id)") }

    // MARK: The list

    func testTheBellOpensTheInboxNewestFirstWithItsChips() throws {
        let app = try launch()
        openInbox(app)
        XCTAssertTrue(row(app, "report:week:2030-W10").waitForExistence(timeout: 20), "The report line should be listed.")
        XCTAssertTrue(row(app, "today:2030-03-13").exists, "The morning verdict should be listed.")
        for chip in ["all", "coach", "reports", "plan", "health"] {
            XCTAssertTrue(app.element("plan529-inbox-chip-\(chip)").exists, "The \(chip) chip should be there.")
        }
        XCTAssertTrue(app.element("plan529-inbox-settings").exists, "The way to the switches should close the list.")
        XCTAssertLessThan(row(app, "report:week:2030-W10").frame.minY, row(app, "today:2030-03-13").frame.minY, "The newest line should be first.")
        attach(app, "A2 01 inbox")
    }

    func testARowShowsTheTimeForTodayAndYesterdayForTheDayBefore() throws {
        let app = try launch()
        openInbox(app)
        let today = row(app, "report:week:2030-W10")
        XCTAssertTrue(today.waitForExistence(timeout: 20))
        XCTAssertNotNil(today.label.range(of: #"\b\d{2}:\d{2}\b"#, options: .regularExpression), "A line from today should carry its time: \(today.label)")
        XCTAssertTrue(row(app, "problem:synthetic-signin").label.contains("Yesterday"), "A line from yesterday should say Yesterday.")
    }

    func testTheEarlierAlertHistoryIsMergedIn() throws {
        let app = try launch()
        openInbox(app)
        XCTAssertTrue(row(app, "alert:al-1").waitForExistence(timeout: 20), "An alert the server still keeps should be listed with the rest.")
    }

    func testChipsNarrowTheList() throws {
        let app = try launch()
        openInbox(app)
        XCTAssertTrue(row(app, "plan:changes:2030-W11").waitForExistence(timeout: 20))
        app.element("plan529-inbox-chip-plan").tap()
        XCTAssertTrue(row(app, "plan:changes:2030-W11").exists, "Plan should keep the plan change.")
        XCTAssertFalse(row(app, "report:week:2030-W10").exists, "Plan should leave the report out.")
        attach(app, "A2 02 plan chip")
        app.element("plan529-inbox-chip-coach").tap()
        XCTAssertTrue(row(app, "coach:synthetic_note:2030-03-13").waitForExistence(timeout: 5), "Coach should keep the coach note.")
        XCTAssertTrue(row(app, "workout:9000000003").exists, "Coach should keep the workout review.")
        app.element("plan529-inbox-chip-health").tap()
        XCTAssertTrue(row(app, "health:effort:2030-03-13").waitForExistence(timeout: 5), "Health should keep the health alerts.")
        XCTAssertFalse(row(app, "plan:changes:2030-W11").exists, "Health should leave the plan change out.")
    }

    // MARK: Unread

    func testNewLinesAreMarkedAndMarkAllReadClearsThem() throws {
        let app = try launch()
        openInbox(app)
        let header = app.element("plan529-inbox-new")
        XCTAssertTrue(header.waitForExistence(timeout: 20))
        XCTAssertFalse(header.label.uppercased().hasPrefix("NOTHING"), "With nothing read, the inbox should say how many are new.")
        XCTAssertEqual(row(app, "report:week:2030-W10").value as? String, "Unread", "A new line should be marked.")
        attach(app, "A2 03 new lines")
        app.element("plan529-inbox-mark-all").tap()
        expectation(for: NSPredicate(format: "label ==[c] 'Nothing new'"), evaluatedWith: app.element("plan529-inbox-new"))
        waitForExpectations(timeout: 10)
        attach(app, "A2 04 all read")
    }

    func testThePlanTabAndTheCoachButtonCarryADotWhileSomethingIsUnread() throws {
        let app = try launch()
        let plan = app.shellTab("Plan")
        XCTAssertTrue(plan.waitForExistence(timeout: 30))
        let dot = NSPredicate(format: "value == 'New'")
        expectation(for: dot, evaluatedWith: plan)
        expectation(for: dot, evaluatedWith: app.coachButton)
        waitForExpectations(timeout: 30)
        attach(app, "A2 05 dots")
        openInbox(app)
        app.element("plan529-inbox-mark-all").tap()
        let none = NSPredicate(format: "value != 'New'")
        expectation(for: none, evaluatedWith: plan)
        expectation(for: none, evaluatedWith: app.coachButton)
        waitForExpectations(timeout: 15)
    }

    // MARK: Where a tap goes

    func testATapMarksTheLineReadAndOpensWhatItIsAbout() throws {
        let app = try launch()
        openInbox(app)
        let line = row(app, "problem:synthetic-signin")
        XCTAssertTrue(line.waitForExistence(timeout: 20))
        line.tap()
        XCTAssertTrue(app.element("today-six-rings").waitForExistence(timeout: 20), "A line that opens Today should close the inbox and show it.")
        openInbox(app)
        XCTAssertNotEqual(row(app, "problem:synthetic-signin").value as? String, "Unread", "The line should stay read.")
    }

    func testTheEffortAndStressLinesOpenTheirScreens() throws {
        let app = try launch()
        openInbox(app)
        let effort = row(app, "health:effort:2030-03-13")
        XCTAssertTrue(effort.waitForExistence(timeout: 20))
        effort.tap()
        XCTAssertTrue(app.element("plan529-landing-effort").waitForExistence(timeout: 20), "The effort line should open the Effort screen.")
        attach(app, "A2 06 effort screen")
        app.element("plan529-landing-done").tap()
        openInbox(app)
        let stress = row(app, "health:stress:2030-03-13")
        XCTAssertTrue(stress.waitForExistence(timeout: 20))
        stress.tap()
        XCTAssertTrue(app.element("plan529-landing-stress").waitForExistence(timeout: 20), "The stress line should open the Stress screen.")
    }

    func testAWeekLineOpensThePlanTab() throws {
        let app = try launch()
        openInbox(app)
        let line = row(app, "report:week:2030-W10")
        XCTAssertTrue(line.waitForExistence(timeout: 20))
        line.tap()
        XCTAssertTrue(app.element("calendar-host").waitForExistence(timeout: 30), "A week line should land on the Plan tab.")
        XCTAssertTrue(app.element("plan529-verdict").waitForExistence(timeout: 30), "A finished week's line should land on that week's report.")
        XCTAssertEqual(app.element("plan529-week-label").label, "Week 46 \u{00B7} 9\u{2013}15 Nov", "It should be the week the line names.")
    }

    /// A notification tap lands from Today: the daily line's report is a sheet over the Plan tab, with the day's verdict.
    func testADailyLineOpensItsReportAsASheetOverThePlanTab() throws {
        let app = try launch()
        openInbox(app)
        let line = row(app, "today:2030-03-13")
        XCTAssertTrue(line.waitForExistence(timeout: 20))
        line.tap()
        XCTAssertTrue(app.element("plan529-daily-report").waitForExistence(timeout: 30), "A daily line should open the daily report over the Plan tab.")
        XCTAssertTrue(app.staticTexts["Rest today."].waitForExistence(timeout: 20), "The report should show the day's verdict.")
        XCTAssertTrue(app.element("calendar-host").exists, "The Plan tab should be under the sheet.")
        attach(app, "A2 09 daily line opens its report sheet")
    }

    func testAChangesLineLandsOnTheWeekPageWithTheChangesCard() throws {
        let app = try launch()
        openInbox(app)
        let line = row(app, "plan:changes:2030-W11")
        XCTAssertTrue(line.waitForExistence(timeout: 20))
        line.tap()
        XCTAssertTrue(app.element("plan529-changes").waitForExistence(timeout: 30), "A changes line should land on the Week page with the changes card.")
        XCTAssertEqual(app.element("plan529-week-label").label, "Week 47 \u{00B7} 16\u{2013}22 Nov", "It should be the week the line names.")
    }

    // MARK: What you are told about

    func testEveryKindHasASwitchThatKeepsItsSetting() throws {
        let app = try launch()
        openInbox(app)
        app.element("plan529-inbox-settings").tap()
        XCTAssertTrue(app.element("plan529-inbox-settings-screen").waitForExistence(timeout: 20), "The way in should open the switches.")
        for kind in ["today", "workout", "health", "coach", "report", "plan", "problem"] {
            XCTAssertTrue(app.element("plan529-inbox-switch-\(kind)").exists, "There should be a switch for \(kind).")
        }
        let plan = app.switches["plan529-inbox-switch-plan"]
        for kind in ["today", "workout", "health", "coach", "report", "plan", "problem"] {
            XCTAssertEqual(app.switches["plan529-inbox-switch-\(kind)"].value as? String, "1", "Every kind starts on: \(kind).")
        }
        attach(app, "A2 07 what you are told about")
        flip(plan)
        XCTAssertEqual(plan.value as? String, "0", "A tap should switch the kind off.")
        XCTAssertTrue(app.element("plan529-inbox-last-check").exists, "The last check should be shown.")
        XCTAssertTrue(app.element("plan529-inbox-last-delay").exists, "The delay of the last new item should be shown.")
        flip(plan)
    }

    /// The row is the switch's element, so its centre is the label: the control itself sits at the right end.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    // MARK: States

    func testWhenTheServerCannotBeReachedTheInboxSaysSo() throws {
        let app = try launch(extra: ["-PaceForgeFetchFails"])
        openInbox(app)
        XCTAssertTrue(app.element("plan529-inbox-failed").waitForExistence(timeout: 30), "With no copy and no server the inbox should say it could not be reached.")
        attach(app, "A2 08 inbox when the server cannot be reached")
    }
}
