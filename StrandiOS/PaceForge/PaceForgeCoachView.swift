import SwiftUI
import StrandDesign

/// PaceForge "Coach": the daily brief, Coach's Take, the latest weekly review and the chat tail.
struct PFCoachView: View {
    let snapshot: PFSnapshot

    private var coach: PFCoach { snapshot.coach }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            briefCard
            takeCard
            weeklyReviewCard
            chatCard
        }
    }

    // MARK: Daily brief

    private var briefCard: some View {
        PFCard("Daily brief" + (coach.brief.date.map { " \u{00B7} \(PFFormat.shortDate($0))" } ?? ""), icon: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                Text(coach.brief.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array((coach.brief.outlook ?? []).enumerated()), id: \.offset) { _, paragraph in
                    PFParagraph(paragraph)
                }
            }
        }
    }

    // MARK: Coach's Take

    private var takeCard: some View {
        PFCard(title: "Coach's Take", icon: "sparkles", trailing: { readinessChip }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(coach.take.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                let limiters = coach.take.limiters ?? []
                if !limiters.isEmpty {
                    Text("Your top limiters").strandOverline()
                    ForEach(Array(limiters.enumerated()), id: \.offset) { index, l in
                        PFLimiterRow(rank: index + 1, limiter: l)
                    }
                }

                let actions = coach.take.weekActions ?? []
                if !actions.isEmpty {
                    Text("This week's actions").strandOverline()
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, a in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}").foregroundStyle(StrandPalette.accent)
                            Text(a.action)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var readinessChip: some View {
        if let score = coach.take.readinessScore {
            let band = coach.take.readinessBand ?? ""
            PFChip(text: "Readiness \(Int(score.rounded())) \u{00B7} \(band)",
                   color: band == "low" ? PFColor.critical : band == "moderate" ? PFColor.warning : PFColor.positive)
        }
    }

    // MARK: Weekly review

    private var weeklyReviewCard: some View {
        let review = coach.weeklyReview
        return PFCard(title: "Week review", icon: "calendar", trailing: {
            Text(PFFormat.span(review.period.start, review.period.end))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(review.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let planned = review.plannedRuns, let done = review.completedRuns {
                    HStack(spacing: 8) {
                        PFChip(text: "\(done) of \(planned) runs", color: done == planned ? PFColor.positive : PFColor.warning)
                        if let quality = review.qualityDone {
                            PFChip(text: "\(quality) quality", color: StrandPalette.accent)
                        }
                    }
                }

                ForEach(Array((review.sessions ?? []).enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: s.completed ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(s.completed ? PFColor.positive : PFColor.critical)
                            .font(.system(size: 14))
                        Text(s.name)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Text(PFFormat.shortDate(s.date))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }

                if let limiters = review.limiters, !limiters.isEmpty {
                    PFLabeled(label: "Limiters", text: limiters.joined(separator: " \u{00B7} "))
                }
                if let fatigue = review.fatigue, !fatigue.isEmpty {
                    PFLabeled(label: "Fatigue", text: fatigue.map(\.text).joined(separator: "\n"))
                }
                if let said = review.strengthSaid { PFLabeled(label: "Strength", text: said) }
                if let actions = review.thisWeek, !actions.isEmpty {
                    PFLabeled(label: "Next up", text: actions.joined(separator: "\n"))
                }
            }
        }
    }

    // MARK: Chat

    private var chatCard: some View {
        PFCard("Talk to your coach", icon: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(coach.chat) { PFChatBubble(turn: $0) }

                HStack(spacing: 10) {
                    TextField("Ask your coach", text: .constant(""))
                        .textFieldStyle(.plain)
                        .disabled(true)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Capsule(style: .continuous).fill(StrandPalette.surfaceInset))
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .opacity(0.55)
                .accessibilityIdentifier("pf-chat-input")

                Text("Live chat arrives with the server step")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

private struct PFLimiterRow: View {
    let rank: Int
    let limiter: PFLimiter

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(StrandFont.rounded(13))
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(StrandPalette.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(limiter.name)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(limiter.area)
                        .font(StrandFont.overline)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Text(limiter.evidence)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(limiter.recommendation)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceInset))
            }
        }
    }
}

private struct PFChatBubble: View {
    let turn: PFChatTurn

    private var isAthlete: Bool { turn.role == "athlete" }

    var body: some View {
        HStack {
            if isAthlete { Spacer(minLength: 40) }
            Text(turn.text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isAthlete ? StrandPalette.accent.opacity(0.22) : StrandPalette.surfaceInset)
                )
            if !isAthlete { Spacer(minLength: 40) }
        }
    }
}
