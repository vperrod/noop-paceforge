import XCTest

/// Build 530, APP-4: the switches under the bell list the four new alert kinds, and a switch keeps its setting. The delivery rules and the
/// acknowledgement queue are proved by the unit tests (PFAlertDelivery530Tests, PFAlertAck530Tests); this class only covers the screen.
/// Synthetic fixture, like Plan529InboxUITests. Screenshot names start with "APP4".
final class Alerts530UITests: XCTestCase {
    private let newKinds = ["progress", "bedtime", "journal", "review"]

    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture", "-Plan529InboxUnread"])
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
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

    private func openSwitches(_ app: XCUIApplication) {
        let bell = app.element("today-alerts")
        XCTAssertTrue(bell.waitForExistence(timeout: 30), "Today should carry the bell.")
        bell.tap()
        XCTAssertTrue(app.element("plan529-inbox").waitForExistence(timeout: 20), "The bell should open the inbox.")
        app.element("plan529-inbox-settings").tap()
        XCTAssertTrue(app.element("plan529-inbox-settings-screen").waitForExistence(timeout: 20), "The way in should open the switches.")
    }

    /// The row is the switch's element, so its centre is the label: the control itself sits at the right end.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    func testTheSwitchesListTheFourNewKindsAllOn() throws {
        let app = try launch()
        openSwitches(app)
        app.swipeUp()
        for kind in newKinds {
            let toggle = app.switches["plan529-inbox-switch-\(kind)"]
            XCTAssertTrue(toggle.exists, "There should be a switch for \(kind).")
            XCTAssertEqual(toggle.value as? String, "1", "A new kind starts on: \(kind).")
        }
        attach(app, "APP4 01 switches")
    }

    func testASwitchKeepsItsSettingWhenTheScreenIsLeftAndOpenedAgain() throws {
        let app = try launch()
        openSwitches(app)
        app.swipeUp()
        flip(app.switches["plan529-inbox-switch-progress"])
        XCTAssertEqual(app.switches["plan529-inbox-switch-progress"].value as? String, "0", "A tap should switch the kind off.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.element("plan529-inbox-settings").waitForExistence(timeout: 20), "Back should return to the inbox.")
        app.element("plan529-inbox-settings").tap()
        XCTAssertTrue(app.element("plan529-inbox-settings-screen").waitForExistence(timeout: 20), "The switches should open again.")
        app.swipeUp()
        XCTAssertEqual(app.switches["plan529-inbox-switch-progress"].value as? String, "0", "The kind should still be off.")
        attach(app, "APP4 02 progress switched off")
        flip(app.switches["plan529-inbox-switch-progress"])
    }
}
