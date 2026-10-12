import SwiftUI
import WidgetKit
import StrandDesign

// The second set of PaceForge widget faces: the week strip, the sleep and HRV trend, training load and
// the body score. Like the first set they read only a PFSummary, and the app's debug widget gallery
// draws the very same views.

extension PFWidgetFormat {
    /// "M", "T", ... for a `yyyy-MM-dd` day.
    static func weekdayLetter(_ iso: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: iso) else { return "" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.dateFormat = "EEEEE"
        return out.string(from: date)
    }

    /// 432 minutes as "7h12".
    static func hoursMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return "\(total / 60)h" + String(format: "%02d", total % 60)
    }

    /// A signed change such as "+0.4", or nil when there is none.
    static func signed(_ value: Double?, decimals: Int = 1) -> String? {
        value.map { String(format: "%+.\(decimals)f", $0) }
    }
}

private struct PFWidgetOverline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(StrandPalette.textTertiary)
            .lineLimit(1)
    }
}

// MARK: Week strip (medium)

struct PFWeekWidgetFace: View {
    let summary: PFSummary?
    let stale: Bool

    var body: some View {
        if let s = summary, !stale, let days = s.weekDays, !days.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    PFWidgetOverline(text: "THIS WEEK")
                    Spacer(minLength: 4)
                    Text(loadText(s))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        VStack(spacing: 5) {
                            Text(day.label)
                                .font(.system(size: 10, weight: day.isToday ? .bold : .semibold))
                                .foregroundStyle(day.isToday ? StrandPalette.accent : StrandPalette.textTertiary)
                            marker(day, today: s.date)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                loadBar(s)
                Text(footnote(s, days))
                    .font(.system(size: 11))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            PFWidgetStale()
        }
    }

    @ViewBuilder private func marker(_ day: PFSummary.WeekDay, today: String) -> some View {
        if day.planned == 0 {
            Circle()
                .fill(StrandPalette.textTertiary.opacity(0.35))
                .frame(width: 6, height: 6)
                .frame(height: 22)
        } else if day.done >= day.planned {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 21))
                .foregroundStyle(StrandPalette.statusPositive)
        } else if day.done > 0 {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 21))
                .foregroundStyle(StrandPalette.accent)
        } else if day.date < today {
            Image(systemName: "circle.dashed")
                .font(.system(size: 21))
                .foregroundStyle(StrandPalette.statusWarning)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 21))
                .foregroundStyle(day.isToday ? StrandPalette.accent : StrandPalette.textSecondary)
        }
    }

    private func loadText(_ s: PFSummary) -> String {
        let done = (s.weekDoneMinutes ?? 0) / 60
        guard let target = s.weekTargetMinutes, target > 0 else { return String(format: "%.1f h", done) }
        return String(format: "%.1f of %.1f h", done, target / 60)
    }

    @ViewBuilder private func loadBar(_ s: PFSummary) -> some View {
        let fraction = (s.weekTargetMinutes ?? 0) > 0 ? min((s.weekDoneMinutes ?? 0) / (s.weekTargetMinutes ?? 1), 1) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.textPrimary.opacity(0.10))
                Capsule().fill(StrandPalette.effortColor)
                    .frame(width: max(geo.size.width * CGFloat(fraction), fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
    }

    private func footnote(_ s: PFSummary, _ days: [PFSummary.WeekDay]) -> String {
        let planned = days.reduce(0) { $0 + $1.planned }
        let done = days.reduce(0) { $0 + $1.done }
        return planned == 0 ? "No sessions planned this week." : "\(done) of \(planned) sessions done"
    }
}

// MARK: Sleep and HRV trend (medium)

struct PFSleepHrvWidgetFace: View {
    let summary: PFSummary?
    let stale: Bool

    var body: some View {
        if let s = summary, !stale, let nights = s.nights, !nights.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                sleepPanel(s, nights)
                hrvPanel(s, nights)
            }
        } else {
            PFWidgetStale()
        }
    }

    private func sleepPanel(_ s: PFSummary, _ nights: [PFSummary.Night]) -> some View {
        let values = nights.map { $0.sleepMinutes ?? 0 }
        let present = nights.compactMap { $0.sleepMinutes }
        let need = s.sleepNeedMinutes
        let top = max(values.max() ?? 0, (need ?? 0) * 1.1, 60)
        return VStack(alignment: .leading, spacing: 5) {
            PFWidgetOverline(text: "SLEEP")
            Text(present.isEmpty ? "\u{2013}" : PFWidgetFormat.hoursMinutes(present.reduce(0, +) / Double(present.count)))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(StrandPalette.textPrimary)
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                            let minutes = night.sleepMinutes ?? 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(StrandPalette.restColor.opacity(minutes >= (need ?? 0) ? 1 : 0.55))
                                .frame(height: max(geo.size.height * CGFloat(minutes / top), minutes > 0 ? 3 : 0))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let need {
                        Rectangle()
                            .fill(StrandPalette.textTertiary)
                            .frame(height: 1)
                            .offset(y: -geo.size.height * CGFloat(need / top))
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                    Text(PFWidgetFormat.weekdayLetter(night.date))
                        .font(.system(size: 9))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hrvPanel(_ s: PFSummary, _ nights: [PFSummary.Night]) -> some View {
        let values = nights.map { $0.hrv }
        let last = nights.last(where: { $0.hrv != nil })?.hrv
        return VStack(alignment: .leading, spacing: 5) {
            PFWidgetOverline(text: "HRV")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(last.map { PFWidgetFormat.whole($0) } ?? "\u{2013}")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("ms").font(.system(size: 11)).foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
                if let base = s.hrvBaseline {
                    Text("base \(PFWidgetFormat.whole(base))")
                        .font(.system(size: 10))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            if values.contains(where: { $0 != nil }) {
                PFTrendLine(values: values, baseline: s.hrvBaseline, low: s.hrvLow, high: s.hrvHigh)
            } else {
                Text("Nightly HRV fills in as you open NOOP.")
                    .font(.system(size: 11))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            Color.clear.frame(height: 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A line over equal slots, a shaded normal band and a dashed baseline. Gaps break the line.
private struct PFTrendLine: View {
    let values: [Double?]
    let baseline: Double?
    let low: Double?
    let high: Double?

    private var bounds: (lo: Double, hi: Double) {
        let all = values.compactMap { $0 } + [baseline, low, high].compactMap { $0 }
        let lo = all.min() ?? 0
        let hi = all.max() ?? 1
        let pad = max((hi - lo) * 0.15, 1)
        return (lo - pad, hi + pad)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let low, let high {
                    Rectangle()
                        .fill(StrandPalette.effortColor.opacity(0.14))
                        .frame(height: max(abs(y(low, geo.size) - y(high, geo.size)), 2))
                        .position(x: geo.size.width / 2, y: (y(low, geo.size) + y(high, geo.size)) / 2)
                }
                if let baseline {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y(baseline, geo.size)))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y(baseline, geo.size)))
                    }
                    .stroke(StrandPalette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                linePath(geo.size)
                    .stroke(StrandPalette.effortColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    if let value {
                        Circle()
                            .fill(StrandPalette.effortColor)
                            .frame(width: 5, height: 5)
                            .position(point(index, value, geo.size))
                    }
                }
            }
        }
    }

    private func x(_ index: Int, _ size: CGSize) -> CGFloat {
        size.width * (CGFloat(index) + 0.5) / CGFloat(max(values.count, 1))
    }

    private func y(_ value: Double, _ size: CGSize) -> CGFloat {
        let b = bounds
        return size.height - CGFloat((value - b.lo) / (b.hi - b.lo)) * size.height
    }

    private func point(_ index: Int, _ value: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: x(index, size), y: y(value, size))
    }

    private func linePath(_ size: CGSize) -> Path {
        var path = Path()
        var penDown = false
        for (index, value) in values.enumerated() {
            guard let value else { penDown = false; continue }
            let p = point(index, value, size)
            if penDown { path.addLine(to: p) } else { path.move(to: p); penDown = true }
        }
        return path
    }
}

// MARK: Training load (small and circular lock-screen)

struct PFLoadWidgetFace: View {
    let summary: PFSummary?
    let stale: Bool
    let family: WidgetFamily

    var body: some View {
        if let s = summary, !stale {
            if family == .accessoryCircular { circular(s) } else { small(s) }
        } else if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "arrow.clockwise")
            }
        } else {
            PFWidgetStale()
        }
    }

    private func color(_ ratio: Double) -> Color {
        switch PFLoadZone.state(ratio) {
        case .safe: return StrandPalette.statusPositive
        case .high: return StrandPalette.statusWarning
        case .low: return StrandPalette.effortColor
        }
    }

    private func word(_ ratio: Double) -> String {
        switch PFLoadZone.state(ratio) {
        case .safe: return "In the safe zone"
        case .high: return "Ramping fast"
        case .low: return "Below your base"
        }
    }

    private func small(_ s: PFSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            PFWidgetOverline(text: "TRAINING LOAD")
            if let ratio = s.acwr {
                Text(String(format: "%.2f", ratio))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(color(ratio))
                    .minimumScaleFactor(0.7)
                Text(word(ratio))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                scale(ratio)
                if let ctl = s.ctl, let atl = s.atl {
                    Text("Fitness \(PFWidgetFormat.whole(ctl)) \u{00B7} Fatigue \(PFWidgetFormat.whole(atl))")
                        .font(.system(size: 10))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("\u{2013}")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Building your load history")
                    .font(.system(size: 12))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 0 to 2 with the safe band shaded and the ratio marked.
    private func scale(_ ratio: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let unit = w / CGFloat(PFLoadZone.scaleMax)
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.textPrimary.opacity(0.10))
                Capsule()
                    .fill(StrandPalette.statusPositive.opacity(0.35))
                    .frame(width: unit * CGFloat(PFLoadZone.safeHigh - PFLoadZone.safeLow))
                    .offset(x: unit * CGFloat(PFLoadZone.safeLow))
                Circle()
                    .fill(color(ratio))
                    .frame(width: 9, height: 9)
                    .offset(x: min(max(unit * CGFloat(ratio) - 4.5, 0), w - 9))
            }
        }
        .frame(height: 9)
    }

    private func circular(_ s: PFSummary) -> some View {
        Group {
            if let ratio = s.acwr {
                Gauge(value: min(max(ratio, 0), PFLoadZone.scaleMax), in: 0...PFLoadZone.scaleMax) {
                    Text(label(ratio))
                } currentValueLabel: {
                    Text(String(format: "%.1f", ratio))
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Text("A:C").font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    private func label(_ ratio: Double) -> String {
        switch PFLoadZone.state(ratio) {
        case .safe: return "OK"
        case .high: return "HIGH"
        case .low: return "LOW"
        }
    }
}

// MARK: Body score (small)

struct PFBodyWidgetFace: View {
    let summary: PFSummary?
    let stale: Bool

    var body: some View {
        if let s = summary, !stale {
            VStack(alignment: .leading, spacing: 5) {
                PFWidgetOverline(text: "BODY")
                if let b = s.body, b.score != nil || b.weightKg != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(PFWidgetFormat.whole(b.score))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(StrandPalette.textPrimary)
                        if let band = b.band {
                            Text(band)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    row("Weight", b.weightKg.map { String(format: "%.1f kg", $0) }, PFWidgetFormat.signed(b.weightDelta))
                    row("Body fat", b.fatPct.map { String(format: "%.1f%%", $0) }, PFWidgetFormat.signed(b.fatPctDelta))
                    if let date = b.date {
                        Text("Reading " + PFWidgetFormat.dayLine(date))
                            .font(.system(size: 10))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text("No scale reading yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Step on the Hume Body Pod.")
                        .font(.system(size: 12))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            PFWidgetStale()
        }
    }

    private func row(_ label: String, _ value: String?, _ delta: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(StrandPalette.textTertiary)
            Spacer(minLength: 2)
            Text(value ?? "\u{2013}")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let delta {
                Text(delta)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: Heart recovery (small and circular lock-screen)

/// First-minute heart-rate recovery of the latest PaceForge session that has one. It describes a past
/// session, so unlike the day faces it is not hidden when the summary is a day old.
struct PFHeartRecoveryWidgetFace: View {
    let summary: PFSummary?
    let family: WidgetFamily

    /// Only a scored "post" figure is shown; a file from an older build may still hold a "mid" one.
    private var hrr: PFSummary.HRR1? { summary?.hrr1.flatMap { $0.kind == "post" ? $0 : nil } }

    var body: some View {
        if family == .accessoryCircular { circular } else { small }
    }

    private func color(_ band: String?) -> Color {
        switch band {
        case "good": return StrandPalette.statusPositive
        case "watch": return StrandPalette.statusWarning
        case "flag": return StrandPalette.statusCritical
        default: return StrandPalette.effortColor
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            PFWidgetOverline(text: "HEART RECOVERY")
            if let h = hrr {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(h.bpm)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(color(h.band))
                    Text("bpm")
                        .font(.system(size: 12))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if let band = h.band {
                    Text(band.prefix(1).uppercased() + band.dropFirst())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color(band))
                }
                Text("Drop in the first minute after")
                    .font(.system(size: 10))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text([h.sessionName, h.date.map(PFWidgetFormat.dayLine)].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
            } else {
                Text("\u{2013}")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Shows after a session with a measurable heart-rate recovery.")
                    .font(.system(size: 12))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let h = hrr {
                VStack(spacing: 0) {
                    Text("\(h.bpm)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                    Text("HRR").font(.system(size: 9))
                }
            } else {
                Image(systemName: "heart.text.square")
            }
        }
    }
}
