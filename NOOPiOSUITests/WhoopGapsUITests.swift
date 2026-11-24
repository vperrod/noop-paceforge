import XCTest

/// Simulator checks for the NOOP-native additions: weekly goals on Today, Hide numbers, the health report in the
/// trends report sheet, pace of aging, and Coach history, thumbs, response length and Ask about this. They run on
/// the demo seed. Coach runs on `-CoachFixture` (DEBUG only): connected to nothing, with a made-up conversation
/// and two made-up past ones, so no key and no network are needed. Nothing here is real data.
final class WhoopGapsUITests: XCTestCase {

    private func launch(extraArguments: [String] = [], paceForge: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
        if paceForge {
            // On iPhone "Ask about this" is drawn only while PaceForge is configured (AskCoachButton, since dcfe459c6): the shared Coach
            // is PaceForge's, so the fixture stands in for the connection.
            app.launchArguments.append("-PaceForgeFixture")
            if let url = Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
               let json = try? Data(contentsOf: url) {
                app.launchEnvironment["PF_FIXTURE_JSON"] = (try? Fixtures529.merged(json)) ?? String(decoding: json, as: UTF8.self)
            }
        }
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

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        for _ in 0..<(maxSwipes * 2) {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    // MARK: Weekly goals

    func testWeeklyGoalsPresetShowsItsRings() {
        let app = launch()
        let open = element(app, "weekly-goals-open")
        XCTAssertTrue(open.waitForExistence(timeout: 30), "Today should show the Weekly goals card.")
        XCTAssertTrue(reveal(open, in: app))
        attach(app, "70 Weekly goals no plan")
        open.tap()
        XCTAssertTrue(element(app, "weekly-goals-sheet").waitForExistence(timeout: 10), "The plan picker should open.")
        for preset in ["sleepDeeper", "boostFitness", "feelBetter", "custom"] {
            XCTAssertTrue(element(app, "weekly-goals-preset-\(preset)").exists, "The picker should offer \(preset).")
        }
        attach(app, "70 Weekly goals plans")
        element(app, "weekly-goals-preset-boostFitness").tap()
        let ring = element(app, "weekly-goal-ring-zone45Minutes")
        XCTAssertTrue(ring.waitForExistence(timeout: 15), "The chosen plan should draw one ring per target.")
        XCTAssertTrue(element(app, "weekly-goal-ring-steps").exists)
        XCTAssertTrue(element(app, "weekly-goal-ring-sleepHours").exists)
        attach(app, "70 Weekly goals Boost fitness")
        // Leave no plan behind for the other tests.
        element(app, "weekly-goals-open").tap()
        let clear = element(app, "weekly-goals-clear")
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        clear.tap()
    }

    func testCustomWeeklyPlanNeedsTwoTargets() {
        let app = launch()
        let open = element(app, "weekly-goals-open")
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        XCTAssertTrue(reveal(open, in: app))
        open.tap()
        XCTAssertTrue(element(app, "weekly-goals-sheet").waitForExistence(timeout: 10))
        element(app, "weekly-goals-preset-custom").tap()
        let save = element(app, "weekly-goals-custom-save")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "A custom plan needs at least two targets.")
        element(app, "weekly-goals-custom-steps").tap()
        element(app, "weekly-goals-custom-sleepHours").tap()
        attach(app, "71 Weekly goals custom")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(element(app, "weekly-goal-ring-steps").waitForExistence(timeout: 15))
        attach(app, "71 Weekly goals custom plan")
        element(app, "weekly-goals-open").tap()
        let clear = element(app, "weekly-goals-clear")
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        clear.tap()
    }

    // MARK: Hide numbers

    func testHideNumbersReplacesTheScoresWithHidden() {
        let app = launch(extraArguments: ["-noop.hide.scores", "YES"])
        XCTAssertTrue(element(app, "today-settings").waitForExistence(timeout: 30), "Today should be up.")
        XCTAssertTrue(element(app, "hidden-value").waitForExistence(timeout: 15), "With the switch on, the scores read Hidden.")
        attach(app, "72 Today with scores hidden")
    }

    func testHideNumbersSwitchesAreInSettings() {
        let app = launch()
        let settings = element(app, "today-settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        let scores = element(app, "hide-scores-toggle")
        XCTAssertTrue(reveal(scores, in: app, maxSwipes: 6), "Settings should have the Hide numbers switches.")
        XCTAssertTrue(element(app, "hide-body-toggle").exists)
        attach(app, "72 Hide numbers settings")
    }

    // MARK: Health report

    func testTrendsReportSheetOffersTheHealthReport() {
        let app = launch()
        let health = app.shellTab("Health")
        XCTAssertTrue(health.waitForExistence(timeout: 30), "The Health tab should be in the bar.")
        health.tap()
        let trends = element(app, "health-chip-trends")
        XCTAssertTrue(trends.waitForExistence(timeout: 20), "Health should have a Trends chip.")
        trends.tap()
        let export = element(app, "trends-export-report")
        XCTAssertTrue(reveal(export, in: app, maxSwipes: 20), "Trends should offer the report export.")
        export.tap()
        let card = element(app, "health-report-card")
        XCTAssertTrue(card.waitForExistence(timeout: 15), "The report sheet should carry the health report.")
        for _ in 0..<4 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(element(app, "health-report-disclaimer").exists, "The health report must say it is not medical advice.")
        let ready = element(app, "health-report-share").waitForExistence(timeout: 20)
            || element(app, "health-report-empty").exists
        XCTAssertTrue(ready, "The card should offer the PDF or say there are no vitals yet.")
        attach(app, "73 Health report")
    }

    // MARK: Pace of aging

    func testHealthShowsPaceOfAging() {
        let app = launch()
        let tab = app.shellTab("Health")
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        // The Health Monitor, with Vitality, is the Vitals chip of the Health tab.
        let vitals = element(app, "health-chip-vitals")
        XCTAssertTrue(vitals.waitForExistence(timeout: 20), "Health should have a Vitals chip.")
        vitals.tap()
        app.openSection("vitals-body-age")
        let card = element(app, "pace-of-aging-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Health should show the Pace of aging card under Vitality.")
        XCTAssertTrue(element(app, "pace-of-aging-value").exists || element(app, "pace-of-aging-calibrating").exists,
                      "The card shows a pace or says how many weekly readings it still needs.")
        attach(app, "74 Pace of aging")
        let info = element(app, "pace-of-aging-info")
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()
        XCTAssertTrue(element(app, "pace-of-aging-info-sheet").waitForExistence(timeout: 10))
        attach(app, "74 Pace of aging info")
    }

    // MARK: Coach

    // The NOOP chat's history, thumbs-down reasons and Response length were tested here. On the iPhone that chat (CoachView) has not been
    // mounted since dcfe459c6 (24 Oct, "unify NOOP and PaceForge coaching") removed its chip from CoachUnifiedView; CoachView is the
    // macOS Coach only (RootView.swift), so those three tests had nothing to open and were removed.

    func testAskAboutThisFromAScoreInfoSheetPutsTheQuestionInCoach() {
        let app = launch(extraArguments: ["-CoachFixture"], paceForge: true)
        // The Coach sheet opens over Today at launch; close it, then open a score's guide from Today.
        XCTAssertTrue(element(app, "coach-host").waitForExistence(timeout: 40), "The Coach should open at launch.")
        app.buttons["Done"].firstMatch.tap()
        // The ring itself opens the trend; the name under it (the second button of the dial's cell) opens the guide.
        let guide = element(app, "six-rings-noop-charge").buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Charge")).element(boundBy: 1)
        XCTAssertTrue(guide.waitForExistence(timeout: 20), "Today should show the Charge label.")
        guide.tap()
        let ask = element(app, "ask-coach-button")
        XCTAssertTrue(ask.waitForExistence(timeout: 10), "A score's info sheet should offer Ask about this.")
        attach(app, "78 Ask about this")
        ask.tap()
        XCTAssertTrue(element(app, "coach-chip-content-ask").waitForExistence(timeout: 20), "The question should open the Coach on its Ask chip.")
        // The unified Coach sends a handed question at once and keeps it in the box; the fixture has no server behind api/app/chat, so the
        // send fails, which shows the status line and leaves the question there to resend.
        let sent = element(app, "pf-chat-status")
        XCTAssertTrue(sent.waitForExistence(timeout: 20), "Coach should send the question that was handed to it.")
        let question = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", "explain my Charge", "explain my Charge")).firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 20), "Coach should show the question that was handed to it.")
        attach(app, "78 Coach with the question")
    }
}
