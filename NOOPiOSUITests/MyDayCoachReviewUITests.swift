import XCTest

/// Simulator check for the coach review on a workout opened from My Day. My Day is the made-up day (`-MyDayFixture full`) and
/// PaceForge is the synthetic fixture with one extra Garmin run at 07:10 on that day and its coach analysis (`-PaceForgeMyDayRun`).
/// Nothing here is real data.
final class MyDayCoachReviewUITests: XCTestCase {

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func text(_ app: XCUIApplication, containing fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    func testAWorkoutOpenedFromMyDayShowsTheCoachReview() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "-MyDayFixture", "full", "-PaceForgeFixture", "-PaceForgeMyDayRun"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic PaceForge fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        app.launch()
        dumpHierarchyOnFailure(app)

        app.openChip("Health", "day")
        XCTAssertTrue(element(app, "myday-strip").waitForExistence(timeout: 20), "My Day should draw its 24 h strip.")
        let row = element(app, "myday-row-workout-garmin")
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists && row.isHittable, "The run should be listed on My Day.")
        row.tap()

        let review = element(app, "workout-coach-review")
        XCTAssertTrue(review.waitForExistence(timeout: 20), "The workout opened from My Day should carry the coach review.")
        XCTAssertTrue(text(app, containing: "Synthetic My Day verdict").waitForExistence(timeout: 20),
                      "The coach's verdict on the run should be visible.")
        XCTAssertTrue(text(app, containing: "Keep the first kilometre easier").waitForExistence(timeout: 10),
                      "The coach's written analysis should be visible under the verdict.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "60 My Day workout coach review"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
