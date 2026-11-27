import XCTest

/// Simulator checks for the share cards: the images the Share button hands over (made-up figures, attached as PNGs)
/// the three Share buttons, and the editor's photo card through Apple's picker and Save Image. Data is `--demo-seed` and the synthetic PaceForgeFixture.json.
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

    /// Apple's picker, with the simulator's own sample pictures in it.
    private func pickPhoto(_ app: XCUIApplication, at index: Int) {
        let photos = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info' OR label BEGINSWITH 'Photo, '"))
        XCTAssertTrue(photos.element(boundBy: index).waitForExistence(timeout: 30), "The photo picker should list pictures.")
        // The picker runs in its own process: a tap on the picture's place works where a hit test does not.
        photos.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func cancelPicker(_ app: XCUIApplication) {
        let cancel = app.buttons
            .matching(NSPredicate(format: "(label == 'Cancel' OR label == 'Close') AND identifier != 'share-editor-close'"))
            .firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), "The photo picker should have a way out.")
        cancel.tap()
    }

    private func waitUntilHittable(_ element: XCUIElement, _ message: String) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                                 object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 30), .completed, message)
    }

    func testPhotoCardChangePhotoCancelAndSaveImage() throws {
        let app = try launch()
        openEditor(app, button: "share-card-today")
        let card = app.element("share-editor-card")
        let photo = app.element("share-editor-photo")
        let change = app.element("share-editor-change")

        photo.tap()
        cancelPicker(app)
        waitUntilHittable(photo, "Cancelling the picker should return to the editor.")
        XCTAssertTrue(card.isSelected, "With no photo chosen the card stays.")
        XCTAssertFalse(change.exists, "No photo, no Change photo.")

        photo.tap()
        pickPhoto(app, at: 0)
        XCTAssertTrue(change.waitForExistence(timeout: 30), "A chosen photo should show the photo card.")
        XCTAssertTrue(photo.isSelected, "Photo is selected on the photo card.")
        XCTAssertFalse(app.element("share-editor-photo-problem").exists, "A sample picture should be readable.")
        attach(app, "ShareCard photo card")

        waitUntilHittable(change, "Change photo should be tappable.")
        change.tap()
        pickPhoto(app, at: 1)
        waitUntilHittable(change, "Choosing another photo should return to the photo card.")
        XCTAssertTrue(photo.isSelected, "The new photo stays on the photo card.")
        attach(app, "ShareCard changed photo")

        change.tap()
        cancelPicker(app)
        waitUntilHittable(change, "Cancelling Change photo should keep the photo card.")
        XCTAssertTrue(photo.isSelected, "The photo is kept.")

        card.tap()
        XCTAssertTrue(change.waitForNonExistence(timeout: 10), "Card hides Change photo.")
        photo.tap()
        XCTAssertTrue(change.waitForExistence(timeout: 10), "Photo shows the chosen picture again, with no picker.")

        app.element("share-editor-share").tap()
        let save = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save Image'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 30), "The share sheet should offer Save Image.")
        save.tap()
        // The first save asks for permission to add to the photo library.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Allow'")).firstMatch
        if allow.waitForExistence(timeout: 15) { allow.tap() }
        XCTAssertTrue(save.waitForNonExistence(timeout: 30), "Saving should close the share sheet.")
        XCTAssertEqual(app.state, .runningForeground, "Saving the image should leave the app running.")
        waitUntilHittable(change, "The editor should still be there with the photo after saving.")
        attach(app, "ShareCard after Save Image")
    }

    func testWorkoutDetailShareButtonOpensTheEditor() throws {
        let app = try launch(screen: "shareworkout")
        openEditor(app, button: "share-card-workout")
    }
}
