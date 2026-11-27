import XCTest

/// Opens Body signals from Today's call and attaches a picture of both halves. Made-up readings (`-BodySignalsFixture`, DEBUG
/// builds only) on the synthetic PaceForgeFixture.json; the `signals` block is added to its brief here.
final class BodySignalsUITests: XCTestCase {
    private func launch(signals: [String: Any]?) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "-theme.appearance", "dark", "-BodySignalsFixture", "-PaceForgeFixture"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"))
        let merged = try Fixtures529.merged(Data(contentsOf: url))
        var files = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        var state = try XCTUnwrap(files["api/state"] as? [String: Any])
        var brief = try XCTUnwrap(state["daily_brief"] as? [String: Any])
        brief["signals"] = signals
        state["daily_brief"] = brief
        files["api/state"] = state
        app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try JSONSerialization.data(withJSONObject: files), as: UTF8.self)
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

    private func open(_ app: XCUIApplication) {
        let call = app.element("pf-today-card-the-call")
        XCTAssertTrue(call.waitForExistence(timeout: 60), "Today should carry the call.")
        call.tap()
        let link = app.element("body-signals-link")
        XCTAssertTrue(link.waitForExistence(timeout: 30), "Today's call should offer Body signals.")
        link.tap()
        XCTAssertTrue(app.element("signals-recovery").waitForExistence(timeout: 30), "Body signals should open.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    func testEverySourceIsNamedAndAMissingValueStaysMissing() throws {
        let app = try launch(signals: [
            "status": ["garmin": "Synthetic productive", "paceforge_load_balance": "grey"],
            "focus": ["garmin": "Synthetic aerobic high shortage", "paceforge_running_zones": NSNull()],
        ])
        open(app)
        XCTAssertEqual(app.element("signals-whoop-hrv").label, "Current calculation, WHOOP: 46 ms")
        XCTAssertEqual(app.element("signals-garmin-hrv").label, "Overnight, Garmin: missing")
        XCTAssertEqual(app.element("signals-feel-value").label, "Not answered")
        attach(app, "Signals 01 Recovery HRV and feel")
        let focus = app.element("signals-focus-paceforge")
        reveal(focus, in: app)
        XCTAssertEqual(app.element("signals-status-garmin").label, "Status, Garmin: Synthetic productive")
        XCTAssertEqual(focus.label, "Running time in zones, PaceForge: missing")
        attach(app, "Signals 02 Training status and focus")
    }

    func testWithoutASignalsBlockStatusAndFocusStayMissing() throws {
        let app = try launch(signals: nil)
        open(app)
        let status = app.element("signals-status-garmin")
        reveal(status, in: app)
        XCTAssertEqual(status.label, "Status, Garmin: missing")
        attach(app, "Signals 03 No signals block")
    }
}
