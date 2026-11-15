import XCTest

/// Build 529, APP-3: what Today no longer shows twice (D1 to D11), the kept copy of each, the journal's morning question and the
/// proposals row's way to Plan > Week. It runs on `--demo-seed` data and the synthetic PaceForgeFixture.json (its day is 2030-03-13).
/// Today's lower half is lazy, so an element exists only while it is near the screen: the tests scroll in steps and write down what they
/// met. Screenshot names start with "D" and the line they prove.
final class Plan529TodayUITests: XCTestCase {
    private func launch(extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture"])
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

    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && frame.midY > 120 && frame.midY < app.frame.height * 0.85
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 16) -> Bool {
        for _ in 0..<(maxSwipes * 2) {
            if isOnScreen(element, in: app) { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return isOnScreen(element, in: app)
    }

    /// Scrolls Today from the top to the bottom in steps and returns which of `ids` and which of `texts` (static text labels) were on the
    /// screen at any step.
    private func scrollToday(_ app: XCUIApplication, ids: [String], texts: [String] = []) -> (ids: Set<String>, texts: Set<String>) {
        var metIDs: Set<String> = []
        var metTexts: Set<String> = []
        func record() {
            for id in ids where app.element(id).exists { metIDs.insert(id) }
            for text in texts where app.staticTexts[text].exists { metTexts.insert(text) }
        }
        XCTAssertTrue(app.element("today-six-rings").waitForExistence(timeout: 30), "Today should be up.")
        record()
        for _ in 1...16 {
            app.swipeUp()
            record()
        }
        return (metIDs, metTexts)
    }

    // MARK: The removals

    func testNothingIsShownTwiceAnyMoreAndTheKeptCopiesStay() throws {
        let app = try launch()
        let removedIDs = ["pf-open-myday", "today-daily-report-row", "pf-day-review", "look-stress-tile", "pf-page-note-today", "pf-sofar-activity-9000000003"]
        let removedTexts = ["SYNTHESIS", "RECOVERY VITALS", "LAST WORKOUTS", "DATA SOURCES"]
        let keptIDs = ["today-six-rings", "pf-today-card-how-you-are", "today-bookend", "today-stress-monitor", "today-workouts", "pf-sofar-plan",
                       "effort-target-card", "today-vs30", "look-health-tile", "pf-today-card-the-call"]
        let met = scrollToday(app, ids: removedIDs + keptIDs, texts: removedTexts)
        for id in removedIDs { XCTAssertFalse(met.ids.contains(id), "Today should no longer show \(id).") }
        for text in removedTexts { XCTAssertFalse(met.texts.contains(text), "Today should no longer show \(text).") }
        for id in keptIDs { XCTAssertTrue(met.ids.contains(id), "Today should keep \(id).") }
        attach(app, "D1-D11 Today bottom")
    }

    // MARK: D4 and D8: the call states the call

    func testTheCallBannerCarriesTheCallAndNeitherTheTargetNorTheSession() throws {
        let app = try launch()
        let banner = app.element("pf-today-card-the-call")
        XCTAssertTrue(reveal(banner, in: app), "Today should show the call.")
        XCTAssertTrue(banner.label.contains("Keep the plan"), "The banner should keep the call's chip.")
        XCTAssertFalse(banner.label.contains("Effort target"), "The Effort target is not stated on the call (D8).")
        XCTAssertFalse(banner.label.contains("Planned today"), "Today's session is not stated on the call (D4).")
        attach(app, "D4 D8 the call")
    }

    func testTheEffortTargetCardNamesBothTargets() throws {
        let app = try launch()
        let card = app.element("effort-target-card")
        XCTAssertTrue(reveal(card, in: app), "Today should show the Effort target card.")
        XCTAssertTrue(app.staticTexts["NOOP STRAP"].exists, "The strap's target should be named.")
        XCTAssertTrue(app.element("effort-target-garmin").waitForExistence(timeout: 10), "Garmin's target, from PaceForge, should be on the same card.")
        XCTAssertTrue(app.staticTexts["GARMIN VIA PACEFORGE"].exists, "Garmin's target should be named.")
        attach(app, "D8 effort target, both targets")
    }

    // MARK: D1: the marks

    func testTheVsThirtyDaysCardKeepsItsSleepRowsAndNoLongerListsHrvOrRestingHeartRate() throws {
        let app = try launch()
        let card = app.element("today-vs30")
        XCTAssertTrue(reveal(card, in: app), "Today should show Today vs 30 days.")
        XCTAssertFalse(app.element("look-dashboard-rows").staticTexts["HRV"].exists, "HRV is a Key Metrics tile, not a row of this card.")
        attach(app, "D1 today vs 30 days")
    }

    // MARK: D6: one Day in review

    func testTheEveningDayInReviewIsTheRowInMyDayAndOpensTheCard() throws {
        let app = try launch(extra: ["-PaceForgeEvening"])
        let row = app.element("today-bookend")
        XCTAssertTrue(reveal(row, in: app), "My Day should carry the evening row.")
        XCTAssertTrue(row.label.contains("DAY IN REVIEW"), "In the evening the row is the Day in review.")
        XCTAssertFalse(app.element("pf-day-review").exists, "The card is not drawn a second time lower on Today.")
        row.tap()
        XCTAssertTrue(app.element("pf-day-review").waitForExistence(timeout: 15), "The row should open the Day in review.")
        attach(app, "D6 day in review")
    }

    // MARK: D10: one list of the day's workouts

    func testTodaysWorkoutsIsOneListAndARowOpensTheWorkoutWithTheCoachReview() throws {
        let app = try launch()
        let list = app.element("today-workouts")
        XCTAssertTrue(reveal(list, in: app), "Today should show Today's workouts.")
        let row = app.element("today-workout-row-garmin-9000000003")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The recording of the day should be one row.")
        XCTAssertFalse(app.element("pf-sofar-activity-9000000003").exists, "Today so far no longer lists the recording.")
        attach(app, "D10 today's workouts")
        row.tap()
        XCTAssertTrue(app.element("pf-ask-coach-workout").waitForExistence(timeout: 15), "A row should open the workout with the coach's review.")
        attach(app, "D10 the workout")
    }

    // MARK: D11: Data sources is reachable

    func testDataSourcesOpensFromTheAvatarAndSettings() throws {
        let app = try launch()
        let avatar = app.element("today-settings")
        XCTAssertTrue(avatar.waitForExistence(timeout: 30), "Today should carry the avatar.")
        avatar.tap()
        let data = app.element("settings-tool-data")
        XCTAssertTrue(reveal(data, in: app, maxSwipes: 12), "Settings should offer Data.")
        data.tap()
        XCTAssertTrue(app.element("data-section-sources").waitForExistence(timeout: 20), "Data should open on its Sources chip.")
        attach(app, "D11 data sources from settings")
    }

    // MARK: Deep links to Plan > Week

    func testTheProposalsRowOpensPlanWeek() throws {
        let app = try launch(extra: ["-PaceForgeNeedsYou"])
        XCTAssertTrue(app.element("today-six-rings").waitForExistence(timeout: 30), "Today should be up.")
        let proposals = app.element("pf-proposals-row")
        XCTAssertTrue(proposals.waitForExistence(timeout: 30), "Today should carry the proposals row.")
        proposals.tap()
        XCTAssertTrue(app.element("calendar-chip-content-week").waitForExistence(timeout: 30), "The proposals row should open Plan > Week.")
        attach(app, "Today proposals row to Plan Week")
    }

    func testTheThisWeekStripOpensPlanWeek() throws {
        let app = try launch()
        let strip = app.element("pf-today-card-this-week")
        XCTAssertTrue(reveal(strip, in: app), "Today should show the This week strip.")
        strip.tap()
        XCTAssertTrue(app.element("calendar-chip-content-week").waitForExistence(timeout: 30), "The strip should open Plan > Week.")
    }

    // MARK: The journal's morning question

    /// The demo data logs every day up to yesterday, so without the flag the card is already the folded row.
    func testOnceYesterdayIsLoggedTheJournalCardIsTheFoldedRow() throws {
        let app = try launch()
        XCTAssertTrue(reveal(app.element("today-journal-logged"), in: app), "With yesterday logged the card should fold to one row.")
        XCTAssertFalse(app.element("today-journal").exists, "The prompt should be gone.")
    }

    func testTheJournalCardAsksAboutYesterdayAndOpensTheFlowOnIt() throws {
        let app = try launch(extra: ["-JournalYesterdayUnlogged"])
        let card = app.element("today-journal")
        XCTAssertTrue(reveal(card, in: app), "Until yesterday's journal is logged, Today should show the journal prompt.")
        XCTAssertTrue(app.staticTexts["What happened yesterday?"].exists, "The card should ask what happened yesterday.")
        attach(app, "Journal morning question")
        card.buttons["Journal"].firstMatch.tap()
        let day = app.element("look-journal-day")
        XCTAssertTrue(day.waitForExistence(timeout: 20), "The card should open the journal.")
        XCTAssertEqual(day.label, "YESTERDAY", "The flow should open on yesterday.")
        attach(app, "Journal flow on yesterday")
    }
}
