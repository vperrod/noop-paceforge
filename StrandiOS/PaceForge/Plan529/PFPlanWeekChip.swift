import SwiftUI

/// The Week chip of the Plan tab. Until APP-1 replaces it, it shows what This week and Next week showed: the week with My Plan above it,
/// then the week report and next week's plan. `week` is the ISO week a deep link asked for ("2026-W47"); the placeholder ignores it.
struct PFPlanWeekChip: View {
    var week: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Next week reads its own store, so the snapshot's lock, loading and failed states must not stand in front of it.
            PFSnapshotHost(content: { snapshot in AnyView(CalendarPlanChip(snapshot: snapshot)) })
            CalendarNextWeekChip()
        }
        .containerIdentifier("calendar-chip-content-week")
    }
}
