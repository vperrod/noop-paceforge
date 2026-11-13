import SwiftUI
import StrandDesign

// MARK: Daily briefing

/// The coach's daily briefing with every field the PaceForge web Today card renders. Dimmed and
/// labelled when it was written on an earlier day.
struct PFBriefCard: View {
    let brief: PFDailyBrief
    let todayISO: String
    private let hiding = PFHiding()

    private var isToday: Bool { brief.date == todayISO }
    /// The Daily Outlook bar opens and closes the briefing. Open by default, so the briefing reads as it always did.
    @State private var isOpen = true

    var body: some View {
        PFCard(title: "Daily briefing", icon: "sparkles", trailing: {
            if !isToday, let date = brief.date {
                PFChip(text: "from \(PFFormat.shortDate(date))", color: StrandPalette.textTertiary)
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                OutlookBar(isOpen ? "Your Daily Outlook" : hiding.text(brief.headline), isExpanded: isOpen) {
                    withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
                }
                .accessibilityIdentifier("pf-brief-outlook")
                if isOpen { briefBody }
            }
        }
        .opacity(isToday ? 1 : 0.7)
        .containerIdentifier("pf-brief-card")
    }

    private var briefBody: some View {
        PFBriefBody(brief: brief)
    }
}

/// The whole briefing, every field the web card renders. Split out of the card so the outlook bar can fold it.
private struct PFBriefBody: View {
    let brief: PFDailyBrief
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text(hiding.text(brief.headline))
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let changes = brief.changes {
                    Label(hiding.text(changes), systemImage: "arrow.left.arrow.right")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-brief-changes")
                }
                if brief.partial && !brief.missing.isEmpty {
                    Label("Waiting for: " + brief.missing.joined(separator: ", "), systemImage: "hourglass")
                        .font(StrandFont.caption)
                        .foregroundStyle(PFColor.warning)
                        .accessibilityIdentifier("pf-brief-waiting")
                }
                if let updated = brief.updatedAt, let time = PFFormat.timeOfDay(updated) {
                    Text("Updated \(time)")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityIdentifier("pf-brief-updated")
                }

                ForEach(Array(brief.notes.enumerated()), id: \.offset) { _, note in
                    PFCallout(text: note, color: PFColor.warning, label: nil)
                }
                ForEach(Array(brief.outlook.enumerated()), id: \.offset) { _, paragraph in
                    PFParagraph(paragraph)
                }
                section("Your body today", brief.bodyState)
                section("Today's training", brief.training)
                section("The last few days", brief.recent)

                if !brief.focus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Focus").strandOverline()
                        ForEach(Array(brief.focus.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\u{2022}").foregroundStyle(StrandPalette.accent)
                                Text(hiding.text(item))
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                ForEach(Array(brief.pulses.enumerated()), id: \.offset) { _, pulse in
                    PFCallout(text: pulse.text, color: PFColor.sky,
                              label: "Day pulse" + (PFFormat.relative(pulse.at).map { " \u{00B7} \($0)" } ?? ""))
                }
        }
    }

    @ViewBuilder private func section(_ title: String, _ markdown: String?) -> some View {
        if let markdown {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).strandOverline()
                PFMarkdown(text: markdown)
            }
        }
    }
}

private struct PFCallout: View {
    let text: String
    let color: Color
    let label: String?
    private let hiding = PFHiding()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                if let label { Text(label).strandOverline() }
                Text(hiding.text(text))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
    }
}
