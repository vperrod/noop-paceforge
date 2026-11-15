import XCTest

/// Build 529, Season, Calendar and the plan settings: the season bar and the race cards (S1), a race page (S2), the calendar with its
/// bars and day panel (C1) and "How your plan is built" (K1). Each test serves the merged synthetic fixture (`Fixtures529/*.json`) and
/// attaches screenshots named with the screen code.
final class Plan529SeasonUITests: XCTestCase {
    /// `today` sets the fixture's day: the Calendar opens on today when the plan covers it, and the plan now covers the big fixture's
    /// 2030 week too, so its tests ask for the Monday of the 2026 current week.
    private func launch(open target: String? = nil, extra: [String] = [], today: String? = nil) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture"])
        app.launchArguments.append(contentsOf: extra)
        if let target { app.launchArguments.append(contentsOf: ["-Plan529Open", target]) }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url), today: today)
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

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: S1 Season

    func testSeasonShowsTheBarTheNextRaceAndTheRacesAfterIt() throws {
        let app = try launch()
        app.openChip("Plan", "season")
        XCTAssertTrue(app.element("season-bar").waitForExistence(timeout: 30), "Season should draw the season bar.")
        XCTAssertTrue(app.element("season-now").exists, "The bar should say where you are in the season.")
        XCTAssertTrue(app.element("season-next-race").exists, "Season should have a card for the next race.")
        XCTAssertTrue(app.element("season-set-priority").exists, "A race with no priority should offer Set priority.")
        attach(app, "S1 season top")
        XCTAssertTrue(reveal(app.element("season-race-2027-02-20"), in: app), "The races after the next one should be listed.")
    }

    func testSeasonShowsTheHoursChartAndTheThreeRows() throws {
        let app = try launch()
        app.openChip("Plan", "season")
        XCTAssertTrue(reveal(app.element("season-hours"), in: app), "Season should draw the hours by week.")
        XCTAssertTrue(reveal(app.element("season-add-race"), in: app), "Season should have an Add a race row.")
        XCTAssertTrue(app.element("season-programmes").exists, "Programmes should stay reachable (it opens the web).")
        XCTAssertTrue(app.element("season-how-built").exists, "Season should link to how the plan is built.")
        attach(app, "S1 season hours and rows")
    }

    func testAddARaceOpensTheEventsSheet() throws {
        let app = try launch()
        app.openChip("Plan", "season")
        let row = app.element("season-add-race")
        XCTAssertTrue(reveal(row, in: app), "Season should have an Add a race row.")
        row.tap()
        XCTAssertTrue(app.element("pf-events-upcoming").waitForExistence(timeout: 20), "Add a race should open the events sheet.")
    }

    func testOpenRaceOpensTheRacePage() throws {
        let app = try launch()
        app.openChip("Plan", "season")
        let open = app.element("season-open-race")
        XCTAssertTrue(open.waitForExistence(timeout: 30), "The next race card should have Open race.")
        open.tap()
        XCTAssertTrue(app.element("plan529-race").waitForExistence(timeout: 20), "Open race should open the race page.")
        XCTAssertTrue(app.element("race-priority-A").exists, "The race page should offer the priority A.")
    }

    func testHowYourPlanIsBuiltOpensTheSettings() throws {
        let app = try launch()
        app.openChip("Plan", "season")
        let row = app.element("season-how-built")
        XCTAssertTrue(reveal(row, in: app), "Season should link to how the plan is built.")
        row.tap()
        XCTAssertTrue(app.element("plan529-plan-settings").waitForExistence(timeout: 20), "The row should open the plan settings.")
    }

    // MARK: S2 Race

    func testRacePageShowsDaysGoalPriorityAndTheTimeline() throws {
        let app = try launch(open: "race:2026-12-16")
        app.openTab("Plan")
        XCTAssertTrue(app.element("plan529-race").waitForExistence(timeout: 30), "The race page should open.")
        XCTAssertTrue(app.element("race-days-goal").exists, "The page should show the days to go and the goal.")
        XCTAssertTrue(app.element("race-priority-B").exists, "The page should offer the priority B.")
        attach(app, "S2 race page top")
        XCTAssertTrue(reveal(app.element("race-timeline"), in: app), "The page should show what happens when.")
        XCTAssertTrue(reveal(app.element("race-edit"), in: app), "The page should offer editing goal, date or partner.")
        XCTAssertTrue(app.element("race-cancel").exists, "The page should offer cancelling the race.")
        XCTAssertTrue(app.element("race-pacing").exists, "A HYROX race should open its pacing.")
        attach(app, "S2 race page bottom")
    }

    func testChoosingAPriorityMarksIt() throws {
        let app = try launch(open: "race:2026-12-16")
        app.openTab("Plan")
        let optionA = app.element("race-priority-A")
        XCTAssertTrue(optionA.waitForExistence(timeout: 30), "The race page should offer the priority A.")
        optionA.tap()
        XCTAssertTrue(waitForValue(optionA, "selected"), "The chosen priority should read as selected.")
        attach(app, "S2 priority chosen")
    }

    func testEditRaceOpensGoalDateAndPartner() throws {
        let app = try launch(open: "race:2026-12-16")
        app.openTab("Plan")
        let edit = app.element("race-edit")
        XCTAssertTrue(app.element("plan529-race").waitForExistence(timeout: 30), "The race page should open.")
        XCTAssertTrue(reveal(edit, in: app), "The page should offer editing.")
        edit.tap()
        XCTAssertTrue(app.element("race-edit-goal").waitForExistence(timeout: 20), "The edit sheet should have the goal time.")
        XCTAssertTrue(app.element("race-edit-partner").exists, "The edit sheet should have the partner.")
        attach(app, "S2 edit race")
    }

    func testCancellingARaceAsksFirst() throws {
        let app = try launch(open: "race:2026-12-16")
        app.openTab("Plan")
        let cancel = app.element("race-cancel")
        XCTAssertTrue(app.element("plan529-race").waitForExistence(timeout: 30), "The race page should open.")
        XCTAssertTrue(reveal(cancel, in: app), "The page should offer cancelling.")
        cancel.tap()
        XCTAssertTrue(app.buttons["Cancel race"].waitForExistence(timeout: 10), "Cancelling should ask for confirmation.")
    }

    func testAPastRaceShowsItsResultAndOpensTheResultsWithWhereTheTimeWent() throws {
        let app = try launch(open: "race:2026-11-14")
        app.openTab("Plan")
        XCTAssertTrue(app.element("race-result").waitForExistence(timeout: 30), "A past race should show its result.")
        attach(app, "S2 past race")
        let results = app.element("race-open-results")
        XCTAssertTrue(reveal(results, in: app), "A past race should open its results.")
        results.tap()
        XCTAssertTrue(app.element("pf-race-result").waitForExistence(timeout: 30), "The results sheet should show the race result.")
        XCTAssertTrue(app.element("pf-race-losses").waitForExistence(timeout: 10), "The results sheet should show where the time went.")
        XCTAssertTrue(app.element("pf-race-next-block").exists, "The results sheet should show what the next block changes.")
        attach(app, "P4 race results with losses")
    }

    // MARK: K1 How your plan is built

    func testPlanSettingsShowWhatYouDecideAndTheRulesTheCoachFollows() throws {
        let app = try launch(open: "settings")
        app.openTab("Plan")
        XCTAssertTrue(app.element("settings-you-decide").waitForExistence(timeout: 30), "The settings should list what you decide.")
        XCTAssertTrue(app.element("settings-row-hours").exists, "Hours a week should be a row.")
        XCTAssertTrue(app.element("settings-row-run_days").exists, "Run days should be a row.")
        attach(app, "K1 plan settings top")
        let all = app.element("settings-see-all-rules")
        XCTAssertTrue(reveal(all, in: app), "The rules should end with See all.")
        all.tap()
        let last = app.staticTexts["For a HYROX goal, HYROX strength replaces generic Push, Pull and Legs"]
        XCTAssertTrue(reveal(last, in: app), "See all should list every rule.")
        attach(app, "K1 plan settings all rules")
    }

    func testHoursRowOpensTheStepper() throws {
        let app = try launch(open: "settings")
        app.openTab("Plan")
        let row = app.element("settings-row-hours")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Hours a week should be a row.")
        row.tap()
        XCTAssertTrue(app.element("hours-stepper").waitForExistence(timeout: 20), "The row should open the hours stepper.")
        attach(app, "K1 hours a week")
    }

    func testRacePrioritiesRowListsTheRaces() throws {
        let app = try launch(open: "settings")
        app.openTab("Plan")
        let row = app.element("settings-row-priorities")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Race priorities should be a row.")
        row.tap()
        XCTAssertTrue(app.element("priorities-race-2026-12-16").waitForExistence(timeout: 20), "The list should hold the races to come.")
    }

    // MARK: C1 Calendar

    func testCalendarShowsTheMonthWithBarsAndTheHoursOfEachWeek() throws {
        let app = try launch(today: "2026-11-16")
        app.openChip("Plan", "calendar")
        let title = app.element("calendar-month-title")
        XCTAssertTrue(title.waitForExistence(timeout: 30), "The calendar should show a month.")
        XCTAssertTrue(title.label.lowercased().contains("november 2026"), "The month should be November 2026.")
        XCTAssertTrue(app.element("calendar-day-2026-11-17").exists, "The grid should hold the days of the month.")
        XCTAssertTrue(app.element("calendar-week-hours-2026-11-16").waitForExistence(timeout: 20), "Each week row should end with its hours.")
        attach(app, "C1 calendar")
    }

    func testCalendarPagesToDecember() throws {
        let app = try launch(today: "2026-11-16")
        app.openChip("Plan", "calendar")
        let next = app.element("calendar-month-next")
        XCTAssertTrue(next.waitForExistence(timeout: 30), "The calendar should page forward.")
        next.tap()
        XCTAssertTrue(app.element("calendar-day-2026-12-16").waitForExistence(timeout: 20), "December should show the race day.")
    }

    func testATappedDayListsItsItemsAndASessionOpensItsSheet() throws {
        let app = try launch(today: "2026-11-16")
        app.openChip("Plan", "calendar")
        let day = app.element("calendar-day-2026-11-18")
        XCTAssertTrue(day.waitForExistence(timeout: 30), "The grid should hold Wednesday 18 November.")
        day.tap()
        let item = app.element("calendar-item-448dbb84")
        XCTAssertTrue(reveal(item, in: app), "The day panel should list the session of the day.")
        attach(app, "C1 calendar day panel")
        item.tap()
        XCTAssertTrue(app.element("plan529-session").waitForExistence(timeout: 20), "A session should open its sheet.")
    }

    func testAddAnActivityOpensTheChangeTodaySheetWhileThereIsNoPhoneJob() throws {
        let app = try launch(today: "2026-11-16")
        app.openChip("Plan", "calendar")
        let add = app.element("calendar-add-activity")
        XCTAssertTrue(reveal(add, in: app), "The day panel should offer + Add an activity.")
        add.tap()
        XCTAssertTrue(app.element("plan529-change-today").waitForExistence(timeout: 20), "The button should open the change-today sheet.")
    }

    func testAddADayOffFromTheDayPanel() throws {
        let app = try launch(today: "2026-11-16")
        app.openChip("Plan", "calendar")
        let add = app.element("calendar-add-day-off")
        XCTAssertTrue(reveal(add, in: app), "The day panel should offer + Day off.")
        add.tap()
        XCTAssertTrue(app.element("day-off-sheet").waitForExistence(timeout: 20), "The button should open the form.")
        app.element("day-off-save").tap()
        XCTAssertTrue(app.element("day-off-sheet").waitForNonExistence(timeout: 20), "A saved day off should close the form.")
    }
}
