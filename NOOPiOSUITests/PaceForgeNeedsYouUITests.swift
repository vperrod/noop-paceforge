import XCTest

/// Simulator checks for Needs you on NOOP Today: a 44 pt row (`pf-needs-row`) that opens a sheet holding the whole card
/// (`pf-needs-card`). They serve the synthetic PaceForgeFixture.json (made-up values only): `-PaceForgeNeedsYou` switches on the list
/// in `data/needs-you.active.json`, and the `api/app/answer` entry stands in for the server's reply to an answer.
final class PaceForgeNeedsYouUITests: XCTestCase {
    private func launch(_ extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append("-PaceForgeFixture")
        app.launchArguments.append(contentsOf: extraArguments)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.shellTab("Today").waitForExistence(timeout: 20), "NOOP Today should be on screen.")
        return app
    }

    /// Taps the Needs you row and waits for the sheet's card.
    private func openSheet(_ app: XCUIApplication) {
        let row = element(app, "pf-needs-row")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Today should lead with the Needs you row.")
        row.tap()
        XCTAssertTrue(element(app, "pf-needs-card").waitForExistence(timeout: 10), "The row should open the Needs you card.")
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

    /// Scrolls until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    func testNoRowWhenNothingIsWaiting() throws {
        let app = try launch()
        XCTAssertFalse(element(app, "pf-needs-row").waitForExistence(timeout: 8), "With nothing waiting there is no Needs you row.")
        XCTAssertFalse(element(app, "pf-needs-card").exists, "With nothing waiting there is no Needs you card.")
    }

    func testRowOpensTheSheetWithEveryKindAndAnsweringEverythingClosesIt() throws {
        let app = try launch(["-PaceForgeNeedsYou"])
        openSheet(app)
        attach(app, "Needs you sheet")

        // Treadmill: Save waits for a valid number inside the server's limits.
        let save = element(app, "pf-needs-save-treadmill_pace:9100000001")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save is off while the speed is empty.")
        XCTAssertTrue(element(app, "pf-needs-same-treadmill_pace:9100000001").exists, "Same as last treadmill run is offered.")
        XCTAssertTrue(element(app, "pf-needs-unknown-treadmill_pace:9100000001").exists, "Don't know is offered.")
        let speed = element(app, "pf-needs-speed-treadmill_pace:9100000001")
        speed.tap()
        speed.typeText("30")
        XCTAssertFalse(save.isEnabled, "30 km/h is outside the belt's limits.")
        speed.typeText("\u{8}\u{8}11.6")
        XCTAssertTrue(save.isEnabled, "11.6 km/h is a valid speed.")
        // The keyboard covers the lower half of the screen, where the scroll drags start.
        let done = app.keyboards.buttons["return"]
        if done.exists { done.tap() }

        // A proposal is one line with Accept and Dismiss; accepting it removes it and keeps the rest.
        let accept = element(app, "pf-needs-accept-proposal:synth01")
        XCTAssertTrue(reveal(accept, in: app), "The proposal has an Accept button.")
        accept.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: accept)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(element(app, "pf-needs-card").exists, "The other items are still waiting.")
        attach(app, "After accepting the proposal")

        // Effort 1-10 and feel 1-5 are one tap each; Don't know answers the treadmill run. The last answer closes the sheet.
        let rpe = element(app, "pf-needs-rpe-7-rpe:9100000002")
        XCTAssertTrue(reveal(rpe, in: app), "The effort row has a 7.")
        rpe.tap()
        let feel = element(app, "pf-needs-feel-4-feel:2030-03-13")
        XCTAssertTrue(reveal(feel, in: app), "The feel row has a 4.")
        feel.tap()
        let unknown = element(app, "pf-needs-unknown-treadmill_pace:9100000001")
        XCTAssertTrue(reveal(unknown, in: app), "The treadmill row has Don't know.")
        unknown.tap()
        expectation(for: gone, evaluatedWith: element(app, "pf-needs-sheet-done"))
        waitForExpectations(timeout: 10)
        XCTAssertFalse(element(app, "pf-needs-row").exists, "With everything answered the row is gone too.")
        attach(app, "After the last answer")
    }

    func testFailedAnswerBringsTheRowBackWithAReason() throws {
        let app = try launch(["-PaceForgeNeedsYou", "-PaceForgeAnswerFails"])
        openSheet(app)
        let dismiss = element(app, "pf-needs-dismiss-proposal:synth01")
        XCTAssertTrue(reveal(dismiss, in: app), "The proposal has a Dismiss button.")
        dismiss.tap()
        XCTAssertTrue(element(app, "pf-needs-error-proposal:synth01").waitForExistence(timeout: 10),
                      "A failed answer says why.")
        XCTAssertTrue(element(app, "pf-needs-dismiss-proposal:synth01").exists, "The proposal is back to answer again.")
        attach(app, "After a failed answer")
    }
}
