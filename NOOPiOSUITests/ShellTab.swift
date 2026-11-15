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

extension XCUIApplication {
    /// Any element by its accessibility identifier, whatever its type.
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The identifier prefix of a tab's host and chips (`<prefix>-host`, `<prefix>-chip-<chip>`, `<prefix>-chip-content-<chip>`).
    private static let chipHosts = ["Plan": "calendar", "Train": "train", "Health": "health"]

    /// Taps a tab in the bar and waits for its screen: Today's rings, or the host of Plan, Train or Health.
    func openTab(_ title: String) {
        let button = shellTab(title)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "The \(title) tab should be in the bar.")
        button.tap()
        let screen = title == "Today" ? "today-six-rings" : "\(Self.chipHosts[title] ?? title.lowercased())-host"
        XCTAssertTrue(element(screen).waitForExistence(timeout: 30), "The \(title) screen should open.")
    }

    /// Opens a tab and picks one of its chips (a tab reopens on the chip it was left on, so the chip is always chosen). `chip` is the
    /// chip's raw value: Plan `thisWeek`, `nextWeek`, `calendar`, `season`; Train `hyrox`, `running`, `strength`, `bike`, `workouts`,
    /// `athlete`; Health `day`, `sleep`, `recovery`, `body`, `vitals`, `journal`, `trends`. Waits for the chip's content to mount.
    func openChip(_ tab: String, _ chip: String) {
        openTab(tab)
        let prefix = Self.chipHosts[tab] ?? tab.lowercased()
        pickChip(prefix: prefix, chip: chip, content: "\(prefix)-chip-content-\(chip == "thisWeek" ? "plan" : chip)")
    }

    /// Opens the Coach sheet over the screen on show and picks one of its chips: `read`, `ask`, `reports` or `insights`.
    func openCoach(_ chip: String) {
        XCTAssertTrue(coachButton.waitForExistence(timeout: 30), "The Coach button should be beside the bar.")
        coachButton.tap()
        XCTAssertTrue(element("coach-host").waitForExistence(timeout: 30), "The Coach sheet should open.")
        // The Insights chip has no content marker of its own; its column is `insights-host`.
        pickChip(prefix: "coach", chip: chip, content: chip == "insights" ? "insights-host" : "coach-chip-content-\(chip)")
    }

    /// Coach > Insights and one of its own chips: `overview` or `deepDives`.
    func openCoachInsights(_ chip: String) {
        openCoach("insights")
        pickChip(prefix: "insights", chip: chip, content: "insights-chip-content-\(chip)")
    }

    /// Taps `<prefix>-chip-<chip>` and waits for the element `content`.
    private func pickChip(prefix: String, chip: String, content: String) {
        let button = element("\(prefix)-chip-\(chip)")
        XCTAssertTrue(button.waitForExistence(timeout: 20), "The \(chip) chip should be in the \(prefix) chip bar.")
        button.tap()
        XCTAssertTrue(element(content).waitForExistence(timeout: 30), "The \(chip) chip should mount.")
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
