import XCTest

/// Builds 465 and 466 crashed on a real iPhone that had been running build 464; the simulator, which starts with no saved
/// state, never did. These tests start the app from what a 464 phone held (the app's DEBUG seed `-NoopSeedBuild464State`:
/// the Today order and hidden sections, the PaceForge arrangement and "Not today" list, and the PaceForge documents saved
/// for offline use WITHOUT the daily-intel and Phase 4 documents), and from damaged copies of all of it
/// (`-NoopSeedDamagedState`). Each step only checks that the app is still running, so a crash names the step that caused
/// it; the CI step after the run prints the crash report.
final class SavedStateUITests: XCTestCase {

    private func launch(_ extra: [String]) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extra)
        app.launchArguments.append("-PaceForgeFixture")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeRealShapes", withExtension: "json"),
                                "The real-shape fixture should be bundled with the UI tests.")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var files = try XCTUnwrap(root["docs"] as? [String: Any])
        files["today"] = root["today"]
        let data = try JSONSerialization.data(withJSONObject: files)
        app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: data, as: UTF8.self)
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

    private func alive(_ app: XCUIApplication, _ step: String) {
        XCTAssertEqual(app.state, .runningForeground, "The app is no longer running after: \(step)")
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openPaceForge(_ app: XCUIApplication) -> XCUIElement {
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 30), "The PaceForge segmented control should load.")
        return segments
    }

    private func walkSegments(_ app: XCUIApplication, _ segments: XCUIElement, _ name: String) {
        for title in ["Today", "Coach", "This week", "Insights", "Body"] {
            let button = segments.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "The \(title) segment should exist.")
            button.tap()
            if !button.isSelected { button.tap() }
            Thread.sleep(forTimeInterval: 2)
            alive(app, "\(name): opening \(title)")
            attach(app, "\(name) \(title)")
            for step in 0..<6 {
                app.swipeUp()
                alive(app, "\(name): \(title) scroll down \(step + 1)")
            }
            for _ in 0..<6 { app.swipeDown() }
            alive(app, "\(name): \(title) scroll back up")
        }
    }

    private func scrollToday(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 5)
        alive(app, "\(name): opening NOOP Today")
        attach(app, "\(name) NOOP Today")
        for step in 0..<10 {
            app.swipeUp()
            alive(app, "\(name): NOOP Today scroll down \(step + 1)")
        }
        attach(app, "\(name) NOOP Today bottom")
    }

    // MARK: Build 464 state, the PaceForge server not answering (the phone shows only what 464 saved)

    func testTabOpensFromTheBuild464SavedDocumentsWhileOffline() throws {
        let app = try launch(["-NoopSeedBuild464State", "-PaceForgeFetchFails"])
        let segments = openPaceForge(app)
        XCTAssertTrue(element(app, "pf-offline-banner").waitForExistence(timeout: 30),
                      "With the server unreachable the tab should say it shows saved data.")
        walkSegments(app, segments, "Build464 offline")
    }

    // MARK: Build 464 state, then the live documents arrive

    func testTabMovesFromTheBuild464SavedDocumentsToTheLiveOnes() throws {
        let app = try launch(["-NoopSeedBuild464State"])
        let segments = openPaceForge(app)
        Thread.sleep(forTimeInterval: 3)
        alive(app, "opening the tab on the saved documents")
        walkSegments(app, segments, "Build464 live")
    }

    func testTodayInTheEveningFromTheBuild464State() throws {
        let app = try launch(["-NoopSeedBuild464State", "-PaceForgeEvening"])
        let segments = openPaceForge(app)
        segments.buttons["Today"].tap()
        Thread.sleep(forTimeInterval: 3)
        alive(app, "opening PaceForge Today in the evening")
        attach(app, "Build464 evening Today")
        for step in 0..<8 {
            app.swipeUp()
            alive(app, "Build464 evening Today scroll \(step + 1)")
        }
    }

    func testArrangingTheBuild464TodayStillWorks() throws {
        let app = try launch(["-NoopSeedBuild464State"])
        let segments = openPaceForge(app)
        segments.buttons["Today"].tap()
        let customise = element(app, "pf-today-customise")
        XCTAssertTrue(customise.waitForExistence(timeout: 20), "Today should offer Customise.")
        customise.tap()
        Thread.sleep(forTimeInterval: 1)
        alive(app, "turning Customise on")
        let downs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "pf-arrange-down-"))
        for index in 0..<min(downs.count, 4) {
            let button = downs.element(boundBy: index)
            if button.exists && button.isHittable && button.isEnabled { button.tap() }
            alive(app, "moving card \(index) down")
        }
        attach(app, "Build464 arranged Today")
        customise.tap()
        alive(app, "turning Customise off")
    }

    // MARK: Build 464 state on NOOP Today and the other tabs

    func testNoopTodayFromTheBuild464State() throws {
        let app = try launch(["-NoopSeedBuild464State"])
        scrollToday(app, "Build464")
    }

    func testEveryTabOpensFromTheBuild464State() throws {
        let app = try launch(["-NoopSeedBuild464State"])
        for title in ["Workouts", "Sleep", "More", "Today"] {
            let tab = app.shellTab(title)
            XCTAssertTrue(tab.waitForExistence(timeout: 30), "The \(title) tab should be present.")
            tab.tap()
            Thread.sleep(forTimeInterval: 2)
            alive(app, "opening the \(title) tab")
            attach(app, "Build464 \(title) tab")
        }
    }

    // MARK: Damaged saved state

    func testTabSurvivesDamagedSavedState() throws {
        let app = try launch(["-NoopSeedDamagedState", "-PaceForgeFetchFails"])
        let segments = openPaceForge(app)
        walkSegments(app, segments, "Damaged offline")
    }

    func testTabSurvivesDamagedSavedStateThenLiveDocuments() throws {
        let app = try launch(["-NoopSeedDamagedState"])
        let segments = openPaceForge(app)
        Thread.sleep(forTimeInterval: 3)
        alive(app, "opening the tab on damaged saved documents")
        walkSegments(app, segments, "Damaged live")
    }

    func testNoopTodayFromDamagedSavedState() throws {
        let app = try launch(["-NoopSeedDamagedState"])
        scrollToday(app, "Damaged")
    }
}
