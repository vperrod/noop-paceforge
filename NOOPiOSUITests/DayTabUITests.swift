import XCTest

/// The New Day tab (beta), Settings > Tools: with the switch on at launch, tab 2 is Day and shows My Day, Sleep, Recovery, Activity
/// and Health as chips, one mounted at a time. With the switch off the tab is Sleep, as in build 479. The switch is a launch
/// argument here (`-unifiedDay YES`); like the other UI tests these run on `--demo-seed` data.
final class DayTabUITests: XCTestCase {
    private func launch(dayTab: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: ["-theme.appearance", "dark"])
        if dayTab { app.launchArguments.append(contentsOf: ["-unifiedDay", "YES"]) }
        app.launch()
        dumpHierarchyOnFailure(app)
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openDayTab(_ app: XCUIApplication) {
        let tab = app.shellTab("Day")
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The Day tab should be in the bar.")
        tab.tap()
        XCTAssertTrue(element(app, "day-host").waitForExistence(timeout: 30), "The Day screen should open.")
    }

    private func choose(_ chip: String, in app: XCUIApplication) {
        let button = element(app, "day-chip-\(chip)")
        XCTAssertTrue(button.waitForExistence(timeout: 15), "The \(chip) chip should be in the chip bar.")
        button.tap()
    }

    func testFlagOnNamesTheSecondTabDay() {
        let app = launch(dayTab: true)
        XCTAssertTrue(app.shellTab("Day").waitForExistence(timeout: 20), "With the switch on, tab 2 is Day.")
    }

    func testFlagOnHasNoSleepTab() {
        let app = launch(dayTab: true)
        XCTAssertTrue(app.shellTab("Day").waitForExistence(timeout: 20))
        XCTAssertFalse(app.shellTab("Sleep").exists, "With the switch on, Sleep is a chip of Day, not a tab.")
    }

    func testFlagOffKeepsTheSleepTab() {
        let app = launch(dayTab: false)
        XCTAssertTrue(app.shellTab("Sleep").waitForExistence(timeout: 20), "With the switch off, tab 2 is Sleep.")
    }

    func testFlagOffHasNoDayTab() {
        let app = launch(dayTab: false)
        XCTAssertTrue(app.shellTab("Sleep").waitForExistence(timeout: 20))
        XCTAssertFalse(app.shellTab("Day").exists, "With the switch off there is no Day tab.")
    }

    func testDayOpensOnTheSleepChip() {
        let app = launch(dayTab: true)
        openDayTab(app)
        XCTAssertTrue(element(app, "day-sleep-three-readings").waitForExistence(timeout: 30),
                      "Day opens on Sleep, which starts with the three readings.")
    }

    func testRecoveryChipShowsReadingsAndTheThreeDetails() {
        let app = launch(dayTab: true)
        openDayTab(app)
        choose("recovery", in: app)
        XCTAssertTrue(element(app, "day-recovery-three-readings").waitForExistence(timeout: 20), "Recovery starts with the readings.")
        XCTAssertTrue(element(app, "day-recovery-charge").waitForExistence(timeout: 10), "Recovery offers the Charge detail.")
    }

    func testActivityChipOffersTheLiftLog() {
        let app = launch(dayTab: true)
        openDayTab(app)
        choose("activity", in: app)
        XCTAssertTrue(element(app, "day-activity-lifts").waitForExistence(timeout: 20), "Activity offers the Lift Log.")
    }

    func testHealthChipOffersStress() {
        let app = launch(dayTab: true)
        openDayTab(app)
        choose("health", in: app)
        XCTAssertTrue(element(app, "day-health-stress").waitForExistence(timeout: 20), "Health offers Stress.")
    }

    func testMyDayChipMountsMyDay() {
        let app = launch(dayTab: true)
        openDayTab(app)
        choose("myDay", in: app)
        XCTAssertTrue(element(app, "day-chip-content-myDay").waitForExistence(timeout: 20), "My Day should mount under the chips.")
    }

    func testSleepChipReturnsAfterAnotherChip() {
        let app = launch(dayTab: true)
        openDayTab(app)
        choose("recovery", in: app)
        choose("sleep", in: app)
        XCTAssertTrue(element(app, "day-sleep-three-readings").waitForExistence(timeout: 20), "Sleep mounts again with its readings.")
    }
}
