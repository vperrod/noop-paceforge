import XCTest

/// Today, Trends and every PaceForge segment on phone-sized data, measured by the app on itself:
/// - PaceForge documents at their real list lengths: the synthetic PaceForgeRealShapes.json grown to `PerfRealCounts`
///   (PerfFixtureBuilder; no real athlete value anywhere), passed packed (`PF_FIXTURE_DEFLATE`);
/// - 800 days of daily history and 7 days of 1 Hz strap heart rate (`--demo-seed-days`, `--demo-seed-raw-hr-days`).
/// The app walks the screens itself (`-NoopPerfAutopilot`: open, load, scroll to the end and back, rest) while its
/// main-thread watchdog (8 ms tick, stalls from 33 ms, `-NoopPerf`) counts every stall against the screen visit on show.
/// The test does not touch the app until the walk is over: an XCUITest query makes SwiftUI build the whole accessibility
/// tree on the main thread, which would be measured as the screen's own cost. A simulator on a Mac runs faster than an
/// iPhone, so every simulator figure is multiplied by `deviceFactor` before it is held to the phone budget.
final class PerfHarnessUITests: XCTestCase {
    /// Simulator on a CI Mac vs an iPhone: a figure measured here counts four times against the phone budget.
    static let deviceFactor = 4.0
    /// Phone budget: no single main-thread stall above 250 ms on any screen.
    static let maxStallMs = 250.0
    /// Phone budget: opening and scrolling one screen blocks the main thread for 1 s at most in total.
    static let maxBlockedMs = 1_000.0
    /// Peak physical footprint of the whole app over the run, in MB (simulator figure, not scaled).
    static let peakBudgetMB = 400.0
    /// Simulator budget for the PaceForge tab's first load, tab opened to content (fixture: no network).
    static let maxTimeToReadyMs = 1_500.0

    static let budgetedScreens = ["tab.trends#1", "tab.today#2", "pf.today#1", "pf.coach#1", "pf.week#1",
                                  "pf.insights#1", "pf.body#1"]

    private func launch(autopilot: Bool = true) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-seed", "--demo-seed-days", "800", "--demo-seed-raw-hr-days", "7",
                                "-theme.appearance", "dark", "-PaceForgeFixture", "-NoopPerf"]
        if autopilot { app.launchArguments += ["-NoopPerfAutopilot"] }
        if let omit = ProcessInfo.processInfo.environment["PERF_OMIT"], !omit.isEmpty { app.launchArguments += ["-NoopPerfOmit", omit] }
        // No "-noop.paceforge.segment" argument here: the argument domain would override the segments the autopilot picks.
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

    /// The app's own numbers once its walk is over: {"autopilot", "peak_mb", "screens", "sections", "bodies", "main_thread"}.
    private func summaryAfterWalk(_ app: XCUIApplication) throws -> [String: Any] {
        // The walk takes about 80 s after a 25 s settle; nothing is asked of the app before then.
        Thread.sleep(forTimeInterval: 110)
        let probe = app.descendants(matching: .any).matching(identifier: "noop-perf-summary").firstMatch
        var text = ""
        for _ in 0..<12 {
            XCTAssertTrue(probe.waitForExistence(timeout: 20), "The perf probe should be on screen under -NoopPerf.")
            text = (probe.value as? String) ?? ""
            if text.contains("\"autopilot\":\"done\"") { break }
            Thread.sleep(forTimeInterval: 10)
        }
        print("PERF_SUMMARY walk \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "perf-summary.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let summary = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any])
        XCTAssertEqual(summary["autopilot"] as? String, "done", "The autopilot should have finished its walk.")
        return summary
    }

    private func assertBudget(_ summary: [String: Any], screen: String) {
        let screens = summary["screens"] as? [String: [String: Any]] ?? [:]
        guard let entry = screens[screen] else {
            XCTFail("No numbers for \(screen); measured: \(screens.keys.sorted())")
            return
        }
        let maxMs = entry["max_ms"] as? Double ?? 0
        let blocked = entry["blocked_ms"] as? Double ?? 0
        let label = entry["max_label"] as? String ?? "?"
        print("PERF_SCREEN \(screen) stalls=\(entry["stalls"] ?? "?") max_ms=\(maxMs) (x\(Self.deviceFactor) = \(maxMs * Self.deviceFactor)) blocked_ms=\(blocked) (x\(Self.deviceFactor) = \(blocked * Self.deviceFactor)) worst=\(label) cpu_s=\(entry["cpu_s"] ?? "?")")
        XCTAssertLessThanOrEqual(maxMs * Self.deviceFactor, Self.maxStallMs,
                                 "\(screen): a \(maxMs) ms main-thread stall in \(label) is \(maxMs * Self.deviceFactor) ms on a phone.")
        XCTAssertLessThanOrEqual(blocked * Self.deviceFactor, Self.maxBlockedMs,
                                 "\(screen): \(blocked) ms of main-thread stalls is \(blocked * Self.deviceFactor) ms on a phone.")
    }

    func testScreensOnPhoneSizedData() throws {
        let app = try launch()
        let summary = try summaryAfterWalk(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Perf PaceForge Body after the walk"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let screens = summary["screens"] as? [String: [String: Any]] ?? [:]
        print("PERF_SCREEN launch (seed, first refresh, scoring; not budgeted): \(screens["tab.today#1"] ?? [:])")
        for screen in Self.budgetedScreens { assertBudget(summary, screen: screen) }

        let peak = summary["peak_mb"] as? Double ?? 0
        print("PERF_PEAK_MB \(peak)")
        XCTAssertLessThanOrEqual(peak, Self.peakBudgetMB, "Peak footprint \(peak) MB is over the \(Self.peakBudgetMB) MB budget.")

        let sections = summary["sections"] as? [String: [String: Any]] ?? [:]
        let ready = sections["pf.time_to_ready"]?["max_ms"] as? Double
        print("PERF_TTI pf.today \(ready.map { "\($0) ms" } ?? "not measured")")
        XCTAssertNotNil(ready, "The PaceForge tab should report its time to content.")
        XCTAssertLessThanOrEqual(ready ?? .infinity, Self.maxTimeToReadyMs, "The PaceForge tab took \(ready ?? -1) ms to show its content.")
    }

    /// The field report: the app ran on Today, went to the background, and froze the moment it was opened again.
    /// Settle on Today, press Home, wait, open the app, wait, read the app's own stall numbers.
    func testActivateAfterBackground() throws {
        let app = try launch(autopilot: false)
        Thread.sleep(forTimeInterval: 45)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 70)
        app.activate()
        Thread.sleep(forTimeInterval: 30)
        let probe = app.descendants(matching: .any).matching(identifier: "noop-perf-summary").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 60), "The perf probe should be on screen under -NoopPerf.")
        let text = (probe.value as? String) ?? ""
        print("PERF_SUMMARY activate \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "perf-summary.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
