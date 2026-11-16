import SwiftUI

/// The behaviour insights (screen 5e) as a sheet or a pushed route: its own copy of the journal document, in the screen frame of the Plan
/// section. `PFJournalImpactScreen` (the older route, kept) shows the same body and falls back to its earlier content when the document is
/// not served.
struct PFJournalInsights530: View {
    @StateObject private var store = PFDocStore529<PFJournalDoc530>(path: PFDocPath529.journal)

    var body: some View {
        content
            .planScreen529(title: "Behaviour insights", identifier: "pf530-journal-insights")
            .task { await store.refresh() }
            .reloadsAfterPull529 { await store.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .loading:
            PFDocPlaceholder529(kind: .loading)
        case .empty:
            PFDocPlaceholder529(kind: .empty, emptyTitle: "Nothing learned yet",
                                emptyText: "PaceForge has not published your journal results. They show here once it has.")
        case .failed:
            PFDocPlaceholder529(kind: .failed, failedText: "PaceForge could not be reached, so the journal results are not on this phone yet.",
                                retry: { Task { await store.refresh() } })
        case .loaded(let doc):
            VStack(alignment: .leading, spacing: 12) {
                if store.isStale { PFStaleNote529() }
                PFJournalInsightsBody530(doc: doc)
            }
        }
    }
}
