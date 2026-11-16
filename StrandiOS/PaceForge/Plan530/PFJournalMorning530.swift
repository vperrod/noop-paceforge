import SwiftUI

/// The journal's morning sheet (screen 5b): the device-answered block, then the morning questions about last night. Opened by the morning
/// journal notification, the inbox row and the Today journal card. The screen is `PFJournalDaySheet530` (Plan530/Journal).
struct PFJournalMorning530: View {
    var body: some View {
        PFJournalDaySheet530(window: PFJournalLogic530.morning)
    }
}
