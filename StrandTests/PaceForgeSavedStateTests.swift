import XCTest
@testable import Strand

/// Builds 465 and 466 crashed on a real iPhone that had been running build 464, while the simulator (which always starts
/// with empty app state, and in a fixture run never reads the phone's saved copies) found nothing. These tests feed what
/// build 464 itself wrote to the current readers, then damaged copies of it: the Today order and hidden sections, the
/// PaceForge Today arrangement, the "Not today" list, the last good PaceForge documents kept for offline use, and the new
/// Healthspan / Journal impact / My Dashboard values. Nothing may trap, and a saved value must read as a sane one.
/// The 464 payloads below were produced by build 464's own encoders (git ef21a268). All values are made up.
final class PaceForgeSavedStateTests: XCTestCase {

    // MARK: What build 464 wrote

    private let noopOrder464 = "hero,liveSession,synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards,menstrualCycle,journal,addedCards"
    private let noopCustomOrder464 = "journal,hero,workouts,synthesis,liveSession,keyMetrics,heartRate,recoveryVitals,yourCards,menstrualCycle,addedCards"
    private let noopHidden464 = "synthesis,journal"
    private let pfLayout464 = #"{"order":["race-week","brief","today-so-far","session","next-best-action","easy","feel","alerts","daily","what-changed","readiness","standing","next-race"],"pinned":["brief","alerts"]}"#
    private let pfDismissed464 = #"[{"key":"brief","text_hash":"f55c314b","dismissed_at":"2026-10-03T04:00:00Z"},{"dismissed_at":"2026-10-03T04:00:00Z","until":"2026-10-13","key":"alerts","text_hash":"12aa51d3"}]"#

    private let newDocumentPaths: Set<String> = [
        "data/daily-intel.json", "data/healthspan.json", "data/journal-impact.json", "data/highlights.json",
        "data/monthly-report.json", "data/my-plan.json",
    ]

    private func suite() throws -> UserDefaults {
        let name = "PaceForgeSavedStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: NOOP Today order and hidden sections

    func testBuild464TodayOrderReadsAsAFullOrderWithTheNewSectionsInTheirDefaultPlaces() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(noopOrder464), TodaySection.defaultOrder)
    }

    func testBuild464CustomTodayOrderKeepsTheUsersOrderAndPlacesTheNewSections() {
        let order = TodayLayoutPrefs.decodeOrder(noopCustomOrder464)
        XCTAssertEqual(order.prefix(6).map(\.rawValue), ["todays-call", "day-in-review", "my-plan", "my-dashboard", "journal", "hero"])
    }

    func testBuild464CustomTodayOrderContainsEverySectionOnce() {
        let order = TodayLayoutPrefs.decodeOrder(noopCustomOrder464)
        XCTAssertEqual(order.count, Set(order).count)
        XCTAssertEqual(Set(order), Set(TodaySection.allCases))
    }

    func testBuild464HiddenSectionsStayHiddenAndTheNewOnesStayVisible() {
        let visible = TodayLayoutPrefs.visibleOrder(orderRaw: noopOrder464, hiddenRaw: noopHidden464)
        XCTAssertFalse(visible.contains(.synthesis) || visible.contains(.journal))
        XCTAssertTrue(visible.contains(.todaysCall) && visible.contains(.myDashboard))
    }

    func testDamagedTodayOrdersAlwaysYieldEverySectionOnce() {
        let damaged = ["", ",,,", "hero,hero,hero", "\u{0}", "hero\nliveSession", String(repeating: "hero,", count: 5000),
                       "todays-call,TODAYS-CALL,my-plan", "{\"a\":1}", "   hero  ,  journal "]
        for raw in damaged {
            let order = TodayLayoutPrefs.decodeOrder(raw)
            XCTAssertEqual(Set(order), Set(TodaySection.allCases), raw)
            XCTAssertEqual(order.count, Set(order).count, raw)
        }
    }

    func testDamagedHiddenListsNeverTrap() {
        for raw in ["", ",", "bogus", "hero,hero", "\u{0}", String(repeating: "x,", count: 5000)] {
            XCTAssertLessThanOrEqual(TodayLayoutPrefs.decodeHidden(raw).count, TodaySection.allCases.count, raw)
        }
    }

    // MARK: PaceForge Today arrangement kept on the phone

    func testBuild464ArrangementDecodes() throws {
        let defaults = try suite()
        defaults.set(data(pfLayout464), forKey: PFTodayLayoutStorage.defaultsKey)
        XCTAssertEqual(PFTodayLayoutStorage.load(defaults: defaults)?.pinned, ["brief", "alerts"])
    }

    func testBuild464ArrangementOrdersEveryCardOnceIncludingTheNewOnes() throws {
        let defaults = try suite()
        defaults.set(data(pfLayout464), forKey: PFTodayLayoutStorage.defaultsKey)
        let layout = try XCTUnwrap(PFTodayLayoutStorage.load(defaults: defaults))
        let ids = PFTodayCard.defaultOrder.map(\.rawValue)
        let sorted = PFTodayOrder.sorted(ids, layout: layout)
        XCTAssertEqual(sorted.sorted(), ids.sorted())
    }

    func testBuild464ArrangementKeepsPinnedCardsFirst() throws {
        let defaults = try suite()
        defaults.set(data(pfLayout464), forKey: PFTodayLayoutStorage.defaultsKey)
        let layout = try XCTUnwrap(PFTodayLayoutStorage.load(defaults: defaults))
        let sorted = PFTodayOrder.sorted(PFTodayCard.defaultOrder.map(\.rawValue), layout: layout)
        XCTAssertEqual(Array(sorted.prefix(2)), ["brief", "alerts"])
    }

    func testBuild464ArrangementPutsTheNewCardsAfterTheNamedOnesInDefaultOrder() throws {
        let defaults = try suite()
        defaults.set(data(pfLayout464), forKey: PFTodayLayoutStorage.defaultsKey)
        let layout = try XCTUnwrap(PFTodayLayoutStorage.load(defaults: defaults))
        let sorted = PFTodayOrder.sorted(PFTodayCard.defaultOrder.map(\.rawValue), layout: layout)
        XCTAssertEqual(Array(sorted.suffix(3)), ["todays-call", "day-in-review", "my-plan"])
    }

    func testBuild464ArrangementCanStillBeMovedAndPinnedWithTheNewCards() throws {
        let defaults = try suite()
        defaults.set(data(pfLayout464), forKey: PFTodayLayoutStorage.defaultsKey)
        let layout = try XCTUnwrap(PFTodayLayoutStorage.load(defaults: defaults))
        let ids = PFTodayCard.defaultOrder.map(\.rawValue)
        let moved = PFTodayOrder.moving("my-plan", step: -1, ids: ids, visible: Set(ids), layout: layout)
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: moved).sorted(), ids.sorted())
    }

    func testDamagedArrangementsReadAsNoArrangement() throws {
        let damaged = ["", "{", "[]", "null", "\"order\"", #"{"order":"brief"}"#, #"{"order":[1,2,3]}"#, #"{"pinned":{"a":1}}"#, "\u{0}\u{1}"]
        for text in damaged {
            let defaults = try suite()
            defaults.set(data(text), forKey: PFTodayLayoutStorage.defaultsKey)
            XCTAssertNil(PFTodayLayoutStorage.load(defaults: defaults), text)
        }
    }

    func testAnArrangementSavedAsTheWrongTypeReadsAsNoArrangement() throws {
        let defaults = try suite()
        defaults.set("order=brief", forKey: PFTodayLayoutStorage.defaultsKey)
        XCTAssertNil(PFTodayLayoutStorage.load(defaults: defaults))
    }

    func testAnArrangementWithRepeatsAndUnknownIdsStillOrdersEveryCardOnce() {
        let layout = PFTodayLayout(order: ["brief", "brief", "ghost", "", "todays-call", "brief"],
                                   pinned: ["ghost", "ghost", "alerts", "alerts"])
        let ids = PFTodayCard.defaultOrder.map(\.rawValue)
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: layout).sorted(), ids.sorted())
    }

    func testAHugeArrangementOrdersWithoutTrapping() {
        let order = (0..<20_000).map { "card-\($0)" } + PFTodayCard.defaultOrder.map(\.rawValue)
        let ids = PFTodayCard.defaultOrder.map(\.rawValue)
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: PFTodayLayout(order: order, pinned: [])).count, ids.count)
    }

    func testMovingWithAnArrangementThatNamesNoPresentCardLeavesTheCardsInTheirDefaultOrder() {
        let layout = PFTodayLayout(order: ["ghost"], pinned: [])
        let ids = ["brief", "feel", "session"]
        let moved = PFTodayOrder.moving("feel", step: -1, ids: ids, visible: Set(ids), layout: layout)
        XCTAssertEqual(PFTodayOrder.sorted(ids, layout: moved), ["feel", "brief", "session"])
    }

    func testEveryCardHasAnIdTheLayoutCanRoundTrip() {
        for card in PFTodayCard.allCases { XCTAssertEqual(PFTodayCard(rawValue: card.rawValue), card) }
    }

    // MARK: "Not today" list kept on the phone

    func testBuild464DismissalsDecode() throws {
        let defaults = try suite()
        defaults.set(data(pfDismissed464), forKey: PFDismissStorage.defaultsKey)
        XCTAssertEqual(PFDismissStorage.load(defaults: defaults, today: "2026-10-12").map(\.key), ["brief", "alerts"])
    }

    func testBuild464SnoozeRunsOutAndIsDropped() throws {
        let defaults = try suite()
        defaults.set(data(pfDismissed464), forKey: PFDismissStorage.defaultsKey)
        XCTAssertEqual(PFDismissStorage.load(defaults: defaults, today: "2026-10-13").map(\.key), ["brief"])
    }

    func testBuild464DismissalStillHidesTheSameCardText() throws {
        let defaults = try suite()
        defaults.set(data(pfDismissed464), forKey: PFDismissStorage.defaultsKey)
        let local = PFDismissStorage.load(defaults: defaults, today: "2026-10-12")
        XCTAssertTrue(PFDismissLogic.isHidden(key: "brief", text: "Hello", today: "2026-10-12", local: local, server: []))
    }

    func testDamagedDismissalListsReadAsEmpty() throws {
        for text in ["", "{", "{}", "null", #"[{"key":1}]"#, #"[{"until":"2026-10-13"}]"#, "[1,2]", "\u{0}"] {
            let defaults = try suite()
            defaults.set(data(text), forKey: PFDismissStorage.defaultsKey)
            XCTAssertEqual(PFDismissStorage.load(defaults: defaults, today: "2026-10-12"), [], text)
        }
    }

    func testASnoozeWithAnUnreadableDayIsKeptOrDroppedWithoutTrapping() {
        let items = [PFDismissal(key: "brief", until: "not-a-day", dismissedAt: nil, textHash: nil),
                     PFDismissal(key: "feel", until: "", dismissedAt: nil, textHash: nil)]
        XCTAssertEqual(PFDismissLogic.pruned(items, today: "2026-10-12").map(\.key), ["brief"])
    }

    func testTomorrowOfAnUnreadableDayIsTheDayItself() {
        XCTAssertEqual(PFDismissLogic.tomorrow(after: "not-a-day"), "not-a-day")
    }

    // MARK: Saved PaceForge documents (what the tab shows first, before the network answers)

    private func fixtureFiles(file: StaticString = #filePath) throws -> [String: Any] {
        let fallback = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NOOPiOSUITests/PaceForgeFixture.json")
        let url = ProcessInfo.processInfo.environment["PF_FIXTURE_FILE"].map { URL(fileURLWithPath: $0) } ?? fallback
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// What `PFStore` held after build 464's fetches: every document that build asked for, as the bytes the server sent.
    private func build464Cache() throws -> (String) -> Data? {
        let files = try fixtureFiles()
        return { [newDocumentPaths] path in
            guard !newDocumentPaths.contains(path), let value = files[path] else { return nil }
            if let text = value as? String { return Data(text.utf8) }
            return try? JSONSerialization.data(withJSONObject: value)
        }
    }

    private func daysFromFixtureDay(_ offset: Int) -> String {
        let today = "2030-03-13"
        return PFFormat.addDays(today, offset)
    }

    func testTheBuild464CacheOpensTheTab() throws {
        let raw = try XCTUnwrap(PFRawBundle.cached(read: try build464Cache()))
        XCTAssertNotNil(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
    }

    func testTheBuild464CacheHasNoDailyIntelAndNoPhaseFourDocuments() throws {
        let raw = try XCTUnwrap(PFRawBundle.cached(read: try build464Cache()))
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
        XCTAssertNil(snapshot.dailyIntel)
        XCTAssertNil(snapshot.intelDocs.myPlan.value)
        XCTAssertNil(snapshot.intelDocs.healthspan.value)
        XCTAssertNil(snapshot.intelDocs.highlights.value)
    }

    func testTheBuild464CacheBuildsOnEveryDayAroundTheOneItWasSavedOn() throws {
        let raw = try XCTUnwrap(PFRawBundle.cached(read: try build464Cache()))
        for offset in [-400, -30, -7, -1, 0, 1, 2, 6, 7, 8, 14, 30, 90, 400, 4000] {
            let today = daysFromFixtureDay(offset)
            let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: raw, today: today), today)
            XCTAssertEqual(snapshot.weeks.count, 3, today)
            XCTAssertTrue(snapshot.weeks.indices.contains(snapshot.currentWeekIndex), today)
        }
    }

    func testTheBuild464CacheWithOnlyTheTwoRequiredDocumentsStillBuilds() throws {
        let full = try build464Cache()
        let required: Set<String> = ["api/state", "data/fitness.json"]
        let raw = try XCTUnwrap(PFRawBundle.cached(read: { required.contains($0) ? full($0) : nil }))
        XCTAssertNotNil(PFBuilder.snapshot(from: raw, today: "2030-03-13"))
    }

    func testACacheMissingTheRequiredDocumentsIsNotUsed() throws {
        let full = try build464Cache()
        XCTAssertNil(PFRawBundle.cached(read: { $0 == "data/fitness.json" ? nil : full($0) }))
    }

    func testDamagedCachedDocumentsNeverTrapTheBuilder() throws {
        let full = try build464Cache()
        let junk: [Data] = [Data(), Data("{".utf8), Data("null".utf8), Data("[]".utf8), Data("\"x\"".utf8), Data("1e999".utf8),
                            Data([0, 1, 2, 255]), Data("{\"daily\":[1,2,3]}".utf8), Data("<html>502 Bad Gateway</html>".utf8)]
        for bytes in junk {
            for damaged in ["data/fitness.json", "api/state", "data/standing.json", "data/insights-v2.json", "data/alerts.json",
                            "data/body.json", "data/activities.json", "data/dismissed.json", "data/today-layout.json"] {
                let raw = PFRawBundle.cached(read: { $0 == damaged ? bytes : full($0) })
                if let raw { _ = PFBuilder.snapshot(from: raw, today: "2030-03-13") }
            }
        }
    }

    func testCachedPhaseFourDocumentsFromAnotherDayStillParse() throws {
        let files = try fixtureFiles()
        let read: (String) -> Data? = { path in
            guard let value = files[path] else { return nil }
            if let text = value as? String { return Data(text.utf8) }
            return try? JSONSerialization.data(withJSONObject: value)
        }
        let raw = try XCTUnwrap(PFRawBundle.cached(read: read))
        for offset in [-400, -3, 0, 3, 400] {
            XCTAssertNotNil(PFBuilder.snapshot(from: raw, today: daysFromFixtureDay(offset)), "\(offset)")
        }
    }

    // MARK: Healthspan weeks kept on the phone, Journal impact "seen" list, My Dashboard list

    func testHealthspanWeeksRoundTrip() throws {
        let weeks = [PFHealthspanWeek(week: "2030-W11", asOf: "2030-03-13", ageLow: 30.1, ageHigh: 33.2, paceValue: 0.9, paceLow: 0.8, paceHigh: 1.1)]
        XCTAssertEqual(PFHealthspanHistory.decode(PFHealthspanHistory.encode(weeks)), weeks)
    }

    func testDamagedHealthspanWeeksReadAsNone() {
        for text in ["", "{", "null", "{}", #"[{"week":"2030-W11"}]"#, #"[{"week":1,"asOf":2,"ageLow":"x","ageHigh":null}]"#, "[1]"] {
            XCTAssertEqual(PFHealthspanHistory.decode(Data(text.utf8)), [], text)
        }
    }

    func testAbsentHealthspanWeeksReadAsNone() {
        XCTAssertEqual(PFHealthspanHistory.decode(nil), [])
    }

    func testHealthspanWeeksNeverGrowPastTheCap() {
        var weeks: [PFHealthspanWeek] = []
        for n in 0..<(PFHealthspanHistory.maxWeeks + 40) {
            let entry = PFHealthspanWeek(week: String(format: "2030-W%03d", n), asOf: "", ageLow: 30, ageHigh: 31, paceValue: nil, paceLow: nil, paceHigh: nil)
            weeks = PFHealthspanHistory.upserting(entry, into: weeks)
        }
        XCTAssertEqual(weeks.count, PFHealthspanHistory.maxWeeks)
    }

    func testHealthspanNeighbourOfAWeekThePhoneNeverSavedIsNil() {
        XCTAssertNil(PFHealthspanHistory.neighbour(of: "2030-W99", step: 1, in: []))
    }

    func testJournalImpactSeenListOfAnyShapeReadsAsASet() {
        for raw in [nil, "", ",", "a,b,a", "\u{0}", String(repeating: "id,", count: 5000)] {
            _ = PFSeenIDs.decode(raw)
        }
        XCTAssertEqual(PFSeenIDs.decode("a,b,a"), ["a", "b"])
    }

    func testJournalImpactFirstVisitMarksNothingNew() {
        XCTAssertEqual(PFSeenIDs.newIDs(current: ["a"], seen: PFSeenIDs.decode(nil)), [])
    }

    func testMyDashboardListOfAnyShapeReadsAsAList() {
        for raw in ["", ",", ",,a,,", "a,a,a", "\u{0}", " ", String(repeating: "x,", count: 5000)] {
            XCTAssertEqual(Set(MyDashboardPrefs.decode(raw)).count, MyDashboardPrefs.decode(raw).count, raw)
        }
    }

    func testMyDashboardMovesWithBadIndicesLeaveTheListAlone() {
        let ids = ["a", "b", "c"]
        for (from, to) in [(-1, 0), (0, -1), (3, 0), (0, 3), (Int.min, Int.max), (1, 1)] {
            XCTAssertEqual(MyDashboardPrefs.moving(ids, from: from, to: to), ids, "\(from) \(to)")
        }
    }
}
