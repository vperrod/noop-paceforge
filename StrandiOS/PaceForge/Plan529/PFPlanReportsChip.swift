import SwiftUI

/// The Reports chip of the Plan tab. Until APP-2 replaces it, it shows the Coach's Reports index (Day, Week, Month, Race).
struct PFPlanReportsChip: View {
    var body: some View {
        PFReportsIndexContent()
            .containerIdentifier("calendar-chip-content-reports")
    }
}
