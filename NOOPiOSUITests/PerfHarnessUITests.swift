import XCTest

/// The PaceForge tab, Today and Trends on phone-sized data, measured by the app on itself (`-NoopPerf`):
/// - PaceForge documents at their real list lengths: the synthetic PaceForgeRealShapes.json grown to `PerfRealCounts`
///   (PerfFixtureBuilder; no real athlete value anywhere), passed packed (`PF_FIXTURE_DEFLATE`);
/// - 800 days of daily history and 7 days of 1 Hz strap heart rate (`--demo-seed-days`, `--demo-seed-raw-hr-days`).
/// Each screen is opened and scrolled; the app's main-thread watchdog (8 ms tick, stalls from 33 ms) counts every stall
/// against the screen visit on show. A simulator on a Mac runs faster than an iPhone, so every simulator figure is
/// multiplied by `deviceFactor` before it is held to the phone budget.
final class PerfHarnessUITests: XCTestCase {
    /// Simulator on a CI Mac vs an iPhone: a figure measured here counts four times against the phone budget.
    static let deviceFactor = 4.0
    /// Phone budget: no single main-thread stall above 250 ms on any screen.
    static let maxStallMs = 250.0
    /// Phone budget: opening and scrolling one screen blocks the main thread for 1 s at most in total.
    static let maxBlockedMs = 1_000.0
    /// Peak physical footprint of the whole app over the run, in MB (simulator figure, not scaled).
    static let peakBudgetMB = 700.0

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "--demo-seed-days", "800", "--demo-seed-raw-hr-days", "7",
                                "-theme.appearance", "dark", "-PaceForgeFixture", "-NoopPerf",
                                // Start every run on PaceForge Today, whatever an earlier test left selected.
                                "-noop.paceforge.segment", "today"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeRealShapes", withExtension: "json"),
                                "The synthetic real-shapes fixture should be bundled with the UI tests.")
        let documents = try PerfFixtureBuilder.realSize(shapes: url) as NSData
        print("PERF_FIXTURE_BYTES \(documents.length)")
        let packed = try documents.compressed(using: .zlib) as Data
        app.launchEnvironment["PF_FIXTURE_DEFLATE"] = packed.base64EncodedString()
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

    private func scroll(_ app: XCUIApplication, swipes: Int = 6) {
        for _ in 0..<swipes { app.swipeUp(velocity: .fast) }
        for _ in 0..<swipes { app.swipeDown(velocity: .fast) }
    }

    /// The app's own numbers: {"peak_mb", "screens": {"pf.today#1": {...}}, "sections": {...}}.
    private func summary(_ app: XCUIApplication, _ label: String) throws -> [String: Any] {
        Thread.sleep(forTimeInterval: 1.5)   // the probe refreshes once a second
        let probe = app.descendants(matching: .any).matching(identifier: "noop-perf-summary").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "The perf probe should be on screen under -NoopPerf.")
        let text = try XCTUnwrap(probe.value as? String, "The perf probe should carry the summary JSON.")
        print("PERF_SUMMARY \(label) \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "perf-summary \(label).json"
        attachment.lifetime = .keepAlways
        add(attachment)
        return try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any])
    }

    private func assertBudget(_ summary: [String: Any], screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let screens = summary["screens"] as? [String: [String: Any]] ?? [:]
        guard let entry = screens[screen] else {
            XCTFail("No numbers for \(screen); measured: \(screens.keys.sorted())", file: file, line: line)
            return
        }
        let maxMs = entry["max_ms"] as? Double ?? 0
        let blocked = entry["blocked_ms"] as? Double ?? 0
        let label = entry["max_label"] as? String ?? "?"
        print("PERF_SCREEN \(screen) max_ms=\(maxMs) (x\(Self.deviceFactor) = \(maxMs * Self.deviceFactor)) blocked_ms=\(blocked) (x\(Self.deviceFactor) = \(blocked * Self.deviceFactor)) worst=\(label) cpu_s=\(entry["cpu_s"] ?? "?")")
        XCTAssertLessThanOrEqual(maxMs * Self.deviceFactor, Self.maxStallMs,
                                 "\(screen): a \(maxMs) ms main-thread stall in \(label) is \(maxMs * Self.deviceFactor) ms on a phone.",
                                 file: file, line: line)
        XCTAssertLessThanOrEqual(blocked * Self.deviceFactor, Self.maxBlockedMs,
                                 "\(screen): \(blocked) ms of main-thread stalls is \(blocked * Self.deviceFactor) ms on a phone.",
                                 file: file, line: line)
    }

    private func assertPeak(_ summary: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        let peak = summary["peak_mb"] as? Double ?? 0
        print("PERF_PEAK_MB \(peak)")
        XCTAssertLessThanOrEqual(peak, Self.peakBudgetMB, "Peak footprint \(peak) MB is over the \(Self.peakBudgetMB) MB budget.",
                                 file: file, line: line)
    }

    /// Lets the launch work (the seed, the first refresh and the scoring pass) finish before a screen is measured.
    private func settle(_ app: XCUIApplication) {
        XCTAssertTrue(app.shellTab("Today").waitForExistence(timeout: 60), "Today's tab should show.")
        Thread.sleep(forTimeInterval: 25)
    }

    func testPaceForgeTabOnRealSizeDocuments() throws {
        let app = try launch()
        settle(app)
        let tab = app.shellTab("PaceForge")
        let opened = Date()
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 20), "The PaceForge tab should load the real-size fixture.")
        let timeToSegments = Date().timeIntervalSince(opened)
        print("PERF_TTI pf.today \(String(format: "%.2f", timeToSegments)) s")
        XCTAssertLessThan(timeToSegments, 6, "The PaceForge tab took \(timeToSegments) s to show its segments.")
        Thread.sleep(forTimeInterval: 2)
        attach(app, "Perf 1 PaceForge Today")
        scroll(app)
        for (index, title) in ["Coach", "This week", "Insights", "Body"].enumerated() {
            let button = segments.buttons[title]
            for _ in 0..<3 where !button.isSelected { button.tap(); Thread.sleep(forTimeInterval: 1) }
            Thread.sleep(forTimeInterval: 2)
            attach(app, "Perf \(index + 2) PaceForge \(title)")
            scroll(app)
        }
        let numbers = try summary(app, "paceforge")
        for screen in ["pf.today#1", "pf.coach#1", "pf.week#1", "pf.insights#1", "pf.body#1"] {
            assertBudget(numbers, screen: screen)
        }
        assertPeak(numbers)
    }

    func testTodayAndTrendsOnPhoneSizedHistory() throws {
        let app = try launch()
        settle(app)
        attach(app, "Perf 7 Today")
        // The launch visit carries the seed and the first scoring pass; Today is measured on a second visit.
        app.shellTab("Trends").tap()
        Thread.sleep(forTimeInterval: 3)
        attach(app, "Perf 8 Trends")
        scroll(app)
        app.shellTab("Today").tap()
        Thread.sleep(forTimeInterval: 3)
        scroll(app)
        let numbers = try summary(app, "today-trends")
        let screens = numbers["screens"] as? [String: [String: Any]] ?? [:]
        print("PERF_SCREEN launch (seed, first refresh, scoring; not budgeted): \(screens["tab.today#1"] ?? [:])")
        assertBudget(numbers, screen: "tab.trends#1")
        assertBudget(numbers, screen: "tab.today#2")
        assertPeak(numbers)
    }
}
