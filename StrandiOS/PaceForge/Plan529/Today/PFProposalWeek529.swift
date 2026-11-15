import Foundation

/// "Your coach wants to change N things in your plan" opens Plan > Week on the week the changes are about, with them at the top.
/// The week comes from the earliest day any waiting change names (`data/pending-changes.json`); with none named, the Week chip opens as
/// it was.
@MainActor
enum PFProposalWeek529 {
    static func openWeekWithChanges() {
        Task { @MainActor in
            if let week = await weekWithChanges() {
                PFDeepLink529.open(.week(week))
            } else {
                PFDeepLink529.open(.chip(.week))
            }
        }
    }

    /// "2026-W47", or nil when no waiting change names a day (or the list cannot be read).
    static func weekWithChanges() async -> String? {
        guard let data = try? await PFAPI.fetch(PFWeekPlanStore.pendingPath) else { return nil }
        guard let day = PFWeekPlan.proposals(data).compactMap({ $0.day }).map({ String($0.prefix(10)) }).min() else { return nil }
        return PFFormat.isoWeekKey(day)
    }
}
