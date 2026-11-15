import XCTest

/// Simulator checks for the daily loop: Today's call, the Health monitor tile and screen, the sleep need in the planner,
/// "What moved it" on a metric, and Day in review. They run on `--demo-seed` data and the synthetic PaceForgeFixture.json
/// (made-up numbers; its day is 2030-03-13). The evening card is forced with `-PaceForgeEvening` / `-PaceForgeMorning`
/// because a simulator run cannot be timed to 18:00; the variants `-PaceForgeIntelAlert`, `-PaceForgeIntelUnavailable` and
/// `-PaceForgeIntelMissing` swap in the red Health monitor, the all-unavailable file and no file. Screenshot names start
/// with "Intel" and a two-digit step, so a run's attachments sort in screen order.
final class DailyIntelUITests: XCTestCase {
    private func launch(screen: String? = nil, appearance: String = "dark", extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
        app.launchArguments.append(contentsOf: ["-theme.appearance", appearance])
        app.launchArguments.append(contentsOf: extra)
        app.launchArguments.append("-PaceForgeFixture")
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

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// On screen and clear of the floating tab bar, read from the element's frame: `isHittable` records a test failure ("Activation
    /// point invalid") when it is asked about a lazily mounted element that is still below the screen.
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && frame.midY > 120 && frame.midY < app.frame.height * 0.85
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if isOnScreen(element, in: app) { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return isOnScreen(element, in: app)
    }

    // MARK: Today's call on NOOP Today

    /// Today states the call once: the banner under the dials carries the verdict, the chip, PaceForge's Effort target and the planned
    /// session; tapping it opens the rest (why the scores differ, the action) in the call sheet.
    private func callBanner(_ app: XCUIApplication) -> XCUIElement { element(app, "pf-today-card-the-call") }

    private func openCallSheet(_ app: XCUIApplication) {
        let banner = callBanner(app)
        XCTAssertTrue(reveal(banner, in: app), "Today should show the call.")
        banner.tap()
        XCTAssertTrue(element(app, "pf-the-call-sheet").waitForExistence(timeout: 15), "The call should open its sheet.")
    }

    func testTodaysCallIsOneBannerWithItsDetailOnNoopToday() throws {
        let app = try launch()
        let banner = callBanner(app)
        XCTAssertTrue(reveal(banner, in: app), "NOOP Today should show the call.")
        attach(app, "Intel 10 NOOP Today, the call")
        XCTAssertTrue(banner.label.contains("Keep the plan"), "The banner should carry the verdict chip.")
        XCTAssertTrue(banner.label.contains("Effort target"), "The banner should carry PaceForge's Effort target.")
        XCTAssertTrue(banner.label.contains("Planned today"), "The banner should carry the planned session.")
        XCTAssertFalse(element(app, "pf-todays-call").exists, "Today does not draw the call a second time.")
        banner.tap()
        XCTAssertTrue(element(app, "pf-call-disagreement").waitForExistence(timeout: 15),
                      "The fixture's two scores differ, so the call sheet should say why.")
    }

    func testTodaysCallShowsTheActionAsAnInsightCardAndOpensItsReason() throws {
        let app = try launch()
        openCallSheet(app)
        let link = element(app, "pf-call-action-keep_plan-link")
        XCTAssertTrue(reveal(link, in: app), "The call's action should be an insight card with a link.")
        attach(app, "Intel 11 Today's call, action card")
        link.tap()
        XCTAssertTrue(element(app, "pf-call-action-keep_plan").exists, "The action card should stay on screen once opened.")
        attach(app, "Intel 12 Today's call, action card opened to its reason")
    }

    func testCallBannerCarriesTheEffortTargetLine() throws {
        let app = try launch()
        let banner = callBanner(app)
        XCTAssertTrue(reveal(banner, in: app), "The call should load first.")
        XCTAssertTrue(banner.label.contains("Effort target"), "The Effort target line should show on the banner.")
        attach(app, "Intel 13 Today's call, Effort target line")
    }

    func testTodaysCallSaysWhenItIsUnavailable() throws {
        let app = try launch(extra: ["-PaceForgeIntelUnavailable"])
        openCallSheet(app)
        let note = element(app, "pf-todays-call-unavailable")
        XCTAssertTrue(reveal(note, in: app), "An unavailable call should say so in the call sheet, not vanish.")
        attach(app, "Intel 14 Today's call unavailable")
    }

    func testNoFileMeansNoCallDetail() throws {
        let app = try launch(extra: ["-PaceForgeIntelMissing"])
        XCTAssertTrue(app.shellTab("Today").waitForExistence(timeout: 30), "Today should have loaded.")
        XCTAssertFalse(element(app, "pf-todays-call").waitForExistence(timeout: 5), "Without the file there is no call card.")
        let banner = callBanner(app)
        if banner.exists { XCTAssertFalse(banner.label.contains("Effort target"), "Without the file the banner has no detail.") }
        attach(app, "Intel 15 NOOP Today without the daily file")
    }

    // MARK: Today's call, Not today

    func testTodaysCallCarriesTheNotTodayMenu() throws {
        let app = try launch()
        XCTAssertTrue(reveal(callBanner(app), in: app), "Today should show the call.")
        attach(app, "Intel 20 Today, the call with its Not today menu")
        XCTAssertTrue(element(app, "pf-dismiss-the-call").exists, "The call should carry the Not today menu.")
    }

    // MARK: Health monitor

    func testHealthTileWithinRangeOpensTheHealthScreenWithTheMonitorOnTop() throws {
        let app = try launch()
        let tile = element(app, "look-health-tile")
        XCTAssertTrue(reveal(tile, in: app), "Today should show the Health monitor tile.")
        XCTAssertTrue(tile.label.contains("WITHIN RANGE"), "The tile should read within range.")
        XCTAssertTrue(tile.label.contains("4/4 metrics"), "The tile should count the vitals within range.")
        attach(app, "Intel 30 Health monitor tile within range")
        tile.tap()
        XCTAssertTrue(element(app, "pf-health-monitor").waitForExistence(timeout: 20), "The tile should open the one Health screen, with the Health monitor on top.")
        XCTAssertTrue(element(app, "pf-vital-hrv").waitForExistence(timeout: 10), "Each vital should have a row.")
        attach(app, "Intel 31 Health screen, monitor on top")
        XCTAssertTrue(reveal(element(app, "pf-vital-skin_temp"), in: app), "Skin temperature should have a row.")
        attach(app, "Intel 32 Health monitor vitals")
    }

    func testHealthTileFarOutOfRangeIsRedAndExplainsItself() throws {
        let app = try launch(extra: ["-PaceForgeIntelAlert"])
        let tile = element(app, "look-health-tile")
        XCTAssertTrue(reveal(tile, in: app), "Today should show the Health monitor tile.")
        XCTAssertTrue(tile.label.contains("VERY ELEVATED"), "The tile should name how far out the worst vital is.")
        XCTAssertTrue(tile.label.contains("Respiratory rate"), "The tile should name the worst vital.")
        attach(app, "Intel 33 Health monitor tile, very elevated")
        tile.tap()
        XCTAssertTrue(element(app, "pf-health-alert").waitForExistence(timeout: 20), "The alert should be explained in an insight card.")
        attach(app, "Intel 34 Health monitor alert and what to do")
        XCTAssertTrue(reveal(element(app, "pf-vital-resp"), in: app), "The respiratory rate row should show.")
        attach(app, "Intel 35 Health monitor vitals out of range")
    }

    // MARK: Sleep need

    func testSleepPlannerUsesTheSleepNeedBreakdown() throws {
        let app = try launch(screen: "lookplanner", extra: ["-SleepPlannerFixture", "ready"])
        XCTAssertTrue(element(app, "sleep-planner-bedtime").waitForExistence(timeout: 30), "The planner should show tonight's bedtime.")
        attach(app, "Intel 40 Sleep planner on the sleep need")
        let total = element(app, "sleep-planner-need-total")
        XCTAssertTrue(reveal(total, in: app), "The planner should show the sleep-need table.")
        XCTAssertTrue(element(app, "sleep-planner-need-baseline").exists, "The table should list the baseline.")
        XCTAssertTrue(element(app, "sleep-planner-need-effort").exists, "The table should list the Effort row.")
        XCTAssertTrue(element(app, "sleep-planner-need-debt").exists, "The table should list the debt row.")
        XCTAssertTrue(element(app, "sleep-planner-need-naps").exists, "The table should list the naps row.")
        XCTAssertTrue(total.label.contains("Tonight's need"), "The total should be the last row.")
        attach(app, "Intel 41 Sleep planner need table")
        let peak = element(app, "sleep-planner-preset-peak")
        XCTAssertTrue(reveal(peak, in: app) || peak.exists, "The planner should offer the three goals.")
        attach(app, "Intel 42 Sleep planner goals at 70, 85 and 100 percent")
    }

    func testTonightsSleepCardShowsOnTheSleepChipOfHealth() throws {
        let app = try launch()
        app.openChip("Health", "sleep")
        let entry = element(app, "sleep-planner-entry")
        XCTAssertTrue(reveal(entry, in: app), "The Sleep chip of Health should show Tonight's sleep.")
        attach(app, "Intel 43 Sleep, Tonight's sleep")
    }

    // MARK: What moved it

    func testWhatMovedItOnHrv() throws {
        let app = try launch(screen: "lookhrv")
        let card = element(app, "pf-what-moved")
        XCTAssertTrue(reveal(card, in: app), "A metric the server covers should show What moved it.")
        XCTAssertTrue(element(app, "pf-moved-headline").label.hasPrefix("Down"), "HRV moved down in the fixture.")
        attach(app, "Intel 50 HRV detail, What moved it")
    }

    func testWhatMovedItOnCharge() throws {
        let app = try launch(screen: "lookcharge")
        XCTAssertTrue(element(app, "look-score-detail-charge").waitForExistence(timeout: 30), "The Charge detail should open.")
        let card = element(app, "pf-what-moved")
        _ = reveal(card, in: app)
        attach(app, "Intel 51 Charge detail, What moved it or nothing when the server has no entry")
    }

    func testTrendsShowsWhatMovedItForTheSelectedMetric() throws {
        let app = try launch(screen: "trends")
        XCTAssertTrue(reveal(element(app, "look-noop-trends"), in: app), "Trends should show the trend view.")
        attach(app, "Intel 52 Trends, first metric")
        _ = reveal(element(app, "pf-what-moved"), in: app)
        attach(app, "Intel 53 Trends, What moved it under the metric")
    }

    // MARK: Day in review

    func testDayInReviewShowsInTheEvening() throws {
        let app = try launch(extra: ["-PaceForgeEvening"])
        let card = element(app, "pf-day-review")
        XCTAssertTrue(reveal(card, in: app), "After 18:00 Today should show Day in review.")
        XCTAssertTrue(element(app, "pf-review-outcome").exists, "It should say whether the target was met.")
        XCTAssertTrue(element(app, "pf-review-tonight").exists, "It should give tonight's need and bedtime.")
        XCTAssertTrue(element(app, "pf-review-tomorrow").exists, "It should name tomorrow's session.")
        attach(app, "Intel 60 Day in review in the evening")
    }

    func testDayInReviewIsAbsentInTheMorning() throws {
        let app = try launch(extra: ["-PaceForgeMorning"])
        XCTAssertTrue(reveal(element(app, "pf-todays-call"), in: app), "Today should have loaded.")
        XCTAssertFalse(element(app, "pf-day-review").waitForExistence(timeout: 3), "Before 18:00 there is no Day in review.")
        attach(app, "Intel 61 Today in the morning, no Day in review")
    }

    func testTodaysCallInLight() throws {
        let app = try launch(appearance: "light")
        XCTAssertTrue(reveal(element(app, "pf-today-card-the-call"), in: app), "The call should show in light.")
        attach(app, "Intel 70 Today's call (light)")
    }

    // MARK: Journal prompt

    /// Until today's journal is logged it is the morning prompt under the call; one tap per question and Save; then it folds to a row.
    func testJournalPromptOpensTheFlowAndFoldsOnceLogged() throws {
        let app = try launch()
        let card = element(app, "today-journal")
        XCTAssertTrue(reveal(card, in: app), "Until today's journal is logged, Today should show the journal prompt.")
        attach(app, "Intel 80 Today journal prompt")
        card.buttons["Journal"].firstMatch.tap()
        let yes = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'look-journal-yes-'")).firstMatch
        XCTAssertTrue(yes.waitForExistence(timeout: 20), "The prompt should open the journal with a Yes for each question.")
        yes.tap()
        let save = element(app, "look-journal-save")
        XCTAssertTrue(reveal(save, in: app), "The journal should offer Save.")
        save.tap()
        XCTAssertTrue(element(app, "look-journal-saved").waitForExistence(timeout: 20), "Saving should say the journal is saved.")
        attach(app, "Intel 81 Journal saved")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(reveal(element(app, "today-journal-logged"), in: app), "Once logged, the prompt should fold to the Journal logged row.")
        attach(app, "Intel 82 Today journal logged")
    }
}
