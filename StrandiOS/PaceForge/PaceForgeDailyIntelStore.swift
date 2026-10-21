import SwiftUI

// Where daily-intel.json lives on the phone. NOOP Today, the Health monitor screen, the Sleep Planner and the metric
// screens read it without the PaceForge tab being open, so it has one shared store: the tab's refresh hands it the file
// it already fetched, and every other screen asks it to refresh itself when its copy is more than two minutes old.
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

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    /// The file when it was written for the phone's today; a file from another day is not today's call.
    var current: PFDailyIntel? {
        guard let intel, intel.isCurrent(for: PFAPI.todayISO) else { return nil }
        return intel
    }

    /// The PaceForge tab already fetched the file; keep it instead of fetching it a second time.
    func update(_ new: PFDailyIntel?) {
        // Assigning a @Published value publishes even when it is equal, and NOOP Today (the whole dashboard) observes this
        // store: only a changed file is assigned.
        if intel != new { intel = new }
        if !didLoad { didLoad = true }
        lastFetch = Date()
    }

    func refreshIfStale() async {
        if PFBeta.isOn, await refreshViaCoordinator() { return }
        if let lastFetch, didLoad, Date().timeIntervalSince(lastFetch) < 120 { return }
        await refresh()
    }

    /// Beta only (see PaceForgeBeta.swift): the coordinator downloads the file only when the server's hash differs from the saved
    /// copy and hands it to `update`. False after a `refresh.beta.fallback` breadcrumb: the caller then refreshes the way build 477 did.
    private func refreshViaCoordinator() async -> Bool {
        guard PFAPI.isConfigured else {
            didLoad = true
            return true
        }
        do {
            _ = try await PFRefreshCoordinator.shared.refreshIfStale(.dailyIntel, maxAge: 120)
            // A refresh that published nothing still ends the load: a screen shows nothing until `didLoad`.
            if !didLoad { didLoad = true }
            return true
        } catch {
            PFBeta.fallback(PFBeta.reason(error))
            return false
        }
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
        var data = await PFAPI.fetchOptional(Self.path)
        // Offline: the copy the last good fetch left on the phone. A fixture never reads it.
        if data == nil, PFAPI.usesPhoneState { data = PFStore.read(path: Self.path) }
        let parsed = PFDailyIntelParse.document(PFJ(data: data))
        if intel != parsed { intel = parsed }
        // A load that found nothing (offline with no saved copy) is not "fresh": the next screen that asks tries again.
        if parsed != nil { lastFetch = Date() }
        if !didLoad { didLoad = true }
    }
}
