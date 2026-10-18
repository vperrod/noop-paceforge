import Foundation

/// UI tests only. A simulator starts with no saved state, and a fixture run ignores the phone's saved copies, so neither ever
/// meets what a real iPhone holds after an update: the Today order, the PaceForge arrangement and "Not today" list, and the
/// last good PaceForge documents that the tab shows first. Two launch arguments start the app from such state:
///
/// - `-NoopSeedBuild464State`: exactly what build 464 wrote (its own encoders produced these values, git ef21a268), with the
///   documents kept for offline use holding only what 464 fetched. The new daily-intel and Phase 4 documents are not there.
/// - `-NoopSeedDamagedState`: every one of those values damaged (wrong type, truncated, junk), and a damaged cached document.
///
/// Preferences go in the registration domain, so nothing outlives the launch; the cached documents are files that every seeded
/// launch writes again. Release builds contain none of this.
enum PFSavedStateSeed {
    static let build464Flag = "-NoopSeedBuild464State"
    static let damagedFlag = "-NoopSeedDamagedState"

    #if DEBUG
    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(build464Flag) || arguments.contains(damagedFlag)
    }

    /// The documents build 464 never fetched.
    private static let documentsAdded465 = [
        "data/daily-intel.json", "data/healthspan.json", "data/journal-impact.json", "data/highlights.json",
        "data/monthly-report.json", "data/my-plan.json",
    ]

    /// Call first thing at launch, before any screen reads a preference.
    static func apply() {
        let arguments = ProcessInfo.processInfo.arguments
        guard PFAPI.isFixture else { return }
        guard isRequested else {
            // The Healthspan weeks are the one value a seeded run can leave behind in the real preferences.
            UserDefaults.standard.removeObject(forKey: PFHealthspanHistory.storageKey)
            return
        }
        let damaged = arguments.contains(damagedFlag)
        let preferences = damaged ? damagedPreferences : build464Preferences
        // A value an earlier seeded launch saved would hide the registered one.
        for key in preferences.keys { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.register(defaults: preferences)
        seedCache(damaged: damaged)
    }

    // What build 464 wrote.
    private static let build464Preferences: [String: Any] = [
        "today.sectionOrder": "journal,hero,workouts,synthesis,liveSession,keyMetrics,heartRate,recoveryVitals,yourCards,menstrualCycle,addedCards",
        "today.hiddenSections": "synthesis,journal",
        "noop.paceforge.segment": "insights",
        "theme.appearance": "system",
        "noop.showDayCycleBackground": true,
        PFTodayLayoutStorage.defaultsKey: Data(#"{"order":["race-week","brief","today-so-far","session","next-best-action","easy","feel","alerts","daily","what-changed","readiness","standing","next-race"],"pinned":["brief","alerts"]}"#.utf8),
        PFDismissStorage.defaultsKey: Data(#"[{"key":"brief","text_hash":"f55c314b","dismissed_at":"2030-03-01T04:00:00Z"},{"dismissed_at":"2030-03-01T04:00:00Z","until":"2099-01-01","key":"what-changed","text_hash":"12aa51d3"}]"#.utf8),
    ]

    // The same keys, every value of the wrong type or unreadable.
    private static let damagedPreferences: [String: Any] = [
        "today.sectionOrder": ",,,hero,hero,\u{0},BOGUS,journal,,",
        "today.hiddenSections": 42,
        "noop.paceforge.segment": "no-such-segment",
        "theme.appearance": "sepia",
        "noop.showDayCycleBackground": "maybe",
        "noop.myDashboard.metrics": "my-whoop:hrv,,nope,my-whoop:hrv, ,x:y:z",
        PFTodayLayoutStorage.defaultsKey: Data("{\"order\":[1,2,".utf8),
        PFDismissStorage.defaultsKey: "not data at all",
        PFHealthspanHistory.storageKey: Data("[{\"week\":7}]".utf8),
        PFSeenIDs.storageKey: Data([0, 255, 1]),
    ]

    /// `Application Support/PaceForge`: the documents a 464 phone had saved from its last good fetch, as the server's own
    /// bytes. A damaged run saves junk for the documents the tab reads first and keeps the two it cannot open without.
    private static func seedCache(damaged: Bool) {
        guard let files = PFAPI.fixture else { return }
        for path in documentsAdded465 { PFStore.remove(path: path) }
        for (path, value) in files where (path.hasPrefix("data/") && !documentsAdded465.contains(path)) || path == "api/state" {
            let junk = damaged && path != "api/state" && path != "data/fitness.json"
            if junk { PFStore.write(Data("{\"truncated\":".utf8), path: path); continue }
            if let text = value as? String { PFStore.write(Data(text.utf8), path: path); continue }
            if let data = try? JSONSerialization.data(withJSONObject: value) { PFStore.write(data, path: path) }
        }
    }
    #else
    static var isRequested: Bool { false }
    #endif
}
