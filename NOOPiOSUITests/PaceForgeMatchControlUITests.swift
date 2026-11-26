import XCTest

/// Simulator checks for Plan match on a recording's results (`pf-match-card`). The synthetic fixture's recording 9000000001
/// (2030-03-11) counts as "Synthetic easy run"; the `api/app/job` entry stands in for the server's reply, and the documents do not change.
final class PaceForgeMatchControlUITests: XCTestCase {
    private func openRecording() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-PaceForgeFixture"])
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        app.launch()
        let train = app.shellTab("Train")
        XCTAssertTrue(train.waitForExistence(timeout: 30), "The Train tab should be in the bar.")
        train.tap()
        let chip = app.element("train-chip-workouts")
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "Train should have the Workouts chip.")
        chip.tap()
        let row = app.element("pf-recording-9000000001")
        XCTAssertTrue(reveal(row, in: app), "The recording should be listed.")
        row.tap()
        XCTAssertTrue(reveal(app.element("pf-match-link"), in: app), "The results sheet should offer Plan match.")
        return app
    }

    /// Scrolls until the element can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 20) -> Bool {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLinkingToAnotherSessionWithinAWeek() throws {
        let app = try openRecording()
        XCTAssertTrue(app.element("pf-match-current").label.contains("Synthetic easy run"), "It says what the recording counts as.")
        attach(app, "Plan match")
        app.element("pf-match-session").tap()
        let tempo = app.buttons["2030-03-15 \u{2014} Synthetic tempo"]
        XCTAssertTrue(tempo.waitForExistence(timeout: 10), "A session four days later is offered.")
        XCTAssertFalse(app.buttons["2030-03-20 \u{2014} Synthetic hills"].exists, "A session nine days later is not offered.")
        attach(app, "Plan match choices")
        tempo.tap()
        app.element("pf-match-link").tap()
        XCTAssertTrue(app.element("pf-match-note").waitForExistence(timeout: 15), "The link is confirmed.")
        XCTAssertTrue(app.navigationBars["Synthetic tempo"].waitForExistence(timeout: 10), "The sheet now shows the linked session.")
        attach(app, "Plan match linked")
    }

    func testUnmatch() throws {
        let app = try openRecording()
        let unmatch = app.element("pf-match-unlink")
        XCTAssertTrue(reveal(unmatch, in: app), "A matched recording offers Unmatch.")
        unmatch.tap()
        let note = app.element("pf-match-note")
        XCTAssertTrue(note.waitForExistence(timeout: 15), "Unmatch is confirmed.")
        XCTAssertEqual(note.label, "Unmatched. Plan updated.")
    }
}
