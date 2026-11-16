import SwiftUI
import StrandDesign

/// The Season chip of the Plan tab (S1): the season bar, the next race, the races after it, the hours of every week, and the rows for
/// adding a race, programmes and how the plan is built. Race week, when it is race week, sits at the top.
struct PFPlanSeasonChip: View {
    @StateObject private var store = PFDocStore529<PFSeasonDoc>(path: PFDocPath529.season)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFSeasonRaceWeek529()
            switch store.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading)
            case .empty:
                PFDocPlaceholder529(kind: .empty, emptyTitle: "No season yet",
                                    emptyText: "PaceForge writes the season once it has your races. Add one below.")
                // A server that does not write the season document yet still has the season plan as the coach panels hold it.
                PFSeasonPlanCard()
                    .task { await PFCoachPanelsStore.shared.refreshIfStale() }
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await store.refresh() } })
            case .loaded(let doc):
                if store.isStale { PFStaleNote529() }
                PFSeasonContent529(doc: doc)
            }
            PFSeasonLinks529(programmes: store.doc?.programmes, reload: { await store.refresh() })
        }
        .lockGate529()
        .containerIdentifier("calendar-chip-content-season")
        .task { await store.refreshIfStale() }
        .reloadsAfterPull529 { await store.refresh() }
    }
}
