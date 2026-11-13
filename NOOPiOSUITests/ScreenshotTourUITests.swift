import XCTest

/// Walks every main screen once and attaches a named screenshot of each, so a reviewer can see the app before a build is installed.
/// Run it with the simulator-verify workflow: `only=NOOPiOSUITests/ScreenshotTourUITests`. Only the launch and the five tabs are
/// assertions; a chip, a row or a sheet that is not found is written down as "missing: <id>" and the tour goes on.
final class ScreenshotTourUITests: XCTestCase {
    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: ["-theme.appearance", "dark"])
        app.launchArguments.append("-PaceForgeFixture")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        app.launch()
        dumpHierarchyOnFailure(app)
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = text
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps the element when it shows up in time; otherwise records it as missing and returns false.
    @discardableResult
    private func tapIfThere(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 15) -> Bool {
        let target = element(app, id)
        guard target.waitForExistence(timeout: timeout) else { note("missing: \(id)"); return false }
        target.tap()
        return true
    }

    /// One screenshot, then `scrolls` more after a swipe up each, named `<prefix>-<n>`-style by the caller's list.
    private func shoot(_ app: XCUIApplication, _ names: [String]) {
        for (index, name) in names.enumerated() {
            if index > 0 { app.swipeUp() }
            attach(app, name)
        }
    }

    func testTour() throws {
        let app = try launch()

        // Today
        let today = app.shellTab("Today")
        XCTAssertTrue(today.waitForExistence(timeout: 30), "The Today tab should be in the bar.")
        for title in ["Plan", "Coach", "Reports", "Body"] {
            XCTAssertTrue(app.shellTab(title).exists, "The \(title) tab should be in the bar.")
        }
        if !element(app, "pf-today-cards").waitForExistence(timeout: 30) { note("missing: pf-today-cards") }
        shoot(app, ["01-today-top", "02-today-scroll1", "03-today-scroll2", "04-today-scroll3", "05-today-scroll4"])

        // Plan
        app.shellTab("Plan").tap()
        XCTAssertTrue(element(app, "calendar-host").waitForExistence(timeout: 30), "The Plan screen should open.")
        if tapIfThere(app, "calendar-chip-thisWeek") { attach(app, "10-plan-this-week") }
        openRace(app)
        if tapIfThere(app, "calendar-chip-calendar") { attach(app, "11-plan-calendar") }
        if tapIfThere(app, "calendar-chip-season") {
            shoot(app, ["12-plan-season", "12-plan-season-scrolled"])
        }

        // Coach
        app.shellTab("Coach").tap()
        XCTAssertTrue(element(app, "coach-host").waitForExistence(timeout: 30), "The Coach screen should open.")
        if !element(app, "coach-full-brain").waitForExistence(timeout: 30) { note("missing: coach-full-brain") }
        shoot(app, ["20-coach", "21-coach-scrolled"])

        // Reports
        app.shellTab("Reports").tap()
        XCTAssertTrue(element(app, "reports-host").waitForExistence(timeout: 30), "The Reports screen should open.")
        attach(app, "30-reports")
        if tapIfThere(app, "reports-chip-insights") {
            if !element(app, "insights-host").waitForExistence(timeout: 30) { note("missing: insights-host") }
            attach(app, "31-reports-insights")
            for (index, chip) in ["overview", "trends", "journal", "deepDives"].enumerated() {
                if tapIfThere(app, "insights-chip-\(chip)") { attach(app, "3\(index + 2)-insights-\(chip)") }
            }
        }

        // Body
        app.shellTab("Body").tap()
        XCTAssertTrue(element(app, "body-host").waitForExistence(timeout: 30), "The Body screen should open.")
        shoot(app, ["40-body", "41-body-scrolled"])
    }

    /// Plan > This week: the finished race row of the fixture's week opens the results sheet with the HYROX race layout.
    private func openRace(_ app: XCUIApplication) {
        let row = "pf-week-race-2030-03-12"
        let target = element(app, row)
        for _ in 0..<6 where !(target.exists && target.isHittable) { app.swipeUp() }
        guard target.exists, target.isHittable else { note("missing: \(row)"); return }
        target.tap()
        let done = app.buttons["Done"]
        guard done.waitForExistence(timeout: 15) else { note("missing: results sheet Done button"); return }
        attach(app, "13-race-results")
        app.swipeUp()
        attach(app, "14-race-results-scrolled")
        done.tap()
        for _ in 0..<6 { app.swipeDown() }
    }
}
