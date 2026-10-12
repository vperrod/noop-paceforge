import XCTest

/// Simulator checks for My Day. The screen is driven by a made-up day (`-MyDayFixture full | gap | empty`,
/// DEBUG builds only) so every state can be captured with no strap and no data: the full day, a scrubbed
/// strip, gaps, an empty day, the PaceForge "today so far" strip and the widget gallery. Nothing here is real
/// data.
final class MyDayUITests: XCTestCase {

    private func launch(day variant: String? = nil, paceForge: Bool = false, widgetGallery: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let variant { app.launchArguments += ["-MyDayFixture", variant] }
        if paceForge {
            app.launchArguments.append("-PaceForgeFixture")
            if widgetGallery { app.launchArguments.append("-PaceForgeWidgetGallery") }
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                    "The synthetic PaceForge fixture should be bundled with the UI tests.")
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

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Overline labels are rendered upper-case, so match the text case-insensitively.
    private func label(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    private func labelContaining(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Today tab, then the My Day card under the rings.
    private func openMyDay(_ app: XCUIApplication) {
        let card = element(app, "myday-entry")
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Today should show the My Day card under the rings.")
        card.tap()
        XCTAssertTrue(element(app, "myday-strip").waitForExistence(timeout: 20), "My Day should draw its 24 h strip.")
    }

    func testFullDayIsCaptured() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        attach(app, "20 My Day full")
        XCTAssertTrue(element(app, "myday-list").waitForExistence(timeout: 10), "The day's events should be listed.")
        app.swipeUp()
        attach(app, "20 My Day full scrolled")
        app.swipeUp()
        attach(app, "20 My Day full scrolled 2")
    }

    func testThreeSourcesOfTheSameRunAreOneRowWithEveryBadge() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        let row = element(app, "myday-row-workout-garmin")
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.exists, "The run recorded by the strap, Garmin and Apple should be one row.")
        for badge in ["Strap", "Garmin", "Apple", "PaceForge"] {
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label ==[c] %@", badge)).firstMatch.exists,
                          "The merged run should carry the \(badge) badge.")
        }
        XCTAssertFalse(element(app, "myday-row-workout-strap").exists, "The strap's own copy should not be a second row.")
        attach(app, "21 Merged workout row")
    }

    func testScrubbingTheStripNamesWhatWasHappening() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        let strip = element(app, "myday-strip")
        let from = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.4))
        let to = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.4))
        from.press(forDuration: 0.1, thenDragTo: to)
        let readout = element(app, "myday-readout")
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertTrue((readout.label).contains("Mobility"), "Around 08:10 the strip should name the mobility session.")
        attach(app, "22 My Day scrubbed")
    }

    func testStressAndStepsOverlaysToggleOn() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        element(app, "myday-chip-stress").tap()
        element(app, "myday-chip-steps").tap()
        attach(app, "23 My Day overlays")
    }

    func testGapsAreHatchedAndExplained() throws {
        let app = try launch(day: "gap")
        openMyDay(app)
        attach(app, "24 My Day gaps")
        let charging = labelContaining(app, "Strap was charging")
        for _ in 0..<6 where !charging.exists { app.swipeUp() }
        XCTAssertTrue(charging.exists, "A gap beside a charging event should say the strap was charging.")
        XCTAssertTrue(labelContaining(app, "Not synced yet").exists, "The tail of today should say it is not synced yet.")
        attach(app, "24 My Day gaps listed")
    }

    func testEmptyDayShowsThePlanAndASyncHint() throws {
        let app = try launch(day: "empty")
        openMyDay(app)
        XCTAssertTrue(element(app, "myday-empty").waitForExistence(timeout: 10), "An empty day should say so.")
        XCTAssertTrue(label(app, "Synthetic 4 x 800 m").waitForExistence(timeout: 5), "The plan should still be listed.")
        attach(app, "25 My Day empty")
    }

    func testPaceForgeTodaySoFarOpensMyDay() throws {
        let app = try launch(paceForge: true)
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        XCTAssertTrue(element(app, "pf-sofar-card").waitForExistence(timeout: 20), "PaceForge Today should open on the today-so-far strip.")
        XCTAssertTrue(label(app, "0 of 1 session done").exists, "One session is planned and none is done yet.")
        attach(app, "26 PaceForge today so far")
        element(app, "pf-open-myday").tap()
        XCTAssertTrue(element(app, "myday-strip").waitForExistence(timeout: 20), "Open My Day should land on My Day.")
        attach(app, "26 PaceForge to My Day")
    }

    func testMyDayWidgetIsInTheGallery() throws {
        let app = try launch(paceForge: true, widgetGallery: true)
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let caption = label(app, "My Day, medium")
        XCTAssertTrue(app.staticTexts["Widget gallery"].waitForExistence(timeout: 20))
        for _ in 0..<8 where !caption.exists { app.swipeUp() }
        XCTAssertTrue(caption.exists, "The My Day widget should be drawn in the debug gallery.")
        attach(app, "27 My Day widget")
        app.swipeUp()
        attach(app, "27 My Day widget stale")
    }

    // MARK: PaceForge enrichment (Energy, Garmin stress, planned times, weigh-in time, niggle)

    func testEnergyToggleDrawsBodyBatteryAndTheLastRecharge() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        let energy = element(app, "myday-chip-energy")
        XCTAssertTrue(energy.waitForExistence(timeout: 10), "A day with Garmin data should offer the Energy toggle.")
        attach(app, "28 My Day energy off")
        energy.tap()
        XCTAssertTrue(element(app, "myday-energy-note").waitForExistence(timeout: 5), "The Energy curve should name Garmin Body Battery.")
        XCTAssertTrue(element(app, "myday-recharge").exists, "The last recharge line should show under the curve.")
        attach(app, "28 My Day energy on")
    }

    func testGarminStressIsItsOwnToggleLabelledBySource() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        let garmin = element(app, "myday-chip-garmin-stress")
        XCTAssertTrue(garmin.waitForExistence(timeout: 10), "Garmin's stress should have its own toggle.")
        XCTAssertTrue(app.buttons["myday-chip-stress"].label.contains("NOOP"), "NOOP's stress toggle should be labelled by its source.")
        element(app, "myday-chip-stress").tap()
        garmin.tap()
        XCTAssertTrue(element(app, "myday-garmin-stress-note").waitForExistence(timeout: 5), "Garmin's curve should say it is separate.")
        attach(app, "29 My Day two stress curves")
    }

    func testAPlannedSessionWithATimeIsNotAnAllDayRow() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        let row = element(app, "myday-row-plan-s-wed")
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.exists, "The planned intervals should be listed.")
        XCTAssertFalse(row.label.lowercased().contains("all day"), "A planned session with a slot should show its time, not All day.")
        attach(app, "29b My Day planned with a time")
    }

    func testTheTimedWeighInAndTheNiggleAreListed() throws {
        let app = try launch(day: "full")
        openMyDay(app)
        let niggle = element(app, "myday-row-note-n1")
        for _ in 0..<8 where !niggle.exists { app.swipeUp() }
        XCTAssertTrue(niggle.exists, "The niggle PaceForge logged should be a note on the day.")
        attach(app, "29c My Day niggle")
    }

    func testNoEnergyToggleWithoutGarminData() throws {
        let app = try launch(day: "empty")
        openMyDay(app)
        XCTAssertFalse(element(app, "myday-chip-energy").exists, "Without Garmin data there is no Energy toggle.")
        XCTAssertFalse(element(app, "myday-chip-garmin-stress").exists, "Without Garmin data there is no Garmin stress toggle.")
    }
}
