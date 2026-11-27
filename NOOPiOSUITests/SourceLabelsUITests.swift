import XCTest

/// Screens that carry both devices name each one, and WHOOP-only and all-source figures say so. They run on the demo
/// seed with `--demo-garmin-vitals`: every figure is made up. Each test keeps a screenshot of its screen.
final class SourceLabelsUITests: XCTestCase {

    private func launch(_ screen: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "--demo-garmin-vitals"])
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
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

    /// The first element whose label contains `text`.
    private func labelled(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Scrolls down until the element is on screen.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 20) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    func testTodayShowsEachVitalUnderItsDevice() {
        let app = launch("today")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sleep(8)
        attach(app, "A1 Today top")
        // The Key Metrics HRV tile carries the strap's reading with Garmin's on a line of its own. ("Garmin" alone would
        // also match the PaceForge rings' caption at the top of Today.)
        let garmin = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "(?s).*Garmin [0-9]+ ms.*")).firstMatch
        XCTAssertTrue(reveal(garmin, in: app, maxSwipes: 30), "Today should give Garmin's HRV beside the strap's.")
        attach(app, "A1 Today vitals by source")
    }

    func testHealthTrendsDrawTwoNamedSeries() {
        let app = launch("trends")
        app.openSection("trends-hrv")
        let average = labelled(app, "Average WHOOP")
        XCTAssertTrue(average.waitForExistence(timeout: 20), "HRV should give each device's own average.")
        XCTAssertTrue(average.label.contains("Garmin"), average.label)
        app.swipeUp()
        attach(app, "A2 Trends HRV two series")
        app.openSection("trends-rhr")
        app.swipeUp()
        attach(app, "A2 Trends resting HR two series")
    }

    func testSleepSaysItsFiguresAreWhoopAndSplitsDuration() {
        let app = launch("sleep")
        let note = app.element("sleep-source-note")
        XCTAssertTrue(note.waitForExistence(timeout: 30), "Sleep should say its figures come from WHOOP nights.")
        reveal(note, in: app)
        attach(app, "A3 Sleep source note")
        let duration = labelled(app, "Hours asleep trend")
        reveal(duration, in: app, maxSwipes: 30)
        attach(app, "A2 Sleep duration two series")
    }

    func testWorkoutTotalsSayAllSources() {
        let app = launch("workouts")
        let note = labelled(app, "These totals add up workouts from every source")
        XCTAssertTrue(note.waitForExistence(timeout: 30), "Workout totals should say they cover every source.")
        reveal(note, in: app)
        attach(app, "A4 Workout totals all sources")
    }

    func testTheStreakCardSaysItCountsWhoopCharge() {
        let app = launch("settings")
        let note = labelled(app, "Counts days with a WHOOP Charge only")
        XCTAssertTrue(reveal(note, in: app), "The streak should say it counts WHOOP Charge days only.")
        attach(app, "A4 Charge streak")
    }

    func testBodyAgeNamesItsSourceAndPointsToHealthspan() {
        let app = launch("health")
        app.openSection("vitals-body-age")
        let row = app.element("vitals-pace-in-healthspan")
        XCTAssertTrue(reveal(row, in: app, maxSwipes: 30), "Body age should point to Healthspan for the pace of aging.")
        attach(app, "P1 Body age pace pointer")
    }
}
