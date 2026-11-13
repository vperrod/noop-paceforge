import SwiftUI
import StrandDesign

/// PaceForge "Coach": today's read (a headline and up to three sentences, the full read folded), the one composer, how many things
/// wait on the athlete. The Coach log (three days) follows it on the screen. The week review lives with the reports (Insights), the
/// season plan and the race plans with Plan, the numbers and the readiness with Today.
struct PFCoachView: View {
    let snapshot: PFSnapshot
    @EnvironmentObject private var model: PFModel

    private var coach: PFCoach { snapshot.coach }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coach.brief != nil || coach.take != nil { todayRead(brief: coach.brief, take: coach.take) }
            PFCoachComposer(snapshot: snapshot)
            waitingRow
        }
    }

    // MARK: Waiting on you

    /// How many things PaceForge is waiting on him for; the row opens the week plan, where each proposal has its reasons and Accept / Reject.
    @ViewBuilder private var waitingRow: some View {
        let count = snapshot.needsYou.count
        if count > 0 {
            NavigationLink(value: TabRoute.reports("week")) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityHidden(true)
                    Text("Waiting on you")
                        .lookCaps(12.5)
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineLimit(1)
                    PFChip(text: "\(count)", color: PFNeutral.other)
                        .fixedSize()
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach-waiting-on-you")
        }
    }

    // MARK: Today's read

    private static let summarySentences = 3

    private func todayRead(brief: PFBrief?, take: PFTake?) -> some View {
        let headline = brief?.headline ?? take?.headline ?? ""
        let summary = PFCoachRead.summary(paragraphs: brief?.outlook ?? [], sentences: Self.summarySentences)
        return PFCard(title: "Today's read", icon: "sparkles", trailing: {
            HStack(spacing: 6) {
                if let date = brief?.date {
                    Text(PFFormat.shortDate(date)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                if let take { readinessChip(take) }
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !summary.isEmpty { PFParagraph(summary) }
                DisclosureGroup("Full read") {
                    fullRead(brief: brief, take: take)
                        .padding(.top, 8)
                }
                .font(StrandFont.subhead.weight(.semibold))
                .tint(StrandPalette.accent)
                .accessibilityIdentifier("coach-todays-full-read")
            }
        }
        .accessibilityIdentifier("coach-todays-read")
    }

    /// Everything the brief and the take say, as the card used to draw it.
    private func fullRead(brief: PFBrief?, take: PFTake?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let brief {
                if let sourceContext = brief.sourceContext {
                    Text(sourceContext)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array((brief.outlook ?? []).enumerated()), id: \.offset) { _, paragraph in
                    PFParagraph(paragraph)
                }
            }
            if let take {
                if brief != nil { Rectangle().fill(StrandPalette.hairline).frame(height: 1).padding(.vertical, 2) }
                Text(take.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                let limiters = take.limiters ?? []
                if !limiters.isEmpty {
                    Text("What is affecting you").strandOverline()
                    ForEach(Array(limiters.enumerated()), id: \.offset) { index, limiter in
                        PFLimiterRow(rank: index + 1, limiter: limiter)
                    }
                }
                let actions = take.weekActions ?? []
                if !actions.isEmpty {
                    Text("What to do next").strandOverline()
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}").foregroundStyle(StrandPalette.accent)
                            Text(action.action)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let generatedAt = snapshot.generatedAt {
                HStack(alignment: .firstTextBaseline) {
                    Text("PaceForge snapshot assembled")
                    Spacer(minLength: 8)
                    Text(PFFormat.relative(generatedAt) ?? generatedAt)
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
            }
            if let offlineNote = model.offlineNote {
                Text(offlineNote)
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func readinessChip(_ take: PFTake) -> some View {
        if let score = take.readinessScore {
            let band = take.readinessBand ?? ""
            PFChip(text: "Readiness \(Safe.int(score)) \u{00B7} \(band)",
                   color: band == "low" ? PFColor.critical : band == "moderate" ? PFColor.warning : PFColor.positive)
        }
    }

    // MARK: Weekly review

    func weeklyReviewCard(_ review: PFWeeklyReview) -> some View {
        PFCard(title: "Week review", icon: "calendar", trailing: {
            Text(PFFormat.span(review.period.start, review.period.end))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(review.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let sourceContext = review.sourceContext {
                    DisclosureGroup("Evidence sources and dates") {
                        Text(sourceContext)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .font(StrandFont.caption.weight(.semibold))
                    .tint(StrandPalette.accent)
                }

                if let fullRead = review.fullRead, !fullRead.isEmpty {
                    DisclosureGroup("Read the full week") {
                        PFMarkdown(text: fullRead)
                            .padding(.top, 8)
                    }
                    .font(StrandFont.subhead.weight(.semibold))
                    .tint(StrandPalette.accent)
                    .accessibilityIdentifier("coach-week-full-read")
                }

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
