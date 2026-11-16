import SwiftUI
import StrandDesign

/// The ways into the Sunday review that sit on other screens.

/// The row on a finished week's page (Plan, Week) that opens its review.
struct PFReviewLinkRow530: View {
    let week: String

    var body: some View {
        Button { PFDeepLink529.open(.sheet(.review(week: week))) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sunday review")
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    PFWeekSub529(text: "The week in charts, then the week ahead.")
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .pfWeekCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review530-open-\(week)")
    }
}

/// The card Today shows on Sunday evening and Monday morning (mounted by the Today stream): "Week 46 reviewed", a tap opens the review.
/// `week` is the finished week's ISO week ("2026-W46").
struct PFReviewTodayRow530: View {
    let week: String

    var body: some View {
        Button { PFDeepLink529.open(.sheet(.review(week: week))) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week \(PFReviewFormat530.weekNumber(week)) reviewed")
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    PFWeekSub529(text: "The week behind you, then the week ahead.")
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .pfWeekCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review530-today-row")
    }
}
