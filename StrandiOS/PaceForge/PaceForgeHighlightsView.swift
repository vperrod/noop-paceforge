import SwiftUI
import StrandDesign

// Highlights and streaks, in the look: a 1M / 3M / ALL TIME control, three dials with the best Rest, the peak Charge and the
// max Effort of the period (the strap's, with the Garmin-side record written beside it and never merged into it), a STREAKS
// row with a badge each, the insight card carrying the streak's own line, and NOTABLE STATS with the date each was set.
// Everything is read from highlights.json; the app only draws it. The streak chip on Today's top bar lives here too.

// MARK: - Streak chip (Today's top bar)

/// The flame and the count of the longest streak alive, on the top bar. Nothing when no streak is alive or PaceForge is
/// not set up. Opens Highlights.
struct PFStreakChipView: View {
    @ObservedObject private var store = PFPhase4Store.shared

    var body: some View {
        Group {
            if let chip = store.streakChip {
                NavigationLink(value: TabRoute.highlights) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "#FFA722"))
                        Text(chip.text)
                            .font(LookFont.numeral(15))
                            .foregroundStyle(NoopLook.textPrimary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: NoopMetrics.compactControlSize)
                    .background(Capsule(style: .continuous).fill(Color(light: "#DDE2E8", dark: "#35393E")))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip.spoken)
                .accessibilityHint("Opens Highlights and streaks")
                .accessibilityIdentifier("look-streak-chip")
            }
        }
        .task { await store.refreshIfStale() }
    }
}

// MARK: - Screen

struct PFHighlightsScreen: View {
    @ObservedObject private var store = PFPhase4Store.shared

    var body: some View {
        PFDocScreen(title: "Highlights", identifier: "pf-highlights") {
            PFDocStateView(state: store.docs.highlights, didLoad: store.didLoad, title: "Highlights", icon: "star",
                           identifier: "pf-highlights") { highlights, item in
                PFHighlightsBody(highlights: highlights, item: item)
            }
        }
    }
}

struct PFHighlightsBody: View {
    let highlights: PFHighlights
    let item: PFIntelItem

    @State private var period = PFHighlightPeriod.allTime
    @State private var chosenStreak: String?
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private let hiding = PFHiding()

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// The streak the insight card quotes: the one tapped, else the longest alive.
    private var selectedStreak: PFStreak? {
        if let chosenStreak, let found = highlights.streaks.first(where: { $0.id == chosenStreak }) { return found }
        return PFHighlightsLogic.leadStreak(highlights.streaks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LookSegmented(options: PFHighlightPeriod.allCases, selection: $period, identifier: "pf-highlights-period") { $0.title }
                .frame(height: 44)
            dials
            if !highlights.streaks.isEmpty {
                PFRuleLabel("STREAKS")
                streakGrid
                streakInsight
            }
            if !highlights.notable.isEmpty {
                PFRuleLabel("NOTABLE STATS")
                notableList
            }
            footnote
        }
        .containerIdentifier("pf-highlights-body")
    }

    // MARK: Dials

    private static let dialOrder = ["rest", "charge", "effort"]

    private func title(_ id: String) -> String {
        switch id {
        case "rest": return "Best Rest"
        case "charge": return "Peak Charge"
        case "effort": return "Max Effort"
        default: return PFBand.titleFromId(id)
        }
    }

    private var dials: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Self.dialOrder, id: \.self) { id in
                if let record = highlights.record(id) {
                    dialCell(record)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .hiddenWhenPrivate(.scores, name: String(localized: "Records"))
        .containerIdentifier("pf-highlights-dials")
    }

    private func dialCell(_ record: PFRecord) -> some View {
        let entry = record.period(period.rawValue)
        let strap = entry?.noop
        let fraction = PFHighlightsLogic.dialFraction(record, period: period) ?? 0
        let valueText: String
        let unit: String?
        let color: Color
        switch record.id {
        case "charge":
            valueText = strap.map { String(Safe.int($0.value)) } ?? "\u{2013}"
            unit = strap == nil ? nil : "%"
            color = strap.map { NoopLook.chargeColor($0.value) } ?? NoopLook.chargeHigh
        case "effort":
            valueText = strap.map { UnitFormatter.effortDisplay($0.value, scale: effortScale) } ?? "\u{2013}"
            unit = nil
            color = NoopLook.effort
        default:
            valueText = strap.map { String(Safe.int($0.value)) } ?? "\u{2013}"
            unit = strap == nil ? nil : "%"
            color = NoopLook.rest
        }
        return VStack(spacing: 8) {
            RingDial(fraction: fraction, color: color, valueText: valueText, unitText: unit, diameter: 92,
                     accessibilityName: title(record.id))
            Text(title(record.id))
                .font(LookFont.text(15, weight: .medium))
                .foregroundStyle(NoopLook.textPrimary)
                .multilineTextAlignment(.center)
            if let strap, let date = strap.date, let short = PFDocDate.shortDate(date) {
                Text("\(short) \u{00B7} NOOP strap")
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            } else {
                Text("No strap record yet")
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            if let garmin = entry?.garmin {
                garminLine(garmin)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pf-record-\(record.id)")
    }

    /// The Garmin-side record under the strap's, labelled with its own name ("Sleep score (Garmin)") and date.
    private func garminLine(_ value: PFRecordValue) -> some View {
        VStack(spacing: 1) {
            Text(hiding.text(value.display ?? value.label ?? ""))
                .font(LookFont.text(12, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
            Text([value.source, value.date.flatMap(PFDocDate.shortDate)].compactMap { $0 }.joined(separator: " \u{00B7} "))
                .font(LookFont.text(11, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-record-garmin-\(value.label ?? "")")
    }

    // MARK: Streaks

    private func streakColor(_ streak: PFStreak) -> Color {
        switch streak.id {
        case "rest_70": return NoopLook.rest
        case "charge_green": return NoopLook.chargeHigh
        case "effort_10": return NoopLook.effort
        default: return Color(hex: "#9B7BFF")
        }
    }

    private func streakSymbol(_ streak: PFStreak) -> String {
        switch streak.id {
        case "rest_70": return "moon.fill"
        case "charge_green": return "bolt.heart.fill"
        case "effort_10": return "flame.fill"
        default: return "calendar"
        }
    }

    private var streakGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), spacing: 18) {
            ForEach(highlights.streaks) { streak in
                Button { chosenStreak = streak.id } label: {
                    VStack(spacing: 4) {
                        PFBadgeIcon(symbol: streakSymbol(streak), color: streakColor(streak), isDimmed: !streak.alive)
                            .padding(.bottom, 6)
                        Text(streak.alive ? streak.countText : streak.bestText)
                            .font(LookFont.text(16, weight: .semibold))
                            .foregroundStyle(streak.alive ? NoopLook.textPrimary : NoopLook.textTertiary)
                        Text(hiding.text(streak.label))
                            .font(LookFont.text(13, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSourceTag(source: streak.source)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(streak.alive ? "\(streak.countText), \(streak.label)" : "\(streak.label), not alive, \(streak.bestText)")
                .accessibilityAddTraits(selectedStreak?.id == streak.id ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("pf-streak-\(streak.id)")
            }
        }
        .containerIdentifier("pf-streaks")
    }

    /// The streak's own line: what the athlete's numbers were while it ran.
    @ViewBuilder private var streakInsight: some View {
        if let streak = selectedStreak, let line = streak.line {
            LookInsightCard(hiding.text(line))
                .accessibilityIdentifier("pf-streak-insight")
        } else if highlights.streaks.allSatisfy({ !$0.alive }) {
            LookInfoCard(title: "No streak is going",
                         message: "A streak counts days in a row. A day with no reading breaks it, so start one tomorrow.")
                .accessibilityIdentifier("pf-streak-none")
        }
    }

    // MARK: Notable stats

    private var notableList: some View {
        VStack(spacing: 0) {
            ForEach(Array(highlights.notable.enumerated()), id: \.element.id) { index, stat in
                notableRow(stat)
                if index < highlights.notable.count - 1 {
                    Rectangle().fill(NoopLook.divider).frame(height: 1)
                }
            }
        }
        .containerIdentifier("pf-notable")
    }

    private func notableRow(_ stat: PFNotable) -> some View {
        let parts = PFHighlightsLogic.valueParts(stat.display)
        let caption = PFHighlightsLogic.dateCaption(date: stat.date, daysAgo: stat.daysAgo)
        return HStack(spacing: 14) {
            PFBadgeIcon(symbol: PFHighlightsLogic.notableSymbol(stat.id), color: Color(hex: "#C9A24B"))
            VStack(alignment: .leading, spacing: 3) {
                Text(stat.label)
                    .font(LookFont.text(16, weight: .medium))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let caption {
                        Text(caption)
                            .font(LookFont.text(12, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                    PFSourceTag(source: stat.source)
                }
                if let detail = stat.detail {
                    Text(detail)
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.number)
                    .font(LookFont.numeral(26))
                    .foregroundStyle(NoopLook.textPrimary)
                if !parts.unit.isEmpty {
                    Text(parts.unit)
                        .font(LookFont.text(14, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stat.label), \(stat.display), \(caption ?? ""), \(stat.source ?? "")")
        .accessibilityIdentifier("pf-notable-\(stat.id)")
    }

    // MARK: Footnote

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let since = highlights.noopSince, let short = PFDocDate.dayMonthYear(since) {
                Text("Strap records and streaks start on \(short), the day the strap was first worn. The Garmin-side records beside them cover the earlier months and are never merged with the strap's.")
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFIntelFootnote(item: item)
        }
        .containerIdentifier("pf-highlights-footnote")
    }
}

#if DEBUG
#Preview("Highlights") {
    NavigationStack {
        ScrollView {
            PFHighlightsBody(highlights: PFPhase4Sample.highlights, item: PFPhase4Sample.item(PFDocID.highlights))
                .padding(16)
        }
        .lookScreenBackground()
    }
    .preferredColorScheme(.dark)
}
#endif
