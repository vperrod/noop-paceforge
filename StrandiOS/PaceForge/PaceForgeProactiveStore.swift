import SwiftUI

// Where proactive.json lives on the phone. NOOP Today and the Coach's Insights chip both read it without the PaceForge tab being open,
// so it has one shared store; a screen asks it to refresh itself when its copy is more than two minutes old. Read-only.

@MainActor
final class PFProactiveStore: ObservableObject {
    static let shared = PFProactiveStore()

    static let path = "data/proactive.json"

    @Published private(set) var doc: PFProactiveDoc?

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 120 { return }
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
        guard PFAPI.isConfigured else { return }
        var data = await PFAPI.fetchOptional(Self.path)
        // Offline: the copy the last good fetch left on the phone. A fixture never reads it.
        if data == nil, PFAPI.usesPhoneState { data = PFStore.read(path: Self.path) }
        let parsed = PFProactiveDoc.parse(PFJ(data: data))
        if doc != parsed { doc = parsed }
        // A load that found nothing is not "fresh": the next screen that asks tries again.
        if parsed != nil { lastFetch = Date() }
    }
}
