import SwiftUI
import StrandDesign

/// The floating tab bar with the inbox's dots: one on the Plan tab while a plan change, a report or the morning verdict is unread, one on
/// the Coach button while a coach note or a workout review is unread. Its own view, so the shell does not watch the inbox.
struct PFInboxTabBar529: View {
    let items: [LookTabItem]
    @Binding var selection: String
    let onCoach: () -> Void

    @ObservedObject private var inbox = PFInboxStore529.shared

    var body: some View {
        FloatingTabBar(items: items, selection: $selection, onCoach: onCoach,
                       dotIDs: inbox.hasUnreadPlan ? ["plan"] : [],
                       coachDot: inbox.hasUnreadCoach)
            .task { await inbox.refreshIfStale() }
    }
}
