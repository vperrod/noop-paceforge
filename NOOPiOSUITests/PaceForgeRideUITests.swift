import XCTest

/// Simulator checks for bike rides: the ride rows in This week, Today and My Day, and the ride screen for a
/// second-by-second ride and a 240-point one. Like the other PaceForge UI tests they serve the synthetic
/// PaceForgeFixture.json (made-up values only); `-PaceForgeRideNone` drops ride-metrics.json and
/// `-PaceForgeRideNoStream` drops one ride's stream file. `-MyDayFixture ride` adds a ride to the made-up day.
final class PaceForgeRideUITests: XCTestCase {
    private let longRide = "pf-ride-bike:2030-03-13"
    private let sampledRide = "pf-ride-bike:2030-03-11"

    private func launch(extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
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

    private func label(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    private func openSegment(_ app: XCUIApplication, _ title: String) throws {
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        let button = segments.buttons[title]
        button.tap()
        // The segment is remembered between launches; a tap that lands while the previous one is restored is lost.
        if !button.isSelected { button.tap() }
    }

    /// Scrolls down until the element can be tapped.
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

    private func openRide(_ app: XCUIApplication, _ id: String) throws {
        try openSegment(app, "This week")
        let row = app.buttons[id]
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 20), "This week should list the ride.")
        row.tap()
        XCTAssertTrue(element(app, "pf-ride-sheet").waitForExistence(timeout: 10), "The ride screen should open.")
    }

    // MARK: Rows

    func testThisWeekListsBothRidesAndTodayListsTheOneOnTheDay() throws {
        let app = try launch()
        try openSegment(app, "This week")
        XCTAssertTrue(reveal(app.buttons[longRide], in: app, maxSwipes: 20))
        XCTAssertTrue(reveal(app.buttons[sampledRide], in: app, maxSwipes: 20))
        attach(app, "50 Ride rows in This week")
        try openSegment(app, "Today")
        XCTAssertTrue(reveal(app.buttons[longRide], in: app, maxSwipes: 20), "Today should list today's ride.")
        attach(app, "50 Ride row on Today")
    }

    func testWithoutRideMetricsNoRideRowShows() throws {
        let app = try launch(extraArguments: ["-PaceForgeRideNone"])
        try openSegment(app, "This week")
        XCTAssertTrue(app.staticTexts["Wed 13 Mar"].waitForExistence(timeout: 10) || label(app, "Wed 13 Mar").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[longRide].exists, "Without ride-metrics.json there is no ride row.")
    }

    // MARK: The ride screen

    func testSecondBySecondRideShowsEverySection() throws {
        let app = try launch()
        try openRide(app, longRide)
        XCTAssertEqual(element(app, "pf-ride-resolution").label, "second-by-second")
        XCTAssertTrue(element(app, "pf-ride-numbers").exists, "The key numbers should show.")
        XCTAssertTrue(element(app, "pf-ride-power-zones").exists, "Power zones should show.")
        attach(app, "51 Ride top")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-ride-hr-zones").waitForExistence(timeout: 5), "Heart-rate zones should show.")
        attach(app, "51 Ride zones")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-ride-panel-power").waitForExistence(timeout: 10), "The power chart should draw from the stream.")
        XCTAssertTrue(element(app, "pf-ride-panel-heart-rate").exists, "The heart-rate chart should draw.")
        attach(app, "51 Ride chart")
        app.swipeUp()
        attach(app, "51 Ride chart scrolled")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-ride-mmp").waitForExistence(timeout: 5), "Best power by duration should show.")
        XCTAssertTrue(element(app, "pf-ride-lap-2").exists, "The laps should be listed.")
        attach(app, "51 Ride best power and laps")
        app.swipeUp()
        attach(app, "51 Ride compliance and recovery")
        app.swipeUp()
        XCTAssertTrue(element(app, "pf-ride-analysis").waitForExistence(timeout: 10), "The coach analysis should show.")
        XCTAssertFalse(element(app, "pf-ride-estimate-note").exists, "A second-by-second ride is not an estimate.")
        attach(app, "51 Ride analysis")
    }

    func testSampledRideSaysSoAndMarksDecouplingNotValid() throws {
        let app = try launch()
        try openRide(app, sampledRide)
        XCTAssertEqual(element(app, "pf-ride-resolution").label, "240-point sample")
        XCTAssertTrue(label(app, "Not valid").exists, "Decoupling that is not valid should say so.")
        attach(app, "52 Sampled ride top")
        for _ in 0..<6 where !element(app, "pf-ride-estimate-note").exists { app.swipeUp() }
        let note = element(app, "pf-ride-estimate-note")
        XCTAssertTrue(note.waitForExistence(timeout: 10), "A sampled ride's analysis should carry the estimate note.")
        XCTAssertEqual(note.label, "Estimated from a 240-point sample")
        attach(app, "52 Sampled ride analysis")
    }

    func testRideScreenUsesNoRunningVocabulary() throws {
        let app = try launch()
        try openRide(app, longRide)
        for word in ["/km", "spm", "stride", "split"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", word)).firstMatch.exists,
                           "A ride should not use \"\(word)\".")
        }
    }

    func testRideWithoutAStreamFileSaysTheChartIsNotSynced() throws {
        let app = try launch(extraArguments: ["-PaceForgeRideNoStream"])
        try openRide(app, longRide)
        for _ in 0..<6 where !element(app, "pf-ride-chart-missing").exists { app.swipeUp() }
        XCTAssertTrue(element(app, "pf-ride-chart-missing").waitForExistence(timeout: 10),
                      "Without a stream file the chart card should say it is not synced.")
        attach(app, "53 Ride without a stream")
    }

    // MARK: My Day

    func testMyDayListsTheRideAndItOpensTheRideScreen() throws {
        let app = try launch(extraArguments: ["-MyDayFixture", "ride"])
        let card = element(app, "myday-entry")
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Today should show the My Day card under the rings.")
        card.tap()
        XCTAssertTrue(element(app, "myday-strip").waitForExistence(timeout: 20))
        let row = element(app, "myday-row-ride-bike:2030-03-13")
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.exists, "My Day should list the PaceForge ride.")
        attach(app, "54 My Day with a ride")
        row.tap()
        XCTAssertTrue(element(app, "pf-ride-sheet").waitForExistence(timeout: 15), "The ride row should open the ride screen.")
        XCTAssertTrue(element(app, "pf-ride-numbers").waitForExistence(timeout: 10))
        attach(app, "54 Ride opened from My Day")
    }
}
