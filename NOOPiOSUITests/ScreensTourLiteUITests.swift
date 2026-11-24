import XCTest

/// A lighter walk of every main screen, scrolled top to bottom, for the simulator-verify workflow (`only=NOOPiOSUITests/ScreensTourLiteUITests`).
/// On Today every element query makes SwiftUI build the whole accessibility tree and the main thread stalls for 20-60 s, which killed
/// `ScreenshotTourUITests`. This tour therefore asks for one element per step at most, scrolls by coordinate drags, shoots the screen itself
/// and makes no query at all while Today is scrolled. The only assertion is that the app launched to the Today tab; whatever is not found
/// is written down as "missing: <id>" and the walk goes on. Screenshot names are `NN-screen-SS` (screen order, scroll step).
final class ScreensTourLiteUITests: XCTestCase {
    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: ["-theme.appearance", "dark"])
        app.launchArguments.append("-PaceForgeFixture")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        app.launch()
        dumpHierarchyOnFailure(app)
        return app
    }

    private func shoot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

    /// A press-and-drag between two points of the screen, then a pause so the page settles before the screenshot.
    private func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func scrollDown(_ app: XCUIApplication) { drag(app, from: 0.75, to: 0.25) }

    /// Back to the top, so the chip bar is on screen again for the next chip.
    private func scrollToTop(_ app: XCUIApplication, drags: Int) {
        for _ in 0..<drags { drag(app, from: 0.25, to: 0.75) }
    }

    /// The first shot of a screen, then one per scroll step, named `<prefix>-00`, `<prefix>-01` ...
    private func shootScrolling(_ app: XCUIApplication, _ prefix: String, steps: Int) {
        shoot("\(prefix)-00")
        for step in 1...steps {
            scrollDown(app)
            shoot(String(format: "\(prefix)-%02d", step))
        }
    }

    /// Taps the element with the identifier when it shows up in time; otherwise records it as missing.
    @discardableResult
    private func tap(_ app: XCUIApplication, _ target: XCUIElement, label: String, timeout: TimeInterval) -> Bool {
        guard target.waitForExistence(timeout: timeout) else { note("missing: \(label)"); return false }
        target.tap()
        return true
    }

    private func tourChips(_ app: XCUIApplication, tab: String, order: Int, prefix: String, screen: String, chips: [String]) {
        guard tap(app, app.shellTab(tab), label: tab, timeout: 60) else { return }
        for (index, chip) in chips.enumerated() {
            guard tap(app, app.element("\(prefix)-chip-\(chip)"), label: "\(prefix)-chip-\(chip)", timeout: 20) else { continue }
            Thread.sleep(forTimeInterval: 4)
            shootScrolling(app, "\(order + index)-\(screen)-\(chip)", steps: 8)
            scrollToTop(app, drags: 10)
        }
    }

    func testTourLite() throws {
        continueAfterFailure = true
        let app = try launch()

        // Today: one query to know the app is up, then coordinates only.
        XCTAssertTrue(app.shellTab("Today").waitForExistence(timeout: 60), "The Today tab should be in the bar.")
        Thread.sleep(forTimeInterval: 8)
        shootScrolling(app, "01-today", steps: 16)
        scrollToTop(app, drags: 20)
        Thread.sleep(forTimeInterval: 5)

        tourChips(app, tab: "Plan", order: 10, prefix: "calendar", screen: "plan", chips: ["week", "reports", "calendar", "season"])
        tourChips(app, tab: "Train", order: 20, prefix: "train", screen: "train", chips: ["hyrox", "running", "strength", "bike", "workouts", "athlete"])
        tourChips(app, tab: "Health", order: 30, prefix: "health", screen: "health", chips: ["day", "sleep", "recovery", "body", "vitals", "journal", "trends"])
        tourCoach(app)
        // The Journal sheet has no identifier reachable from Today or Health without a query on a scrolled page (it opens through
        // `-Plan529Open journal-morning` or Today's lazy `today-journal-fill`), so it is not walked; Health > Journal is.
        note("skipped: journal sheet (Health > Journal is in the tour)")
    }

    /// The Coach button opens a sheet; its three chips are walked, then the sheet is dragged down to close it.
    private func tourCoach(_ app: XCUIApplication) {
        guard tap(app, app.coachButton, label: "look-coach", timeout: 30) else { return }
        Thread.sleep(forTimeInterval: 4)
        shootScrolling(app, "40-coach", steps: 5)
        scrollToTop(app, drags: 6)
        for (index, chip) in ["read", "ask", "insights"].enumerated() {
            guard tap(app, app.element("coach-chip-\(chip)"), label: "coach-chip-\(chip)", timeout: 20) else { continue }
            Thread.sleep(forTimeInterval: 4)
            shootScrolling(app, "4\(index + 1)-coach-\(chip)", steps: 5)
            scrollToTop(app, drags: 6)
        }
        drag(app, from: 0.15, to: 0.9)
    }
}
