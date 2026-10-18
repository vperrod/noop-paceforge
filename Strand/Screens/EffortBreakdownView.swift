import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import WhoopProtocol
import Foundation

// MARK: - Effort: why this number
//
// Opened from the Effort detail screen. It re-reads today's heart rate over the SAME window and with the
// SAME inputs the Today views score Effort with, then lets `StrainScorer.breakdown` (which shares the
// scorer's own functions) explain the result, so nothing here re-derives the formula.

/// The row on the Effort detail screen that opens the breakdown.
struct EffortBreakdownLink: View {
    var body: some View {
        NavigationLink {
            EffortBreakdownView()
        } label: {
            NoopCard {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Why this number")
                            .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text("See what built today's Effort, minute by minute.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("effort-why-link")
    }
}

/// Everything the screen shows, resolved once per load.
private struct EffortWhy {
    enum StartSource { case sleepOnset, midnightByChoice, midnightFallback }
    enum HRMaxSource { case manual, ageFormula(age: Int), defaultNoAge }

    let breakdown: EffortBreakdown
    let windowStart: Int
    let windowEnd: Int
    let startSource: StartSource
    let hrMaxSource: HRMaxSource
    /// The day's stored resting HR, nil when the 60 bpm fallback was used.
    let storedRestingHR: Int?
    let storedEffort: Double?
    let displayed: Double?
    /// Max bpm per equal slice of the window, nil where the slice has no reading.
    let chart: [Int?]
}

struct EffortBreakdownView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var why: EffortWhy?
    @State private var loaded = false

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        ScreenScaffold(title: "Why this number", subtitle: "Effort, step by step") {
            if let why {
                content(why)
            } else if loaded {
                card {
                    Text("There is no heart rate for today yet, so there is nothing to explain.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                card {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading today's heart rate…")
                            .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
        .task(id: "\(dayCycleModeRaw)-\(repo.refreshSeq)") { await load() }
    }

    // MARK: Sections

    @ViewBuilder private func content(_ why: EffortWhy) -> some View {
        let b = why.breakdown
        headline(why)
        if !b.enoughData || b.effort == nil {
            insufficient(b)
        }
        windowCard(why)
        inputsCard(why)
        if b.effort != nil {
            addUpCard(why)
            chartCard(why)
            stretchesCard(b)
        }
    }

    private func headline(_ why: EffortWhy) -> some View {
        let b = why.breakdown
        return card {
            VStack(alignment: .leading, spacing: 6) {
                Text("EFFORT").font(StrandFont.overline).foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(why.displayed.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "—")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("of \(UnitFormatter.effortScaleMax(effortScale))")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                }
                Text(originLine(why, live: b.effort))
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func originLine(_ why: EffortWhy, live: Double?) -> String {
        guard why.displayed != nil else {
            return String(localized: "No Effort has been scored for today yet.")
        }
        let stored = why.storedEffort
        if let live, let stored, stored > live {
            return String(localized: "Held at the score already earned today (\(fmt(stored))). Effort never drops during the day, and the live recompute from the heart rate below reads \(fmt(live)).")
        }
        if live == nil {
            return String(localized: "There is not enough heart rate for a live reading, so this is the score stored for today.")
        }
        return String(localized: "Recomputed live from today's heart rate, below.")
    }

    private func windowCard(_ why: EffortWhy) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Window counted")
                Text("\(clock(why.windowStart)) to \(clock(why.windowEnd)) · \(duration(Double(why.windowEnd - why.windowStart) / 60.0))")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(startSourceLine(why.startSource))
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(why.breakdown.sampleCount) heart-rate readings from your WHOOP strap, the only source Effort uses.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func startSourceLine(_ source: EffortWhy.StartSource) -> String {
        switch source {
        case .sleepOnset:
            return String(localized: "It starts when you fell asleep, so the day runs from sleep onset to now.")
        case .midnightByChoice:
            return String(localized: "It starts at midnight, which is your day-cycle setting. The day rolls over at 04:00.")
        case .midnightFallback:
            return String(localized: "No sleep onset was found for today, so it starts at midnight instead. The day rolls over at 04:00.")
        }
    }

    private func inputsCard(_ why: EffortWhy) -> some View {
        let b = why.breakdown
        return card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("What it is measured against")
                row("Max heart rate", "\(Int(b.hrMax.rounded())) bpm", hrMaxSourceLine(why.hrMaxSource))
                row("Resting heart rate", "\(Int(b.restingHR.rounded())) bpm",
                    why.storedRestingHR != nil
                        ? String(localized: "Today's stored resting heart rate.")
                        : String(localized: "A 60 bpm fallback, because no resting heart rate is stored for today yet."))
                row("Reserve", "\(Int(b.reserve.rounded())) bpm", String(localized: "Max minus resting. Zones are shares of this."))
                row("Method", Self.methodName(b.method), Self.methodLine(b.method))
            }
        }
    }

    private static func methodName(_ method: StrainScorer.Method) -> String {
        switch method {
        case .edwards: return "Edwards"
        case .banister: return "Banister"
        case .allDay: return "All-day"
        }
    }

    private static func methodLine(_ method: StrainScorer.Method) -> String {
        switch method {
        case .edwards:
            return String(localized: "Time in five zones above 50% of reserve, each weighted 1 to 5.")
        case .banister:
            return String(localized: "Experimental: every minute above the sedentary floor counts, rising steeply with intensity.")
        case .allDay:
            return String(localized: "Zones 1 to 5 as before, plus easy movement above about 25% of reserve while awake. Includes all-day movement (heart rate above your resting level), not steps.")
        }
    }

    private func hrMaxSourceLine(_ source: EffortWhy.HRMaxSource) -> String {
        switch source {
        case .manual: return String(localized: "Your manual max heart rate setting.")
        case .ageFormula(let age): return String(localized: "Age formula (208 − 0.7 × \(age)). Set a measured max in your profile to replace it.")
        case .defaultNoAge: return String(localized: "A default, because no date of birth is set in your profile.")
        }
    }

    private func addUpCard(_ why: EffortWhy) -> some View {
        let b = why.breakdown
        return card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("How it adds up")
                if b.method != .banister, let zones = b.zoneMinutes {
                    ForEach(1...5, id: \.self) { zone in
                        let pct = 40 + zone * 10
                        let low = b.restingHR + Double(pct) / 100.0 * b.reserve
                        HStack {
                            Text("Zone \(zone) · \(pct)%+ · \(Int(low.rounded()))+ bpm")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            Spacer()
                            Text("\(duration(zones[zone])) × \(zone)")
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                        }
                    }
                    HStack {
                        Text(b.method == .allDay ? "Below 50% (above 25% adds a little)" : "Below 50%")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        Spacer()
                        Text(b.method == .allDay ? duration(zones[0]) : "\(duration(zones[0])) × 0")
                            .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                Text(sentence(b))
                    .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sentence(_ b: EffortBreakdown) -> String {
        let trimp = b.trimp ?? 0
        let effort = b.effort.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "0"
        let bpm = Int(b.thresholdBpm.rounded())
        let t = String(format: "%.1f", trimp)
        if trimp <= 0 {
            return String(localized: "No time at or above \(bpm) bpm (\(Int(b.thresholdFraction * 100))% of your reserve) in this window, so the load is 0 and Effort is 0.")
        }
        let minutes = duration(b.countedMinutes)
        switch b.method {
        case .edwards:
            return String(localized: "\(minutes) above 50% of your reserve (about \(bpm) bpm), weighted by zone, gave a training load (TRIMP) of \(t). That scores Effort \(effort).")
        case .banister:
            return String(localized: "\(minutes) above the sedentary floor (about \(bpm) bpm), weighted by intensity, gave a training load (TRIMP) of \(t). That scores Effort \(effort).")
        case .allDay:
            return String(localized: "\(minutes) of movement above about \(bpm) bpm, weighted by intensity, gave a training load (TRIMP) of \(t). That scores Effort \(effort). Effort includes all-day movement (heart rate above your resting level), not steps.")
        }
    }

    private func chartCard(_ why: EffortWhy) -> some View {
        let b = why.breakdown
        return card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Heart rate in the window")
                EffortWindowChart(points: why.chart, start: why.windowStart, end: why.windowEnd,
                                  thresholdBpm: b.thresholdBpm, stretches: b.stretches)
                    .frame(height: 150)
                    .accessibilityElement()
                    .accessibilityLabel("Heart rate across the window, with the counting line at \(Int(b.thresholdBpm.rounded())) bpm")
                HStack {
                    Text(clock(why.windowStart))
                    Spacer()
                    Text(clock(why.windowEnd))
                }
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                Text("Dashed line: \(Int(b.thresholdBpm.rounded())) bpm. Shaded stretches are the time that counted.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stretchesCard(_ b: EffortBreakdown) -> some View {
        let top = b.topStretches(5)
        return card {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Longest stretches that counted")
                if top.isEmpty {
                    Text("Your heart rate has not reached \(Int(b.thresholdBpm.rounded())) bpm in this window.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(top.enumerated()), id: \.offset) { _, s in
                        Text("\(clock(s.startTs)) · \(duration(s.minutes)) · peak \(s.peakBpm) bpm")
                            .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    }
                }
            }
        }
    }

    private func insufficient(_ b: EffortBreakdown) -> some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Not enough to score yet")
                Text(b.reserve <= 0
                     ? String(localized: "Your max heart rate (\(Int(b.hrMax.rounded())) bpm) is not above your resting heart rate (\(Int(b.restingHR.rounded())) bpm), so zones cannot be worked out. Check your profile.")
                     : String(localized: "Effort needs about 10 minutes of heart rate in the window. This one has \(b.sampleCount) readings covering \(duration(Double(b.spanSeconds) / 60.0)). Keep the strap on and it fills in."))
                    .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Pieces

    private func card<Inner: View>(@ViewBuilder _ inner: @escaping () -> Inner) -> some View {
        NoopCard { inner() }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
    }

    private func row(_ label: LocalizedStringKey, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Text(value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
            }
            Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fmt(_ v: Double) -> String { UnitFormatter.effortDisplay(v, scale: effortScale) }

    private func clock(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }

    private func duration(_ minutes: Double) -> String {
        if minutes < 0.5 { return String(localized: "under 1 min") }
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
    }

    // MARK: Load

    /// Today only, with the window, HRmax, resting HR and method resolved exactly as `TodayView.loadAll`
    /// resolves them for the live Effort, so the explanation matches the ring.
    private func load() async {
        let now = Int(Date().timeIntervalSince1970)
        let logical = Repository.logicalDay(Date())
        let calendarStart = Int(Calendar.current.startOfDay(for: logical).timeIntervalSince1970)
        let dayKey = repo.today?.day ?? Repository.localDayKey(logical)
        let mode = DayCycleMode.persisted(dayCycleModeRaw)

        var onset: Int?
        if mode == .sleepOnset {
            let series = await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop")
            onset = series.last(where: { $0.day <= dayKey }).map { Int($0.value.rounded()) }
        }
        let start = onset ?? calendarStart
        let source: EffortWhy.StartSource = onset != nil ? .sleepOnset
            : (mode == .sleepOnset ? .midnightFallback : .midnightByChoice)
        let end = max(start, now - 1)

        let hr = await repo.hrSamples(from: start, to: end, limit: 200_000)
        let day = repo.today ?? repo.days.last(where: { $0.day == dayKey })
        let storedRest = day?.restingHr
        let restHR = storedRest.map(Double.init) ?? StrainScorer.defaultRestingHR
        let maxHR = profile.effortHRmax
        let method = PuffinExperiment.effortMethod
        let sex = profile.sex

        let b = await Task.detached(priority: .utility) {
            StrainScorer.breakdown(hr, maxHR: maxHR, restingHR: restHR, method: method, sex: sex)
        }.value

        guard !hr.isEmpty else {
            why = nil
            loaded = true
            return
        }
        let hrMaxSource: EffortWhy.HRMaxSource = profile.hrMaxOverride > 0 ? .manual
            : (profile.age > 0 ? .ageFormula(age: profile.age) : .defaultNoAge)
        why = EffortWhy(
            breakdown: b, windowStart: start, windowEnd: end, startSource: source, hrMaxSource: hrMaxSource,
            storedRestingHR: storedRest, storedEffort: day?.strain,
            displayed: StrainScorer.effectiveEffort(live: b.effort, stored: day?.strain),
            chart: Self.sliceMax(hr, start: start, end: end, slices: 160))
        loaded = true
    }

    /// Max bpm per equal slice of [start, end], so a day of ~18k readings draws as a few hundred points.
    private static func sliceMax(_ hr: [HRSample], start: Int, end: Int, slices: Int) -> [Int?] {
        var out = [Int?](repeating: nil, count: slices)
        let span = max(1, end - start)
        for s in hr {
            let i = min(slices - 1, max(0, (s.ts - start) * slices / span))
            out[i] = max(out[i] ?? s.bpm, s.bpm)
        }
        return out
    }
}

/// The window's heart rate as a line, the counting threshold as a dashed line and the counted
/// stretches as shaded bands.
private struct EffortWindowChart: View {
    let points: [Int?]
    let start: Int
    let end: Int
    let thresholdBpm: Double
    let stretches: [EffortStretch]

    var body: some View {
        Canvas { ctx, size in
            let present = points.compactMap { $0 }
            guard !present.isEmpty else { return }
            let lo = Double(min(present.min() ?? 50, Int(thresholdBpm)) - 5)
            let hi = Double(max(present.max() ?? 100, Int(thresholdBpm))) + 5
            let span = Double(max(1, end - start))
            func x(_ ts: Int) -> CGFloat { CGFloat(Double(ts - start) / span) * size.width }
            func y(_ bpm: Double) -> CGFloat { size.height - CGFloat((bpm - lo) / (hi - lo)) * size.height }

            for s in stretches {
                let left = x(s.startTs), right = max(left + 1.5, x(s.endTs))
                ctx.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)),
                         with: .color(StrandPalette.strain066.opacity(0.22)))
            }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(thresholdBpm)))
            line.addLine(to: CGPoint(x: size.width, y: y(thresholdBpm)))
            ctx.stroke(line, with: .color(StrandPalette.textTertiary),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            var trace = Path()
            var penDown = false
            for (i, value) in points.enumerated() {
                guard let value else { penDown = false; continue }
                let p = CGPoint(x: (CGFloat(i) + 0.5) / CGFloat(points.count) * size.width, y: y(Double(value)))
                if penDown { trace.addLine(to: p) } else { trace.move(to: p); penDown = true }
            }
            ctx.stroke(trace, with: .color(StrandPalette.accent),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
