import SwiftUI

/// The Calendar chip of the Plan tab. Until APP-2 replaces it, it shows the month grid and the chosen day's sessions, as before.
struct PFPlanCalendarChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(CalendarMonthChip(snapshot: snapshot)) })
    }
}
