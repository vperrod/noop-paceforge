import SwiftUI
import StrandDesign

/// The floating tab bar with the inbox's dots: one on the Plan tab while a plan change, a report or the morning verdict is unread, one on
/// the Coach button while a coach note or a workout review is unread. Its own view, so the shell does not watch the inbox.
struct PFInboxTabBar529: View {
    let items: [LookTabItem]
    @Binding var selection: String
    let onCoach: () -> Void

    @ObservedObject private var inbox = PFInboxStore529.shared
    @ObservedObject private var history = PFAlertHistoryStore.shared

    var body: some View {
        let unread = inbox.unreadRows()
        FloatingTabBar(items: items, selection: $selection, onCoach: onCoach,
                       dotIDs: PFInboxLogic529.hasUnread(unread, kinds: PFInboxLogic529.planDotKinds) ? ["plan"] : [],
                       coachDot: PFInboxLogic529.hasUnread(unread, kinds: PFInboxLogic529.coachDotKinds))
            .task { await inbox.refreshIfStale() }
    }
}
