import SwiftUI
import StrandDesign

/// The Calendar chip of the Plan tab (C1): a month grid for every month of the plan with each day drawn as bars, the hours of each week,
/// and the chosen day's items with "+ Add an activity" and "+ Day off".
struct PFPlanCalendarChip: View {
    @StateObject private var index = PFDocStore529<PFPlanWeekIndexDoc>(path: PFDocPath529.weekIndex)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch index.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading)
            case .empty:
                // A server that does not write the week documents yet: the month grid from the snapshot's three weeks, as before.
                PFSnapshotHost(content: { snapshot in AnyView(CalendarMonthChip(snapshot: snapshot)) })
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await index.refresh() } })
            case .loaded(let doc):
                if index.isStale { PFStaleNote529() }
                PFCalendarContent529(index: doc)
            }
        }
        .lockGate529()
        .containerIdentifier("calendar-chip-content-calendar")
        .task { await index.refreshIfStale() }
        .reloadsAfterPull529 { await index.refresh() }
    }
}
