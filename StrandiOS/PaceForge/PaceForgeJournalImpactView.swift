import SwiftUI
import StrandDesign

// Journal impact, in the look of a "recovery impact analysis": a header with HURTS on the left, the % impact in the middle and
// HELPS on the right, then one card per behaviour with its signed percentage and a diverging bar over a hatched track. A
// behaviour new since the last visit carries a NEW chip; the ones with too few days are listed with what they still need;
// a tap opens the days behind a behaviour, the confidence and what to do. The numbers are the next morning's score with versus
// without the behaviour (journal-impact.json); they lined up with it, they do not prove the cause, and the screen says so.

// MARK: - The bar

/// A diverging bar: the track is hatched, the centre line is zero, and the fill grows left (hurts) or right (helps).
struct PFImpactBar: View {
    /// 0...1 of the half-width.
    let fraction: Double
    let pointsRight: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
                    context.fill(track, with: .color(NoopLook.track.opacity(0.55)))
                    var hatch = Path()
                    var x: CGFloat = -size.height
                    while x < size.width {
                        hatch.move(to: CGPoint(x: x, y: size.height))
                        hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 7
                    }
                    context.clip(to: track)
                    context.stroke(hatch, with: .color(NoopLook.hatch), style: StrokeStyle(lineWidth: 1))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                if fraction > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: max(half * CGFloat(min(fraction, 1)), 3), height: geo.size.height - 4)
                        .offset(x: pointsRight ? half : half - max(half * CGFloat(min(fraction, 1)), 3), y: 0)
                }
                Rectangle()
                    .fill(NoopLook.textPrimary.opacity(0.85))
                    .frame(width: 2, height: geo.size.height + 6)
                    .offset(x: half - 1)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - Screen

struct PFJournalImpactScreen: View {
    @ObservedObject private var store = PFPhase4Store.shared

    var body: some View {
        PFDocScreen(title: "Journal impact", identifier: "pf-journal-impact") {
            PFDocStateView(state: store.docs.journalImpact, didLoad: store.didLoad, title: "Journal impact", icon: "book.closed",
                           identifier: "pf-journal-impact") { impact, item in
                PFJournalImpactBody(impact: impact, item: item)
            }
        }
    }
}

struct PFJournalImpactBody: View {
    let impact: PFJournalImpact
    let item: PFIntelItem

    @State private var newIDs: Set<String> = []
    @State private var detail: PFImpactEntry?
    private let hiding = PFHiding()

    private var scale: Double { PFImpactFormat.barScale(impact.scored) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock
            if impact.hasAnyEffect {
                columnHeader
                ForEach(PFImpactFormat.sortedHurts(impact.hurts)) { card($0, tint: NoopLook.trendDown, pointsRight: false) }
                ForEach(PFImpactFormat.sortedHelps(impact.helps)) { card($0, tint: NoopLook.trendUp, pointsRight: true) }
            } else {
                LookInfoCard(title: "Nothing clearly helps or hurts yet",
                             message: hiding.text(item.base.meaning ?? "No behaviour has a clear effect on the next morning's score yet."))
                    .accessibilityIdentifier("pf-impact-none")
            }
            if !impact.noClearEffect.isEmpty {
                PFRuleLabel("NO CLEAR EFFECT")
                ForEach(impact.noClearEffect) { card($0, tint: NoopLook.textTertiary, pointsRight: ($0.pct ?? 0) >= 0) }
            }
            if !impact.notEnoughData.isEmpty {
                PFRuleLabel("NOT ENOUGH DATA")
                notEnough
            }
            ForEach(item.base.actions) { action in
                PFIntelActionCard(action: action, identifier: "pf-impact-action-\(action.id)")
            }
            Text("These are differences in the score, not causes. A behaviour needs \(impact.minEach) days with it and \(impact.minEach) without in the last \(impact.windowDays ?? 90) days before it is tested.")
                .font(LookFont.text(12.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            PFIntelFootnote(item: item)
        }
        .containerIdentifier("pf-impact-body")
        .task { await markNew() }
        .sheet(item: $detail) { entry in
            PFImpactDetail(entry: entry, impact: impact)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Header

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recovery impact analysis")
                .font(LookFont.text(22, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            if let outcome = impact.outcomeLabel {
                HStack(spacing: 6) {
                    Text("Next-morning \(outcome) over \(impact.outcomeDays ?? impact.windowDays ?? 90) days")
                        .font(LookFont.text(13.5, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                    PFSourceTag(source: impact.outcomeSource)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var columnHeader: some View {
        HStack {
            HStack(spacing: 4) {
                LookTriangle(pointsUp: false).fill(NoopLook.trendDown).frame(width: 10, height: 7)
                Text("HURTS").lookCaps(12).foregroundStyle(NoopLook.trendDown)
            }
            Spacer(minLength: 0)
            Text("% IMPACT").lookCaps(12).foregroundStyle(NoopLook.textSecondary)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text("HELPS").lookCaps(12).foregroundStyle(NoopLook.trendUp)
                LookTriangle(pointsUp: true).fill(NoopLook.trendUp).frame(width: 10, height: 7)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }

    // MARK: A behaviour

    private func card(_ entry: PFImpactEntry, tint: Color, pointsRight: Bool) -> some View {
        let pct = entry.pct ?? 0
        return Button { detail = entry } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.label)
                        .font(LookFont.text(16, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if newIDs.contains(entry.id) {
                        Text("NEW")
                            .lookCaps(9.5)
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.white))
                            .accessibilityIdentifier("pf-impact-new-\(entry.id)")
                    }
                    Spacer(minLength: 8)
                    Text(PFImpactFormat.pctText(pct))
                        .font(LookFont.numeral(24))
                        .foregroundStyle(tint)
                }
                PFImpactBar(fraction: PFImpactFormat.barFraction(pct, scale: scale), pointsRight: pointsRight, color: tint)
                Text(PFImpactFormat.countsText(with: entry.nWith, without: entry.nWithout))
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.label), \(PFImpactFormat.pctText(pct)) impact, \(PFImpactFormat.countsText(with: entry.nWith, without: entry.nWithout))")
        .accessibilityHint("Opens the days behind it")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("pf-impact-\(entry.id)")
    }

    // MARK: Not enough data

    private var notEnough: some View {
        VStack(spacing: 0) {
            ForEach(Array(impact.notEnoughData.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label)
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Text(PFImpactFormat.needText(row, minEach: impact.minEach))
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                    Text(PFImpactFormat.countsText(with: row.nWith, without: row.nWithout))
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-impact-need-\(row.id)")
                if index < impact.notEnoughData.count - 1 {
                    Rectangle().fill(NoopLook.divider).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-impact-not-enough")
    }

    // MARK: NEW chips

    /// A behaviour that was not on screen the last time this screen was opened gets a NEW chip until the next visit.
    private func markNew() async {
        let defaults = UserDefaults.standard
        let seen = PFSeenIDs.decode(defaults.string(forKey: PFSeenIDs.storageKey))
        let current = impact.scored.map(\.id)
        newIDs = PFSeenIDs.newIDs(current: current, seen: seen)
        if !PFAPI.isFixture {
            defaults.set(PFSeenIDs.encode(PFSeenIDs.updated(seen: seen, current: current)), forKey: PFSeenIDs.storageKey)
        }
    }
}

// MARK: - Detail

/// The days behind one behaviour, how sure the server is, and what to do about it.
struct PFImpactDetail: View {
    let entry: PFImpactEntry
    let impact: PFJournalImpact
    private let hiding = PFHiding()

    private var verdict: String {
        guard entry.clear, let pct = entry.pct else { return "No clear effect" }
        return pct < 0 ? "Hurts" : "Helps"
    }

    private func mean(_ value: Double?) -> String {
        guard let value else { return "\u{2013}" }
        return hiding.shown(String(format: "%.0f", value) + (impact.outcomeUnit ?? ""), .scores)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verdict.uppercased())
                        .lookCaps(12)
                        .foregroundStyle(entry.clear ? ((entry.pct ?? 0) < 0 ? NoopLook.trendDown : NoopLook.trendUp) : NoopLook.textTertiary)
                    Text(entry.label)
                        .font(LookFont.text(22, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pct = entry.pct {
                        Text("\(PFImpactFormat.pctText(pct)) on the next morning's score")
                            .font(LookFont.numeral(26))
                            .foregroundStyle(NoopLook.textPrimary)
                    }
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    row("Days with it", "\(entry.nWith)")
                    divider
                    row("Days without it", "\(entry.nWithout)")
                    divider
                    row("Score with it", mean(entry.meanWith))
                    divider
                    row("Score without it", mean(entry.meanWithout))
                    divider
                    row("Confidence", entry.confidence.map { PFFormat.capitalized($0) } ?? "\u{2013}")
                    if let t = entry.t {
                        divider
                        row("Strength of the difference (t)", String(format: "%.1f", t))
                    }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                .accessibilityIdentifier("pf-impact-detail-counts")

                if let note = entry.note {
                    Text(hiding.text(note))
                        .font(LookFont.text(14, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let action = entry.action {
                    PFIntelActionCard(action: action, identifier: "pf-impact-detail-action")
                }
                Text("Source: \(impact.outcomeSource ?? "not named"). A lined-up difference is not proof of a cause.")
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            .padding(20)
        }
        .lookScreenBackground()
        .accessibilityIdentifier("pf-impact-detail")
    }

    private var divider: some View { Rectangle().fill(NoopLook.divider).frame(height: 1) }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(LookFont.text(14, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(LookFont.numeral(18))
                .foregroundStyle(NoopLook.textPrimary)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Journal impact") {
    NavigationStack {
        ScrollView {
            PFJournalImpactBody(impact: PFPhase4Sample.journalImpact, item: PFPhase4Sample.item(PFDocID.journalImpact))
                .padding(16)
        }
        .lookScreenBackground()
    }
    .preferredColorScheme(.dark)
}
#endif
