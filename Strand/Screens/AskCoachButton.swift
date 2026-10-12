import SwiftUI
import StrandDesign

/// "Ask about this": at the foot of a metric's info sheet, hands Coach a prefilled question about that
/// metric. It closes the sheet and opens Coach, which sends the question (the same hand-off the Today launcher
/// uses, so the send, consent and error handling stay in one place). Nothing is sent from here, and the button
/// is not drawn until a provider is connected and Coach is switched on.
struct AskCoachButton: View {
    /// The metric as the question should name it: "HRV", "Charge", "Sleep Planner".
    let metric: String
    /// Dismisses the sheet this button sits in.
    let onClose: () -> Void

    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter

    var body: some View {
        if coach.isConfigured && CoachBriefScheduler.coachMasterEnabled {
            Button {
                coach.pendingPrompt = CoachAskPrompt.question(about: metric)
                onClose()
                router.openCoach()
            } label: {
                Label {
                    Text(verbatim: "Ask about this")
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(StrandFont.subhead)
            }
            .buttonStyle(.bordered)
            .tint(StrandPalette.accent)
            .accessibilityIdentifier("ask-coach-button")
        }
    }
}
