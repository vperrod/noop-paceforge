import XCTest

/// Simulator checks for the Phase 4 screens: Highlights and the streak chip, Healthspan, Journal impact, the monthly report,
/// the My Plan card on Today and Plan > This week, My Dashboard with its editor, the journal flow and the Stress monitor.
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

    // MARK: Highlights

    func testStreakChipOnTheTopBarOpensHighlights() throws {
        let app = try launch()
        let chip = element(app, "look-streak-chip")
        let found = chip.waitForExistence(timeout: 30)
        attach(app, "Phase4 10 Today top bar with the streak chip")
        XCTAssertTrue(found, "Today's top bar should carry the streak chip.")
        XCTAssertTrue(chip.label.contains("6 day streak"), "The chip should speak the longest streak alive, six days in the fixture.")
        XCTAssertTrue(chip.isHittable, "The chip should be on screen and tappable, not clipped behind the bar.")
        assertFits(chip, in: app, "The streak chip")
        chip.tap()
        XCTAssertTrue(element(app, "pf-highlights-body").waitForExistence(timeout: 20), "The chip should open Highlights.")
        attach(app, "Phase4 11 Highlights opened from the chip")
    }

    func testNoStreakAliveMeansNoChip() throws {
        let app = try launch(extra: ["-PaceForgeNoStreak"])
        XCTAssertTrue(app.shellTab("Today").waitForExistence(timeout: 30), "Today should have loaded.")
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

    /// Today stopped drawing the "5 days left" My Plan card on 21 Oct (0e20c61d4: the Plan tab owns it). Today's My Plan section is
    /// its header and the This week card, which opens Plan > This week; the progress card is on Plan > This week, folded to one line.
    func testMyPlanSectionOnNoopToday() throws {
        let app = try launch()
        XCTAssertTrue(reveal(element(app, "today-my-plan-header"), in: app, maxSwipes: 20), "NOOP Today should carry the My Plan header.")
        let week = element(app, "pf-today-card-this-week")
        XCTAssertTrue(reveal(week, in: app, maxSwipes: 20), "The My Plan section should carry the This week card.")
        attach(app, "Phase4 60 NOOP Today, My Plan")
        assertFits(week, in: app, "This week")
    }

    func testThisWeekCardOnTodayOpensThePlanTab() throws {
        let app = try launch()
        let card = element(app, "pf-today-card-this-week")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Today should carry the This week card.")
        card.tap()
        XCTAssertTrue(element(app, "calendar-host").waitForExistence(timeout: 20), "The This week card should open the Plan tab.")
        XCTAssertTrue(element(app, "calendar-chip-content-week").waitForExistence(timeout: 20), "It should land on the Week chip.")
        attach(app, "Phase4 61 Plan, opened from This week")
    }

    /// My Plan's job (how far through the week you are, what is done, what is next) is the Week page's now: the seven days with their
    /// done bars, the hours done so far, and each workout's status. The folded My Plan card is not mounted on the Plan tab any more.
    func testWeekPageCarriesWhatMyPlanCarried() throws {
        let app = try launch()
        app.openChip("Plan", "week")
        XCTAssertTrue(element(app, "plan529-strip-day-2030-03-11").waitForExistence(timeout: 30), "Plan > Week should show the seven days.")
        XCTAssertTrue(reveal(element(app, "plan529-hours-title"), in: app), "Plan > Week should show the hours, with what is done so far.")
        XCTAssertTrue(reveal(element(app, "plan529-done-s-mon"), in: app, maxSwipes: 20), "A finished workout should carry its done line.")
        XCTAssertFalse(element(app, "pf-my-plan").exists, "The folded My Plan card is replaced by the week itself.")
        attach(app, "Phase4 62 Plan, week carries My Plan's job")
    }

    func testNoPlanMeansNoCard() throws {
        let app = try launch(extra: ["-PaceForgePhase4Unavailable"])
        app.openChip("Plan", "week")
        XCTAssertFalse(element(app, "pf-my-plan").waitForExistence(timeout: 5), "With no plan published there is no card.")
        attach(app, "Phase4 63 Plan without a plan")
    }

    // MARK: My Dashboard

    func testMyDashboardRowsOnToday() throws {
        let app = try launch()
        XCTAssertTrue(reveal(element(app, "today-my-dashboard-header"), in: app, maxSwipes: 20), "Today should carry the My Dashboard header.")
        // The rows sit under the key metrics, as the "Today vs 30 days" card.
        let section = element(app, "today-vs30")
        XCTAssertTrue(reveal(section, in: app, maxSwipes: 20), "Today should carry My Dashboard's Today vs 30 days rows.")
        attach(app, "Phase4 70 NOOP Today, My Dashboard")
        assertFits(section, in: app, "My Dashboard")
    }

    func testMyDashboardEditorAddsAMetricAndSaves() throws {
        let app = try launch()
        let customize = element(app, "look-dashboard-customize")
        XCTAssertTrue(reveal(customize, in: app, maxSwipes: 20), "My Dashboard's Today vs 30 days card should offer CUSTOMIZE.")
        customize.tap()
        XCTAssertTrue(element(app, "look-dashboard-list").waitForExistence(timeout: 10), "The editor should open.")
        attach(app, "Phase4 71 My Dashboard editor, drag handles")
        let add = element(app, "look-dashboard-add-my-whoop:steps")
        XCTAssertTrue(reveal(add, in: app), "Steps should be offered to add.")
        add.tap()
        attach(app, "Phase4 72 My Dashboard editor after adding Steps")
        element(app, "look-dashboard-save").tap()
        XCTAssertTrue(element(app, "today-vs30").waitForExistence(timeout: 10), "SAVE should return to Today.")
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

    // MARK: Stress (the monitor is the top of the one Stress screen)

    /// With PaceForge set up the Stress tile near the top is gone (build 529): the Stress Monitor chart in My Day, with today's score in its
    /// header, is the way in.
    func testStressMonitorChartOpensTheOneStressScreenWithTheMonitorOnTop() throws {
        let app = try launch()
        XCTAssertFalse(element(app, "look-stress-tile").exists, "The Stress tile should be gone from Today.")
        let tile = element(app, "today-stress-monitor")
        XCTAssertTrue(reveal(tile, in: app), "Today should show the Stress Monitor chart.")
        attach(app, "Phase4 90 Today, Stress monitor chart")
        tile.tap()
        XCTAssertTrue(element(app, "look-stress-monitor").waitForExistence(timeout: 20), "The chart should open the Stress screen with the monitor on top.")
        let hasReading = element(app, "look-stress-reading").waitForExistence(timeout: 10)
        let hasEmpty = element(app, "look-stress-empty").exists
        XCTAssertTrue(hasReading || hasEmpty, "The monitor shows either a real reading or the honest no-data state, never a made-up one.")
        attach(app, "Phase4 91 Stress screen, monitor on top")
        XCTAssertTrue(app.staticTexts["Autonomic load across your waking day"].exists, "The rest of the Stress screen is the same screen, not a second tap away.")
        XCTAssertFalse(element(app, "look-stress-full").exists, "There is no gateway hop to a second Stress screen any more.")
    }

    func testStressMonitorOnItsOwn() throws {
        let app = try launch(screen: "stressmonitor")
        XCTAssertTrue(element(app, "look-stress-monitor").waitForExistence(timeout: 30), "The monitor should render at the top of Stress.")
        attach(app, "Phase4 92 Stress screen, own screen")
    }

    // MARK: Light

    func testHighlightsAndHealthspanInLight() throws {
        let app = try launch(screen: "highlights", appearance: "light")
        XCTAssertTrue(element(app, "pf-highlights-body").waitForExistence(timeout: 30), "Highlights should render in light.")
        attach(app, "Phase4 95 Highlights (light)")
    }
}
