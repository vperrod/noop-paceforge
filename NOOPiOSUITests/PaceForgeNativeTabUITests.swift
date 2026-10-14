import XCTest

/// Simulator checks for the native PaceForge tab. There is no server in CI, so the fixture tests launch
/// with `-PaceForgeFixture` and serve the synthetic PaceForgeFixture.json (made-up values only).
final class PaceForgeNativeTabUITests: XCTestCase {
    private func launch(fixture: Bool, widgetGallery: Bool = false, extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
        if fixture {
            app.launchArguments.append("-PaceForgeFixture")
            if widgetGallery { app.launchArguments.append("-PaceForgeWidgetGallery") }
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                    "The synthetic fixture should be bundled with the UI tests.")
            app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
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

    /// Overline labels are rendered upper-case, so match the text case-insensitively.
    private func label(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    private func openPaceForge(_ app: XCUIApplication) throws -> XCUIElement {
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        return segments
    }

    /// The segment is remembered between launches; a tap that lands while the previous one is restored is lost.
    private func select(_ segments: XCUIElement, _ title: String) {
        let button = segments.buttons[title]
        button.tap()
        if !button.isSelected { button.tap() }
    }

    /// Any element with this accessibility identifier, whatever its type.
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if element.exists && element.isHittable { return true }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        // A short, slow drag: a full swipe can carry a small element past the hittable band between two checks.
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        if element.exists && element.isHittable { return true }
        // Keep the accessibility tree so a failure shows what the screen really exposed.
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "hierarchy after a failed reveal"
        tree.lifetime = .keepAlways
        add(tree)
        return false
    }

    func testBottomBarShowsPaceForgeTab() throws {
        let app = try launch(fixture: false)
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The bottom bar should show a PaceForge tab.")
        XCTAssertFalse(app.tabBars.buttons["Coach"].exists, "NOOP's Coach tab should no longer be in the bottom bar.")
        attach(app, "00 Bottom bar")
    }

    func testNotSetUpStateWithoutSyncSettings() throws {
        let app = try launch(fixture: false)
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(label(app, "PaceForge sync not set up").waitForExistence(timeout: 10),
                      "Without an endpoint and token the tab should say sync is not set up.")
        attach(app, "00b Not set up")
    }

    func testEachSegmentRendersAndIsCaptured() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)

        // (segment title, text that proves the screen drew, screenshot name)
        let screens: [(String, String, String)] = [
            ("Today", "Your body today", "01 Today"),
            ("Coach", "Coach's Take", "02 Coach"),
            ("This week", "Mon 11 Mar", "03 This week"),
            ("Insights", "Fitness, fatigue and form", "04 Insights"),
            ("Body", "Body breakdown", "05 Body"),
        ]
        for (title, marker, name) in screens {
            let button = segments.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "The \(title) segment should exist.")
            button.tap()
            XCTAssertTrue(label(app, marker).waitForExistence(timeout: 10), "\(title) should show \"\(marker)\".")
            attach(app, name)
            app.swipeUp()
            attach(app, name + " scrolled")
            app.swipeUp()
            attach(app, name + " scrolled 2")
            app.swipeUp()
            attach(app, name + " scrolled 3")
            for _ in 0..<4 { app.swipeDown() }
        }
    }

    func testTodayShowsTheBriefingAndNoVerdictCard() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Today")
        XCTAssertTrue(label(app, "Daily briefing").waitForExistence(timeout: 10), "Today should lead with the daily briefing.")
        XCTAssertFalse(label(app, "Should you push today?").exists, "The verdict card should be gone.")
        XCTAssertFalse(label(app, "Coach's morning read").exists, "The morning-read card should be gone.")
    }

    func testCompletedSessionOpensItsResults() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "This week")

        let done = app.buttons["pf-workout-s-mon"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The completed easy run should be listed.")
        done.tap()
        XCTAssertTrue(label(app, "Coach analysis").waitForExistence(timeout: 15),
                      "A completed session should open its results with the coach's analysis.")
        attach(app, "06 Session results")
        for index in 1...4 {
            app.swipeUp()
            attach(app, "06 Session results scrolled \(index)")
        }
        app.buttons["Done"].tap()
    }

    func testBodyProgressCardIsCaptured() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Body")
        XCTAssertTrue(label(app, "Progress").waitForExistence(timeout: 10), "Body should lead with the Progress card.")
        XCTAssertTrue(label(app, "Needs readings").exists, "A goal without a pace should say it needs more readings.")
        attach(app, "09 Body progress")
        app.swipeUp()
        attach(app, "09 Body progress scrolled")
    }

    func testTodayShowsPartialBriefAlertsAndReadiness() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Today")
        XCTAssertTrue(label(app, "Waiting for: scale").waitForExistence(timeout: 10),
                      "A partial brief should say what it is waiting for.")
        XCTAssertTrue(label(app, "Updated 08:12").exists, "An updated brief should show when.")
        attach(app, "10 Today brief")
        XCTAssertTrue(label(app, "Alerts").waitForExistence(timeout: 5), "Open alerts should be listed on Today.")
        XCTAssertTrue(label(app, "Why my readiness is this").exists, "The three readiness reads should be on Today.")
        app.swipeUp()
        attach(app, "10 Today alerts and readiness")
        app.swipeUp()
        attach(app, "10 Today readiness")
    }

    func testSessionResultsShowHeartRateRecovery() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "This week")
        let done = app.buttons["pf-workout-s-mon"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(label(app, "Heart rate recovery").waitForExistence(timeout: 15),
                      "A session with a first-minute recovery should show it in its results.")
        attach(app, "11 Session heart rate recovery")
        app.swipeUp()
        attach(app, "11 Session heart rate recovery scrolled")
        app.buttons["Done"].tap()
    }

    func testPlannedSessionStillExpandsToPlanDetail() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "This week")

        let planned = app.buttons["pf-workout-s-wed"]
        XCTAssertTrue(planned.waitForExistence(timeout: 10), "The planned intervals session should be listed.")
        planned.tap()
        XCTAssertTrue(label(app, "Session breakdown").waitForExistence(timeout: 5),
                      "Opening a planned session should show its step breakdown.")
        attach(app, "07 Planned session expanded")
    }

    func testWidgetGalleryIsCaptured() throws {
        let app = try launch(fixture: true, widgetGallery: true)
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(label(app, "Widget gallery").waitForExistence(timeout: 15), "The widget gallery should draw from the fixture.")
        attach(app, "08 Widgets large")
        for index in 1...4 {
            app.swipeUp()
            attach(app, "08 Widgets scrolled \(index)")
        }
    }

    // MARK: Wave 2 (feel, what changed, answers, explainers, behaviour)

    func testFeelCardSavesAnAnswerAndShowsTheSentenceAndStrip() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Today")
        let four = app.buttons["pf-feel-4"]
        XCTAssertTrue(reveal(four, in: app), "The feel card should offer five buttons on Today.")
        XCTAssertTrue(element(app, "pf-feel-strip").exists, "The 14-day dot strip should be drawn.")
        attach(app, "12 Feel card before")
        four.tap()
        XCTAssertTrue(element(app, "pf-feel-saved").waitForExistence(timeout: 5)
                      || label(app, "Saved \u{00B7} 4 of 5").waitForExistence(timeout: 5),
                      "The saved answer should show on the card.")
        XCTAssertTrue(element(app, "pf-feel-sentence").exists, "The agreement sentence should show.")
        attach(app, "12 Feel card saved")
    }

    func testFeelCardSaysSoWhenTheSaveFails() throws {
        let app = try launch(fixture: true, extraArguments: ["-PaceForgeFeelFails"])
        let segments = try openPaceForge(app)
        select(segments, "Today")
        let three = app.buttons["pf-feel-3"]
        XCTAssertTrue(reveal(three, in: app))
        three.tap()
        XCTAssertTrue(element(app, "pf-feel-error").waitForExistence(timeout: 5),
                      "A failed save should say \"Couldn't save \u{2014} try again\".")
        attach(app, "12b Feel card save failed")
    }

    func testWhatChangedCardShowsRowsAndTheCalibrationLine() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Today")
        let hrv = app.buttons["pf-change-hrv_7d"]
        XCTAssertTrue(reveal(hrv, in: app), "The what-changed card should list the HRV row.")
        XCTAssertTrue(label(app, "Day 12 of 21").exists, "A calibrating metric should show its Day N of M line.")
        attach(app, "13 What changed")
        hrv.tap()
        XCTAssertTrue(label(app, "Usual 36\u{2013}44 (your normal band)").waitForExistence(timeout: 3),
                      "Tapping a row should open its reason and typical range.")
        attach(app, "13 What changed row open")
    }

    func testReadinessShowsTheTwoAnswersAndATrustNote() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Today")
        let train = element(app, "pf-answer-train")
        XCTAssertTrue(reveal(train, in: app), "The readiness card should show 'OK to train'.")
        XCTAssertTrue(element(app, "pf-answer-hard").exists, "And 'OK to train hard'.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Low confidence: the watch recorded only 52%")).firstMatch.exists,
                      "A low-confidence source should say why.")
        attach(app, "14 Readiness answers and trust")
    }

    func testExplainerSheetOpensFromTheRecoveryRing() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Today")
        let info = app.buttons["pf-info-recovery"].firstMatch
        XCTAssertTrue(reveal(info, in: app), "The recovery ring should carry an info button.")
        info.tap()
        XCTAssertTrue(element(app, "pf-explainer-sheet").waitForExistence(timeout: 5), "The explainer sheet should open.")
        attach(app, "15 Explainer sheet")
        app.buttons["pf-explainer-done"].tap()
    }

    func testExplainerSheetShowsCalibrationProgress() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Insights")
        let row = app.buttons["pf-how-hrv_status"]
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 20), "Insights should list 'How these scores work'.")
        attach(app, "16 How these scores work")
        row.tap()
        XCTAssertTrue(app.progressIndicators["pf-calibration-bar"].waitForExistence(timeout: 5)
                      || label(app, "Day 12 of 21").exists, "A calibrating metric's sheet should show its progress.")
        attach(app, "16 Explainer calibration")
        app.buttons["pf-explainer-done"].tap()
    }

    func testBehaviourImpactQualifyingState() throws {
        let app = try launch(fixture: true)
        let segments = try openPaceForge(app)
        select(segments, "Insights")
        let card = element(app, "pf-behaviour-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 6) || card.waitForExistence(timeout: 5),
                      "Insights should show 'What affects your recovery'.")
        XCTAssertTrue(element(app, "pf-behaviour-waiting").exists, "Questions still short of days should be listed.")
        attach(app, "17 Behaviour impact")
    }

    func testBehaviourImpactInsufficientState() throws {
        let app = try launch(fixture: true, extraArguments: ["-PaceForgeBehaviourInsufficient"])
        let segments = try openPaceForge(app)
        select(segments, "Insights")
        let message = element(app, "pf-behaviour-insufficient")
        XCTAssertTrue(reveal(message, in: app, maxSwipes: 6) || message.waitForExistence(timeout: 5),
                      "With no qualifying question the card should say 'Insufficient data yet'.")
        attach(app, "17b Behaviour impact insufficient")
    }

    func testLargeWidgetShowsTheTwoAnswers() throws {
        let app = try launch(fixture: true, widgetGallery: true)
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(label(app, "Train: yes \u{00B7} Hard: careful").waitForExistence(timeout: 15),
                      "The large Today widget should show the two answers on one line.")
        attach(app, "18 Widget large with answers")
    }
}
