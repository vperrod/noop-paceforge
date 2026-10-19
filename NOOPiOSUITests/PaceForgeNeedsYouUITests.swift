import XCTest

/// Simulator checks for the Needs you card on PaceForge Today. They serve the synthetic PaceForgeFixture.json
/// (made-up values only): `-PaceForgeNeedsYou` switches on the list in `data/needs-you.active.json`, and the
/// `api/app/answer` entry stands in for the server's reply to an answer.
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
        let tab = app.shellTab("PaceForge")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        let today = segments.buttons["Today"]
        today.tap()
        // The segment is remembered between launches; a tap that lands while the previous one is restored is lost.
        if !today.isSelected { today.tap() }
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

    func testNoCardWhenNothingIsWaiting() throws {
        let app = try launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Daily briefing")).firstMatch
            .waitForExistence(timeout: 15), "Today should have loaded.")
        XCTAssertFalse(element(app, "pf-needs-card").exists, "With nothing waiting the Needs you card is not shown.")
    }

    func testCardShowsEveryKindAndAcceptingAProposalRemovesIt() throws {
        let app = try launch(["-PaceForgeNeedsYou"])
        XCTAssertTrue(element(app, "pf-needs-card").waitForExistence(timeout: 15), "The Needs you card should lead Today.")
        attach(app, "Needs you card")

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

        // Effort 1-10 and feel 1-5 are one tap each.
        XCTAssertTrue(reveal(element(app, "pf-needs-rpe-7-rpe:9100000002"), in: app), "The effort row has a 7.")
        XCTAssertTrue(reveal(element(app, "pf-needs-feel-4-feel:2030-03-13"), in: app), "The feel row has a 4.")

        // A proposal is one line with Accept and Dismiss; accepting it removes it and keeps the rest.
        let accept = element(app, "pf-needs-accept-proposal:synth01")
        XCTAssertTrue(reveal(accept, in: app), "The proposal has an Accept button.")
        accept.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: accept)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(element(app, "pf-needs-card").exists, "The other items are still waiting.")
        attach(app, "After accepting the proposal")
    }

    func testFailedAnswerBringsTheRowBackWithAReason() throws {
        let app = try launch(["-PaceForgeNeedsYou", "-PaceForgeAnswerFails"])
        XCTAssertTrue(element(app, "pf-needs-card").waitForExistence(timeout: 15))
        let dismiss = element(app, "pf-needs-dismiss-proposal:synth01")
        XCTAssertTrue(reveal(dismiss, in: app), "The proposal has a Dismiss button.")
        dismiss.tap()
        XCTAssertTrue(element(app, "pf-needs-error-proposal:synth01").waitForExistence(timeout: 10),
                      "A failed answer says why.")
        XCTAssertTrue(element(app, "pf-needs-dismiss-proposal:synth01").exists, "The proposal is back to answer again.")
        attach(app, "After a failed answer")
    }
}
