import SwiftUI

// Where the five Phase 4 documents live on the phone (healthspan, journal impact, highlights, monthly report, my plan).
// NOOP Today (the streak chip, the My Plan card), the Highlights, Healthspan, Journal impact and Monthly report screens read
// them without the PaceForge tab being open, so they share one store: the refresh coordinator hands it the documents, and
// every screen asks the coordinator to refresh when its copy is more than two minutes old.
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

    private init() {
        weeks = PFHealthspanHistory.decode(UserDefaults.standard.data(forKey: PFHealthspanHistory.storageKey))
    }

    /// The highlights for the Home streak chip. Nothing when the document is missing, unavailable or has no streak alive.
    var streakChip: PFHighlightsLogic.Chip? { PFHighlightsLogic.chip(docs.highlights.value) }

    /// The refresh coordinator hands the store the documents when one changed (or the first time), whichever screen asked.
    func update(_ new: PFIntelDocs) {
        // NOOP Today (the whole dashboard) observes this store; an equal assignment would still publish.
        if docs != new { docs = new }
        if !didLoad { didLoad = true }
        rememberWeek()
    }

    /// Asks the coordinator for the documents when its copy is more than two minutes old. The coordinator downloads only the ones
    /// whose server hash differs from the saved copy, and shares the run with whatever else is refreshing.
    func refreshIfStale() async {
        guard PFAPI.isConfigured else {
            didLoad = true
            return
        }
        _ = try? await PFRefreshCoordinator.shared.refreshIfStale(.phase4, maxAge: 120)
        // A refresh that failed before it published still ends the load: a screen shows nothing until `didLoad`.
        if !didLoad { didLoad = true }
    }

    /// Keeps this week's body age and pace so the week stepper and the trend card have something to step through.
    private func rememberWeek() {
        if !PFAPI.usesPhoneState {
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
