import XCTest

/// Simulator checks for the wave-3 PaceForge cards: race week, race simulations, easy mode, the muscle check,
/// tape measurements, heat, the estimate label and the widget privacy state. Like the other PaceForge UI
/// tests they serve the synthetic PaceForgeFixture.json (made-up values only); the launch switches
/// `-PaceForgeRaceWeek`, `-PaceForgeSimsEmpty`, `-PaceForgeEasyPending`, `-PaceForgeEasyIdle` and
/// `-PaceForgeMuscleCalibrating` swap one fixture file for its second state.
final class PaceForgeWave3UITests: XCTestCase {
    private func launch(extraArguments: [String] = [], widgetGallery: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
        app.launchArguments.append("-PaceForgeFixture")
        if widgetGallery { app.launchArguments.append("-PaceForgeWidgetGallery") }
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

    /// Overline labels are rendered upper-case, so match the text case-insensitively.
    private func label(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
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
        segments.buttons[title].tap()
    }

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    // MARK: Race week

    func testRaceWeekCardReplacesTheCountdownAndTheChecklistTicks() throws {
        let app = try launch(extraArguments: ["-PaceForgeRaceWeek"])
        try openSegment(app, "Today")
        let card = element(app, "pf-race-week-card")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Race week should show its card on Today.")
        XCTAssertTrue(element(app, "pf-race-week-phase").exists, "The card should name the phase.")
        XCTAssertTrue(element(app, "pf-race-week-volume").exists, "The card should show the volume target.")
        XCTAssertFalse(label(app, "Next race").exists, "The plain race countdown should be replaced in race week.")
        attach(app, "30 Race week card")
        let shoes = app.buttons["pf-race-check-shoes"]
        XCTAssertTrue(reveal(shoes, in: app), "The checklist should list the shoes item.")
        XCTAssertEqual(shoes.value as? String, "Not ticked")
        shoes.tap()
        XCTAssertEqual(shoes.value as? String, "Ticked", "Tapping an item should tick it.")
        attach(app, "30 Race week checklist ticked")
        XCTAssertTrue(reveal(element(app, "pf-race-morning"), in: app), "The race-morning timeline should be listed.")
        attach(app, "30 Race week morning timeline")
    }

    func testOutsideRaceWeekTheCountdownStaysAndNoRaceWeekCardShows() throws {
        let app = try launch()
        try openSegment(app, "Today")
        XCTAssertTrue(label(app, "Daily briefing").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "pf-race-week-card").exists, "Outside race week there is no race-week card.")
        for _ in 0..<8 where !label(app, "Next race").exists { app.swipeUp() }
        XCTAssertTrue(label(app, "Next race").exists, "The plain race countdown should still show.")
    }

    // MARK: Race simulations

    func testRaceSimulationsCardShowsTheSplitsFadeAndWeakestStations() throws {
        let app = try launch()
        try openSegment(app, "Insights")
        let card = element(app, "pf-sims-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20) || card.waitForExistence(timeout: 5), "Insights should show Race simulations.")
        XCTAssertTrue(element(app, "pf-sims-total").exists, "The latest total should show.")
        XCTAssertTrue(element(app, "pf-sims-vs-goal").exists, "The total should be set against the goal.")
        XCTAssertTrue(element(app, "pf-sims-fade").exists, "Run fade should show.")
        attach(app, "31 Race simulations")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-sims-band").waitForExistence(timeout: 5), "The 5 % pacing band result should show.")
        XCTAssertTrue(element(app, "pf-sims-table").exists, "The 16 splits should be in a table.")
        attach(app, "31 Race simulations splits")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-sims-weak-Burpee broad jumps").exists || element(app, "pf-sims-weak-Wall balls").exists,
                      "The two weakest stations should be listed.")
        XCTAssertFalse(element(app, "pf-sims-weak-Sled push").exists, "Only the two weakest stations should show.")
        XCTAssertTrue(element(app, "pf-sims-unmapped").exists, "An unmapped Garmin simulation should be mentioned.")
        attach(app, "31 Race simulations weakest")
    }

    func testRaceSimulationsEmptyStateTellsTheAthleteWhatToSay() throws {
        let app = try launch(extraArguments: ["-PaceForgeSimsEmpty"])
        try openSegment(app, "Insights")
        let empty = element(app, "pf-sims-empty")
        XCTAssertTrue(reveal(empty, in: app, maxSwipes: 20) || empty.waitForExistence(timeout: 5),
                      "With no simulation the card should say how to log one.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Log a simulation")).firstMatch.exists,
                      "The empty state should say where to log one.")
        attach(app, "32 Race simulations empty")
    }

    // MARK: Easy mode

    func testEasyModeActiveShowsTheChipTheCardAndTheChangedSession() throws {
        let app = try launch()
        try openSegment(app, "Today")
        XCTAssertTrue(element(app, "pf-easy-chip").waitForExistence(timeout: 10), "An active mode should show a chip on Today.")
        attach(app, "33 Easy mode chip")
        let card = element(app, "pf-easy-card")
        XCTAssertTrue(reveal(card, in: app), "An active mode should show its card.")
        XCTAssertTrue(element(app, "pf-easy-days").exists, "The card should say day N of M and when it returns.")
        XCTAssertTrue(element(app, "pf-easy-restorable").exists, "A restorable mode should say so.")
        attach(app, "33 Easy mode card")
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        app.segmentedControls["pf-segments"].buttons["This week"].tap()
        XCTAssertTrue(element(app, "pf-easy-changed-s-wed").waitForExistence(timeout: 10),
                      "A session the mode changed should be marked in This week.")
        attach(app, "33 Easy mode changed session")
    }

    func testEasyModePendingProposalSaysToAcceptInTelegram() throws {
        let app = try launch(extraArguments: ["-PaceForgeEasyPending"])
        try openSegment(app, "Today")
        let proposal = element(app, "pf-easy-pending-p1")
        XCTAssertTrue(reveal(proposal, in: app), "A pending proposal should be listed.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Accept in Telegram")).firstMatch.exists,
                      "It should say where to accept it.")
        attach(app, "34 Easy mode pending")
    }

    func testEasyModeHintShowsWhenNothingIsOn() throws {
        let app = try launch(extraArguments: ["-PaceForgeEasyIdle"])
        try openSegment(app, "Today")
        let hint = element(app, "pf-easy-hint")
        XCTAssertTrue(reveal(hint, in: app), "With no mode on, Today should offer the Telegram hint.")
        XCTAssertFalse(element(app, "pf-easy-chip").exists, "There should be no chip when no mode is on.")
        attach(app, "35 Easy mode hint")
    }

    // MARK: Body: muscle check, tape, estimate label

    func testMuscleCheckWithARaisedFlagIsCaptured() throws {
        let app = try launch()
        try openSegment(app, "Body")
        let card = element(app, "pf-muscle-card")
        XCTAssertTrue(reveal(card, in: app), "Body should show the Muscle check card.")
        XCTAssertTrue(element(app, "pf-muscle-lean").exists, "The lean trend figures should show.")
        attach(app, "36 Muscle check")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-muscle-split-14d").waitForExistence(timeout: 5), "The 14 day split should show.")
        XCTAssertTrue(element(app, "pf-muscle-quality-14d").exists, "The split should carry its quality label.")
        XCTAssertTrue(element(app, "pf-muscle-flag").exists, "A raised flag should give its rule.")
        attach(app, "36 Muscle check split and flag")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-muscle-advice").waitForExistence(timeout: 5), "The advice lines should show.")
        attach(app, "36 Muscle check advice")
    }

    func testMuscleCheckWhileCalibratingSaysSo() throws {
        let app = try launch(extraArguments: ["-PaceForgeMuscleCalibrating"])
        try openSegment(app, "Body")
        let card = element(app, "pf-muscle-card")
        XCTAssertTrue(reveal(card, in: app), "Body should show the Muscle check card while calibrating.")
        XCTAssertTrue(label(app, "Calibrating").waitForExistence(timeout: 5), "The card should say it is calibrating.")
        attach(app, "37 Muscle check calibrating")
    }

    func testTapeMeasurementsCardIsCaptured() throws {
        let app = try launch()
        try openSegment(app, "Body")
        let card = element(app, "pf-tape-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Body should show Tape measurements.")
        XCTAssertTrue(element(app, "pf-tape-waist").exists, "The waist should be listed.")
        XCTAssertTrue(element(app, "pf-tape-waist-hip").exists, "Waist-to-hip should show.")
        XCTAssertTrue(element(app, "pf-tape-hint").exists, "The card should say to log in Telegram.")
        attach(app, "38 Tape measurements")
    }

    func testLeftRightFiguresAreLabelledAsAnEstimate() throws {
        let app = try launch()
        try openSegment(app, "Body")
        let note = element(app, "pf-body-estimate-note")
        XCTAssertTrue(reveal(note, in: app, maxSwipes: 24), "The segmental analysis should say left and right are an estimate.")
        XCTAssertTrue(element(app, "pf-body-estimate-left_arm").exists, "Each limb figure should carry the estimate label.")
        XCTAssertFalse(element(app, "pf-body-estimate-trunk").exists, "The trunk is not a left/right figure.")
        attach(app, "39 Segmental estimate label")
    }

    // MARK: Heat

    func testHeatChipShowsInSessionResultsAndAThermometerInTheWeek() throws {
        let app = try launch()
        try openSegment(app, "This week")
        XCTAssertTrue(element(app, "pf-heat-glyph-s-mon").waitForExistence(timeout: 10), "A hot day should carry a thermometer in the week.")
        attach(app, "40 Hot day thermometer")
        let done = app.buttons["pf-workout-s-mon"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(element(app, "pf-heat-chip").waitForExistence(timeout: 15), "The session results should show the heat chip.")
        attach(app, "40 Heat chip in results")
        app.buttons["Done"].tap()
    }

    // MARK: Widgets

    func testWidgetGalleryShowsTheHiddenBodyAndRaceWeekFaces() throws {
        let app = try launch(widgetGallery: true)
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        XCTAssertTrue(label(app, "Widget gallery").waitForExistence(timeout: 15))
        XCTAssertTrue(label(app, "Race week").waitForExistence(timeout: 5), "The large widget should carry the race-week line.")
        attach(app, "41 Widget race week")
        let hidden = label(app, "Hidden \u{2014} open NOOP")
        for _ in 0..<10 where !hidden.exists { app.swipeUp() }
        XCTAssertTrue(hidden.exists, "With the privacy setting on, the body widget should read Hidden \u{2014} open NOOP.")
        attach(app, "41 Widget body hidden")
        app.swipeUp()
        attach(app, "41 Widget body hidden scrolled")
    }
}
