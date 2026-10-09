import XCTest

final class PaceForgeMenuVisibilityUITests: XCTestCase {
    func testPaceForgePushAppearsInMoreData() {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 15), "The More tab should be present.")
        moreTab.tap()

        let dataSection = app.buttons["Data"]
        XCTAssertTrue(dataSection.waitForExistence(timeout: 10), "The Data section should be present.")
        if (dataSection.value as? String) != "Expanded" {
            for _ in 0..<8 where !dataSection.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(dataSection.isHittable, "The Data section should be reachable by scrolling.")
            dataSection.tap()
        }

        let paceForgeRow = app.staticTexts["PaceForge push"]
        XCTAssertTrue(paceForgeRow.waitForExistence(timeout: 10), "The PaceForge push setting should appear under More → Data.")
    }
}
