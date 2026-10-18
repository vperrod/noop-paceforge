#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Charge / Effort / Rest detail in the dark look
//
// The top of the Charge, Effort and Rest metric screens: TODAY title bar, the big ring, the notched card of rows
// against the last 30 days (or the three-step rows for Rest), the gradient insight card carrying NOOP's own
// explanation with its link, the last seven days as bars, and two compact trend lines. It sits at the top of
// MetricDetailView; everything that screen already had (the Effort "why" link, history chart, stat tiles,
// readings, correlations, and for Charge the "what shaped it" drivers) stays below it.
//
// Every number is read from the same series the rest of the app reads (`Repository.exploreSeries`); nothing is
// scored or stored here. The Poor / Sufficient / Optimal bands are NOOP's own and the info sheet says so.

enum LookScoreKind: String, CaseIterable {
    case charge, effort, rest

    init?(metricKey: String) {
        switch metricKey {
        case HeroRingMetric.charge: self = .charge
        case HeroRingMetric.effort: self = .effort
        case HeroRingMetric.rest: self = .rest
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .charge: return "Charge"
        case .effort: return "Effort"
        case .rest: return "Rest"
        }
    }

    var metricKey: String {
        switch self {
        case .charge: return HeroRingMetric.charge
        case .effort: return HeroRingMetric.effort
        case .rest: return HeroRingMetric.rest
        }
    }
}

struct LookScoreDetailView: View {
    let kind: LookScoreKind

    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var series: [String: [LookPoint]] = [:]
    @State private var loaded = false
    @State private var effortReading: EffortTargetReading?
    @State private var chargeDrivers: [ChargeDriver] = []
    @State private var showInfo = false
    @State private var showGuide = false

    private var calendar: Calendar { Calendar.current }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var loadKey: String { "\(repo.refreshSeq)|\(effortScaleRaw)|\(kind.rawValue)" }

    // MARK: Series

    private static let whoop = "my-whoop"
    private static let garmin = "paceforge-garmin"
    private static let apple = "apple-health"

    private func seriesKey(_ key: String, _ source: String) -> String { "\(source):\(key)" }

    private func points(_ key: String, _ source: String = LookScoreDetailView.whoop) -> [LookPoint] {
        series[seriesKey(key, source)] ?? []
    }

    /// What this screen has to read, per kind.
    private var specs: [(key: String, source: String)] {
        switch kind {
        case .charge:
            return [("recovery", Self.whoop), ("hrv", Self.whoop), ("rhr", Self.whoop), ("resp_rate", Self.whoop),
                    ("sleep_performance", Self.whoop)]
        case .effort:
            return [("strain", Self.whoop), ("hr_zones13_min", Self.whoop), ("hr_zones45_min", Self.whoop),
                    ("strength_min", Self.whoop), ("steps", Self.garmin), ("steps", Self.whoop), ("steps", Self.apple)]
        case .rest:
            return [("sleep_performance", Self.whoop), ("hours_vs_needed_pct", Self.whoop),
                    ("sleep_consistency", Self.whoop), ("sleep_efficiency", Self.whoop),
                    ("sleep_avg_stress", Self.garmin)]
        }
    }

    private var mainPoints: [LookPoint] { points(kind.metricKey) }
    private var latest: LookPoint? { LookSeries.latest(mainPoints) }

    /// Steps come from Garmin first, then the strap, then Apple Health; the row says which.
    private var stepsSource: (source: String, label: String)? {
        for candidate in [(Self.garmin, "STEPS \u{00B7} GARMIN"), (Self.whoop, "STEPS"), (Self.apple, "STEPS \u{00B7} APPLE HEALTH")] {
            if !points("steps", candidate.0).isEmpty { return (candidate.0, candidate.1) }
        }
        return nil
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 16) {
            LookDetailTitleBar(onInfo: { showInfo = true })
            ring
            asOfCaption
            rowsCard
            insight
            LookWeekCard(title: "Last 7 days", items: weekItems, maxValue: 100, usesBands: kind == .charge,
                         color: kind == .effort ? NoopLook.effort : NoopLook.rest, valueText: weekValueText)
            ForEach(lineCards, id: \.id) { card in
                LookTrendLineCard(title: card.title, unit: card.unit, decimals: card.decimals,
                                  points: lastDays(card.points, 30), identifier: "look-line-\(card.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-score-detail-\(kind.rawValue)")
        .task(id: loadKey) { await load() }
        .sheet(isPresented: $showInfo) { LookScoreInfoSheet(kind: kind) { showInfo = false } }
        .sheet(isPresented: $showGuide) {
            NavigationStack {
                ScoringGuideView(initialSection: .charge, onClose: { showGuide = false })
            }
        }
    }

    // MARK: Ring

    private var ring: some View {
        let strain = latest?.value
        let fraction = latest.map { LookDial.fraction($0.value, max: 100) } ?? 0
        let valueText: String
        let unit: String?
        let color: Color
        let target: (start: Double, end: Double)?
        switch kind {
        case .charge:
            valueText = latest.map { String(Safe.int($0.value)) } ?? "\u{2013}"
            unit = latest == nil ? nil : "%"
            color = latest.map { NoopLook.chargeColor($0.value) } ?? NoopLook.chargeHigh
            target = nil
        case .effort:
            valueText = strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "\u{2013}"
            unit = nil
            color = NoopLook.effort
            let band = effortReading?.progress
            target = LookDial.targetArc(low: band?.lowFraction, high: band?.highFraction, max: 1)
        case .rest:
            valueText = latest.map { String(Safe.int($0.value)) } ?? "\u{2013}"
            unit = latest == nil ? nil : "%"
            color = NoopLook.rest
            target = nil
        }
        return RingDial(fraction: fraction, color: color, valueText: valueText, unitText: unit, target: target,
                        diameter: 272, style: .hero, wordmark: "NOOP", titleLines: [kind.title.uppercased()],
                        accessibilityName: kind.title)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .accessibilityIdentifier("look-score-ring")
    }

    @ViewBuilder private var asOfCaption: some View {
        if let latest, !calendar.isDateInToday(latest.date) {
            Text("As of \(Self.captionFormatter.string(from: latest.date)). Today's score is not in yet.")
                .font(LookFont.text(13, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else if loaded && latest == nil {
            Text("No \(kind.title) has been scored yet.")
                .font(LookFont.text(13, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private static let captionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    // MARK: Rows

    private func number(_ value: Double) -> String { String(Safe.int(value)) }
    private func percent(_ value: Double) -> String { "\(Safe.int(value))%" }
    private func clock(_ minutes: Double) -> String { LookFormat.hoursMinutes(minutes: Safe.int(minutes)) }
    private func grouped(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value.rounded())) ?? number(value)
    }

    private func compareRow(_ id: String, _ icon: String, _ label: String, key: String,
                            source: String = LookScoreDetailView.whoop, decimals: Int = 0, higherIsBetter: Bool?,
                            format: (Double) -> String) -> LookCompareRow? {
        guard let c = LookBaseline.comparison(points(key, source), decimals: decimals, higherIsBetter: higherIsBetter,
                                              calendar: calendar) else { return nil }
        return LookCompareRow(id: id, icon: icon, label: label, valueText: format(c.value),
                              baselineText: c.baseline.map(format), mark: c.mark)
    }

    private var compareRows: [LookCompareRow] {
        switch kind {
        case .charge:
            return [
                compareRow("hrv", "waveform.path.ecg", "Heart rate variability", key: "hrv", higherIsBetter: true, format: number),
                compareRow("rhr", "heart", "Resting heart rate", key: "rhr", higherIsBetter: false, format: number),
                compareRow("resp", "lungs", "Respiratory rate", key: "resp_rate", decimals: 1, higherIsBetter: false,
                           format: { LookFormat.number($0, decimals: 1) }),
                compareRow("rest", "moon", "Rest", key: "sleep_performance", higherIsBetter: true, format: percent),
            ].compactMap { $0 }
        case .effort:
            var rows = [
                compareRow("z13", "heart", "HR zones 1-3", key: "hr_zones13_min", higherIsBetter: nil, format: clock),
                compareRow("z45", "heart.fill", "HR zones 4-5", key: "hr_zones45_min", higherIsBetter: nil, format: clock),
                compareRow("strength", "dumbbell", "Strength activity time", key: "strength_min", higherIsBetter: nil, format: clock),
            ]
            if let steps = stepsSource {
                rows.append(compareRow("steps", "figure.walk", steps.label, key: "steps", source: steps.source,
                                       higherIsBetter: true, format: grouped))
            }
            return rows.compactMap { $0 }
        case .rest:
            return []
        }
    }

    private func stepItem(_ id: String, _ icon: String, _ label: String, key: String,
                          source: String = LookScoreDetailView.whoop,
                          band: (Double) -> LookStep, format: (Double) -> String) -> ThreeStepRows.ThreeStepItem? {
        guard let value = LookSeries.latest(points(key, source))?.value else { return nil }
        return .init(id: id, icon: icon, label: label, step: band(value), valueText: format(value))
    }

    private var stepRows: [ThreeStepRows.ThreeStepItem] {
        [
            stepItem("hours", "moon", "Hours vs. needed", key: "hours_vs_needed_pct", band: LookRestBands.hoursVsNeeded, format: percent),
            stepItem("consistency", "calendar", "Sleep consistency", key: "sleep_consistency", band: LookRestBands.consistency, format: percent),
            stepItem("efficiency", "bed.double", "Sleep efficiency", key: "sleep_efficiency", band: LookRestBands.efficiency, format: percent),
            stepItem("stress", "waveform.path", "Sleep stress \u{00B7} Garmin", key: "sleep_avg_stress",
                     source: Self.garmin, band: LookRestBands.sleepStress, format: number),
        ].compactMap { $0 }
    }

    @ViewBuilder private var rowsCard: some View {
        if kind == .rest {
            if stepRows.isEmpty {
                emptyRows
            } else {
                ThreeStepRows(rows: stepRows).accessibilityIdentifier("look-score-rows")
            }
        } else if compareRows.isEmpty {
            emptyRows
        } else {
            TodayVs30Rows(rows: compareRows).accessibilityIdentifier("look-score-rows")
        }
    }

    @ViewBuilder private var emptyRows: some View {
        if loaded {
            LookInfoCard(title: "Nothing to compare yet",
                         message: "These rows fill in as soon as the readings behind \(kind.title) arrive.")
        }
    }

    // MARK: Insight

    private var insightText: String {
        switch kind {
        case .charge:
            let top = chargeDrivers.sorted { abs($0.deltaPoints) > abs($1.deltaPoints) }.prefix(2)
            if !top.isEmpty {
                return top.map { "\($0.label) (\($0.valueText)): \($0.verdict)." }.joined(separator: " ")
            }
            return "Charge is how recovered you are, led by HRV against your own baseline."
        case .effort:
            if let text = effortReading?.progress.text, !text.isEmpty { return text }
            return "Effort is the cardiovascular load of the day."
        case .rest:
            if let hours = LookSeries.latest(points("hours_vs_needed_pct"))?.value {
                return "You slept \(Safe.int(hours)) % of the sleep you needed. Rest also weighs efficiency, depth and timing."
            }
            return "Rest is how restorative your sleep was: duration, efficiency, deep and REM, and timing."
        }
    }

    @ViewBuilder private var insight: some View {
        switch kind {
        case .charge:
            LookInsightCard(insightText, linkTitle: "Break down my Charge", action: { showGuide = true })
                .accessibilityIdentifier("look-score-insight")
        case .effort:
            NavigationLink { EffortBreakdownView() } label: {
                LookInsightCard(insightText, linkTitle: "Explore my Effort")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("look-score-insight")
        case .rest:
            NavigationLink(value: TabRoute.sleep) {
                LookInsightCard(insightText, linkTitle: "Explore your sleep insights")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("look-score-insight")
        }
    }

    // MARK: Week and lines

    private var weekItems: [WeeklyBarItem] {
        let days = LookWeek.days(points: mainPoints, endingOn: Date(), calendar: calendar)
        return days.map { WeeklyBarItem(id: LookDayKey.key($0.date, calendar: calendar), label: $0.letter,
                                        value: $0.value, isToday: $0.isToday) }
    }

    private var weekValueText: (Double) -> String {
        if kind == .effort {
            let scale = effortScale
            return { UnitFormatter.effortDisplay($0, scale: scale) }
        }
        return { String(Safe.int($0)) }
    }

    private struct LineCard {
        let id: String
        let title: String
        let unit: String
        let decimals: Int
        let points: [LookPoint]
    }

    private var lineCards: [LineCard] {
        switch kind {
        case .charge:
            return [LineCard(id: "hrv", title: "Heart rate variability", unit: "ms", decimals: 0, points: points("hrv")),
                    LineCard(id: "rhr", title: "Resting heart rate", unit: "bpm", decimals: 0, points: points("rhr"))]
        case .effort:
            var cards = [LineCard(id: "z45", title: "HR zones 4-5", unit: "min", decimals: 0, points: points("hr_zones45_min"))]
            if let steps = stepsSource {
                cards.append(LineCard(id: "steps", title: steps.label.capitalized, unit: "", decimals: 0,
                                      points: points("steps", steps.source)))
            }
            return cards
        case .rest:
            return [LineCard(id: "hours", title: "Hours vs. needed", unit: "%", decimals: 0, points: points("hours_vs_needed_pct")),
                    LineCard(id: "efficiency", title: "Sleep efficiency", unit: "%", decimals: 0, points: points("sleep_efficiency"))]
        }
    }

    private func lastDays(_ pts: [LookPoint], _ days: Int) -> [LookPoint] {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return LookSeries.within(pts, from: start, to: end)
    }

    // MARK: Load

    @MainActor private func load() async {
        var out: [String: [LookPoint]] = [:]
        for spec in specs {
            let rows = await repo.exploreSeries(key: spec.key, source: spec.source, days: 400)
            out[seriesKey(spec.key, spec.source)] = LookSeries.points(rows, calendar: calendar)
        }
        guard !Task.isCancelled else { return }
        series = out
        if kind == .effort {
            effortReading = EffortTargetReading.make(days: repo.days, effortScale: effortScale)
        }
        if kind == .charge { chargeDrivers = currentChargeDrivers() }
        loaded = true
    }

    /// The same drivers the Charge sheet shows, for the latest scored day.
    @MainActor private func currentChargeDrivers() -> [ChargeDriver] {
        guard let baselines = repo.chargeBaselines,
              let row = repo.days.last(where: { $0.recovery != nil }) else { return [] }
        let rest = LookSeries.latest(points("sleep_performance"))?.value
        return ChargeBreakdownWiring.breakdown(baselines: baselines, row: row, sleepPerfPercent: rest)?.drivers ?? []
    }
}

// MARK: - Info sheet

/// "What is it?" for each score, in NOOP's own words.
private struct LookScoreInfoSheet: View {
    let kind: LookScoreKind
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(cards, id: \.title) { LookInfoCard(title: $0.title, message: $0.message) }
                }
                .padding(16)
            }
            .lookScreenBackground()
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onClose) }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var cards: [(title: String, message: String)] {
        switch kind {
        case .charge:
            return [("What is Charge?", "How recovered you are today, led by your heart rate variability against your own baseline, with resting heart rate, last night's Rest, breathing rate and skin temperature. The rows compare today with your last 30 days: a green triangle is better than usual, an orange one is worse. The bars are red under 34, yellow from 34 and green from 67."),
                    ("Where the numbers come from", "NOOP's own weighting, openly documented in the scoring guide. It is calibrated to you, not to anyone else's scale.")]
        case .effort:
            return [("What is Effort?", "The cardiovascular load of your day, from how hard your heart worked. The grey arc and white tick on the ring are today's target range, taken from your Charge. The rows compare today's training time and steps with your last 30 days."),
                    ("Steps", "Steps come from Garmin when it has them, then the strap, then Apple Health. The row says which.")]
        case .rest:
            return [("What is Rest?", "How restorative your sleep was. The rows show hours against what you needed, how steady your sleep schedule was, how much of your time in bed you spent asleep and, from Garmin, how stressed your body was overnight."),
                    ("Poor, Sufficient, Optimal", "These three bands are NOOP's own cut-offs, not a published standard: hours vs. needed 70 and 100 %, consistency 60 and 80 %, efficiency 75 and 85 %, sleep stress under 40 and under 25.")]
        }
    }
}
#endif
