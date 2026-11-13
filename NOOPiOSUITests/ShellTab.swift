import XCTest

extension XCUIApplication {
    /// A tab in the bottom bar. The shell draws the look's floating bar, whose items carry `look-tab-<lower-cased title>`;
    /// the system tab bar is hidden, so `tabBars` is empty.
    func shellTab(_ title: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: "look-tab-\(title.lowercased())").firstMatch
    }
}

extension XCUIApplication {
    /// The classic navigation (Today, Workouts, Sleep, PaceForge, More) and its PaceForge tab with the `pf-segments` control are gone:
    /// the bar is Today, Plan, Train and Health, with a Coach button beside it (`look-coach`). A test that drove the classic tab calls this before `launch()` and is skipped
    /// until it is ported to the screen that holds its subject now.
    func useClassicNavigation() throws {
        throw XCTSkip("Drives the classic PaceForge tab, which no longer exists. Port it to the unified screens.")
    }
}

extension XCUIApplication {
    /// Opens a row `more-row-<row>` on a tab, scrolling to it. The More rows are gone with the Reports and Body tabs; a test that calls
    /// this fails until it is ported to the Train or Health chip that holds its subject now.
    func openMoreRow(tab: String, row: String) {
        let button = shellTab(tab)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "The \(tab) tab should be in the bar.")
        button.tap()
        let target = descendants(matching: .any).matching(identifier: "more-row-\(row)").firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 20), "The \(tab) tab should end with the \(row) row.")
        for _ in 0..<10 where !target.isHittable { swipeUp() }
        target.tap()
    }
}

extension XCTestCase {
    /// When a test fails, prints what the screen exposed to accessibility, so the log names the identifiers that were missing.
    func dumpHierarchyOnFailure(_ app: XCUIApplication) {
        addTeardownBlock { [self] in
            if (testRun?.totalFailureCount ?? 0) > 0 { print("HIERARCHY \(name)\n\(app.debugDescription)") }
        }
    }
}

extension XCUIApplication {
    /// The round Coach button beside the bar, which opens the Coach as a sheet.
    var coachButton: XCUIElement {
        descendants(matching: .any).matching(identifier: "look-coach").firstMatch
    }
}
