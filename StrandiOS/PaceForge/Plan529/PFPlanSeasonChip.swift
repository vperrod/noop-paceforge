import SwiftUI

/// The Season chip of the Plan tab. Until APP-2 replaces it, it shows the season plan, Events and the weeks, as before.
struct PFPlanSeasonChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(CalendarSeasonChip(snapshot: snapshot)) })
    }
}
