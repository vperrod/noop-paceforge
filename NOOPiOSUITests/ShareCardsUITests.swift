import XCTest

/// Simulator checks for the share cards: the images the Share button hands over (made-up figures, attached as PNGs)
/// and the three Share buttons. Data is `--demo-seed` and the synthetic PaceForgeFixture.json.
final class ShareCardsUITests: XCTestCase {
    private func launch(screen: String? = nil, environment: [String: String] = [:]) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
        app.launchArguments.append(contentsOf: ["-theme.appearance", "dark", "-PaceForgeFixture"])
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        for (key, value) in environment { app.launchEnvironment[key] = value }
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

    private func openEditor(_ app: XCUIApplication, button id: String) {
        let button = app.element(id)
        XCTAssertTrue(button.waitForExistence(timeout: 40), "\(id) should be on the screen.")
        button.tap()
        XCTAssertTrue(app.element("share-editor-share").waitForExistence(timeout: 20), "\(id) should open the editor.")
        XCTAssertTrue(app.element("share-editor-card").isSelected, "The editor opens on Card.")
        XCTAssertFalse(app.element("share-editor-change").exists, "Change photo shows only with a photo.")
        attach(app, "ShareCard editor from \(id)")
    }

    func testRendersTheCardImages() throws {
        // A simulator app can write into the test runner's folder: both are processes of the same Mac.
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("share-cards-\(UUID().uuidString)")
        let app = try launch(screen: "sharecards", environment: ["SHARE_CARDS_DIR": folder.path])
        let rendered = app.staticTexts["Rendered"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 40), "The harness should render: \(app.debugDescription)")
        for name in ["day", "workout", "streak", "day-photo"] {
            let data = try Data(contentsOf: folder.appendingPathComponent("\(name).png"))
            XCTAssertGreaterThan(data.count, 10_000, "\(name) should be a real image.")
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "ShareCard render \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testTodayAndHighlightsShareButtonsOpenTheEditorAndTheShareSheet() throws {
        let app = try launch()
        let chip = app.element("look-streak-chip")
        XCTAssertTrue(chip.waitForExistence(timeout: 40), "Today should carry the streak chip.")
        openEditor(app, button: "share-card-today")
        app.element("share-editor-close").tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "Closing the editor should return to Today.")
        chip.tap()
        XCTAssertTrue(app.element("pf-highlights-body").waitForExistence(timeout: 20), "The chip should open Highlights.")
        openEditor(app, button: "share-card-streak")
        app.element("share-editor-share").tap()
        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'ActivityListView' OR label == 'Save Image' OR label == 'Copy'"))
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "Share should open the iOS share sheet.")
        attach(app, "ShareCard iOS share sheet")
    }

    func testWorkoutDetailShareButtonOpensTheEditor() throws {
        let app = try launch(screen: "shareworkout")
        openEditor(app, button: "share-card-workout")
    }
}
