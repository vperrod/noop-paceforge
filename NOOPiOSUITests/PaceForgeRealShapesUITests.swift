import XCTest

/// The PaceForge tab crashed on a real iPhone (build 465) while these UI tests passed on made-up documents. This suite
/// serves the same screens the shape of the LIVE documents instead (`PaceForgeRealShapes.json`: every key, null, empty
/// list, zero, negative number, one-point series and low-above-high range of the real files, every value replaced) and
/// walks the screens that hold PaceForge's documents (Today, Plan > This week, Health > Body, the Coach sheet), their detail sheets and
/// the Phase 4 screens. Each step only checks that the app is still running, so a
/// crash names the step that caused it; the CI step after the run prints the crash report.
final class PaceForgeRealShapesUITests: XCTestCase {

    private func launch(screen: String? = nil, extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        if let screen { app.launchArguments.append(contentsOf: ["--demo-screen", screen]) }
        app.launchArguments.append(contentsOf: extra)
        app.launchArguments.append("-PaceForgeFixture")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeRealShapes", withExtension: "json"),
                                "The real-shape fixture should be bundled with the UI tests.")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var files = try XCTUnwrap(root["docs"] as? [String: Any])
        files["today"] = root["today"]
        let data = try JSONSerialization.data(withJSONObject: files)
        app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: data, as: UTF8.self)
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

    private func alive(_ app: XCUIApplication, _ step: String) {
        XCTAssertEqual(app.state, .runningForeground, "The app is no longer running after: \(step)")
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func element(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// Scrolls to the bottom and back. `returns: false` for a sheet (the Coach, a detail): a swipe down at its top would dismiss it.
    private func scrollThrough(_ app: XCUIApplication, _ name: String, swipes: Int = 8, returns: Bool = true) {
        for step in 0..<swipes {
            app.swipeUp()
            alive(app, "\(name): scroll down \(step + 1)")
        }
        attach(app, "\(name) bottom")
        guard returns else { return }
        for _ in 0..<swipes { app.swipeDown() }
        alive(app, "\(name): scroll back up")
    }

    private func visit(_ app: XCUIApplication, _ name: String, returns: Bool = true) {
        Thread.sleep(forTimeInterval: 2)
        alive(app, "opening \(name)")
        attach(app, "RealShapes \(name)")
        scrollThrough(app, "RealShapes \(name)", returns: returns)
    }

    // MARK: The screens

    func testTheTabsSurviveRealShapedDocuments() throws {
        let app = try launch()
        app.openTab("Today")
        visit(app, "Today")
        app.openChip("Plan", "week")
        visit(app, "This week")
        app.openChip("Health", "body")
        visit(app, "Body")
    }

    func testTheCoachSurvivesRealShapedDocuments() throws {
        let app = try launch()
        app.openCoach("read")
        visit(app, "Coach Read", returns: false)
    }

    func testCoachInsightsSurvivesRealShapedDocuments() throws {
        for chip in ["overview", "deepDives"] {
            let app = try launch()
            app.openCoachInsights(chip)
            visit(app, "Coach Insights \(chip)", returns: false)
            app.terminate()
        }
    }

    func testTodayInTheEveningSurvivesRealShapedDocuments() throws {
        let app = try launch(extra: ["-PaceForgeEvening"])
        app.openTab("Today")
        Thread.sleep(forTimeInterval: 2)
        alive(app, "opening Today in the evening")
        scrollThrough(app, "RealShapes Today evening")
    }

    // MARK: Detail sheets

    func testEveryInsightDetailOpensOnRealShapedDocuments() throws {
        let app = try launch()
        app.openCoachInsights("overview")
        Thread.sleep(forTimeInterval: 2)
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "pf-insight-card-"))
        let count = min(cards.count, 8)
        for index in 0..<count {
            let card = cards.element(boundBy: index)
            guard card.exists else { continue }
            if !card.isHittable { app.swipeUp() }
            card.tap()
            Thread.sleep(forTimeInterval: 2)
            alive(app, "opening insight detail \(index)")
            attach(app, "RealShapes insight detail \(index)")
            scrollThrough(app, "RealShapes insight detail \(index)", swipes: 6, returns: false)
            let done = element(app, "pf-insight-done")
            if done.exists { done.tap() }
            Thread.sleep(forTimeInterval: 1)
            alive(app, "closing insight detail \(index)")
        }
    }

    // MARK: The trend view: ranges and metrics on a short, flat or one-point series

    func testBodyTrendRangesAndMetricsSurviveRealShapedSeries() throws {
        let app = try launch()
        app.openChip("Health", "body")
        Thread.sleep(forTimeInterval: 2)
        app.openSection("body-trend")
        let chart = element(app, "pf-body-trend-chart")
        for _ in 0..<12 where !(chart.exists && chart.isHittable) { app.swipeUp() }
        alive(app, "finding the Body trend")
        for range in ["W", "M", "6M", "Y"] {
            let button = element(app, "look-trend-range-\(range)")
            if button.exists { button.tap() }
            Thread.sleep(forTimeInterval: 1)
            alive(app, "Body trend range \(range)")
            let earlier = element(app, "look-trend-prev")
            if earlier.exists && earlier.isEnabled { earlier.tap() }
            alive(app, "Body trend range \(range), one step back")
        }
        let menu = element(app, "look-trend-metric-menu")
        if menu.exists {
            menu.tap()
            let items = app.buttons.matching(NSPredicate(format: "label != ''"))
            let pick = min(items.count, 12)
            for index in 0..<pick where index % 3 == 0 {
                let item = items.element(boundBy: index)
                if item.exists && item.isHittable { item.tap(); Thread.sleep(forTimeInterval: 1) }
                alive(app, "Body trend metric \(index)")
                if menu.exists && menu.isHittable { menu.tap() }
            }
        }
        attach(app, "RealShapes Body trend")
    }

    // MARK: The Phase 4 screens and the daily loop

    func testPhase4ScreensSurviveRealShapedDocuments() throws {
        for screen in ["highlights", "healthspan", "journalimpact", "monthlyreport"] {
            let app = try launch(screen: screen)
            Thread.sleep(forTimeInterval: 4)
            alive(app, "opening \(screen)")
            attach(app, "RealShapes \(screen)")
            scrollThrough(app, "RealShapes \(screen)", swipes: 6)
            app.terminate()
        }
    }

    func testNoopTodayWithThePaceForgeCardsSurvivesRealShapedDocuments() throws {
        let app = try launch()
        Thread.sleep(forTimeInterval: 6)
        alive(app, "opening NOOP Today")
        scrollThrough(app, "RealShapes NOOP Today", swipes: 10)
    }
}
