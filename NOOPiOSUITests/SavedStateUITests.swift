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

    /// Back to the top of the screen on show by swiping down, but only until `top` (a chip at the top of the screen) can be tapped: a swipe
    /// down at the top of the Coach sheet would dismiss it.
    private func scrollBack(_ app: XCUIApplication, to top: XCUIElement) {
        for _ in 0..<10 where !(top.exists && top.isHittable) { app.swipeDown() }
    }

    /// One screen: look at it, scroll down to its end, and come back up.
    private func visit(_ app: XCUIApplication, _ name: String, _ title: String, top: String) {
        Thread.sleep(forTimeInterval: 2)
        alive(app, "\(name): opening \(title)")
        attach(app, "\(name) \(title)")
        for step in 0..<6 {
            app.swipeUp()
            alive(app, "\(name): \(title) scroll down \(step + 1)")
        }
        scrollBack(app, to: element(app, top))
        alive(app, "\(name): \(title) scroll back up")
    }

    /// The screens that hold PaceForge's documents: Today, Plan > This week, Health > Body, then the three chips of the Coach sheet.
    private func walkScreens(_ app: XCUIApplication, _ name: String) {
        app.openTab("Today")
        visit(app, name, "Today", top: "today-six-rings")
        app.openChip("Plan", "week")
        visit(app, name, "This week", top: "calendar-chip-week")
        app.openChip("Health", "body")
        visit(app, name, "Body", top: "health-chip-body")
        app.openCoach("read")
        visit(app, name, "Coach Read", top: "coach-chip-read")
        for chip in ["ask", "insights"] {
            let button = element(app, "coach-chip-\(chip)")
            XCTAssertTrue(button.waitForExistence(timeout: 10), "The \(chip) chip should exist.")
            button.tap()
            visit(app, name, "Coach \(chip)", top: "coach-chip-read")
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

    func testScreensOpenFromTheBuild464SavedDocumentsWhileOffline() throws {
        let app = try launch(["-NoopSeedBuild464State", "-PaceForgeFetchFails"])
        app.openTab("Today")
        XCTAssertTrue(element(app, "pf-offline-banner").waitForExistence(timeout: 30),
                      "With the server unreachable Today should say it shows saved data.")
        walkScreens(app, "Build464 offline")
    }

    // MARK: Build 464 state, then the live documents arrive

    func testScreensMoveFromTheBuild464SavedDocumentsToTheLiveOnes() throws {
        let app = try launch(["-NoopSeedBuild464State"])
        app.openTab("Today")
        Thread.sleep(forTimeInterval: 3)
        alive(app, "opening Today on the saved documents")
        walkScreens(app, "Build464 live")
    }

    func testTodayInTheEveningFromTheBuild464State() throws {
        let app = try launch(["-NoopSeedBuild464State", "-PaceForgeEvening"])
        app.openTab("Today")
        Thread.sleep(forTimeInterval: 3)
        alive(app, "opening Today in the evening")
        attach(app, "Build464 evening Today")
        for step in 0..<8 {
            app.swipeUp()
            alive(app, "Build464 evening Today scroll \(step + 1)")
        }
    }

    // MARK: Build 464 state on Today and the other tabs (Customise is gone: 622ffedd fixed the order of Today's cards)

    func testNoopTodayFromTheBuild464State() throws {
        let app = try launch(["-NoopSeedBuild464State"])
        scrollToday(app, "Build464")
    }

    func testEveryTabOpensFromTheBuild464State() throws {
        let app = try launch(["-NoopSeedBuild464State"])
        for title in ["Plan", "Train", "Health", "Today"] {
            let tab = app.shellTab(title)
            XCTAssertTrue(tab.waitForExistence(timeout: 30), "The \(title) tab should be present.")
            tab.tap()
            Thread.sleep(forTimeInterval: 2)
            alive(app, "opening the \(title) tab")
            attach(app, "Build464 \(title) tab")
        }
    }

    // MARK: Damaged saved state

    func testScreensSurviveDamagedSavedState() throws {
        let app = try launch(["-NoopSeedDamagedState", "-PaceForgeFetchFails"])
        app.openTab("Today")
        walkScreens(app, "Damaged offline")
    }

    func testScreensSurviveDamagedSavedStateThenLiveDocuments() throws {
        let app = try launch(["-NoopSeedDamagedState"])
        app.openTab("Today")
        Thread.sleep(forTimeInterval: 3)
        alive(app, "opening Today on damaged saved documents")
        walkScreens(app, "Damaged live")
    }

    func testNoopTodayFromDamagedSavedState() throws {
        let app = try launch(["-NoopSeedDamagedState"])
        scrollToday(app, "Damaged")
    }
}
