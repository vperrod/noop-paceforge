import XCTest

final class PaceForgeMenuVisibilityUITests: XCTestCase {
    func testPaceForgePushAppearsInSettingsData() {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launch()

        // Settings opens from the avatar on Today; Data is a row of its Tools card, and the PaceForge sync settings are a section of Data.
        app.openTab("Today")
        let settings = app.element("today-settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "Today should carry the profile and settings button.")
        settings.tap()
        let dataRow = app.element("settings-tool-data")
        XCTAssertTrue(dataRow.waitForExistence(timeout: 10), "Settings should list Data under Tools.")
        for _ in 0..<12 where !dataRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(dataRow.isHittable, "The Data row should be reachable by scrolling.")
        dataRow.tap()

        let paceForgeChip = app.descendants(matching: .any).matching(identifier: "data-section-paceForge").firstMatch
        XCTAssertTrue(paceForgeChip.waitForExistence(timeout: 10), "The PaceForge push setting should appear under Settings > Data.")
        // The section chips are one horizontal row of eight: PaceForge sync is the sixth, so the row is scrolled sideways until it is on screen.
        let rowY = paceForgeChip.frame.midY / app.frame.height
        for _ in 0..<6 where !paceForgeChip.isHittable {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: rowY))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: rowY))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTAssertTrue(paceForgeChip.isHittable, "The PaceForge push section should be visible on screen.")
        paceForgeChip.tap()
        XCTAssertTrue(app.staticTexts["PaceForge sync"].waitForExistence(timeout: 10) || paceForgeChip.isSelected,
                      "Choosing the section should show the PaceForge sync settings.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "NOOP — PaceForge push in iPhone Simulator"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
