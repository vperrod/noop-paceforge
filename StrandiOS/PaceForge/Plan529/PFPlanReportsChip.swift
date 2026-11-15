import SwiftUI
import StrandDesign

/// The Reports chip of the Plan tab (P1): every report in one list, each row with its verdict, new ones with a dot.
struct PFPlanReportsChip: View {
    @StateObject private var store = PFDocStore529<PFReportsListDoc>(path: PFDocPath529.reportsList)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading)
            case .empty:
                // A server that does not write the reports list yet: the Coach's old index (Day, Week, Month, Race), as before.
                PFReportsIndexContent()
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await store.refresh() } })
            case .loaded(let doc):
                if store.isStale { PFStaleNote529() }
                PFPlanReportsContent529(doc: doc)
            }
        }
        .lockGate529()
        .containerIdentifier("calendar-chip-content-reports")
        .task { await store.refreshIfStale() }
        .reloadsAfterPull529 { await store.refresh() }
    }
}
