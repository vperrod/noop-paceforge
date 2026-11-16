import XCTest

/// Build 531: the three blocks build 530 added to Today (the Sunday review row, the overview card and My Journal) can be switched off in
/// Customize Today, like every other block. Synthetic fixture, `zzz-530-today.json` merged in (the day is 2030-03-13). A switched-off
/// block is passed in with the launch argument `-today.hiddenBlocks <ids>` (the key the sheet writes); one test switches a block off in
/// the sheet itself. Today's lower half is lazy, so each test scrolls the whole page and notes what it met. The review row opens only on
/// Sunday evening and Monday morning by the clock, which a UI test cannot move, so its absence here is trivial; the unit tests prove its
/// switch and the code path is the same `if` as the other two. Screenshot names start with "531".
final class TodayBlocks531UITests: XCTestCase {
    private static let overviewIDs = ["today-overview-morning", "today-overview-evening", "today-overview-loading", "today-overview-failed"]
    private static let journalID = "today-journal"
    private static let reviewRowID = "review530-today-row"
    private static let blockIDs = ["daily-overview", "my-journal", "sunday-review"]

    private func launch(hidden: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture", "-PaceForgeMorning"])
        if !hidden.isEmpty { app.launchArguments.append(contentsOf: ["-today.hiddenBlocks", hidden.joined(separator: ",")]) }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        app.launch()
        dumpHierarchyOnFailure(app)
        XCTAssertTrue(app.element("today-six-rings").waitForExistence(timeout: 30), "Today should be up.")
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Scrolls Today from the top to the bottom and returns, for each id met, the step and the height where it was first met.
    private func traverse(_ app: XCUIApplication, ids: [String], steps: Int = 14) -> [String: (step: Int, y: CGFloat)] {
        var first: [String: (step: Int, y: CGFloat)] = [:]
        func note(_ step: Int) {
            for id in ids where first[id] == nil {
                let element = app.element(id)
                if element.exists, !element.frame.isEmpty { first[id] = (step, element.frame.minY) }
            }
        }
        note(0)
        for step in 1...steps {
            app.swipeUp()
            note(step)
        }
        return first
    }

    private func isBefore(_ a: String, _ b: String, in first: [String: (step: Int, y: CGFloat)]) -> Bool {
        guard let x = first[a], let y = first[b] else { return false }
        return x.step < y.step || (x.step == y.step && x.y < y.y)
    }

    /// The row is the switch's element, so its centre is the label: the control itself sits at the right end.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func openSheet(_ app: XCUIApplication) {
        let button = app.element("today-customize")
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Today should carry the Customize Today button.")
        button.tap()
        XCTAssertTrue(app.navigationBars["Customize Today"].waitForExistence(timeout: 20), "The button should open Customize Today.")
    }

    /// Scrolls the sheet until the switch row is on screen.
    @discardableResult
    private func revealRow(_ id: String, in app: XCUIApplication) -> Bool {
        for _ in 0..<12 {
            let row = app.element("today-customize-block-\(id)")
            if row.exists, row.isHittable { return true }
            app.swipeUp()
        }
        return app.element("today-customize-block-\(id)").isHittable
    }

    // MARK: The overview card

    func testWithTheDailyOverviewOffTheOverviewCardIsGoneAndTheJournalAndTheRestStillDraw() throws {
        let app = try launch(hidden: ["daily-overview"])
        let first = traverse(app, ids: Self.overviewIDs + [Self.journalID, "pf-today-card-the-call", "today-my-day-header"])
        for id in Self.overviewIDs { XCTAssertNil(first[id], "With the daily overview off, \(id) should not draw.") }
        XCTAssertNotNil(first[Self.journalID], "My Journal should still draw.")
        XCTAssertNotNil(first["pf-today-card-the-call"], "The call should still draw.")
        XCTAssertNotNil(first["today-my-day-header"], "The My Day heading and what follows should still draw.")
        for _ in 0..<16 { app.swipeDown() }
        attach(app, "531 daily overview off, top")
    }

    // MARK: All three off

    func testWithAllThreeOffNoneOfThemDrawsAndTheOrderOfTheRestIsUnchanged() throws {
        let app = try launch(hidden: Self.blockIDs)
        let order = ["today-six-rings", "today-daygraph", "pf-today-card-the-call", "look-health-tile", "today-my-day-header"]
        let first = traverse(app, ids: order + Self.overviewIDs + [Self.journalID, Self.reviewRowID])
        for id in Self.overviewIDs + [Self.journalID, Self.reviewRowID] {
            XCTAssertNil(first[id], "With all three switched off, \(id) should not draw.")
        }
        for id in order { XCTAssertNotNil(first[id], "Today should still draw \(id).") }
        for (a, b) in zip(order, order.dropFirst()) {
            XCTAssertTrue(isBefore(a, b, in: first), "\(a) should still come before \(b).")
        }
        for _ in 0..<16 { app.swipeDown() }
        attach(app, "531 all three off, top")
        for _ in 0..<2 { app.swipeUp() }
        attach(app, "531 all three off, below the call")
    }

    // MARK: The sheet

    func testCustomizeTodayListsTheThreeRowsAndASwitchTakesTheCardOffToday() throws {
        let app = try launch()
        addTeardownBlock { [self] in restoreSwitches(app) }
        openSheet(app)
        for id in ["sunday-review", "daily-overview", "my-journal"] {
            XCTAssertTrue(revealRow(id, in: app), "Customize Today should list the row \(id).")
            XCTAssertEqual(app.switches["today-customize-block-\(id)"].value as? String, "1", "\(id) should start on.")
        }
        attach(app, "531 customize today, the three rows")
        flip(app.switches["today-customize-block-daily-overview"])
        XCTAssertEqual(app.switches["today-customize-block-daily-overview"].value as? String, "0", "A tap should switch the daily overview off.")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.element("today-six-rings").waitForExistence(timeout: 20), "Save should return to Today.")
        let first = traverse(app, ids: Self.overviewIDs + [Self.journalID])
        for id in Self.overviewIDs { XCTAssertNil(first[id], "After the switch, \(id) should not draw.") }
        XCTAssertNotNil(first[Self.journalID], "My Journal should still draw after the overview was switched off.")
    }

    /// Puts the three switches back on, so the classes that run after this one see Today as it was. No assertions: best effort.
    private func restoreSwitches(_ app: XCUIApplication) {
        guard app.state == .runningForeground else { return }
        for _ in 0..<16 where !app.element("today-customize").exists { app.swipeDown() }
        guard app.element("today-customize").exists else { return }
        app.element("today-customize").tap()
        guard app.navigationBars["Customize Today"].waitForExistence(timeout: 20) else { return }
        for id in ["sunday-review", "daily-overview", "my-journal"] where revealRow(id, in: app) {
            let toggle = app.switches["today-customize-block-\(id)"]
            if toggle.value as? String == "0" { flip(toggle) }
        }
        if app.buttons["Save"].exists { app.buttons["Save"].tap() }
    }
}
