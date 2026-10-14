import XCTest

/// Simulator checks for the NOOP-native additions: weekly goals on Today, Hide numbers, the health report in the
/// trends report sheet, pace of aging, and Coach history, thumbs, response length and Ask about this. They run on
/// the demo seed. Coach runs on `-CoachFixture` (DEBUG only): connected to nothing, with a made-up conversation
/// and two made-up past ones, so no key and no network are needed. Nothing here is real data.
final class WhoopGapsUITests: XCTestCase {

    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
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
        let trends = app.shellTab("Trends")
        XCTAssertTrue(trends.waitForExistence(timeout: 30))
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
        let more = app.shellTab("More")
        XCTAssertTrue(more.waitForExistence(timeout: 30))
        more.tap()
        let body = app.buttons["Body"]
        if body.waitForExistence(timeout: 10), (body.value as? String) != "Expanded" {
            _ = reveal(body, in: app, maxSwipes: 8)
            body.tap()
        }
        let health = app.staticTexts["Health"]
        XCTAssertTrue(reveal(health, in: app, maxSwipes: 10), "More should list Health.")
        health.tap()
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

    func testCoachHistoryListsPastConversationsAndStartsANewOne() {
        let app = launch(extraArguments: ["-CoachFixture"])
        let history = element(app, "coach-history")
        XCTAssertTrue(history.waitForExistence(timeout: 40), "The made-up Coach should open.")
        attach(app, "75 Coach")
        element(app, "coach-new-conversation").tap()
        history.tap()
        XCTAssertTrue(element(app, "coach-history-sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "coach-history-row-fixture-1").waitForExistence(timeout: 5), "The earlier conversations are listed.")
        attach(app, "75 Coach history")
        element(app, "coach-history-row-fixture-1").tap()
        XCTAssertTrue(element(app, "coach-history-continue").waitForExistence(timeout: 10))
        attach(app, "75 Coach past conversation")
    }

    func testThumbsDownAsksWhy() {
        let app = launch(extraArguments: ["-CoachFixture"])
        let down = element(app, "coach-thumbs-down")
        XCTAssertTrue(down.waitForExistence(timeout: 40))
        down.tap()
        for reason in ["Inaccurate", "Unhelpful", "Off-topic", "Unsafe"] {
            XCTAssertTrue(app.buttons[reason].waitForExistence(timeout: 5), "The thumbs-down menu should offer \(reason).")
        }
        attach(app, "76 Coach feedback reasons")
        app.buttons["Unhelpful"].tap()
        XCTAssertEqual(element(app, "coach-feedback-reason").label, "Unhelpful")
        attach(app, "76 Coach feedback saved")
    }

    func testResponseLengthIsInCoachSettings() {
        let app = launch(extraArguments: ["-CoachFixture"])
        let settings = app.buttons["Coach settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 40))
        settings.tap()
        let picker = element(app, "coach-response-length")
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Coach settings should have the response length.")
        XCTAssertTrue(app.buttons["Condensed"].exists)
        app.buttons["Condensed"].tap()
        attach(app, "77 Coach response length")
        app.buttons["Default"].tap()
    }

    func testAskAboutThisFromAScoreInfoSheetPutsTheQuestionInCoach() {
        let app = launch(extraArguments: ["-CoachFixture"])
        // Coach opens over Today at launch; close it, then open a score's guide from Today.
        let history = element(app, "coach-history")
        XCTAssertTrue(history.waitForExistence(timeout: 40))
        app.buttons["Done"].firstMatch.tap()
        // The label under the ring ("Charge, 49. See how it is scored.") opens the guide; the ring itself opens the trend.
        let guide = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Charge", "See how it is scored")).firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 20), "Today should show the Charge label.")
        guide.tap()
        let ask = element(app, "ask-coach-button")
        XCTAssertTrue(ask.waitForExistence(timeout: 10), "A score's info sheet should offer Ask about this.")
        attach(app, "78 Ask about this")
        ask.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "explain my Charge")).firstMatch
            .waitForExistence(timeout: 20), "Coach should show the question that was handed to it.")
        attach(app, "78 Coach with the question")
    }
}
