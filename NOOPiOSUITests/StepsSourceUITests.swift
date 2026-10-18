import XCTest

/// Simulator check for the steps source label. `--demo-garmin-steps` (DEBUG builds only) makes the made-up
/// account's Apple Health steps stop 14 days ago while a Garmin daily row carries the steps for those days, so
/// Today's steps tile has no Apple count and must show the Garmin one, labelled "Garmin", instead of going
/// blank. Nothing here is real data.
final class StepsSourceUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "--demo-garmin-steps"]
        app.launch()
        dumpHierarchyOnFailure(app)
        return app
    }

    func testStepsTileShowsTheGarminCountWhenAppleHealthHasNoStepsForTheDay() {
        let app = launch()
        let label = app.staticTexts["Garmin"]
        for _ in 0..<10 where !label.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(label.exists, "The steps tile should name Garmin as the source of the count.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "31 Steps from Garmin"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testStepsTileShowsTheFixtureCountNotADash() {
        let app = launch()
        let figure = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@",
                                 "9,119", "9.119", "9119")
        let count = app.staticTexts.matching(figure).firstMatch
        for _ in 0..<10 where !count.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(count.exists, "The tile should print the Garmin figure, 9,119 steps.")
    }
}
