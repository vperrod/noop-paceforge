import XCTest

/// Build 530, the Sunday review (screens 1b to 1e). Fixture-backed (`Fixtures529/zzz-530-review.json`): the finished week 2030-W09 with
/// its `review` block and the coming week 2030-W10. `-Plan529Open review:2030-W09` opens the sheet over the Plan tab.
final class Review530UITests: XCTestCase {
    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture", "-Plan529Open", "review:2030-W09"])
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        app.launch()
        dumpHierarchyOnFailure(app)
        app.openTab("Plan")
        XCTAssertTrue(app.element("pf530-week-review").waitForExistence(timeout: 30), "The review sheet should open.")
        XCTAssertTrue(app.element("review530-verdict").waitForExistence(timeout: 30), "The review should load its verdict.")
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Scrolls until the element can be tapped, in the upper part of the sheet.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 40) -> Bool {
        let height = app.windows.firstMatch.frame.height
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable && element.frame.minY > height * 0.12 && element.frame.maxY < height * 0.85 { return true }
            let up = !element.exists || element.frame.minY > height * 0.12
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.70 : 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.40 : 0.65))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    /// The chart's tile and the line under it, both by identifier; the reading is compared with the fixture's sentence.
    private func assertChart(_ app: XCUIApplication, _ key: String, reading: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.element("review530-chart-\(key)").exists, "The \(key) chart should be on the page.", file: file, line: line)
        XCTAssertEqual(app.element("review530-reading-\(key)").label, reading, "The \(key) chart should carry its reading line.", file: file, line: line)
    }

    // MARK: 1b

    func testWhatYouDidShowsTheVerdictTrainingRacesAndStations() throws {
        let app = try launch()
        XCTAssertTrue(app.element("review530-verdict").label.hasPrefix("Two races in four days"), "The verdict leads the page.")
        assertChart(app, "training", reading: "Everything planned was done, 4 of 4. Time was 45 % under your usual, which is what a race week should be.")
        XCTAssertTrue(app.element("review530-bars-training").exists, "The training bars should draw the seven days.")
        XCTAssertTrue(app.element("review530-bars-hours").exists, "The hours against the usual should draw.")
        attach(app, "1b What you did, top")
        assertChart(app, "races", reading: "You started the singles fresh on both devices (WHOOP 86 %, Garmin 56), so tiredness does not explain the 8 minutes.")
        XCTAssertTrue(app.element("review530-race-0").exists, "The first race tile should show.")
        XCTAssertTrue(app.element("review530-race-1").exists, "The second race tile should show.")
        assertChart(app, "stations", reading: "Wall Balls and Lunges were what the last block trained, and they still cost the most.")
        XCTAssertTrue(reveal(app.element("review530-chart-stations"), in: app), "The stations chart should scroll into view.")
        attach(app, "1b What you did, races and stations")
    }

    // MARK: 1c

    func testWhatYourBodyShowedHasOneChartPerDeviceSleepAndHrv() throws {
        let app = try launch()
        assertChart(app, "whoop", reading: "Three red mornings. Thursday and Sunday each follow a race. Dashed line: your usual 61 %.")
        assertChart(app, "garmin", reading: "Held near your usual 56 until Sunday, then 9 after the doubles finished late.")
        assertChart(app, "sleep", reading: "Five of seven nights short. Average 6 h 56 against the 7 h 40 you need (dashed line).")
        assertChart(app, "hrvrhr", reading: "HRV fell all week while resting heart rate climbed. Two signals moving together is real fatigue, not a sensor blip.")
        XCTAssertTrue(app.element("review530-lines-garmin").exists, "HRV and resting heart rate should draw as two lines.")
        XCTAssertTrue(reveal(app.element("review530-chart-whoop"), in: app), "The WHOOP chart should scroll into view.")
        attach(app, "1c What your body showed, WHOOP and Garmin")
        XCTAssertTrue(reveal(app.element("review530-chart-hrvrhr"), in: app), "The HRV chart should scroll into view.")
        attach(app, "1c What your body showed, sleep and HRV")
    }

    // MARK: 1d

    func testWeekAheadShowsTheCalendarTheSevenDaysTheMixAndTheChange() throws {
        let app = try launch()
        XCTAssertTrue(app.element("review530-headline").waitForExistence(timeout: 20), "The week ahead should state its headline.")
        XCTAssertEqual(app.element("review530-headline").label, "Recover first, then your classes. Nothing hard before Wednesday.")
        XCTAssertTrue(app.element("review530-calendar-bar").exists, "The calendar bar should draw the phases to the race.")
        XCTAssertEqual(app.element("review530-reading-calendar").label,
                       "This week is the recovery part. Only 14 build days follow, so they go to Wall Balls, Lunges and running under fatigue.")
        XCTAssertTrue(app.element("plan529-strip-day-2030-03-05").waitForExistence(timeout: 20), "The seven days should show at once.")
        XCTAssertTrue(app.element("review530-chart-mix").exists, "The mix of work should draw.")
        XCTAssertTrue(app.element("review530-change-accept-chg530a").exists, "The change should offer Accept.")
        XCTAssertTrue(app.element("review530-change-keep-chg530a").exists, "The change should offer Keep as booked.")
        XCTAssertTrue(app.element("review530-accept-week").exists, "The week should offer Accept week.")
        XCTAssertTrue(reveal(app.element("review530-headline"), in: app), "The week ahead should scroll into view.")
        attach(app, "1d The week ahead, calendar")
        let keep = app.element("review530-change-keep-chg530a")
        XCTAssertTrue(reveal(keep, in: app), "Keep as booked should scroll into view.")
        attach(app, "1d The week ahead, change")
        keep.tap()
        XCTAssertFalse(app.element("review530-changes-failed").waitForExistence(timeout: 3), "The server took the answer.")
    }

    // MARK: 1e

    func testEveryWorkoutIsListedWithOneProposedRow() throws {
        let app = try launch()
        XCTAssertTrue(app.element("review530-workouts").waitForExistence(timeout: 20), "Every workout of the week should be listed.")
        XCTAssertTrue(app.element("review530-row-proposed-s530pull").exists, "The coach's session should be marked proposed.")
        XCTAssertTrue(app.element("review530-row-s530cardio").exists, "A booked session should be listed.")
        let proposed = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "review530-row-proposed-"))
        XCTAssertEqual(proposed.count, 1, "Exactly one row should be proposed.")
        XCTAssertTrue(app.element("review530-row-rest-2030-03-04").exists, "A rest day should be listed.")
        XCTAssertTrue(reveal(app.element("review530-row-proposed-s530pull"), in: app), "The proposed row should scroll into view.")
        attach(app, "1e Every workout")
    }
}
