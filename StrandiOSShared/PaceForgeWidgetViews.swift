import SwiftUI
import WidgetKit
import StrandDesign

// The PaceForge widget faces. They live in the shared folder so the widget extension draws them and the
// app's debug widget gallery renders the very same views for simulator screenshots. Every face reads a
// PFSummary only; none touches the network or the Keychain.

/// "Open NOOP to refresh" shown when the summary file is missing or stale.
struct PFWidgetStale: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 2 : 6) {
            Image(systemName: "arrow.clockwise")
                .font(compact ? .caption : .title3)
            Text("Open NOOP to refresh")
                .font(compact ? .caption2 : .footnote)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(compact ? Color.primary : StrandPalette.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A static score ring (no draw-in animation, which WidgetKit timelines do not run reliably).
struct PFWidgetRing: View {
    let fraction: Double?
    let text: String
    let label: String
    let color: Color
    var diameter: CGFloat = 58
    var lineWidth: CGFloat = 7

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(StrandPalette.textPrimary.opacity(0.10), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if let fraction {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(fraction, 0.0001), 1)))
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(text)
                    .font(.system(size: diameter * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, lineWidth)
            }
            .frame(width: diameter, height: diameter)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
        }
    }
}

enum PFWidgetFormat {
    static func whole(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "\u{2013}" }
    static func one(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "\u{2013}" }

    static func dayLine(_ iso: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.dateFormat = "EEE d MMM"
        return f.date(from: iso).map { out.string(from: $0) } ?? iso
    }
}

private struct PFSessionRow: View {
    let session: PFSummary.Session
    var showMainSet = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(session.done ? StrandPalette.statusPositive : StrandPalette.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                let line = [session.detail, session.target].compactMap { $0 }.joined(separator: " \u{00B7} ")
                if !line.isEmpty {
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
                if showMainSet, let main = session.mainSet {
                    Text(main)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StrandPalette.accent)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PFRaceFooter: View {
    let summary: PFSummary

    var body: some View {
        if let race = summary.race {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
                Text(race.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(daysText(summary.raceDaysNow ?? race.days))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
    }

    private func daysText(_ days: Int) -> String {
        days == 0 ? "today" : (days == 1 ? "1 day to go" : "\(days) days to go")
    }
}

// MARK: PaceForge Today (medium, large)

struct PFTodayWidgetFace: View {
    let summary: PFSummary?
    let stale: Bool
    let family: WidgetFamily

    var body: some View {
        Group {
            if let summary, !stale {
                if family == .systemLarge { large(summary) } else { medium(summary) }
            } else {
                PFWidgetStale()
            }
        }
    }

    private func rings(_ s: PFSummary, diameter: CGFloat, lineWidth: CGFloat) -> some View {
        HStack(spacing: family == .systemLarge ? 14 : 8) {
            PFWidgetRing(fraction: s.recovery.map { $0 / 100 }, text: PFWidgetFormat.whole(s.recovery), label: "Recovery",
                         color: StrandPalette.chargeColor, diameter: diameter, lineWidth: lineWidth)
            PFWidgetRing(fraction: s.strain.map { $0 / 21 }, text: PFWidgetFormat.one(s.strain), label: "Strain",
                         color: StrandPalette.effortColor, diameter: diameter, lineWidth: lineWidth)
            PFWidgetRing(fraction: s.sleep.map { $0 / 100 }, text: PFWidgetFormat.whole(s.sleep), label: "Sleep",
                         color: StrandPalette.restColor, diameter: diameter, lineWidth: lineWidth)
        }
    }

    private func medium(_ s: PFSummary) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PACEFORGE \u{00B7} " + PFWidgetFormat.dayLine(s.date).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                if s.sessions.isEmpty {
                    Text("Rest day")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Recovery is training.")
                        .font(.system(size: 12))
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    ForEach(Array(s.sessions.prefix(2))) { PFSessionRow(session: $0, showMainSet: s.sessions.count < 2) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            rings(s, diameter: 46, lineWidth: 5)
        }
    }

    private func large(_ s: PFSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PACEFORGE \u{00B7} " + PFWidgetFormat.dayLine(s.date).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                if let headline = s.briefHeadline {
                    Text(headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(2)
                }
            }
            HStack {
                Spacer()
                rings(s, diameter: 62, lineWidth: 7)
                Spacer()
            }
            metrics(s)
            Divider().overlay(StrandPalette.hairline)
            VStack(alignment: .leading, spacing: 8) {
                if s.sessions.isEmpty {
                    Text("Rest day. Recovery is training.")
                        .font(.system(size: 13))
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    ForEach(Array(s.sessions.prefix(2))) { PFSessionRow(session: $0) }
                }
            }
            Spacer(minLength: 0)
            PFRaceFooter(summary: s)
        }
    }

    private func metrics(_ s: PFSummary) -> some View {
        HStack(alignment: .top, spacing: 6) {
            cell("HRV", s.hrv.map { PFWidgetFormat.whole($0) + " ms" })
            cell("Resting HR", s.restingHr.map { PFWidgetFormat.whole($0) + " bpm" })
            cell("Sleep", sleepText(s))
            cell("Load A:C", s.acwr.map { String(format: "%.2f", $0) })
        }
    }

    private func sleepText(_ s: PFSummary) -> String? {
        guard let hours = s.sleepHours else { return nil }
        return s.sleepNeed.map { "\(hours)/\($0)" } ?? hours
    }

    private func cell(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value ?? "\u{2013}")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Today's session (small, medium) and lock-screen faces

struct PFSessionWidgetFace: View {
    let summary: PFSummary?
    let stale: Bool
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: home(medium: true)
        default: home(medium: false)
        }
    }

    private var fresh: PFSummary? { stale ? nil : summary }

    private func home(medium: Bool) -> some View {
        Group {
            if let s = fresh {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TODAY'S SESSION")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                        if let first = s.sessions.first {
                            if medium {
                                PFSessionRow(session: first)
                            } else {
                                Text(first.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .lineLimit(2)
                                if let detail = first.detail {
                                    Text(detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(StrandPalette.textSecondary)
                                        .lineLimit(1)
                                }
                                if first.done {
                                    Label("Done", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(StrandPalette.statusPositive)
                                }
                            }
                        } else {
                            Text("Rest day")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        if medium, let headline = s.briefHeadline {
                            Text(headline)
                                .font(.system(size: 12))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack {
                        if !medium { Spacer(minLength: 0) }
                        PFWidgetRing(fraction: s.recovery.map { $0 / 100 }, text: PFWidgetFormat.whole(s.recovery),
                                     label: "Recovery", color: StrandPalette.chargeColor,
                                     diameter: medium ? 62 : 46, lineWidth: medium ? 7 : 5)
                    }
                }
            } else {
                PFWidgetStale()
            }
        }
    }

    private var inline: some View {
        Group {
            if let s = fresh {
                let rec = s.recovery.map { " \u{00B7} Rec \(PFWidgetFormat.whole($0))" } ?? ""
                if let first = s.sessions.first(where: { !$0.done }) ?? s.sessions.first {
                    let key = first.detail?.components(separatedBy: " \u{00B7} ").first ?? ""
                    Text(("\(first.name) \(key)").trimmingCharacters(in: .whitespaces) + rec)
                } else {
                    Text("Rest day" + rec)
                }
            } else {
                Text("PaceForge: open NOOP")
            }
        }
    }

    private var rectangular: some View {
        Group {
            if let s = fresh {
                VStack(alignment: .leading, spacing: 1) {
                    if let first = s.sessions.first(where: { !$0.done }) ?? s.sessions.first {
                        HStack(spacing: 4) {
                            if first.done { Image(systemName: "checkmark.circle.fill").font(.caption2) }
                            Text(first.name).font(.headline).lineLimit(1)
                        }
                        let line = [first.detail, first.target].compactMap { $0 }.joined(separator: " \u{00B7} ")
                        if !line.isEmpty { Text(line).font(.caption).lineLimit(1) }
                    } else {
                        Text("Rest day").font(.headline)
                    }
                    Text("Recovery \(PFWidgetFormat.whole(s.recovery))" + (s.strain.map { " \u{00B7} Strain \(PFWidgetFormat.one($0))" } ?? ""))
                        .font(.caption2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PFWidgetStale(compact: true)
            }
        }
    }
}

// MARK: Race countdown (small) and circular lock-screen faces

struct PFRaceWidgetFace: View {
    let summary: PFSummary?
    let stale: Bool
    let family: WidgetFamily

    var body: some View {
        if let s = summary, !stale, let race = s.race {
            let days = s.raceDaysNow ?? race.days
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text("\(days)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                        Text(days == 1 ? "day" : "days").font(.system(size: 9))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "flag.checkered").foregroundStyle(StrandPalette.accent)
                        Text("NEXT RACE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Text(race.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(days)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(StrandPalette.accent)
                            .minimumScaleFactor(0.6)
                        Text(days == 1 ? "day to go" : "days to go")
                            .font(.system(size: 12))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text(PFWidgetFormat.dayLine(race.date))
                        .font(.system(size: 11))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "flag.checkered")
            }
        } else {
            PFWidgetStale()
        }
    }
}

/// Lock-screen circular gauge: recovery 0-100, or strain with its target band.
struct PFGaugeWidgetFace: View {
    enum Kind { case recovery, strain }

    let kind: Kind
    let summary: PFSummary?
    let stale: Bool

    var body: some View {
        if let s = summary, !stale {
            switch kind {
            case .recovery:
                if let value = s.recovery {
                    Gauge(value: min(max(value, 0), 100), in: 0...100) {
                        Text("REC")
                    } currentValueLabel: {
                        Text(PFWidgetFormat.whole(value))
                    }
                    .gaugeStyle(.accessoryCircular)
                } else {
                    placeholder
                }
            case .strain:
                if let value = s.strain {
                    let high = max(s.strainHigh ?? 21, 1)
                    Gauge(value: min(max(value, 0), high), in: 0...high) {
                        Text(targetText(s))
                    } currentValueLabel: {
                        Text(PFWidgetFormat.one(value))
                    }
                    .gaugeStyle(.accessoryCircular)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "arrow.clockwise")
        }
    }

    private func targetText(_ s: PFSummary) -> String {
        guard let lo = s.strainLow, let hi = s.strainHigh else { return "STR" }
        return "\(Int(lo))-\(Int(hi))"
    }
}
