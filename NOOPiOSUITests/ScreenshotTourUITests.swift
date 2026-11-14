import XCTest

/// Walks every main screen once and attaches a named screenshot of each, so a reviewer can see the app before a build is installed.
/// Run it with the simulator-verify workflow: `only=NOOPiOSUITests/ScreenshotTourUITests`. Only the launch, the four tabs and the Coach button are
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
        for title in ["Plan", "Train", "Health"] {
            XCTAssertTrue(app.shellTab(title).exists, "The \(title) tab should be in the bar.")
        }
        if !element(app, "pf-today-cards").waitForExistence(timeout: 30) { note("missing: pf-today-cards") }
        shoot(app, ["01-today-top", "02-today-scroll1", "03-today-scroll2", "04-today-scroll3", "05-today-scroll4"])

        tourRings(app)

        // Plan
        app.shellTab("Plan").tap()
        XCTAssertTrue(element(app, "calendar-host").waitForExistence(timeout: 30), "The Plan screen should open.")
        if tapIfThere(app, "calendar-chip-thisWeek") { attach(app, "10-plan-this-week") }
        openRace(app)
        if tapIfThere(app, "calendar-chip-nextWeek") { attach(app, "11-plan-next-week") }
        if tapIfThere(app, "calendar-chip-calendar") { attach(app, "12-plan-calendar") }
        if tapIfThere(app, "calendar-chip-season") {
            shoot(app, ["13-plan-season", "13-plan-season-scrolled"])
        }

        // Train
        app.shellTab("Train").tap()
        XCTAssertTrue(element(app, "train-host").waitForExistence(timeout: 30), "The Train screen should open.")
        for (index, chip) in ["hyrox", "running", "strength", "bike", "workouts", "athlete"].enumerated() {
            if tapIfThere(app, "train-chip-\(chip)") { attach(app, "2\(index)-train-\(chip)") }
        }

        // Health
        app.shellTab("Health").tap()
        XCTAssertTrue(element(app, "health-host").waitForExistence(timeout: 30), "The Health screen should open.")
        for (index, chip) in ["day", "sleep", "recovery", "body", "vitals", "journal", "trends"].enumerated() {
            if tapIfThere(app, "health-chip-\(chip)") { attach(app, "3\(index)-health-\(chip)") }
        }

        // Coach: the button beside the bar opens it as a sheet over the screen on show.
        let coach = app.coachButton
        XCTAssertTrue(coach.waitForExistence(timeout: 30), "The Coach button should be beside the bar.")
        coach.tap()
        if !element(app, "coach-host").waitForExistence(timeout: 30) { note("missing: coach-host") }
        attach(app, "40-coach")
        for (index, chip) in ["read", "ask", "reports", "insights"].enumerated() {
            if tapIfThere(app, "coach-chip-\(chip)", timeout: 5) { attach(app, "4\(index + 1)-coach-\(chip)") }
        }
    }

    /// Today's six rings, one at a time: the ring opens its page (a pushed detail for NOOP's three, a sheet for PaceForge's three), a
    /// screenshot, then back. Every step is optional: a ring or page that is not found is noted and the tour goes on.
    private func tourRings(_ app: XCUIApplication) {
        // (ring identifier from SixRingSpec, what its page marks itself with, screenshot name)
        let rings: [(ring: String, page: String, shot: String)] = [
            ("six-rings-noop-rest", "look-score-detail-rest", "06-ring-rest"),
            ("six-rings-noop-charge", "look-score-detail-charge", "07-ring-charge"),
            ("six-rings-noop-effort", "look-score-detail-effort", "08-ring-effort"),
            ("six-rings-pf-recovery", "pf-ring-detail-recovery", "09a-ring-pf-recovery"),
            ("six-rings-pf-sleep", "pf-ring-detail-sleep", "09b-ring-pf-sleep"),
            ("six-rings-pf-strain", "pf-ring-detail-strain", "09c-ring-pf-strain"),
        ]
        for item in rings {
            let cell = element(app, item.ring)
            for _ in 0..<8 where !(cell.exists && cell.isHittable) { app.swipeDown() }
            guard cell.exists, cell.isHittable else { note("missing: \(item.ring)"); continue }
            // The ring is the cell's first button (its name, a second button, sits under it).
            let ring = cell.buttons.firstMatch
            if ring.exists, ring.isHittable {
                ring.tap()
            } else {
                cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            }
            if !element(app, item.page).waitForExistence(timeout: 15) { note("missing: \(item.page)") }
            attach(app, item.shot)
            leaveRingPage(app)
        }
    }

    /// Closes a ring's page: the PaceForge sheet's Done button, else the pushed page's back button. A tour that is still not on Today
    /// after that taps the Today tab (or swipes a sheet away), so one miss cannot strand the rest of the tour.
    private func leaveRingPage(_ app: XCUIApplication) {
        let done = app.buttons["pf-ring-detail-done"]
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if done.exists {
            done.tap()
        } else if back.exists {
            back.tap()
        }
        if element(app, "today-six-rings").waitForExistence(timeout: 5) { return }
        app.swipeDown()
        let today = app.shellTab("Today")
        if today.exists, today.isHittable { today.tap() }
        if !element(app, "today-six-rings").waitForExistence(timeout: 5) { note("missing: way back to Today after a ring page") }
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
        attach(app, "15-race-results")
        app.swipeUp()
        attach(app, "16-race-results-scrolled")
        done.tap()
        for _ in 0..<6 { app.swipeDown() }
    }
}
