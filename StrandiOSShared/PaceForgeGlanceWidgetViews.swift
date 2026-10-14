import SwiftUI
import WidgetKit
import StrandDesign

// The three newest PaceForge widget faces: Where you stand, Garmin's own recovery heart rate and the rides. Like
// the others they read only a PFSummary (already redacted for Settings > Hide numbers by the provider), and the
// app's debug widget gallery draws the very same views.

private struct PFGlanceOverline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(StrandPalette.textTertiary)
            .lineLimit(1)
    }
}

/// Shown while the app has not left that glance in the summary yet.
private struct PFGlanceEmpty: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PFGlanceOverline(text: title)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Where you stand (small, medium)

struct PFStandingWidgetFace: View {
    let summary: PFSummary?
    let family: WidgetFamily

    private static let bandColors = [StrandPalette.recovery030, StrandPalette.recovery055, StrandPalette.recovery078,
                                     StrandPalette.recovery100, StrandPalette.restColor]

    var body: some View {
        if let glance = summary?.standing, !glance.isEmpty {
            if family == .systemMedium { medium(glance) } else { small(glance) }
        } else {
            PFGlanceEmpty(title: "WHERE YOU STAND", message: "Open NOOP once PaceForge serves your scorecard.")
        }
    }

    private func small(_ g: PFStandingGlance) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            PFGlanceOverline(text: "WHERE YOU STAND")
            if let top = g.strongest.first { block("Strongest", top) }
            if let focus = g.focus.first { block("Focus", focus) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ g: PFStandingGlance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PFGlanceOverline(text: "WHERE YOU STAND")
            HStack(alignment: .top, spacing: 14) {
                column("Strongest", Array(g.strongest.prefix(3)))
                column("Focus", Array(g.focus.prefix(3)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ title: String, _ items: [PFStandingGlance.Item]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            if items.isEmpty {
                Text("\u{2013}").font(.system(size: 12)).foregroundStyle(StrandPalette.textTertiary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        if let value = item.value {
                            Text(value)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    bar(item.band)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block(_ title: String, _ item: PFStandingGlance.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            Text(item.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            bar(item.band)
            if let name = item.bandName {
                Text(name)
                    .font(.system(size: 10))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Five segments, the metric's band filled in; an unrated metric is all grey.
    private func bar(_ band: Int?) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let reached = (band ?? 0) > index
                Capsule()
                    .fill(reached ? Self.bandColors[index] : StrandPalette.textPrimary.opacity(0.10))
                    .frame(height: 4)
            }
        }
    }
}

// MARK: Garmin recovery heart rate (small, medium)

struct PFGarminRecoveryWidgetFace: View {
    let summary: PFSummary?
    let family: WidgetFamily

    static let tip = "After the last Stop wait 2 minutes before Save, and Garmin records it."

    var body: some View {
        if let g = summary?.garminRecovery {
            if family == .systemMedium { medium(g) } else { small(g) }
        } else {
            PFGlanceEmpty(title: "GARMIN RECOVERY HR", message: "Shows after a session where your watch recorded it. " + Self.tip)
        }
    }

    /// "-46": the heart rate fell by 46 (a rise shows "+"), the sign the card uses.
    private func signed(_ drop: Int) -> String {
        drop > 0 ? "-\(drop)" : (drop < 0 ? "+\(-drop)" : "0")
    }

    private func big(_ g: PFGarminRecoveryGlance, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(signed(g.dropBpm))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(StrandPalette.effortColor)
            Text("bpm")
                .font(.system(size: 12))
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func session(_ g: PFGarminRecoveryGlance) -> String {
        [g.sessionName, g.date.map(PFWidgetFormat.dayLine)].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private func small(_ g: PFGarminRecoveryGlance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PFGlanceOverline(text: "GARMIN RECOVERY HR")
            big(g, size: 36)
            Text("in 2 minutes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            if let detail = g.detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Text(session(g))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ g: PFGarminRecoveryGlance) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                PFGlanceOverline(text: "GARMIN RECOVERY HR")
                big(g, size: 46)
                Text("in 2 minutes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let detail = g.detail {
                    Text(detail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(session(g))
                    .font(.system(size: 11))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
                Text("As the watch recorded it; nothing here is estimated.")
                    .font(.system(size: 10))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Next and last ride (small, medium)

struct PFRideWidgetFace: View {
    let summary: PFSummary?
    let family: WidgetFamily

    var body: some View {
        if let g = summary?.rides, !g.isEmpty {
            if family == .systemMedium { medium(g) } else { small(g) }
        } else {
            PFGlanceEmpty(title: "RIDES", message: "Your next planned ride and your latest one show here once PaceForge has them.")
        }
    }

    /// The small face shows the next ride when there is one, else the last.
    @ViewBuilder private func small(_ g: PFRideGlance) -> some View {
        if let next = g.next {
            nextBlock(next)
        } else if let last = g.last {
            lastBlock(last)
        }
    }

    private func medium(_ g: PFRideGlance) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let next = g.next { nextBlock(next) } else { none("NEXT RIDE", "Nothing planned.") }
            if let last = g.last { lastBlock(last) } else { none("LAST RIDE", "No ride yet.") }
        }
    }

    private func none(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PFGlanceOverline(text: title)
            Text(message).font(.system(size: 12)).foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextBlock(_ next: PFRideGlance.Next) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PFGlanceOverline(text: "NEXT RIDE")
            Text(next.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(2)
            Text(PFWidgetFormat.dayLine(next.date))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StrandPalette.accent)
            if let detail = next.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
            if let target = next.target {
                Text(target)
                    .font(.system(size: 11))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lastBlock(_ last: PFRideGlance.Last) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PFGlanceOverline(text: "LAST RIDE")
            Text(last.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(2)
            Text(PFWidgetFormat.dayLine(last.date))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StrandPalette.textSecondary)
            let line = Self.numbers(last)
            if !line.isEmpty {
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "1h05 · 182 W avg · TSS 62 · 141 bpm". The training stress score is absent while the scores are hidden.
    static func numbers(_ last: PFRideGlance.Last) -> String {
        var bits: [String] = []
        if let seconds = last.durationS, seconds > 0 { bits.append(PFWidgetFormat.hoursMinutes(seconds / 60)) }
        if let power = last.avgPower { bits.append("\(Int(power.rounded())) W avg") }
        if let tss = last.tss { bits.append("TSS \(Int(tss.rounded()))") }
        if let hr = last.avgHr { bits.append("\(Int(hr.rounded())) bpm") }
        return bits.joined(separator: " \u{00B7} ")
    }
}
