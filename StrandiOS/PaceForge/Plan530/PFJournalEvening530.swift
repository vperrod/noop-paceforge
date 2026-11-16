import SwiftUI

/// The journal's evening reflection (screen 5d): the evening card, then the day's questions. The screen is `PFJournalDaySheet530`
/// (Plan530/Journal).
struct PFJournalEvening530: View {
    var body: some View {
        PFJournalDaySheet530(window: PFJournalLogic530.evening)
    }
}
