import SwiftUI
import StrandDesign

/// "What affects your recovery": how the habits logged in NOOP's journal line up with the next morning's
/// scores, from behaviour-impact.json. An association, never a cause: the label says so, and the sources
/// (PaceForge, Garmin, NOOP) are listed apart and never merged.
struct PFBehaviourCard: View {
    let impact: PFBehaviourImpact

    private static let maxItems = 4

    var body: some View {
        PFCard(title: "What affects your recovery", icon: "leaf", info: PFExplainerID.behaviour, trailing: {
            PFChip(text: PFFormat.capitalized(impact.label ?? "association, not proof"), color: PFColor.sky)
                .accessibilityIdentifier("pf-behaviour-label")
        }) {
            VStack(alignment: .leading, spacing: 14) {
                if impact.items.isEmpty {
                    insufficientIntro
                } else {
                    ForEach(impact.items.prefix(Self.maxItems)) { PFBehaviourRow(item: $0) }
                    Text(footnote)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !impact.insufficient.isEmpty { waiting }
            }
        }
        .containerIdentifier("pf-behaviour-card")
    }

    private var footnote: String {
        let window = impact.windowDays.map { "the last \($0) days" } ?? "your recent days"
        return "Compares the morning after a yes with the morning after a no, over \(window). Other things differ on those days."
    }

    private var insufficientIntro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insufficient data yet")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityIdentifier("pf-behaviour-insufficient")
            PFParagraph("A habit needs at least \(impact.minEach) yes days and \(impact.minEach) no days with a next-morning reading before it is compared. Keep answering the journal in NOOP.")
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !impact.items.isEmpty { Text("Insufficient data yet").strandOverline() }
            ForEach(impact.insufficient) { question in
                HStack(alignment: .firstTextBaseline) {
                    Text(PFFormat.capitalized(question.label))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 8)
                    Text("\(question.yes) yes \u{00B7} \(question.no) no, needs \(impact.minEach) each")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .containerIdentifier("pf-behaviour-waiting")
    }
}

private struct PFBehaviourRow: View {
    let item: PFBehaviourItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(PFFormat.capitalized(item.label))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text("\(item.daysYes) yes \u{00B7} \(item.daysNo) no")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if let line = item.line {
                Text(line)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Each source on its own line, so PaceForge's, Garmin's and NOOP's reads are never read as one.
            ForEach(Array(item.orderedEffects.enumerated()), id: \.offset) { _, entry in effectRow(entry.effect) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
        .accessibilityElement(children: .combine)
        .containerIdentifier("pf-behaviour-\(item.id)")
    }

    private func effectRow(_ effect: PFBehaviourEffect) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(effect.source.uppercased())
                .font(StrandFont.overline)
                .foregroundStyle(effect.source == "NOOP" ? PFColor.violet : PFColor.sky)
                .frame(width: 74, alignment: .leading)
            Text(effect.what)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(signed(effect))
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            Text("n \(effect.nYes)/\(effect.nNo)")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func signed(_ effect: PFBehaviourEffect) -> String {
        guard let diff = effect.diff else { return "\u{2013}" }
        let dp = effect.unit == "ms" ? 1 : 0
        let text = String(format: "%.\(dp)f", abs(diff))
        return (diff < 0 ? "\u{2212}" : "+") + text + (effect.unit.isEmpty ? "" : " \(effect.unit)")
    }
}
