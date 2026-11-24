import XCTest

/// Build 530, APP-2: the overview card (3a morning, 5d top evening) and the My Journal card (5a) on Today. It runs on the synthetic fixture
/// (its day is 2030-03-13) with `zzz-530-today.json` merged in. The phone picks the card by the clock, so each test forces the phase the
/// way the bookend row's clock is forced (`-PaceForgeMorning` / `-PaceForgeEvening`). Today's lower half is lazy: an element exists only
/// near the screen, so the tests scroll to each one. Screenshot names start with the screen code.
final class TodayCards530UITests: XCTestCase {
    private func launch(extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture"])
        app.launchArguments.append(contentsOf: extra)
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

    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && frame.midY > 120 && frame.midY < app.frame.height * 0.85
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 16) -> Bool {
        for _ in 0..<(maxSwipes * 2) {
            if isOnScreen(element, in: app) { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return isOnScreen(element, in: app)
    }

    private func waitForToday(_ app: XCUIApplication) {
        XCTAssertTrue(app.element("today-six-rings").waitForExistence(timeout: 30), "Today should be up.")
    }

    /// Scrolls to each id in turn (top to bottom) and returns the ones that were found.
    private func revealAll(_ ids: [String], in app: XCUIApplication) -> Set<String> {
        var found: Set<String> = []
        for id in ids where reveal(app.element(id), in: app) { found.insert(id) }
        return found
    }

    // MARK: 3a, the morning card

    func testMorningCardShowsTheVerdictBothDevicesTheEightMorningTrendTheReadingAndThreeRows() throws {
        let app = try launch(extra: ["-PaceForgeMorning"])
        waitForToday(app)
        let ids = ["today-overview-morning", "today-overview-verdict", "today-overview-device-WHOOP", "today-overview-device-Garmin",
                   "today-overview-trend-WHOOP", "today-overview-trend-Garmin", "today-overview-reading",
                   "today-overview-row-Today", "today-overview-row-Tonight", "today-overview-row-Tomorrow"]
        let found = revealAll(ids, in: app)
        for id in ids { XCTAssertTrue(found.contains(id), "The morning card should show \(id).") }
        XCTAssertTrue(app.element("today-overview-trend-WHOOP").label.contains("last 8 mornings"), "The trend should cover eight mornings.")
        XCTAssertFalse(app.element("today-overview-evening").exists, "The evening card should not show with the morning card.")
        attach(app, "3a morning card")
    }

    // MARK: 5d (top), the evening card

    func testEveningPhaseShowsTheEveningCardAndNotTheMorningCard() throws {
        let app = try launch(extra: ["-PaceForgeEvening"])
        waitForToday(app)
        let ids = ["today-overview-evening", "today-overview-verdict", "today-overview-against-plan", "today-overview-moved",
                   "today-overview-found", "today-overview-tonight"]
        let found = revealAll(ids, in: app)
        for id in ids { XCTAssertTrue(found.contains(id), "The evening card should show \(id).") }
        XCTAssertFalse(app.element("today-overview-morning").exists, "The morning card should not show with the evening card.")
        attach(app, "5d-top evening card")
    }

    // MARK: 5a, My Journal

    func testMyJournalCardShowsTheWeekRowTheLineAndItsButtons() throws {
        let app = try launch(extra: ["-PaceForgeMorning"])
        waitForToday(app)
        app.openChip("Health", "day")
        let card = app.element("today-journal")
        XCTAssertTrue(reveal(card, in: app), "Health > Day should show the My Journal card.")
        let line = app.element("today-journal-line")
        XCTAssertTrue(line.waitForExistence(timeout: 20), "The card should say what the devices answered and what is left for you.")
        XCTAssertTrue(line.label.contains("About Tuesday: 7 answered by your devices, 5 questions for you."), "The line was: \(line.label)")
        let ids = ["today-journal-week", "today-journal-fill", "today-journal-insights"]
        let found = revealAll(ids, in: app)
        for id in ids { XCTAssertTrue(found.contains(id), "The journal card should show \(id).") }
        XCTAssertTrue(app.element("today-journal-day-0").exists, "The week row should have today's cell.")
        let cards = app.descendants(matching: .any).matching(identifier: "today-journal")
        XCTAssertEqual(cards.count, 1, "There should be one journal card.")
        XCTAssertFalse(app.element("today-journal-logged").exists, "The old folded journal row should not show next to My Journal.")
        attach(app, "5a my journal card")
    }

    func testMyJournalButtonsOpenTheirRoutes() throws {
        let app = try launch(extra: ["-PaceForgeMorning"])
        waitForToday(app)
        app.openChip("Health", "day")
        let fill = app.element("today-journal-fill")
        XCTAssertTrue(reveal(fill, in: app), "Health > Day should show Fill out.")
        fill.tap()
        XCTAssertTrue(app.element("pf530-journal-morning").waitForExistence(timeout: 20), "Fill out should open the morning questions.")
    }

    // MARK: Order

    /// The rings, the My Day graph, the call and the overview card come in that order, and the Health tile is the last block of Today. Each id is noted where the scroll first meets it (the step, then the height on screen); an element met in a later step lies
    /// lower on the page. (The Stress tile gives way to the Stress Monitor chart when PaceForge is set up, so the Health tile stands for the tiles.)
    func testTheRingsTheDayGraphTheCallAndTheTilesComeBeforeTheNewCardsInTheScrollOrder() throws {
        let app = try launch(extra: ["-PaceForgeMorning"])
        waitForToday(app)
        let ids = ["today-six-rings", "today-daygraph", "pf-today-card-the-call", "today-overview-morning", "look-health-tile"]
        var first: [String: (step: Int, y: CGFloat)] = [:]
        func note(_ step: Int) {
            for id in ids where first[id] == nil {
                let element = app.element(id)
                if element.exists, !element.frame.isEmpty { first[id] = (step, element.frame.minY) }
            }
        }
        note(0)
        for step in 1...20 {
            app.swipeUp()
            note(step)
        }
        for id in ids { XCTAssertNotNil(first[id], "Today should show \(id).") }
        func isBefore(_ a: String, _ b: String) -> Bool {
            guard let x = first[a], let y = first[b] else { return false }
            return x.step < y.step || (x.step == y.step && x.y < y.y)
        }
        XCTAssertTrue(isBefore("today-six-rings", "today-overview-morning"), "The rings should come before the overview card.")
        XCTAssertTrue(isBefore("today-daygraph", "today-overview-morning"), "The My Day graph should come before the overview card.")
        XCTAssertTrue(isBefore("pf-today-card-the-call", "today-overview-morning"), "The call should come before the overview card.")
        XCTAssertTrue(isBefore("today-overview-morning", "look-health-tile"), "The Health tile should come after the overview card, at the bottom.")
    }
}
