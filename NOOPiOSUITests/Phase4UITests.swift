import XCTest

/// Simulator checks for the Phase 4 screens: Highlights and the streak chip, Healthspan, Journal impact, the monthly report,
/// the My Plan card on NOOP Today and PaceForge Today, My Dashboard with its editor, the journal flow and the Stress monitor.
/// They run on `--demo-seed` data and the synthetic PaceForgeFixture.json (made-up numbers; its day is 2030-03-13, a Wednesday,
/// ISO week 2030-W11). `-PaceForgePhase4Unavailable` and `-PaceForgePhase4Missing` swap in the unavailable and the not-served
/// documents, `-PaceForgeNoStreak` a highlights file with nothing alive and `-PaceForgeJournalImpactEmpty` a journal impact
/// with no clear effect. Screenshot names start with "Phase4" and a two-digit step, so a run's attachments sort in screen order.
final class Phase4UITests: XCTestCase {
    private func launch(screen: String? = nil, appearance: String = "dark", extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
        app.launchArguments.append(contentsOf: ["-theme.appearance", appearance])
        app.launchArguments.append(contentsOf: extra)
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

    private func element(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

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

    /// Nothing on a screen scrolls sideways: the element sits inside the screen's width.
    private func assertFits(_ element: XCUIElement, in app: XCUIApplication, _ what: String) {
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, -1, "\(what) should not start left of the screen.")
        XCTAssertLessThanOrEqual(frame.maxX, app.frame.width + 1, "\(what) should not run past the right edge.")
    }

    private func openPaceForgeToday(_ app: XCUIApplication) throws {
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        let button = segments.buttons["Today"]
        // A tap that lands while the remembered segment is still being restored is lost; look again before moving on.
        for _ in 0..<3 where !button.isSelected { button.tap(); Thread.sleep(forTimeInterval: 1) }
    }

    // MARK: Highlights

    func testStreakChipOnTheTopBarOpensHighlights() throws {
        let app = try launch()
        let chip = element(app, "look-streak-chip")
        XCTAssertTrue(chip.waitForExistence(timeout: 30), "Today's top bar should carry the streak chip.")
        XCTAssertTrue(chip.label.contains("6 day streak"), "The chip should speak the longest streak alive, six days in the fixture.")
        attach(app, "Phase4 10 Today top bar with the streak chip")
        chip.tap()
        XCTAssertTrue(element(app, "pf-highlights-body").waitForExistence(timeout: 20), "The chip should open Highlights.")
        attach(app, "Phase4 11 Highlights opened from the chip")
    }

    func testNoStreakAliveMeansNoChip() throws {
        let app = try launch(extra: ["-PaceForgeNoStreak"])
        XCTAssertTrue(app.shellTab("PaceForge").waitForExistence(timeout: 30), "Today should have loaded.")
        XCTAssertFalse(element(app, "look-streak-chip").waitForExistence(timeout: 5), "With no streak alive there is no chip.")
        attach(app, "Phase4 12 Today top bar without a streak chip")
    }

    func testHighlightsDialsStreaksAndNotableStats() throws {
        let app = try launch(screen: "highlights")
        XCTAssertTrue(element(app, "pf-highlights-body").waitForExistence(timeout: 30), "Highlights should load from the fixture.")
        XCTAssertTrue(element(app, "pf-record-rest").exists, "Best Rest should have a dial.")
        XCTAssertTrue(element(app, "pf-record-charge").exists, "Peak Charge should have a dial.")
        XCTAssertTrue(element(app, "pf-record-effort").exists, "Max Effort should have a dial.")
        attach(app, "Phase4 20 Highlights, all time dials")
        app.buttons["pf-highlights-period-1M"].tap()
        attach(app, "Phase4 21 Highlights, 1M with the Garmin side labelled")
        app.buttons["pf-highlights-period-3M"].tap()
        attach(app, "Phase4 22 Highlights, 3M")
        XCTAssertTrue(reveal(element(app, "pf-streaks"), in: app), "The streaks row should show.")
        XCTAssertTrue(element(app, "pf-streak-rest_70").exists, "The Rest streak should have a badge.")
        attach(app, "Phase4 23 Highlights, streaks")
        XCTAssertTrue(element(app, "pf-streak-insight").exists, "The longest streak's own line should be in the insight card.")
        element(app, "pf-streak-charge_green").tap()
        attach(app, "Phase4 24 Highlights, another streak's line")
        XCTAssertTrue(reveal(element(app, "pf-notable-rhr_low"), in: app), "The notable stats should list the lowest resting heart rate.")
        attach(app, "Phase4 25 Highlights, notable stats with dates")
        assertFits(element(app, "pf-highlights-body"), in: app, "Highlights")
    }

    func testHighlightsRespectHideNumbers() throws {
        let app = try launch(screen: "highlights", extra: ["-noop.hide.scores", "YES"])
        XCTAssertTrue(element(app, "pf-highlights-body").waitForExistence(timeout: 30), "Highlights should load.")
        attach(app, "Phase4 26 Highlights with Hide numbers on")
    }

    func testHighlightsUnavailableSaysWhy() throws {
        let app = try launch(screen: "highlights", extra: ["-PaceForgePhase4Unavailable"])
        XCTAssertTrue(element(app, "pf-highlights-unavailable").waitForExistence(timeout: 30), "An unavailable document says so.")
        attach(app, "Phase4 27 Highlights unavailable")
    }

    func testHighlightsNotServed() throws {
        let app = try launch(screen: "highlights", extra: ["-PaceForgePhase4Missing"])
        XCTAssertTrue(element(app, "pf-highlights-empty").waitForExistence(timeout: 30), "A document that was not served says so.")
        attach(app, "Phase4 28 Highlights not served")
    }

    // MARK: Healthspan

    func testHealthspanRangePaceAndDrivers() throws {
        let app = try launch(screen: "healthspan")
        XCTAssertTrue(element(app, "pf-healthspan-hero").waitForExistence(timeout: 30), "Healthspan should draw the hero.")
        XCTAssertEqual(element(app, "pf-body-age-range").label, "35\u{2013}38", "The body age must be a range, never one number.")
        XCTAssertTrue(element(app, "pf-body-age-verdict").label.contains("years younger"), "It should say how many years younger.")
        XCTAssertEqual(element(app, "pf-healthspan-next-update").label, "NEXT UPDATE IN 5 DAYS", "Wednesday is five days from Monday.")
        attach(app, "Phase4 30 Healthspan hero with the body age range")
        XCTAssertTrue(reveal(element(app, "pf-pace-ruler"), in: app), "The pace of aging ruler should show.")
        attach(app, "Phase4 31 Healthspan pace of aging ruler")
        XCTAssertTrue(reveal(element(app, "pf-healthspan-goto"), in: app), "The GO TO links should show.")
        attach(app, "Phase4 32 Healthspan GO TO links")
        element(app, "pf-goto-sleep").tap()
        let sleepDriver = element(app, "pf-driver-sleep_duration-toggle")
        XCTAssertTrue(sleepDriver.waitForExistence(timeout: 10), "GO TO Sleep should bring the sleep drivers into view.")
        attach(app, "Phase4 33 Healthspan sleep drivers, collapsed")
        sleepDriver.tap()
        XCTAssertTrue(element(app, "pf-driver-sleep_duration-bar").waitForExistence(timeout: 10), "An opened driver shows its 10-segment bar.")
        attach(app, "Phase4 34 Healthspan driver opened with the 6 month and 30 day markers")
        XCTAssertTrue(reveal(element(app, "pf-healthspan-assumptions"), in: app), "The assumptions note should show.")
        let disclaimer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "not WHOOP's number")).firstMatch
        XCTAssertTrue(disclaimer.exists, "It must say it is not WHOOP's number.")
        attach(app, "Phase4 35 Healthspan assumptions")
        assertFits(element(app, "pf-healthspan-body"), in: app, "Healthspan")
    }

    func testHealthspanWeekStepperAndTrend() throws {
        let app = try launch(screen: "healthspan")
        XCTAssertTrue(element(app, "pf-healthspan-week").waitForExistence(timeout: 30), "The week stepper should show.")
        XCTAssertEqual(element(app, "pf-healthspan-week").label, "MAR 11 - MAR 17", "The current ISO week runs Monday to Sunday.")
        element(app, "pf-healthspan-prev-week").tap()
        XCTAssertTrue(element(app, "pf-healthspan-earlier").waitForExistence(timeout: 10), "An earlier week shows its range and a note about the drivers.")
        attach(app, "Phase4 36 Healthspan, an earlier week")
        element(app, "pf-healthspan-next-week").tap()
        XCTAssertTrue(reveal(element(app, "pf-healthspan-trend"), in: app), "With five weeks seeded the trend card should draw.")
        attach(app, "Phase4 37 Healthspan trend")
    }

    func testHealthspanUnavailableSaysWhy() throws {
        let app = try launch(screen: "healthspan", extra: ["-PaceForgePhase4Unavailable"])
        XCTAssertTrue(element(app, "pf-healthspan-unavailable").waitForExistence(timeout: 30), "An unavailable body age says why.")
        attach(app, "Phase4 38 Healthspan unavailable")
    }

    // MARK: Journal impact

    func testJournalImpactHurtsHelpsAndWhatIsMissing() throws {
        let app = try launch(screen: "journalimpact")
        XCTAssertTrue(element(app, "pf-impact-body").waitForExistence(timeout: 30), "Journal impact should load from the fixture.")
        XCTAssertTrue(element(app, "pf-impact-late_meal").exists, "A behaviour that hurts should have its card.")
        XCTAssertTrue(element(app, "pf-impact-easy_day").exists, "A behaviour that helps should have its card.")
        attach(app, "Phase4 40 Journal impact, hurts and helps")
        XCTAssertTrue(reveal(element(app, "pf-impact-not-enough"), in: app), "The behaviours with too few days should be listed.")
        XCTAssertTrue(element(app, "pf-impact-need-late_session").label.contains("Needs"), "Each should say what it still needs.")
        attach(app, "Phase4 41 Journal impact, not enough data")
        assertFits(element(app, "pf-impact-body"), in: app, "Journal impact")
    }

    func testJournalImpactDetail() throws {
        let app = try launch(screen: "journalimpact")
        let card = element(app, "pf-impact-late_meal")
        XCTAssertTrue(card.waitForExistence(timeout: 30), "The hurting behaviour should show.")
        card.tap()
        XCTAssertTrue(element(app, "pf-impact-detail").waitForExistence(timeout: 10), "A tap should open the days behind it.")
        attach(app, "Phase4 42 Journal impact detail")
        XCTAssertTrue(element(app, "pf-impact-detail-action").exists, "A strong effect carries what to do.")
    }

    func testJournalImpactWithNoClearEffect() throws {
        let app = try launch(screen: "journalimpact", extra: ["-PaceForgeJournalImpactEmpty"])
        XCTAssertTrue(element(app, "pf-impact-none").waitForExistence(timeout: 30), "With nothing clear the screen says so.")
        attach(app, "Phase4 43 Journal impact, nothing clear yet")
    }

    // MARK: Monthly report

    func testMonthlyReportPeriodsRowsMoversAndFocus() throws {
        let app = try launch(screen: "monthlyreport")
        XCTAssertTrue(element(app, "pf-monthly-rows").waitForExistence(timeout: 30), "The monthly report should load from the fixture.")
        XCTAssertTrue(element(app, "pf-month-row-charge").exists, "Charge should have a row.")
        attach(app, "Phase4 50 Monthly report, last full month")
        XCTAssertTrue(reveal(element(app, "pf-mover-charge"), in: app), "Charge moved, so it should be listed with what moved it.")
        attach(app, "Phase4 51 Monthly report, movers")
        XCTAssertTrue(reveal(element(app, "pf-goal-weight"), in: app), "The weight goal should show.")
        attach(app, "Phase4 52 Monthly report, goals")
        XCTAssertTrue(reveal(element(app, "pf-focus-0"), in: app), "Next month's focus should list.")
        attach(app, "Phase4 53 Monthly report, focus")
        assertFits(element(app, "pf-monthly-body"), in: app, "Monthly report")
    }

    func testMonthlyReportSwitchesToMonthToDate() throws {
        let app = try launch(screen: "monthlyreport")
        XCTAssertTrue(element(app, "pf-monthly-rows").waitForExistence(timeout: 30), "The monthly report should load.")
        app.buttons["pf-monthly-period-MONTH TO DATE"].tap()
        XCTAssertTrue(element(app, "pf-monthly-no-movers").waitForExistence(timeout: 10), "The month so far has no movers in the fixture.")
        attach(app, "Phase4 54 Monthly report, month to date")
    }

    // MARK: My Plan

    func testMyPlanCardOnNoopToday() throws {
        let app = try launch()
        let card = element(app, "pf-my-plan")
        XCTAssertTrue(reveal(card, in: app), "NOOP Today should carry the My Plan card.")
        XCTAssertEqual(element(app, "pf-plan-header").label, "5 DAYS LEFT \u{00B7} 62 % ACCOMPLISHED", "The header states days left and percent.")
        XCTAssertTrue(element(app, "pf-plan-next").exists, "The next session should be named.")
        attach(app, "Phase4 60 NOOP Today, My Plan")
        assertFits(card, in: app, "My Plan")
    }

    func testViewMyPlanOpensThisWeek() throws {
        let app = try launch()
        let button = element(app, "pf-plan-view")
        XCTAssertTrue(reveal(button, in: app), "The card should have VIEW MY PLAN.")
        button.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 20), "VIEW MY PLAN should open the PaceForge tab.")
        XCTAssertTrue(segments.buttons["This week"].isSelected, "It should land on This week.")
        attach(app, "Phase4 61 This week, opened from My Plan")
    }

    func testMyPlanCardOnPaceForgeToday() throws {
        let app = try launch()
        try openPaceForgeToday(app)
        XCTAssertTrue(reveal(element(app, "pf-my-plan"), in: app), "PaceForge Today should carry My Plan too.")
        attach(app, "Phase4 62 PaceForge Today, My Plan")
    }

    func testNoPlanMeansNoCard() throws {
        let app = try launch(extra: ["-PaceForgePhase4Unavailable"])
        XCTAssertTrue(app.shellTab("PaceForge").waitForExistence(timeout: 30), "Today should have loaded.")
        XCTAssertFalse(element(app, "pf-my-plan").waitForExistence(timeout: 5), "With no plan published there is no card.")
        attach(app, "Phase4 63 NOOP Today without a plan")
    }

    // MARK: My Dashboard

    func testMyDashboardRowsOnToday() throws {
        let app = try launch()
        let section = element(app, "look-my-dashboard")
        XCTAssertTrue(reveal(section, in: app), "Today should carry My Dashboard.")
        attach(app, "Phase4 70 NOOP Today, My Dashboard")
        assertFits(section, in: app, "My Dashboard")
    }

    func testMyDashboardEditorAddsAMetricAndSaves() throws {
        let app = try launch()
        let customize = element(app, "look-dashboard-customize")
        XCTAssertTrue(reveal(customize, in: app), "My Dashboard should offer CUSTOMIZE.")
        customize.tap()
        XCTAssertTrue(element(app, "look-dashboard-list").waitForExistence(timeout: 10), "The editor should open.")
        attach(app, "Phase4 71 My Dashboard editor, drag handles")
        let add = element(app, "look-dashboard-add-my-whoop:steps")
        XCTAssertTrue(reveal(add, in: app), "Steps should be offered to add.")
        add.tap()
        attach(app, "Phase4 72 My Dashboard editor after adding Steps")
        element(app, "look-dashboard-save").tap()
        XCTAssertTrue(element(app, "look-my-dashboard").waitForExistence(timeout: 10), "SAVE should return to Today.")
        attach(app, "Phase4 73 My Dashboard after saving")
    }

    func testDashboardEditorOnItsOwn() throws {
        let app = try launch(screen: "dashboardeditor")
        XCTAssertTrue(element(app, "look-dashboard-list").waitForExistence(timeout: 20), "The editor should render.")
        attach(app, "Phase4 74 My Dashboard editor")
    }

    // MARK: Journal flow

    func testJournalFlowStagesAnAnswerAndSaves() throws {
        let app = try launch(screen: "insights")
        let flow = element(app, "look-journal-flow")
        XCTAssertTrue(flow.waitForExistence(timeout: 30), "Insights should open on the journal flow.")
        XCTAssertTrue(element(app, "look-journal-strip").exists, "The 7-day strip should show.")
        attach(app, "Phase4 80 Journal flow, week strip and the day's question")
        let yes = element(app, prefix: "look-journal-yes-")
        XCTAssertTrue(reveal(yes, in: app), "A yes / no question should show.")
        attach(app, "Phase4 81 Journal flow, grouped questions")
        yes.tap()
        attach(app, "Phase4 82 Journal flow, an answer staged")
        let save = element(app, "look-journal-save")
        XCTAssertTrue(reveal(save, in: app), "SAVE JOURNAL should show.")
        save.tap()
        XCTAssertTrue(element(app, "look-journal-saved").waitForExistence(timeout: 10), "Saving should show SAVED.")
        attach(app, "Phase4 83 Journal flow, saved")
    }

    func testJournalFlowStepsToYesterday() throws {
        let app = try launch(screen: "insights")
        XCTAssertTrue(element(app, "look-journal-flow").waitForExistence(timeout: 30), "Insights should open on the journal flow.")
        element(app, "look-journal-earlier").tap()
        XCTAssertEqual(element(app, "look-journal-day").label, "YESTERDAY", "The stepper should name the day.")
        attach(app, "Phase4 84 Journal flow, yesterday")
    }

    // MARK: Stress monitor

    func testStressTileOpensTheMonitor() throws {
        let app = try launch()
        let tile = element(app, "look-stress-tile")
        XCTAssertTrue(reveal(tile, in: app), "Today should show the Stress monitor tile.")
        attach(app, "Phase4 90 Today, Stress monitor tile")
        tile.tap()
        XCTAssertTrue(element(app, "look-stress-monitor").waitForExistence(timeout: 20), "The tile should open the monitor.")
        let hasReading = element(app, "look-stress-reading").waitForExistence(timeout: 10)
        let hasEmpty = element(app, "look-stress-empty").exists
        XCTAssertTrue(hasReading || hasEmpty, "The monitor shows either a real reading or the honest no-data state, never a made-up one.")
        attach(app, "Phase4 91 Stress monitor")
        XCTAssertTrue(element(app, "look-stress-full").exists, "The full Stress screen stays one tap away.")
    }

    func testStressMonitorOnItsOwn() throws {
        let app = try launch(screen: "stressmonitor")
        XCTAssertTrue(element(app, "look-stress-monitor").waitForExistence(timeout: 30), "The monitor should render.")
        attach(app, "Phase4 92 Stress monitor, own screen")
    }

    // MARK: Light

    func testHighlightsAndHealthspanInLight() throws {
        let app = try launch(screen: "highlights", appearance: "light")
        XCTAssertTrue(element(app, "pf-highlights-body").waitForExistence(timeout: 30), "Highlights should render in light.")
        attach(app, "Phase4 95 Highlights (light)")
    }
}
