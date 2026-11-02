import XCTest

extension XCUIApplication {
    /// A tab in the bottom bar. The shell draws the look's floating bar, whose items carry `look-tab-<lower-cased title>`;
    /// the system tab bar is hidden, so `tabBars` is empty.
    func shellTab(_ title: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: "look-tab-\(title.lowercased())").firstMatch
    }
}

extension XCUIApplication {
    /// Launches in the classic navigation (Today, Workouts, Sleep, PaceForge, More), which Settings > Tools > Unified navigation
    /// switches back to. The unified bar (Today, Plan, Athlete, Insights, More) is the default; the PaceForge tab and its segments
    /// (`pf-segments`) exist only in the classic one. Call it before `launch()`.
    func useClassicNavigation() {
        launchArguments.append(contentsOf: ["-unifiedNav", "NO"])
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
