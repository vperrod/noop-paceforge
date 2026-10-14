import SwiftUI

// Where the five Phase 4 documents live on the phone (healthspan, journal impact, highlights, monthly report, my plan).
// NOOP Today (the streak chip, the My Plan card), the Highlights, Healthspan, Journal impact and Monthly report screens read
// them without the PaceForge tab being open, so they share one store: the tab's refresh hands it the documents it already
// fetched, and every other screen asks it to refresh itself when its copy is more than two minutes old.
// Read-only: nothing here writes to the server. The only thing kept besides the cache is the list of Healthspan weeks the
// phone has seen (the server holds only the current week).

@MainActor
final class PFPhase4Store: ObservableObject {
    static let shared = PFPhase4Store()

    @Published private(set) var docs = PFIntelDocs()
    /// True once a load has finished, whether or not it found anything; a screen shows nothing before that.
    @Published private(set) var didLoad = false
    /// The Healthspan weeks seen so far, oldest first.
    @Published private(set) var weeks: [PFHealthspanWeek]

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    private init() {
        weeks = PFHealthspanHistory.decode(UserDefaults.standard.data(forKey: PFHealthspanHistory.storageKey))
    }

    /// The highlights for the Home streak chip. Nothing when the document is missing, unavailable or has no streak alive.
    var streakChip: PFHighlightsLogic.Chip? { PFHighlightsLogic.chip(docs.highlights.value) }

    /// The PaceForge tab already fetched the documents; keep them instead of fetching them a second time.
    func update(_ new: PFIntelDocs) {
        docs = new
        didLoad = true
        lastFetch = Date()
        rememberWeek()
    }

    func refreshIfStale() async {
        if let lastFetch, didLoad, Date().timeIntervalSince(lastFetch) < 120 { return }
        await refresh()
    }

    /// Overlapping callers share the load already running.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await load()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func load() async {
        guard PFAPI.isConfigured else {
            didLoad = true
            return
        }
        async let healthspan = Self.read(PFDocPath.healthspan)
        async let journalImpact = Self.read(PFDocPath.journalImpact)
        async let highlights = Self.read(PFDocPath.highlights)
        async let monthlyReport = Self.read(PFDocPath.monthlyReport)
        async let myPlan = Self.read(PFDocPath.myPlan)
        docs = PFIntelDocsParse.docs(healthspan: PFJ(data: await healthspan), journalImpact: PFJ(data: await journalImpact),
                                     highlights: PFJ(data: await highlights), monthlyReport: PFJ(data: await monthlyReport),
                                     myPlan: PFJ(data: await myPlan))
        lastFetch = Date()
        didLoad = true
        rememberWeek()
    }

    /// The server's copy, else (offline) the one the last good fetch left on the phone. A fixture never reads the cache.
    nonisolated private static func read(_ path: String) async -> Data? {
        let data = await PFAPI.fetchOptional(path)
        if data == nil, !PFAPI.isFixture { return PFStore.read(path: path) }
        return data
    }

    /// Keeps this week's body age and pace so the week stepper and the trend card have something to step through.
    private func rememberWeek() {
        if PFAPI.isFixture {
            Task { await loadFixtureWeeks() }
            return
        }
        guard let healthspan = docs.healthspan.value, let entry = PFHealthspanHistory.entry(from: healthspan) else { return }
        let updated = PFHealthspanHistory.upserting(entry, into: weeks)
        guard updated != weeks else { return }
        weeks = updated
        if let data = PFHealthspanHistory.encode(updated) {
            UserDefaults.standard.set(data, forKey: PFHealthspanHistory.storageKey)
        }
    }

    /// A UI-test fixture carries earlier weeks of its own (`ui/healthspan-weeks.json`), so the stepper and the trend card can
    /// be captured; nothing is stored.
    private func loadFixtureWeeks() async {
        let seeded = PFHealthspanHistory.decode(await PFAPI.fetchOptional("ui/healthspan-weeks.json"))
        if !seeded.isEmpty { weeks = seeded }
    }
}
