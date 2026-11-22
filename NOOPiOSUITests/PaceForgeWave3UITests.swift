import XCTest

/// Simulator checks for the wave-3 PaceForge cards: race week, race simulations, easy mode, the muscle check,
/// tape measurements, heat and the estimate label. (The widget gallery and its privacy faces are gone: 622ffedd deleted
/// PaceForgeWidgetGallery.) Like the other PaceForge UI
/// tests they serve the synthetic PaceForgeFixture.json (made-up values only); the launch switches
/// `-PaceForgeRaceWeek`, `-PaceForgeSimsEmpty`, `-PaceForgeEasyPending`, `-PaceForgeEasyIdle` and
/// `-PaceForgeMuscleCalibrating` swap one fixture file for its second state.
final class PaceForgeWave3UITests: XCTestCase {
    private func launch(extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
        app.launchArguments.append("-PaceForgeFixture")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
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

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if element.exists && element.isHittable { return true }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        // A short, slow drag: a full swipe can carry a small element past the hittable band between two checks.
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    // MARK: Race week

    func testRaceWeekCardShowsItsPhaseVolumeAndTheChecklistTicks() throws {
        let app = try launch(extraArguments: ["-PaceForgeRaceWeek"])
        app.openChip("Plan", "season")
        let card = element(app, "pf-race-week-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Race week should show its card on Plan > Season.")
        XCTAssertTrue(element(app, "pf-race-week-phase").exists, "The card should name the phase.")
        XCTAssertTrue(element(app, "pf-race-week-volume").exists, "The card should show the volume target.")
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

    func testOutsideRaceWeekThereIsNoRaceWeekCardAndTodayKeepsTheNextRace() throws {
        let app = try launch()
        app.openChip("Plan", "season")
        XCTAssertTrue(reveal(element(app, "season-next-race"), in: app, maxSwipes: 20), "Season should list the races.")
        XCTAssertFalse(element(app, "pf-race-week-card").exists, "Outside race week there is no race-week card.")
        app.openTab("Today")
        XCTAssertTrue(reveal(element(app, "pf-today-next-race"), in: app, maxSwipes: 20), "Today should still show the next race.")
    }

    // MARK: Race simulations

    func testRaceSimulationsCardShowsTheSplitsFadeAndWeakestStations() throws {
        let app = try launch()
        app.openCoachInsights("deepDives")
        let card = element(app, "pf-sims-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 30) || card.waitForExistence(timeout: 5), "Deep dives should show Race simulations.")
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
        app.openCoachInsights("deepDives")
        let empty = element(app, "pf-sims-empty")
        XCTAssertTrue(reveal(empty, in: app, maxSwipes: 30) || empty.waitForExistence(timeout: 5),
                      "With no simulation the card should say how to log one.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Log a simulation")).firstMatch.exists,
                      "The empty state should say where to log one.")
        attach(app, "32 Race simulations empty")
    }

    // MARK: Easy mode

    /// Plan > Week. While a mode is on or proposed Week notes carries one line for it (`plan529-easy-banner`) that opens Change today;
    /// with none on, "How are you today?" opens the same sheet. The sheet holds the card, the start controls and End easy mode.
    private func openEasyMode(_ app: XCUIApplication, banner: Bool = true) -> XCUIElement {
        app.openChip("Plan", "week")
        if banner {
            // Since build 543 the easy-mode line sits under Week notes.
            let notes = element(app, "plan529-week-notes")
            XCTAssertTrue(reveal(notes, in: app, maxSwipes: 20), "Plan > Week should offer its Week notes.")
            notes.tap()
        }
        let entry = element(app, banner ? "plan529-easy-banner" : "plan529-how-today")
        XCTAssertTrue(reveal(entry, in: app, maxSwipes: 20), "Plan > Week should show how to reach easy mode.")
        return entry
    }

    func testEasyModeActiveShowsItsStateTheCardAndTheChangedSession() throws {
        let app = try launch()
        let banner = openEasyMode(app)
        XCTAssertTrue(banner.label.localizedCaseInsensitiveContains("Level"), "An active mode should show its level on the Week page: \(banner.label)")
        attach(app, "33 Easy mode row")
        XCTAssertTrue(reveal(element(app, "pf-easy-changed-s-wed"), in: app, maxSwipes: 20),
                      "A session the mode changed should be marked in the Week page.")
        attach(app, "33 Easy mode changed session")
        banner.tap()
        let card = element(app, "pf-easy-card")
        XCTAssertTrue(reveal(card, in: app), "An active mode should show its card in Change today.")
        XCTAssertTrue(element(app, "pf-easy-days").exists, "The card should say day N of M and when it returns.")
        XCTAssertTrue(element(app, "pf-easy-restorable").exists, "A restorable mode should say so.")
        attach(app, "33 Easy mode card")
    }

    func testEasyModePendingProposalSaysToAcceptInNeedsYou() throws {
        let app = try launch(extraArguments: ["-PaceForgeEasyPending"])
        openEasyMode(app).tap()
        let proposal = element(app, "pf-easy-pending-p1")
        XCTAssertTrue(reveal(proposal, in: app), "A pending proposal should be listed.")
        // The fixture's Needs you list has no matching item, so the card points to Needs you instead of showing Accept.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Accept it in Needs you")).firstMatch.exists,
                      "It should say where to accept it.")
        attach(app, "34 Easy mode pending")
    }

    func testEasyModeStartCardShowsWhenNothingIsOn() throws {
        let app = try launch(extraArguments: ["-PaceForgeEasyIdle"])
        openEasyMode(app, banner: false).tap()
        let start = element(app, "pf-easy-start")
        XCTAssertTrue(reveal(start, in: app), "With no mode on, Change today should offer to start one.")
        XCTAssertFalse(element(app, "pf-easy-card").exists, "There should be no active-mode card when no mode is on.")
        attach(app, "35 Easy mode start")
    }

    // MARK: Body: muscle check, tape, estimate label

    func testMuscleCheckWithARaisedFlagIsCaptured() throws {
        let app = try launch()
        app.openChip("Health", "body")
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
        app.openChip("Health", "body")
        let card = element(app, "pf-muscle-card")
        XCTAssertTrue(reveal(card, in: app), "Body should show the Muscle check card while calibrating.")
        XCTAssertTrue(label(app, "Calibrating").waitForExistence(timeout: 5), "The card should say it is calibrating.")
        attach(app, "37 Muscle check calibrating")
    }

    func testTapeMeasurementsCardIsCaptured() throws {
        let app = try launch()
        app.openChip("Health", "body")
        let card = element(app, "pf-tape-card")
        XCTAssertTrue(reveal(card, in: app, maxSwipes: 20), "Body should show Tape measurements.")
        XCTAssertTrue(element(app, "pf-tape-waist").exists, "The waist should be listed.")
        XCTAssertTrue(element(app, "pf-tape-waist-hip").exists, "Waist-to-hip should show.")
        XCTAssertTrue(element(app, "pf-tape-hint").exists, "The card should say to log in Telegram.")
        attach(app, "38 Tape measurements")
    }

    func testLeftRightFiguresAreLabelledAsAnEstimate() throws {
        let app = try launch()
        app.openChip("Health", "body")
        let note = element(app, "pf-body-estimate-note")
        XCTAssertTrue(reveal(note, in: app, maxSwipes: 24), "The segmental analysis should say left and right are an estimate.")
        XCTAssertTrue(element(app, "pf-body-estimate-left_arm").exists, "Each limb figure should carry the estimate label.")
        XCTAssertFalse(element(app, "pf-body-estimate-trunk").exists, "The trunk is not a left/right figure.")
        attach(app, "39 Segmental estimate label")
    }

    // MARK: Heat

    func testHeatChipShowsInSessionResultsAndAThermometerInTheWeek() throws {
        let app = try launch()
        app.openChip("Plan", "week")
        XCTAssertTrue(reveal(element(app, "pf-heat-glyph-s-mon"), in: app, maxSwipes: 20), "A hot day should carry a thermometer in the week.")
        attach(app, "40 Hot day thermometer")
        let done = app.buttons["pf-workout-s-mon"]
        XCTAssertTrue(reveal(done, in: app, maxSwipes: 20))
        done.tap()
        XCTAssertTrue(element(app, "pf-heat-chip").waitForExistence(timeout: 15), "The session results should show the heat chip.")
        attach(app, "40 Heat chip in results")
        app.buttons["Done"].tap()
    }
}
