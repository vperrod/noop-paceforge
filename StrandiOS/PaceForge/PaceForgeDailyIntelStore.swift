import SwiftUI

// Where daily-intel.json lives on the phone. NOOP Today, the Health monitor screen, the Sleep Planner and the metric
// screens read it without the PaceForge tab being open, so it has one shared store: the refresh coordinator hands it the
// file, and every screen asks the coordinator to refresh when its copy is more than two minutes old.
// Read-only: nothing here writes to the server.

/// Whether the evening card shows. UI tests force it with `-PaceForgeEvening` / `-PaceForgeMorning` (fixture only), since
/// a simulator run cannot be timed to 18:00.
enum PFIntelClock {
    static func isEvening(_ now: Date = Date()) -> Bool {
        #if DEBUG
        if PFAPI.isFixture {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-PaceForgeEvening") { return true }
            if arguments.contains("-PaceForgeMorning") { return false }
        }
        #endif
        return PFEvening.isEvening(now)
    }
}

@MainActor
final class PFDailyIntelStore: ObservableObject {
    static let shared = PFDailyIntelStore()

    static let path = "data/daily-intel.json"

    @Published private(set) var intel: PFDailyIntel?
    /// True once a load has finished, whether or not it found a file; a screen shows nothing before that.
    @Published private(set) var didLoad = false

    /// The file when it was written for the phone's today; a file from another day is not today's call.
    var current: PFDailyIntel? {
        guard let intel, intel.isCurrent(for: PFAPI.todayISO) else { return nil }
        return intel
    }

    /// The refresh coordinator hands the store the file when it changed (or the first time), whichever screen asked for the refresh.
    func update(_ new: PFDailyIntel?) {
        // Assigning a @Published value publishes even when it is equal, and NOOP Today (the whole dashboard) observes this
        // store: only a changed file is assigned.
        if intel != new { intel = new }
        if !didLoad { didLoad = true }
    }

    /// Asks the coordinator for the file when its copy is more than two minutes old. The coordinator downloads it only when the
    /// server's hash differs from the saved copy, and shares the run with whatever else is refreshing.
    func refreshIfStale() async {
        guard PFAPI.isConfigured else {
            didLoad = true
            return
        }
        _ = try? await PFRefreshCoordinator.shared.refreshIfStale(.dailyIntel, maxAge: 120)
        // A refresh that failed before it published still ends the load: a screen shows nothing until `didLoad`.
        if !didLoad { didLoad = true }
    }
}
