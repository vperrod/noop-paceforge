import XCTest

final class PaceForgeMenuVisibilityUITests: XCTestCase {
    func testPaceForgePushAppearsInMoreData() {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launch()

        let moreTab = app.shellTab("More")
        XCTAssertTrue(moreTab.waitForExistence(timeout: 15), "The More tab should be present.")
        moreTab.tap()

        // Since build 468 the Data screen is one row of More (Apple Health, Mi Band, Backup & Sync, PaceForge sync ... are its sections).
        let dataRow = app.descendants(matching: .any).matching(identifier: "more-row-data").firstMatch
        XCTAssertTrue(dataRow.waitForExistence(timeout: 10), "More should list Data.")
        for _ in 0..<8 where !dataRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(dataRow.isHittable, "The Data row should be reachable by scrolling.")
        dataRow.tap()

        let paceForgeChip = app.descendants(matching: .any).matching(identifier: "data-section-paceForge").firstMatch
        XCTAssertTrue(paceForgeChip.waitForExistence(timeout: 10), "The PaceForge push setting should appear under More → Data.")
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
