import XCTest

extension XCUIApplication {
    /// A tab in the bottom bar. The shell draws the look's floating bar, whose items carry `look-tab-<lower-cased title>`;
    /// the system tab bar is hidden, so `tabBars` is empty.
    func shellTab(_ title: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: "look-tab-\(title.lowercased())").firstMatch
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
