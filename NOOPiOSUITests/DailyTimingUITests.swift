import XCTest

/// Opens every daily timing screen on made-up readings (`-DailyTimingFixture`, DEBUG builds only) and attaches a picture of each.
/// 2030-03-13 is a Wednesday; nothing here is real data.
final class DailyTimingUITests: XCTestCase {
    private func launch(_ variant: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "-theme.appearance", "dark", "-DailyTimingFixture", variant, "-PaceForgeFixture"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"))
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

    /// Mounted and clear of the tab bar, read from the frame: `isHittable` records a failure ("Activation point invalid") when it is
    /// asked about an element that is mounted but still below the screen.
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && frame.midY > 0 && frame.midY < app.frame.height - 110
    }

    /// Stops asking as soon as the element can be tapped: each question is a snapshot of the whole (very long) Today screen, and a
    /// `for ... where` loop would go on asking for every remaining turn, which left the app too busy to act on the next tap.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 30) {
        for _ in 0..<maxSwipes {
            if isOnScreen(element, in: app) && element.isHittable { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let element = app.element(id)
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(id) should be on the screen.")
        reveal(element, in: app)
        element.tap()
    }

    private func openDay(_ app: XCUIApplication, shot: String?) {
        let card = app.element("daily-timing-today-card")
        XCTAssertTrue(app.element("today-six-rings").waitForExistence(timeout: 60), "Today should open.")
        reveal(card, in: app)
        XCTAssertTrue(card.exists, "Today should carry the timing card.")
        if let shot { attach(app, shot) }
        card.tap()
        XCTAssertTrue(app.element("daily-timing-screen").waitForExistence(timeout: 30), "The card should open the day.")
        XCTAssertTrue(app.element("timing-cue-bed").waitForExistence(timeout: 30))
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.element("daily-timing-screen").waitForExistence(timeout: 20))
    }

    private func openWhy(_ app: XCUIApplication, row: String, screen: String, shot: String) {
        tap(row, in: app)
        XCTAssertTrue(app.element(screen).waitForExistence(timeout: 20), "\(row) should open its reason.")
        attach(app, shot)
        back(app)
    }

    func testTodayCardTheDayAndEveryReason() throws {
        let app = try launch("normal")
        openDay(app, shot: "Timing 01 Today card")
        attach(app, "Timing 02 The day")
        XCTAssertFalse(app.element("timing-cue-nap").exists, "A full night has no nap.")
        openWhy(app, row: "timing-cue-coffee", screen: "timing-why-coffee", shot: "Timing 03 Why coffee")
        openWhy(app, row: "timing-cue-daylight", screen: "timing-why-daylight", shot: "Timing 03b Why daylight")
        openWhy(app, row: "timing-cue-hardTraining", screen: "timing-why-hardTraining", shot: "Timing 03c Why hard training")
        openWhy(app, row: "timing-cue-dimLights", screen: "timing-why-dimLights", shot: "Timing 03d Why dim lights")
        openWhy(app, row: "timing-cue-bed", screen: "timing-why-bed", shot: "Timing 03e Why bedtime")
        openWhy(app, row: "timing-meals", screen: "timing-why-meals", shot: "Timing 04 Why meals")
    }

    func testAShortNightAddsTheNap() throws {
        let app = try launch("short")
        openDay(app, shot: nil)
        XCTAssertTrue(app.element("timing-cue-nap").exists, "A night under 6 h 30 adds the nap.")
        attach(app, "Timing 05 After a short night")
        openWhy(app, row: "timing-cue-nap", screen: "timing-why-nap", shot: "Timing 05b Why nap")
    }

    func testTheEveBeforeAWeekendShowsThePattern() throws {
        let app = try launch("weekend")
        openDay(app, shot: nil)
        tap("timing-weekend", in: app)
        XCTAssertTrue(app.element("timing-weekend-pattern").waitForExistence(timeout: 20))
        attach(app, "Timing 06 Weekend")
    }

    func testAnEveningClassUsesTheUsualSlot() throws {
        let app = try launch("evening")
        openDay(app, shot: nil)
        attach(app, "Timing 07a The day with a class")
        tap("timing-cue-session", in: app)
        XCTAssertTrue(app.element("timing-session-screen").waitForExistence(timeout: 20))
        XCTAssertEqual(app.element("timing-session-start").label, "18:20")
        XCTAssertTrue(app.element("timing-session-window").exists, "A class ending 2 h 50 before bed states the 4 h line.")
        attach(app, "Timing 07 Evening session")
        tap("timing-session-change", in: app)
        XCTAssertTrue(app.element("timing-picker-set").waitForExistence(timeout: 10))
        attach(app, "Timing 07b Change time")
    }

    func testEarlyStartAsksForEverything() throws {
        let app = try launch("normal")
        openDay(app, shot: nil)
        tap("timing-early-start", in: app)
        XCTAssertTrue(app.element("early-start-race").waitForExistence(timeout: 20))
        XCTAssertFalse(app.element("early-start-make").exists, "No plan before the wake time and the start day are entered.")
        attach(app, "Timing 08 Early start set up")
        tap("early-start-wake", in: app)
        XCTAssertTrue(app.element("timing-picker-set").waitForExistence(timeout: 10))
        attach(app, "Timing 08b Wake time wheel")
        app.element("timing-picker-set").tap()
        tap("early-start-start", in: app)
        XCTAssertTrue(app.element("timing-picker-set").waitForExistence(timeout: 10))
        attach(app, "Timing 08c Start day calendar")
        app.element("timing-picker-set").tap()
        XCTAssertTrue(app.element("early-start-make").waitForExistence(timeout: 10), "With everything entered the plan can be made.")
    }

    func testEarlyStartMakesAPlan() throws {
        let app = try launch("early")
        openDay(app, shot: nil)
        tap("timing-early-start", in: app)
        tap("early-start-make", in: app)
        XCTAssertTrue(app.element("early-plan-days").waitForExistence(timeout: 20), "The plan should list the days.")
        attach(app, "Timing 09 Early start plan")
    }

    func testWithNoSleepDataOnlyBedtimeShows() throws {
        let app = try launch("nodata")
        openDay(app, shot: nil)
        XCTAssertTrue(app.element("daily-timing-waiting").exists)
        XCTAssertFalse(app.element("timing-cue-coffee").exists)
        attach(app, "Timing 10 No sleep data")
    }
}
