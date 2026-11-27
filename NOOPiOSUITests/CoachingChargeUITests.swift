import XCTest

/// Coaching reads the WHOOP strap's Charge, and reports carry Garmin's beside it as a labelled reference. The app's
/// `--demo-screen coachingcharge` merges made-up days (every strap Charge is 40) and prints what each side reads.
final class CoachingChargeUITests: XCTestCase {
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "--demo-screen", "coachingcharge"])
        app.launchEnvironment["COACHING_SCENARIO"] = scenario
        app.launch()
        dumpHierarchyOnFailure(app)
        let status = app.staticTexts["cc-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 60), "The harness should finish.")
        XCTAssertEqual(status.label, "Done")
        return app
    }

    private func text(_ app: XCUIApplication, _ id: String) -> String { app.staticTexts["cc-\(id)"].label }

    func testCoachingReadsWhoopOnADayGarminLeads() {
        let app = launch(scenario: "led")
        let garmin = text(app, "garmin-today")
        XCTAssertNotEqual(garmin, "40")
        XCTAssertEqual(text(app, "merged-today"), garmin, "Precondition: Garmin leads the merged day.")
        XCTAssertEqual(text(app, "coaching-today"), "40")
        XCTAssertTrue(text(app, "coach-today").contains(": charge 40, Garmin Charge \(garmin) (reference only), "),
                      text(app, "coach-today"))
    }

    func testAMissingWhoopDayStaysMissing() {
        let app = launch(scenario: "missing")
        let garmin = text(app, "garmin-today")
        XCTAssertEqual(text(app, "merged-today"), garmin, "Precondition: the merged day carries Garmin's Charge.")
        XCTAssertEqual(text(app, "coaching-today"), "missing")
        XCTAssertTrue(text(app, "coach-today").contains(": charge —, Garmin Charge \(garmin) (reference only), "),
                      text(app, "coach-today"))
        XCTAssertTrue(text(app, "coach-average").hasPrefix("charge: 40, "), text(app, "coach-average"))
    }

    func testReportsCarryBothLabelledAndNeverABlend() {
        let app = launch(scenario: "led")
        XCTAssertTrue(text(app, "coach-yesterday")
            .contains(": charge 40, Garmin Charge \(text(app, "garmin-yesterday")) (reference only), "),
                      text(app, "coach-yesterday"))
        XCTAssertTrue(text(app, "coach-average").hasPrefix("charge: 40, "), text(app, "coach-average"))
        // The strap's figure stays exactly 40 beside a different Garmin one: nothing is blended.
        let reference = "Garmin Charge (?!40 )\\d+ \\(reference only\\)"
        for (id, pattern) in [("coach-garmin-average", reference),
                              ("digest", "Charge 40 \\| \(reference)"),
                              ("report", "Charge 40 \\| \(reference)")] {
            XCTAssertNotNil(text(app, id).range(of: "^\(pattern)$", options: .regularExpression), "\(id): \(text(app, id))")
        }
    }
}
