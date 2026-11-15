import XCTest

/// Build 529, Plan > Week: the coming week written out (W1), the session sheet (W2), a change opened (W3), Change today (W4), Change
/// workout (W5) and a finished week as its report (R1). Fixture-backed (`Fixtures529/week.json` over the contract examples): the weeks are
/// 2026-W46 (finished, the report), 2026-W47 (coming, three changes) and 2026-W48 (coming). `-Plan529Open` opens a week or a sheet.
final class Plan529WeekUITests: XCTestCase {
    private func launch(open target: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture", "-Plan529Open", target])
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        app.launch()
        dumpHierarchyOnFailure(app)
        return app
    }

    /// The Week chip on a given week.
    private func launchWeek(_ week: String) throws -> XCUIApplication {
        let app = try launch(open: "week:\(week)")
        app.openTab("Plan")
        XCTAssertTrue(app.element("plan529-week-label").waitForExistence(timeout: 30), "The Week page should show its week.")
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Scrolls until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 24) -> Bool {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) { app.swipeUp() }
        return element.exists && element.isHittable
    }

    private func text(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    // MARK: W1

    func testComingWeekShowsTheSeasonPlaceTheWhyTheStripAndTheHours() throws {
        let app = try launchWeek("2026-W47")
        XCTAssertEqual(app.element("plan529-week-label").label, "Week 47 \u{00B7} 16\u{2013}22 Nov")
        XCTAssertTrue(app.element("plan529-why").exists, "The week should say why.")
        XCTAssertTrue(app.element("plan529-strip-day-2026-11-17").exists, "The seven days should show at once.")
        XCTAssertTrue(reveal(app.element("plan529-hours-title"), in: app), "The hours should show as one bar.")
        attach(app, "W1 week coming")
    }

    func testEveryWorkoutIsWrittenOutWithItsWhyHowHardDoAndBadMorningLine() throws {
        let app = try launchWeek("2026-W47")
        let card = app.element("pf-workout-448dbb84")
        XCTAssertTrue(reveal(card, in: app), "The Wednesday class should have a card.")
        for label in ["Why", "How hard", "Do", "If you wake up red"] {
            XCTAssertTrue(text(app, label).exists, "The card should carry the \(label) line without a tap.")
        }
        attach(app, "W1 week coming workout cards")
    }

    func testRestDayCardOffersToAddAWorkout() throws {
        let app = try launchWeek("2026-W47")
        let add = app.element("plan529-add-2026-11-16")
        XCTAssertTrue(reveal(add, in: app), "The rest-day card should offer to add a workout.")
        add.tap()
        XCTAssertTrue(app.element("plan529-swap-ask").waitForExistence(timeout: 15), "It should open the picker.")
        XCTAssertTrue(app.navigationBars["Add a workout"].exists, "On a rest day the picker adds instead of replacing.")
    }

    func testChangesWaitingCanBeAcceptedAllAtOnce() throws {
        let app = try launchWeek("2026-W47")
        let all = app.element("plan529-accept-all")
        XCTAssertTrue(reveal(all, in: app), "Three changes should offer Accept all 3.")
        XCTAssertEqual(all.label, "Accept all 3")
        all.tap()
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        XCTAssertFalse(app.element("plan529-changes-failed").waitForExistence(timeout: 3), "The server took the answers.")
    }

    func testTellTheCoachRunsTheChangeMyPlanJob() throws {
        let app = try launchWeek("2026-W47")
        let input = app.element("plan529-tell-input")
        XCTAssertTrue(reveal(input, in: app), "The Tell the coach field should be under the week.")
        input.tap()
        input.typeText("Move Thursday to Friday")
        app.element("plan529-tell-send").tap()
        XCTAssertTrue(app.element("plan529-tell-reply").waitForExistence(timeout: 20), "The coach's answer should show.")
    }

    // MARK: Arrows and R1

    func testArrowsMoveToTheFinishedWeekAndItsReport() throws {
        let app = try launchWeek("2026-W47")
        app.element("plan529-week-prev").tap()
        XCTAssertTrue(app.element("plan529-verdict").waitForExistence(timeout: 20), "A finished week should be its report.")
        XCTAssertEqual(app.element("plan529-week-label").label, "Week 46 \u{00B7} 9\u{2013}15 Nov")
        XCTAssertTrue(app.element("plan529-verdict").label.hasPrefix("Two races in four days"), "The verdict leads with the races.")
        attach(app, "R1 week report")
    }

    func testReportListsRacesAndOpensTheResultsSheet() throws {
        let app = try launchWeek("2026-W46")
        let race = app.element("plan529-race-9100000001")
        XCTAssertTrue(reveal(race, in: app), "The report should list the doubles race.")
        race.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 20), "A race should open the results sheet.")
    }

    func testReportShowsEachDevicesNightsInItsOwnChart() throws {
        let app = try launchWeek("2026-W46")
        XCTAssertTrue(reveal(app.element("plan529-nights-title-whoop"), in: app), "WHOOP's nights should have a chart.")
        XCTAssertTrue(reveal(app.element("plan529-nights-title-garmin"), in: app), "Garmin's nights should have their own chart.")
        attach(app, "R1 week report nights")
    }

    func testReportEndsInTheDecisionForNextWeek() throws {
        let app = try launchWeek("2026-W46")
        let look = app.element("plan529-look-next")
        XCTAssertTrue(reveal(look, in: app), "The report should end with the decision for next week.")
        XCTAssertTrue(app.element("plan529-accept-next").exists, "Accept next week should be offered while changes wait.")
        look.tap()
        XCTAssertTrue(app.element("plan529-why").waitForExistence(timeout: 20), "Look at it should open next week.")
        XCTAssertEqual(app.element("plan529-week-label").label, "Week 47 \u{00B7} 16\u{2013}22 Nov")
    }

    func testReportLinksToTheWeeklyReadingScreen() throws {
        let app = try launchWeek("2026-W46")
        let link = app.element("plan529-link-experts")
        XCTAssertTrue(reveal(link, in: app), "The expert reading should be one tap away.")
        link.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15), "The weekly reading screen should open.")
    }

    // MARK: W2, W3, W4

    func testSessionSheetHasTheActionsAtTheTopAndTheShortBlocks() throws {
        let app = try launch(open: "session:2026-W47:448dbb84")
        app.openTab("Plan")
        XCTAssertTrue(app.element("plan529-session-title").waitForExistence(timeout: 30), "The session sheet should load its session.")
        for action in ["easier", "move", "skip", "optional", "change", "ask"] {
            XCTAssertTrue(app.element("plan529-sheet-\(action)").exists, "The sheet should offer \(action) at the top.")
        }
        XCTAssertTrue(text(app, "Why this session").exists, "Why this session should show.")
        XCTAssertTrue(text(app, "How hard").exists, "How hard should show.")
        XCTAssertTrue(text(app, "If you wake up red").exists, "The bad-morning line should show.")
        attach(app, "W2 session sheet")
    }

    func testChangeSheetShowsBeforeAfterAndTheThreeAnswers() throws {
        let app = try launch(open: "change:0dfc53f2")
        app.openTab("Plan")
        XCTAssertTrue(app.element("plan529-change-before").waitForExistence(timeout: 30), "The change should show what is now.")
        XCTAssertTrue(app.element("plan529-change-after").exists, "The change should show what is proposed.")
        XCTAssertTrue(text(app, "What the data says").exists, "The data should show.")
        XCTAssertTrue(text(app, "If you keep it").exists, "What keeping it means should show.")
        XCTAssertTrue(app.element("plan529-change-accept").exists, "Accept should be offered.")
        attach(app, "W3 change sheet")
    }

    func testChangeTodayHoldsAdjustTodayEasyModeNigglesAndSayIt() throws {
        let app = try launch(open: "change-today")
        app.openTab("Plan")
        XCTAssertTrue(app.element("plan529-change-today").waitForExistence(timeout: 30), "Change today should open.")
        XCTAssertTrue(app.element("pf-adjust-tired").exists, "Tired should be there.")
        XCTAssertTrue(app.element("pf-adjust-45").exists, "Short on time should offer 45 minutes.")
        XCTAssertTrue(reveal(app.element("pf-easy-card"), in: app), "The easy mode that is on should show its card.")
        XCTAssertTrue(reveal(app.element("pf-niggle-site-knee"), in: app), "Something hurts should list the areas.")
        XCTAssertTrue(app.element("pf-niggle-resolve-a1b2c3d4").exists, "An open niggle should offer Resolved.")
        XCTAssertTrue(reveal(app.element("plan529-say-input"), in: app), "Or say it should hold the coach field.")
        attach(app, "W4 change today")
    }

    func testTiredAdjustsTodayAndSaysWhatItDid() throws {
        let app = try launch(open: "change-today")
        app.openTab("Plan")
        let tired = app.element("pf-adjust-tired")
        XCTAssertTrue(tired.waitForExistence(timeout: 30))
        tired.tap()
        XCTAssertTrue(app.element("pf-adjust-result").waitForExistence(timeout: 20), "The sheet should say what it did.")
    }

    // MARK: W5

    func testChangeWorkoutBuildsARunAndOpensItAsAChange() throws {
        let app = try launchWeek("2026-W48")
        let change = app.element("plan529-act-448dbb84-change")
        XCTAssertTrue(reveal(change, in: app), "A workout card should offer Change workout.")
        change.tap()
        XCTAssertTrue(app.element("plan529-swap-ask").waitForExistence(timeout: 15), "The picker should open.")
        XCTAssertTrue(app.element("plan529-swap-kind-hyrox").exists, "HYROX conditioning should be a choice.")
        XCTAssertTrue(app.element("plan529-swap-kind-strength").exists, "Strength should be a choice.")
        XCTAssertTrue(app.element("plan529-swap-kind-bike").exists, "Cycling should be a choice.")
        app.element("plan529-swap-kind-run").tap()
        app.element("plan529-swap-len-30").tap()
        attach(app, "W5 change workout")
        app.element("plan529-swap-ask").tap()
        XCTAssertTrue(app.element("plan529-change-built-title").waitForExistence(timeout: 30), "The built workout should show as a change.")
        XCTAssertTrue(app.element("plan529-change-warning").exists, "A rule the swap breaks should be a warning.")
        XCTAssertTrue(app.element("plan529-change-again").exists, "Try another should be offered.")
        attach(app, "W5 change workout result")
        app.element("plan529-change-keep").tap()
        XCTAssertTrue(app.element("plan529-change-keep").waitForNonExistence(timeout: 10), "Keep the original should close the sheet.")
    }

    func testTryAnotherAsksAgainForTheSameWorkout() throws {
        let app = try launchWeek("2026-W48")
        let change = app.element("plan529-act-448dbb84-change")
        XCTAssertTrue(reveal(change, in: app))
        change.tap()
        XCTAssertTrue(app.element("plan529-swap-kind-run").waitForExistence(timeout: 15))
        app.element("plan529-swap-kind-run").tap()
        app.element("plan529-swap-ask").tap()
        let again = app.element("plan529-change-again")
        XCTAssertTrue(again.waitForExistence(timeout: 30))
        again.tap()
        XCTAssertTrue(app.element("plan529-change-built-title").waitForExistence(timeout: 30), "Another variant should come back as a change.")
    }
}
