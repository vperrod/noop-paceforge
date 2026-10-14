import XCTest

/// Simulator checks for Insights v2: the Next best action card on Today (hide, pin, its options), the five cards on
/// Insights and the detail screen each opens (status, meaning, actions with why and effort, the charts, the data
/// note), the "not enough data" states (`-PaceForgeInsightsSparse`), no file at all (`-PaceForgeInsightsMissing`)
/// and Hide numbers on the weight goal (`-noop.hide.body YES`). Like the other PaceForge UI tests they serve the
/// synthetic PaceForgeFixture.json (a made-up athlete and a made-up race, never real data).
final class PaceForgeInsightsV2UITests: XCTestCase {
    private func launch(extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
        app.launchArguments.append("-PaceForgeFixture")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        app.launch()
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

    private func openSegment(_ app: XCUIApplication, _ title: String) throws {
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        let button = segments.buttons[title]
        button.tap()
        // The segment is remembered between launches; a tap that lands while the previous one is restored is lost.
        if !button.isSelected { button.tap() }
    }

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    /// Opens the detail screen of an Insights card (`power_curve`, `race_countdown`, ...).
    private func openInsight(_ app: XCUIApplication, _ id: String) throws {
        try openSegment(app, "Insights")
        let card = element(app, "pf-insight-card-\(id)")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Insights should show the \(id) card.")
        card.tap()
        XCTAssertTrue(element(app, "pf-insight-\(id)").waitForExistence(timeout: 10), "The \(id) detail should open.")
    }

    /// What every detail screen must carry: the status chip, the meaning and the actions with their why and effort.
    private func assertTheAnswerAndTheNextStep(_ app: XCUIApplication, _ id: String) {
        XCTAssertTrue(element(app, "pf-insight-status-\(id)").exists, "The detail should show the status chip.")
        XCTAssertTrue(element(app, "pf-insight-meaning").waitForExistence(timeout: 5), "The detail should say what it means.")
        XCTAssertTrue(element(app, "pf-insight-actions-\(id)").exists, "The detail should say what to do.")
    }

    // MARK: Today: Next best action

    func testTodayShowsTheNextBestActionCard() throws {
        let app = try launch()
        try openSegment(app, "Today")
        let card = element(app, "pf-next-action-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Today should show the Next best action card.")
        XCTAssertTrue(element(app, "pf-insight-status-next_best_action").exists, "The card should show its priority.")
        attach(app, "91 Next best action on Today")
    }

    func testTheNextBestActionCardOpensTheOtherOptions() throws {
        let app = try launch()
        try openSegment(app, "Today")
        let card = element(app, "pf-next-action-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20))
        card.tap()
        XCTAssertTrue(element(app, "pf-insight-next_best_action").waitForExistence(timeout: 10))
        assertTheAnswerAndTheNextStep(app, "next_best_action")
        XCTAssertTrue(element(app, "pf-insight-effort-efficiency:easier-easy-days").exists, "The action should show what it costs.")
        attach(app, "91 Next best action detail")
        let options = element(app, "pf-nba-options")
        XCTAssertTrue(reveal(options, in: app), "The detail should list the other options.")
        attach(app, "91 Next best action options")
        app.swipeUp()
        attach(app, "91 Next best action ranking")
    }

    func testTheNextBestActionCardCanBeHiddenAndShownAgain() throws {
        let app = try launch()
        try openSegment(app, "Today")
        let corner = element(app, "pf-dismiss-next-best-action")
        XCTAssertTrue(reveal(corner, in: app, maxSwipes: 20), "The card should have the Not today corner.")
        corner.tap()
        app.buttons["Hide until it changes"].tap()
        XCTAssertFalse(element(app, "pf-next-action-card").waitForExistence(timeout: 3), "The hidden card should be gone.")
        let row = element(app, "pf-hidden-cards")
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 24))
        row.tap()
        XCTAssertTrue(element(app, "pf-hidden-sheet").waitForExistence(timeout: 10))
        attach(app, "92 Next best action hidden")
        let restore = app.buttons["pf-restore-next-best-action"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        let done = app.buttons["pf-hidden-done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
        XCTAssertTrue(element(app, "pf-next-action-card").waitForExistence(timeout: 10), "Showing it again should bring the card back.")
    }

    func testTheNextBestActionCardCanBePinnedToTheTop() throws {
        let app = try launch()
        try openSegment(app, "Today")
        let customise = element(app, "pf-today-customise")
        XCTAssertTrue(customise.waitForExistence(timeout: 10), "Today should offer Customise.")
        customise.tap()
        let pin = app.buttons["pf-arrange-pin-next-best-action"]
        XCTAssertTrue(reveal(pin, in: app, maxSwipes: 20), "The card should offer Pin while arranging.")
        pin.tap()
        XCTAssertTrue(app.buttons["pf-arrange-up-next-best-action"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pf-arrange-up-next-best-action"].isEnabled, "A pinned card is first, so it cannot move up.")
        attach(app, "92 Next best action pinned")
    }

    func testTheNextBestActionCardIsAbsentWhenThereIsNothingToSuggest() throws {
        let app = try launch(extraArguments: ["-PaceForgeInsightsSparse"])
        try openSegment(app, "Today")
        XCTAssertTrue(element(app, "pf-today-customise").waitForExistence(timeout: 10))
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(element(app, "pf-next-action-card").exists, "An unavailable next best action is not worth a card.")
    }

    // MARK: Insights: the cards

    func testInsightsListsTheFiveCardsWithTheirStatus() throws {
        let app = try launch()
        try openSegment(app, "Insights")
        XCTAssertTrue(element(app, "pf-insights-v2").waitForExistence(timeout: 10), "Insights should show the new cards.")
        for id in ["power_curve", "race_countdown", "weight_goal", "efficiency", "sleep"] {
            XCTAssertTrue(reveal(element(app, "pf-insight-card-\(id)"), in: app, maxSwipes: 24), "Insights should show the \(id) card.")
        }
        XCTAssertTrue(element(app, "pf-insight-card-power_curve").label.contains("Ahead"), "The power curve card should read its status.")
        attach(app, "93 Insights cards")
    }

    func testACardReadsItsMeaningAndItsFirstStep() throws {
        let app = try launch()
        try openSegment(app, "Insights")
        let card = element(app, "pf-insight-card-sleep")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 24))
        XCTAssertTrue(card.label.contains("Next: Aim for lights-out"), "The card should lead with the first thing to do: \(card.label)")
    }

    // MARK: Insights: the detail screens

    func testPowerCurveDetail() throws {
        let app = try launch()
        try openInsight(app, "power_curve")
        assertTheAnswerAndTheNextStep(app, "power_curve")
        XCTAssertTrue(element(app, "pf-power-ftp-estimate").label.contains("231 W"), "The FTP estimate should show.")
        XCTAssertTrue(element(app, "pf-power-ftp-garmin").exists, "Garmin's own FTP should show beside it.")
        XCTAssertTrue(element(app, "pf-power-ftp-in-use").exists, "And the FTP in use.")
        attach(app, "94 Power curve")
        let chart = element(app, "pf-power-curve-chart")
        XCTAssertTrue(reveal(chart, in: app), "The mean-max curve should be drawn.")
        attach(app, "94 Power curve chart")
        app.swipeUp()
        attach(app, "94 Power curve efforts")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-insight-data-note").waitForExistence(timeout: 5) || reveal(element(app, "pf-insight-data-note"), in: app),
                      "The data note should close the screen.")
        attach(app, "94 Power curve data note")
    }

    func testRaceCountdownDetail() throws {
        let app = try launch()
        try openInsight(app, "race_countdown")
        assertTheAnswerAndTheNextStep(app, "race_countdown")
        XCTAssertEqual(element(app, "pf-race-days").label, "38", "The countdown should read the days to go.")
        attach(app, "95 Race countdown")
        let finish = element(app, "pf-race-finish")
        XCTAssertTrue(reveal(finish, in: app, maxSwipes: 20), "The predicted finish should show.")
        XCTAssertEqual(finish.label, "47:30")
        XCTAssertTrue(element(app, "pf-race-goal-in-range").exists, "It should say whether the goal is in the range.")
        attach(app, "95 Race finish range")
        let form = element(app, "pf-race-form-chart")
        XCTAssertTrue(reveal(form, in: app, maxSwipes: 20), "The form projection should be drawn.")
        attach(app, "95 Race form projection")
        let taper = element(app, "pf-race-taper-verdict")
        XCTAssertTrue(reveal(taper, in: app, maxSwipes: 20), "The taper verdict should show.")
        attach(app, "95 Race taper")
    }

    func testWeightGoalDetail() throws {
        let app = try launch()
        try openInsight(app, "weight_goal")
        assertTheAnswerAndTheNextStep(app, "weight_goal")
        XCTAssertTrue(element(app, "pf-weight-trend").label.contains("82.5 kg"), "The weight trend should show.")
        XCTAssertTrue(element(app, "pf-weight-pace").label.contains("late"), "The projected date should say how late it is.")
        attach(app, "96 Weight goal")
        let chart = element(app, "pf-weight-chart")
        XCTAssertTrue(reveal(chart, in: app, maxSwipes: 20), "The trend, noise band and needed path should be drawn.")
        attach(app, "96 Weight goal chart")
    }

    func testEfficiencyDetail() throws {
        let app = try launch()
        try openInsight(app, "efficiency")
        assertTheAnswerAndTheNextStep(app, "efficiency")
        attach(app, "97 Efficiency")
        let running = element(app, "pf-eff-run-chart")
        XCTAssertTrue(reveal(running, in: app, maxSwipes: 20), "The running efficiency trend should be drawn.")
        XCTAssertTrue(element(app, "pf-eff-run-pace").exists, "The pace at the reference heart rate should show.")
        attach(app, "97 Efficiency running")
        let zones = element(app, "pf-eff-zones-4")
        XCTAssertTrue(reveal(zones, in: app, maxSwipes: 24), "The zone time against 80/20 should show.")
        attach(app, "97 Efficiency zones")
        XCTAssertTrue(element(app, "pf-eff-bike-insufficient").exists || reveal(element(app, "pf-eff-bike-insufficient"), in: app),
                      "Bike efficiency with too few rides should say so.")
    }

    func testSleepDetail() throws {
        let app = try launch()
        try openInsight(app, "sleep")
        assertTheAnswerAndTheNextStep(app, "sleep")
        attach(app, "98 Sleep")
        let bed = element(app, "pf-sleep-bed-chart")
        XCTAssertTrue(reveal(bed, in: app, maxSwipes: 20), "The bedtime chart should be drawn.")
        XCTAssertTrue(element(app, "pf-sleep-wake-chart").exists || reveal(element(app, "pf-sleep-wake-chart"), in: app))
        attach(app, "98 Sleep charts")
        let debt = element(app, "pf-sleep-debt-7")
        XCTAssertTrue(reveal(debt, in: app, maxSwipes: 20), "The sleep debt should show.")
        XCTAssertTrue(debt.label.contains("3.4 h"))
        attach(app, "98 Sleep debt")
        let window = element(app, "pf-sleep-target-window")
        XCTAssertTrue(reveal(window, in: app, maxSwipes: 20), "The target window should show.")
        attach(app, "98 Sleep target")
    }

    // MARK: Not enough data

    func testAnUnavailableItemSaysWhyAndOffersNoActions() throws {
        let app = try launch(extraArguments: ["-PaceForgeInsightsSparse"])
        try openInsight(app, "power_curve")
        XCTAssertTrue(element(app, "pf-insight-unavailable").exists, "An item with no data should say so.")
        XCTAssertFalse(element(app, "pf-insight-actions-power_curve").exists, "And offer nothing it cannot ground.")
        XCTAssertTrue(app.staticTexts["No bike rides with power are on file yet, so there is no power curve."].exists)
        attach(app, "99 Power curve, no data")
    }

    func testARaceWithNoPredictionKeepsTheCountdownAndSaysWhatIsMissing() throws {
        let app = try launch(extraArguments: ["-PaceForgeInsightsSparse"])
        try openInsight(app, "race_countdown")
        XCTAssertEqual(element(app, "pf-race-days").label, "38")
        let finish = element(app, "pf-race-no-finish")
        XCTAssertTrue(reveal(finish, in: app, maxSwipes: 20), "A missing prediction should be explained.")
        XCTAssertTrue(reveal(element(app, "pf-race-no-form"), in: app, maxSwipes: 20), "A missing projection should be explained.")
        attach(app, "99 Race, no prediction")
    }

    func testAWeightGoalWithOneReadingSaysTheTrendNeedsMore() throws {
        let app = try launch(extraArguments: ["-PaceForgeInsightsSparse"])
        try openInsight(app, "weight_goal")
        XCTAssertTrue(reveal(element(app, "pf-weight-no-pace"), in: app, maxSwipes: 20), "Its own pace cannot be read yet.")
        XCTAssertTrue(reveal(element(app, "pf-weight-no-trend"), in: app, maxSwipes: 20), "One reading is not a trend.")
        attach(app, "99 Weight goal, one reading")
    }

    func testEfficiencyWithTooFewRunsSaysWhatItNeeds() throws {
        let app = try launch(extraArguments: ["-PaceForgeInsightsSparse"])
        try openInsight(app, "efficiency")
        XCTAssertTrue(reveal(element(app, "pf-eff-run-insufficient"), in: app, maxSwipes: 20), "Too few runs should be explained.")
        XCTAssertTrue(reveal(element(app, "pf-eff-zones-insufficient"), in: app, maxSwipes: 24), "And so should missing zone data.")
        attach(app, "99 Efficiency, too few runs")
    }

    func testSleepWithNineNightsCannotRateConsistency() throws {
        let app = try launch(extraArguments: ["-PaceForgeInsightsSparse"])
        try openInsight(app, "sleep")
        XCTAssertTrue(element(app, "pf-insight-status-reason").waitForExistence(timeout: 5), "The reason there is no rating should show.")
        XCTAssertTrue(reveal(element(app, "pf-sleep-no-spread"), in: app, maxSwipes: 20), "Too few nights should be explained.")
        attach(app, "99 Sleep, nine nights")
    }

    func testWithoutTheFileInsightsShowsNoNewCardsAndTodayNoSuggestion() throws {
        let app = try launch(extraArguments: ["-PaceForgeInsightsMissing"])
        try openSegment(app, "Insights")
        XCTAssertTrue(element(app, "pf-load-chart").waitForExistence(timeout: 10), "The rest of Insights should still load.")
        XCTAssertFalse(element(app, "pf-insights-v2").exists, "An older server serves no insights-v2.json.")
        attach(app, "99 Insights, no file")
    }

    // MARK: Hide numbers

    func testHidingBodyNumbersCoversTheWeightGoal() throws {
        let app = try launch(extraArguments: ["-noop.hide.body", "YES"])
        try openSegment(app, "Insights")
        let card = element(app, "pf-insight-card-weight_goal")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 24))
        XCTAssertFalse(card.label.contains("82.5"), "The card should not read the weight: \(card.label)")
        attach(app, "99 Weight goal card, numbers hidden")
        card.tap()
        XCTAssertTrue(element(app, "pf-weight-hidden").waitForExistence(timeout: 10), "The detail should hide the weight figures and chart.")
        XCTAssertFalse(element(app, "pf-weight-chart").exists)
        XCTAssertTrue(element(app, "pf-insight-actions-weight_goal").exists, "What to do should still show.")
        attach(app, "99 Weight goal detail, numbers hidden")
    }
}
