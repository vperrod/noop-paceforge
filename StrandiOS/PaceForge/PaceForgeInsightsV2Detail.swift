import SwiftUI
import Charts
import StrandDesign

// The evidence under each Insights v2 item: power curve and FTP, race countdown, weight goal, efficiency and sleep.
// The detail screen (PaceForgeInsightsV2View.swift) puts the status, the meaning and the actions above these cards;
// each card here shows its own honest "not enough data" box when the server has nothing to draw. The charts use the
// same Swift Charts building blocks as the Body and Insights screens.

private struct PFLegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

private func wattsText(_ watts: Double?) -> String {
    guard let watts else { return "\u{2014}" }
    return "\(Safe.int(watts)) W"
}

// MARK: - Power curve and FTP

struct PFPowerCurveDetail: View {
    let item: PFInsightItem
    let power: PFPowerMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ftpCard
            curveCard
            durationsCard
            profileCard
        }
    }

    private var ftpCard: some View {
        PFCard("FTP: estimate, Garmin and in use", icon: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if power.ftpRows.isEmpty {
                    PFInsufficient(title: "No FTP yet",
                                   text: item.status.reason ?? "There is no 20-minute effort in the last 90 days, so an FTP estimate would be a guess.",
                                   identifier: "pf-power-no-ftp")
                } else {
                    ForEach(power.ftpRows) { row in
                        PFInsightRow(label: row.label, value: wattsText(row.watts), caption: row.note)
                            .accessibilityIdentifier("pf-power-ftp-\(row.id)")
                        if row.id != power.ftpRows.last?.id { Divider().overlay(StrandPalette.hairline) }
                    }
                    HStack(spacing: 8) {
                        if let wPerKg = power.wPerKg { PFChip(text: "\(PFNumber.trimmed(wPerKg)) W/kg", color: StrandPalette.accent) }
                        if let pct = power.vsInUsePct {
                            PFChip(text: "\(PFNumber.signed(pct, decimals: 1)) % against the FTP in use", color: StrandPalette.textTertiary)
                        }
                    }
                    if let evidence = power.evidence {
                        PFParagraph("Best 20 minutes in the last 90 days: \(wattsText(evidence.watts))"
                                    + (evidence.date.map { " on \(PFFormat.shortDate($0))" } ?? "") + ".")
                    }
                }
                retest
            }
        }
        .containerIdentifier("pf-power-ftp")
    }

    @ViewBuilder private var retest: some View {
        if power.retestDue == true {
            VStack(alignment: .leading, spacing: 4) {
                PFChip(text: "FTP test due", color: PFColor.warning)
                if let reason = power.retestReason { PFParagraph(reason.prefix(1).uppercased() + reason.dropFirst() + ".") }
            }
            .accessibilityIdentifier("pf-power-retest")
        } else if let next = power.retestNextDate {
            PFParagraph("The estimate holds until about \(PFFormat.shortDate(next)); re-test on or after that day.")
                .accessibilityIdentifier("pf-power-retest")
        }
    }

    private var curveCard: some View {
        PFCard("Mean-max power curve", icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                if power.hasCurve {
                    PFPowerCurveChart(points: power.curve, ftp: power.estimateW)
                        .frame(height: 220)
                        .accessibilityLabel("Best average power for each duration, last 90 days and all time")
                        .accessibilityIdentifier("pf-power-curve-chart")
                    HStack(spacing: 14) {
                        PFLegendDot(color: StrandPalette.accent, text: "Last \(power.windowDays ?? 90) days")
                        PFLegendDot(color: StrandPalette.textTertiary, text: "All time")
                        PFLegendDot(color: PFColor.positive, text: "FTP estimate")
                    }
                    PFParagraph("Each point is the highest average power you held for that long. A higher, flatter curve is fitter.")
                } else {
                    PFInsufficient(title: "No power curve yet",
                                   text: "No ride with second-by-second power has a recent best to plot.",
                                   identifier: "pf-power-no-curve")
                }
            }
        }
        .containerIdentifier("pf-power-curve")
    }

    @ViewBuilder private var durationsCard: some View {
        let rows = power.durations.filter { $0.best90 != nil || $0.bestAll != nil }
        if !rows.isEmpty {
            PFCard("Best efforts", icon: "list.number") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows) { row in
                        PFInsightRow(label: row.label, value: wattsText(row.best90?.watts), caption: caption(row))
                            .accessibilityIdentifier("pf-power-duration-\(row.seconds)")
                        if row.id != rows.last?.id { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
            .containerIdentifier("pf-power-durations")
        }
    }

    private func caption(_ row: PFPowerDuration) -> String? {
        var parts: [String] = []
        if let wPerKg = row.wPerKg90 { parts.append("\(String(format: "%.2f", wPerKg)) W/kg") }
        if let date = row.best90?.date { parts.append(PFFormat.shortDate(date)) }
        if let all = row.bestAll?.watts, all > (row.best90?.watts ?? 0) { parts.append("all time \(wattsText(all))") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    @ViewBuilder private var profileCard: some View {
        if !power.profile.isEmpty {
            PFCard("Against the usual ranges", icon: "scope") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(power.profile) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(StrandFont.subhead.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                if let pct = row.pctFtp {
                                    Text("\(pct) % of FTP" + (row.expected.map { ", usual: \($0)" } ?? ""))
                                        .font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            PFChip(text: PFInsightVerdict.profileText(row.verdict),
                                   color: PFInsightColor.color(for: PFInsightVerdict.profileTone(row.verdict)))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pf-power-profile-\(row.label)")
                    }
                }
            }
            .containerIdentifier("pf-power-profile")
        }
    }
}

/// Mean-max power by duration on a log time axis (5 s to 2 h), last 90 days against all time, with the FTP estimate.
private struct PFPowerCurveChart: View {
    let points: [PFPowerCurvePoint]
    let ftp: Double?

    private static let ticks: [(seconds: Double, label: String)] = [
        (5, "5 s"), (60, "1 min"), (300, "5 min"), (1200, "20 min"), (3600, "1 h"),
    ]

    private static func position(_ seconds: Int) -> Double { log10(Double(max(seconds, 1))) }

    private static func label(forPosition value: Double) -> String {
        ticks.first { abs(log10($0.seconds) - value) < 0.01 }?.label ?? ""
    }

    var body: some View {
        let recent = points.compactMap { point in point.last90.map { (x: Self.position(point.seconds), watts: $0) } }
        let allTime = points.compactMap { point in point.allTime.map { (x: Self.position(point.seconds), watts: $0) } }
        Chart {
            ForEach(Array(allTime.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Duration", p.x), y: .value("Watts", p.watts), series: .value("Series", "all"))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
            }
            ForEach(Array(recent.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Duration", p.x), y: .value("Watts", p.watts), series: .value("Series", "recent"))
                    .foregroundStyle(StrandPalette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.6))
                PointMark(x: .value("Duration", p.x), y: .value("Watts", p.watts))
                    .foregroundStyle(StrandPalette.accent)
                    .symbolSize(24)
            }
            if let ftp {
                RuleMark(y: .value("FTP estimate", ftp))
                    .foregroundStyle(PFColor.positive.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXAxis {
            AxisMarks(values: Self.ticks.map { log10($0.seconds) }) { value in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel {
                    if let position = value.as(Double.self) {
                        Text(Self.label(forPosition: position)).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

// MARK: - Race countdown

struct PFRaceCountdownDetail: View {
    let item: PFInsightItem
    let race: PFRaceMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            countdownCard
            finishCard
            formCard
            taperCard
        }
    }

    private var countdownCard: some View {
        PFCard(race.name ?? "The race", icon: "flag.checkered") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let days = race.daysTo {
                        Text(days > 1 ? "\(days)" : (race.countdownText ?? "\(days)"))
                            .font(StrandFont.rounded(40))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .accessibilityIdentifier("pf-race-days")
                        if days > 1 {
                            Text("days to go").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let date = race.date {
                        Text(PFFormat.dayTitle(date)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                if let goal = race.goalTime { PFChip(text: "Goal \(goal)", color: StrandPalette.accent) }
                if !race.phases.isEmpty { phases }
            }
        }
        .containerIdentifier("pf-race-countdown")
    }

    private var phases: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where you are in the build").strandOverline()
            ForEach(race.phases) { phase in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(phase.isCurrent ? StrandPalette.accent : StrandPalette.textTertiary.opacity(0.35))
                            .frame(width: 8, height: 8)
                        Text(phase.label)
                            .font(StrandFont.subhead.weight(phase.isCurrent ? .bold : .regular))
                            .foregroundStyle(phase.isCurrent ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        Spacer(minLength: 8)
                        if let from = phase.from, let to = phase.to {
                            Text(from == to ? PFFormat.shortDate(from) : "\(PFFormat.shortDate(from)) to \(PFFormat.shortDate(to))")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        } else if let to = phase.to {
                            Text("until \(PFFormat.shortDate(to))")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    if phase.isCurrent {
                        if let protects = phase.protects { PFLabeled(label: "Protect", text: protects) }
                        if let cuts = phase.cuts { PFLabeled(label: "Cut", text: cuts) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("pf-race-phase-\(phase.id)")
            }
        }
    }

    private var finishCard: some View {
        PFCard("Predicted finish", icon: "stopwatch") {
            VStack(alignment: .leading, spacing: 12) {
                if let finish = race.finish {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(finish.central ?? "\u{2014}")
                            .font(StrandFont.rounded(34))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .accessibilityIdentifier("pf-race-finish")
                        if let low = finish.low, let high = finish.high {
                            Text("range \(low) to \(high)").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    PFFinishBar(finish: finish)
                    if let goal = finish.goal {
                        HStack(spacing: 8) {
                            PFChip(text: "Goal \(goal)", color: PFColor.positive)
                            if let gap = finish.gapText { PFChip(text: gap, color: StrandPalette.textTertiary) }
                        }
                        if let inRange = finish.goalInRange {
                            PFParagraph(inRange ? "The goal is inside the predicted range." : "The goal is outside the predicted range.")
                                .accessibilityIdentifier("pf-race-goal-in-range")
                        }
                    } else {
                        PFParagraph("This race has no goal time to compare with.")
                    }
                    if let method = finish.method { PFLabeled(label: "How it is predicted", text: method) }
                    if let basis = finish.rangeBasis { PFLabeled(label: "Where the range comes from", text: basis) }
                } else {
                    PFInsufficient(title: "No finish prediction",
                                   text: item.status.reason ?? "No finish time can be predicted for this kind of event.",
                                   identifier: "pf-race-no-finish")
                }
                if !race.garminPredictions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Garmin's predictions" + (race.garminPredictionsDate.map { ", \(PFFormat.shortDate($0))" } ?? ""))
                            .strandOverline()
                        ForEach(race.garminPredictions) { prediction in
                            PFInsightRow(label: prediction.label, value: prediction.display ?? "\u{2014}")
                        }
                    }
                }
            }
        }
        .containerIdentifier("pf-race-finish-card")
    }

    private var formCard: some View {
        PFCard("Fitness, fatigue and form to race day", icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                if race.form.count >= 2 {
                    PFRaceFormChart(points: race.form, taper: race.taper)
                        .frame(height: 220)
                        .accessibilityLabel("Planned fitness, fatigue and form from today to race day")
                        .accessibilityIdentifier("pf-race-form-chart")
                    HStack(spacing: 14) {
                        PFLegendDot(color: PFColor.positive, text: "Fitness")
                        PFLegendDot(color: PFColor.warning, text: "Fatigue")
                        PFLegendDot(color: PFColor.violet, text: "Form")
                        if race.taper?.hasWindow == true { PFLegendDot(color: PFColor.positive.opacity(0.4), text: "Form target") }
                    }
                    PFParagraph("Counts only the sessions already on the calendar; sessions added later move the lines.")
                } else {
                    PFInsufficient(title: "No projection yet",
                                   text: "The planned calendar does not reach race day, so there is no form curve to draw.",
                                   identifier: "pf-race-no-form")
                }
            }
        }
        .containerIdentifier("pf-race-form")
    }

    @ViewBuilder private var taperCard: some View {
        if let taper = race.taper {
            PFCard("Taper", icon: "arrow.down.right") {
                VStack(alignment: .leading, spacing: 10) {
                    PFChip(text: PFInsightVerdict.taperText(taper.verdict),
                           color: PFInsightColor.color(for: PFInsightVerdict.taperTone(taper.verdict)))
                        .accessibilityIdentifier("pf-race-taper-verdict")
                    if let reason = taper.reason { PFParagraph(reason) }
                    if let low = taper.tsbLow, let high = taper.tsbHigh {
                        PFInsightRow(label: "Form target on race morning", value: "\(PFNumber.trimmed(low)) to \(PFNumber.trimmed(high))")
                    }
                    if let planned = taper.raceMorningTsb {
                        PFInsightRow(label: "Planned form on race morning", value: PFNumber.signed(planned, decimals: 0))
                    }
                    if let scenario = taper.scenarioTsb {
                        PFInsightRow(label: "With the race-week volume table", value: PFNumber.signed(scenario, decimals: 0))
                    }
                }
            }
            .containerIdentifier("pf-race-taper")
        }
    }
}

/// The predicted range as a bar with the central time and the goal marked.
private struct PFFinishBar: View {
    let finish: PFFinishRange

    var body: some View {
        if let bar = finish.bar {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset).frame(height: 10)
                    Capsule()
                        .fill(StrandPalette.accent.opacity(0.35))
                        .frame(width: max(6, width * CGFloat(bar.high - bar.low)), height: 10)
                        .offset(x: width * CGFloat(bar.low))
                    Circle()
                        .fill(StrandPalette.accent)
                        .frame(width: 14, height: 14)
                        .offset(x: width * CGFloat(bar.central) - 7)
                    if let goal = bar.goal {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(PFColor.positive)
                            .frame(width: 3, height: 24)
                            .offset(x: width * CGFloat(goal) - 1.5)
                    }
                }
                .frame(height: 24)
            }
            .frame(height: 24)
            .accessibilityHidden(true)
            .accessibilityIdentifier("pf-race-finish-bar")
        }
    }
}

/// CTL, ATL and TSB from today to race day, with the race-morning form target as a band over the last week.
private struct PFRaceFormChart: View {
    let points: [PFFormPoint]
    let taper: PFTaper?

    private func series(_ key: KeyPath<PFFormPoint, Double>) -> [(date: Date, value: Double)] {
        points.map { (date: PFFormat.date($0.date), value: $0[keyPath: key]) }
    }

    var body: some View {
        let ctl = series(\.ctl), atl = series(\.atl), tsb = series(\.tsb)
        let first = ctl.first?.date ?? Date(), last = ctl.last?.date ?? Date()
        let bandStart = max(first, last.addingTimeInterval(-6 * 86_400))
        Chart {
            if let low = taper?.tsbLow, let high = taper?.tsbHigh {
                RectangleMark(xStart: .value("From", bandStart), xEnd: .value("To", last),
                              yStart: .value("Target low", low), yEnd: .value("Target high", high))
                    .foregroundStyle(PFColor.positive.opacity(0.22))
            }
            ForEach(Array(ctl.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("Load", p.value), series: .value("Series", "ctl"))
                    .foregroundStyle(PFColor.positive)
                    .lineStyle(StrokeStyle(lineWidth: 2.6))
            }
            ForEach(Array(atl.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("Load", p.value), series: .value("Series", "atl"))
                    .foregroundStyle(PFColor.warning)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
            ForEach(Array(tsb.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("Load", p.value), series: .value("Series", "tsb"))
                    .foregroundStyle(PFColor.violet)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

// MARK: - Weight goal

struct PFWeightGoalDetail: View {
    let item: PFInsightItem
    let weight: PFWeightMetric
    private let hiding = PFHiding()

    private var hidden: Bool { hiding.hides(.body) }

    var body: some View {
        if hidden {
            PFCard("Weight", icon: "scalemass") {
                PFParagraph("\(PFRedact.placeholder) \u{2014} body weight is hidden. Tap the eye above to show it, or turn this off in Settings > Hide numbers.")
            }
            .containerIdentifier("pf-weight-hidden")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                figuresCard
                if weight.hasTrend { weightTrendCard }
                PFWhatMovedSection(intelKey: "weight")
                chartCard
            }
        }
    }

    private func kg(_ value: Double?) -> String { value.map { "\(PFNumber.trimmedOne($0)) kg" } ?? "\u{2014}" }

    /// 0.45 kg/week; a minus sign when the trend is moving the wrong way.
    private func perWeek(_ value: Double) -> String {
        (value < 0 ? "\u{2212}" : "") + String(format: "%.2f", abs(value)) + " kg/week"
    }

    private var figuresCard: some View {
        PFCard("Where you are against the goal", icon: "scalemass") {
            VStack(alignment: .leading, spacing: 12) {
                PFInsightRow(label: "Weight trend", value: kg(weight.trendKg),
                             caption: weight.lastReadingKg.map { "Last reading \(PFNumber.trimmedOne($0)) kg" })
                    .accessibilityIdentifier("pf-weight-trend")
                Divider().overlay(StrandPalette.hairline)
                PFInsightRow(label: "Target", value: kg(weight.targetKg),
                             caption: weight.targetDate.map { "By \(PFFormat.shortDate($0))" + (weight.weeksLeft.map { ", \(Safe.int($0)) weeks left" } ?? "") })
                    .accessibilityIdentifier("pf-weight-target")
                if let toGo = weight.kgToGo {
                    Divider().overlay(StrandPalette.hairline)
                    PFInsightRow(label: "To go", value: toGo > 0 ? kg(toGo) : "Reached")
                }
                Divider().overlay(StrandPalette.hairline)
                pace
                if let deficit = weight.deficitKcalPerDay {
                    PFParagraph("The needed pace is about \(Safe.int(deficit)) kcal a day below maintenance (an estimate: 7700 kcal per kg, and this app does not log food).")
                }
                if weight.aggressive == true {
                    PFChip(text: "Faster than \(weight.safeKgPerWeek.map { PFNumber.trimmed($0) } ?? "the safe") kg/week", color: PFColor.warning)
                        .accessibilityIdentifier("pf-weight-aggressive")
                }
                if let text = weight.pathText { PFParagraph(text) }
            }
        }
        .containerIdentifier("pf-weight-figures")
    }

    @ViewBuilder private var pace: some View {
        PFInsightRow(label: "Pace needed", value: weight.neededKgPerWeek.map { perWeek($0) } ?? "\u{2014}")
        if let actual = weight.actualKgPerWeek {
            PFInsightRow(label: "Your pace", value: perWeek(actual),
                         caption: weight.scheduleText { PFFormat.shortDate($0) })
                .accessibilityIdentifier("pf-weight-pace")
        } else {
            PFInsufficient(title: "Your own pace cannot be read yet",
                           text: item.status.reason ?? "Not enough weigh-ins to read your own pace yet (needs 4 readings over at least 7 days).",
                           identifier: "pf-weight-no-pace")
        }
    }

    private var weightTrendCard: some View {
        PFCard("Weight over time", icon: "chart.line.uptrend.xyaxis") {
            LookTrendHost(metrics: [
                PFLook.metric(id: "trend", title: "Weight trend", icon: "scalemass", unit: "kg", decimals: 1, higherIsBetter: nil,
                              rows: weight.series.compactMap { row in row.trendKg.map { (date: row.date, value: $0) } },
                              what: "The smoothed weight: each weigh-in nudges it, so one heavy morning does not move it far."),
                PFLook.metric(id: "readings", title: "Weigh-ins", icon: "scalemass.fill", unit: "kg", decimals: 1, higherIsBetter: nil,
                              rows: weight.series.compactMap { row in row.weightKg.map { (date: row.date, value: $0) } },
                              what: "Each reading from the scale, as measured."),
            ])
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pf-weight-look-trend")
        }
        .containerIdentifier("pf-weight-look-card")
    }

    private var chartCard: some View {
        PFCard("Trend, noise and the path to the target", icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                if weight.hasTrend {
                    PFWeightGoalChart(weight: weight)
                        .frame(height: 230)
                        .accessibilityLabel("Weight readings, trend and noise band against the path to the target")
                        .accessibilityIdentifier("pf-weight-chart")
                    HStack(spacing: 14) {
                        PFLegendDot(color: StrandPalette.accent, text: "Trend")
                        PFLegendDot(color: PFColor.positive, text: "Needed path")
                        PFLegendDot(color: StrandPalette.textTertiary, text: "Usual noise")
                    }
                    if let noise = weight.noiseKg {
                        PFParagraph("The shaded band is +/-\(PFNumber.trimmed(noise)) kg around the trend"
                                    + (weight.noiseBasis == "measured" ? ", measured from your own readings." : ", the default until there are 7 readings."))
                    }
                } else {
                    PFInsufficient(title: "Not enough weigh-ins for a trend",
                                   text: "\(weight.readings ?? 0) reading\(weight.readings == 1 ? "" : "s") so far. A trend line needs at least two.",
                                   identifier: "pf-weight-no-trend")
                }
            }
        }
        .containerIdentifier("pf-weight-chart-card")
    }
}

private struct PFWeightGoalChart: View {
    let weight: PFWeightMetric

    private var readings: [(date: Date, kg: Double)] {
        weight.series.compactMap { row in row.weightKg.map { (date: PFFormat.date(row.date), kg: $0) } }
    }

    private var trend: [(date: Date, kg: Double)] {
        weight.series.compactMap { row in row.trendKg.map { (date: PFFormat.date(row.date), kg: $0) } }
    }

    private var band: [(date: Date, low: Double, high: Double)] {
        weight.series.compactMap { row -> (date: Date, low: Double, high: Double)? in
            guard let low = row.bandLowKg, let high = row.bandHighKg else { return nil }
            return (PFFormat.date(row.date), low, high)
        }
    }

    private var needed: [(date: Date, kg: Double)] {
        weight.neededPath.map { (date: PFFormat.date($0.date), kg: $0.weightKg) }
    }

    private var projected: [(date: Date, kg: Double)] {
        weight.projectedLine.map { (date: PFFormat.date($0.date), kg: $0.weightKg) }
    }

    /// Everything the chart must keep in view: the readings, the trend, the noise band, the needed path and the target.
    private var yDomain: ClosedRange<Double> {
        var all: [Double] = readings.map { $0.kg }
        all += trend.map { $0.kg }
        all += band.flatMap { [$0.low, $0.high] }
        all += needed.map { $0.kg }
        if let target = weight.targetKg { all.append(target) }
        let lo = all.min() ?? 0, hi = all.max() ?? 1
        let pad = max((hi - lo) * 0.12, 0.5)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(Array(band.enumerated()), id: \.offset) { _, b in
                AreaMark(x: .value("Date", b.date), yStart: .value("Noise low", b.low), yEnd: .value("Noise high", b.high))
                    .foregroundStyle(StrandPalette.textTertiary.opacity(0.18))
            }
            ForEach(Array(readings.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("Date", p.date), y: .value("Weight", p.kg))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .symbolSize(18)
            }
            ForEach(Array(trend.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("Weight", p.kg), series: .value("Series", "trend"))
                    .foregroundStyle(StrandPalette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.6))
            }
            ForEach(Array(needed.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("Weight", p.kg), series: .value("Series", "needed"))
                    .foregroundStyle(PFColor.positive)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
            }
            ForEach(Array(projected.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("Weight", p.kg), series: .value("Series", "projected"))
                    .foregroundStyle(StrandPalette.accent.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [2, 3]))
            }
            if let target = weight.targetKg {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(PFColor.positive.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

// MARK: - Efficiency

struct PFEfficiencyDetail: View {
    let item: PFInsightItem
    let efficiency: PFEfficiencyMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            runningCard
            bikeCard
            zonesCard
        }
    }

    private func paceText(_ seconds: Double?) -> String {
        seconds.map { "\(PFFormat.pace($0)) /km" } ?? "\u{2014}"
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(PFNumber.signed($0)) %" } ?? "\u{2014}"
    }

    private var runningCard: some View {
        let run = efficiency.running
        return PFCard(title: "Running efficiency", icon: "figure.run", trailing: {
            PFChip(text: PFInsightVerdict.trendText(run.verdict), color: PFInsightColor.color(for: PFInsightVerdict.trendTone(run.verdict)))
                .accessibilityIdentifier("pf-eff-run-verdict")
        }) {
            VStack(alignment: .leading, spacing: 12) {
                if run.isReadable {
                    PFInsightRow(label: "Pace at \(run.referenceHr.map { "\($0)" } ?? "the same") bpm", value: paceText(run.paceRecentS),
                                 caption: "Six weeks earlier: \(paceText(run.pacePriorS)). Change \(percent(run.changePct)).")
                        .accessibilityIdentifier("pf-eff-run-pace")
                    if run.series.filter({ $0.ef != nil }).count >= 2 {
                        LookTrendHost(metrics: [
                            PFLook.metric(id: "ef", title: "Speed per heartbeat", icon: "figure.run", decimals: 2, higherIsBetter: true,
                                          rows: run.series.compactMap { p in p.ef.map { (date: p.date, value: $0) } },
                                          what: "How fast you run for each heartbeat on steady outdoor runs. A rising line means you are getting more efficient.")
                        ])
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pf-eff-run-chart")
                        PFParagraph("Each dot is one steady run: speed per heartbeat. Higher is more efficient.")
                    }
                } else {
                    PFInsufficient(title: "Not enough steady outdoor runs yet",
                                   text: "\(run.recentRuns ?? 0) in the last 6 weeks and \(run.priorRuns ?? 0) in the 6 before."
                                       + ((run.treadmillRunsLeftOut ?? 0) > 0
                                          ? " \(run.treadmillRunsLeftOut ?? 0) treadmill runs are left out because their pace is a wrist estimate." : ""),
                                   identifier: "pf-eff-run-insufficient")
                }
                if let drift = run.decouplingPct {
                    PFInsightRow(label: "Pace-to-heart-rate drift", value: "\(PFNumber.trimmedOne(drift)) %",
                                 caption: run.decouplingVerdict.map { "\(PFFormat.capitalized($0)): under 5 % good, up to 8 % watch." })
                        .accessibilityIdentifier("pf-eff-run-drift")
                }
                if let rule = run.threshold { footnote(rule) }
            }
        }
        .containerIdentifier("pf-eff-running")
    }

    private var bikeCard: some View {
        let bike = efficiency.bike
        return PFCard(title: "Bike efficiency", icon: "bicycle", trailing: {
            PFChip(text: PFInsightVerdict.trendText(bike.verdict), color: PFInsightColor.color(for: PFInsightVerdict.trendTone(bike.verdict)))
                .accessibilityIdentifier("pf-eff-bike-verdict")
        }) {
            VStack(alignment: .leading, spacing: 12) {
                if bike.isReadable {
                    PFInsightRow(label: "Power at zone-2 heart rate", value: wattsText(bike.powerRecentW),
                                 caption: "Before: \(wattsText(bike.powerPriorW)). Change \(percent(bike.changePct)).")
                        .accessibilityIdentifier("pf-eff-bike-power")
                } else {
                    PFInsufficient(title: "Not enough zone-2 rides yet",
                                   text: "\(bike.recentRides ?? 0) zone-2 rides in the last 90 days and \(bike.priorRides ?? 0) in the 90 before.",
                                   identifier: "pf-eff-bike-insufficient")
                }
                if bike.series.filter({ $0.z2PowerW != nil }).count >= 2 {
                    LookTrendHost(metrics: [
                        PFLook.metric(id: "z2", title: "Power at zone 2", icon: "bicycle", unit: "W", decimals: 0, higherIsBetter: true,
                                      rows: bike.series.compactMap { p in p.z2PowerW.map { (date: p.date, value: $0) } },
                                      what: "The power you hold at a zone-2 heart rate on the bike. A rising line means more output for the same effort.")
                    ])
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pf-eff-bike-chart")
                }
                if let rule = bike.threshold { footnote(rule) }
            }
        }
        .containerIdentifier("pf-eff-bike")
    }

    private var zonesCard: some View {
        PFCard("Time in zones against 80/20", icon: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 12) {
                let splits = ["4", "12"].compactMap { key in efficiency.runZones[key].flatMap { split -> PFZoneSplit? in split.available ? split : nil } }
                if splits.isEmpty {
                    PFInsufficient(title: "No zone data yet",
                                   text: "No run with heart-rate zone time is on file for the last 4 or 12 weeks.",
                                   identifier: "pf-eff-zones-insufficient")
                }
                ForEach(splits, id: \.weeks) { split in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Last \(split.weeks) weeks")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 8)
                            if let grade = split.gradeText {
                                PFChip(text: grade, color: split.grade == "polarized" ? PFColor.positive
                                       : (split.grade == "too_much_mid" ? PFColor.warning : StrandPalette.accent))
                            }
                        }
                        PFZoneBar(split: split)
                        if let shares = split.shares {
                            Text("Easy \(Safe.int(shares.easy)) %, middle \(Safe.int(shares.mid)) %, hard \(Safe.int(shares.hard)) %"
                                 + (split.perWeekMin.map { " of about \($0) min a week" } ?? ""))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        if let move = split.midToMoveMinPerWeek, move > 0 {
                            PFParagraph("Moving about \(move) min a week from zone 3 into zone 2 would bring it to the pattern.")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pf-eff-zones-\(split.weeks)")
                }
                if let cap = efficiency.easyHrCap {
                    PFParagraph("Your easy heart-rate cap is \(cap) bpm.")
                }
                if let rule = efficiency.zonesThreshold { footnote(rule) }
            }
        }
        .containerIdentifier("pf-eff-zones")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PFZoneBar: View {
    let split: PFZoneSplit

    var body: some View {
        if let shares = split.shares {
            let total = max(shares.easy + shares.mid + shares.hard, 1)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        segment(PFColor.positive, shares.easy / total, width)
                        segment(PFColor.warning, shares.mid / total, width)
                        segment(PFColor.critical, shares.hard / total, width)
                    }
                    Rectangle()
                        .fill(StrandPalette.textPrimary)
                        .frame(width: 2, height: 20)
                        .offset(x: width * CGFloat(PFZoneSplit.easyTargetPct / 100) - 1)
                }
            }
            .frame(height: 20)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func segment(_ color: Color, _ fraction: Double, _ width: CGFloat) -> some View {
        if fraction > 0 {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: max(4, width * CGFloat(fraction) - 2), height: 12)
        }
    }
}

// MARK: - Sleep

struct PFSleepDetail: View {
    let item: PFInsightItem
    let sleep: PFSleepMetric

    private func hours(_ value: Double?) -> String {
        value.map { "\(PFNumber.trimmedOne($0)) h" } ?? "\u{2014}"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            consistencyCard
            PFWhatMovedSection(intelKey: "sleep_hours")
            debtCard
            targetCard
        }
    }

    private func spread(_ minutes: Double?) -> String? {
        minutes.map { "spread \(Safe.int($0)) min" }
    }

    private var consistencyCard: some View {
        PFCard("Bedtime and wake time", icon: "bed.double.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if sleep.hasSpread {
                    PFInsightRow(label: "Bedtime", value: sleep.bedtimeMean ?? "\u{2014}", caption: spread(sleep.bedtimeSdMin))
                        .accessibilityIdentifier("pf-sleep-bedtime")
                    Divider().overlay(StrandPalette.hairline)
                    PFInsightRow(label: "Wake time", value: sleep.wakeMedian ?? "\u{2014}", caption: spread(sleep.wakeSdMin))
                        .accessibilityIdentifier("pf-sleep-wake")
                    if let index = sleep.regularityIndex {
                        Divider().overlay(StrandPalette.hairline)
                        PFInsightRow(label: "Regularity", value: "\(Safe.int(index)) / 100",
                                     caption: "100 means the same hours every night; an approximation from your sleep windows.")
                    }
                } else {
                    PFInsufficient(title: "Too few nights to rate consistency",
                                   text: item.status.reason ?? "\(sleep.regularityNights ?? 0) nights have a sleep window; at least 14 are needed.",
                                   identifier: "pf-sleep-no-spread")
                }
                if sleep.series.contains(where: { $0.hours != nil }) {
                    LookTrendHost(metrics: [
                        PFLook.metric(id: "hours", title: "Hours of sleep", icon: "moon.zzz", unit: "h", decimals: 1, higherIsBetter: true,
                                      rows: sleep.series.compactMap { n in n.hours.map { (date: n.date, value: $0) } },
                                      what: "The hours you slept each night, from your sleep windows. Compare it with your need, not with a round eight.")
                    ])
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pf-sleep-hours-trend")
                }
                if sleep.hasNights {
                    PFSleepClockChart(nights: sleep.series, kind: .bedtime, targetWindow: sleep.targetWindow, targetClock: nil)
                        .frame(height: 150)
                        .accessibilityLabel("Bedtime each night with the target window")
                        .accessibilityIdentifier("pf-sleep-bed-chart")
                    PFSleepClockChart(nights: sleep.series, kind: .wake, targetWindow: [], targetClock: sleep.targetWake)
                        .frame(height: 150)
                        .accessibilityLabel("Wake time each night with the target")
                        .accessibilityIdentifier("pf-sleep-wake-chart")
                    HStack(spacing: 14) {
                        PFLegendDot(color: StrandPalette.accent, text: "Night")
                        PFLegendDot(color: PFColor.positive.opacity(0.5), text: "Target")
                        PFLegendDot(color: StrandPalette.textTertiary.opacity(0.5), text: "Travel night")
                    }
                }
            }
        }
        .containerIdentifier("pf-sleep-consistency")
    }

    private var debtCard: some View {
        PFCard("Sleep debt", icon: "moon.zzz.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if sleep.debt7 == nil && sleep.debt14 == nil {
                    PFInsufficient(title: "No debt figure yet",
                                   text: "No recent night has a recorded sleep duration to compare with your need.",
                                   identifier: "pf-sleep-no-debt")
                }
                if let debt = sleep.debt7 { debtRow("Last 7 nights", debt) }
                if let debt = sleep.debt14 {
                    Divider().overlay(StrandPalette.hairline)
                    debtRow("Last 14 nights", debt)
                }
                if let need = sleep.needH {
                    PFParagraph("Your need is \(PFNumber.trimmed(need)) h" + (sleep.needBasis.map { " (\($0))." } ?? "."))
                }
                if let extra = sleep.paybackExtraMinPerNight, extra > 0, let nights = sleep.paybackNights, nights > 0 {
                    PFParagraph("Repay it at +\(extra) min in bed a night for about \(nights) nights, not one long lie-in.")
                        .accessibilityIdentifier("pf-sleep-payback")
                }
            }
        }
        .containerIdentifier("pf-sleep-debt")
    }

    private func debtRow(_ title: String, _ debt: PFSleepDebt) -> some View {
        var caption: [String] = []
        if let avg = debt.avgH { caption.append("averaging \(hours(avg))") }
        if let short = debt.shortfallNights, let nights = debt.nights { caption.append("short on \(short) of \(nights) nights") }
        return PFInsightRow(label: title, value: hours(debt.debtH) + (debt.debtH == nil ? "" : " owed"),
                            caption: caption.isEmpty ? nil : caption.joined(separator: ", "))
            .accessibilityIdentifier("pf-sleep-debt-\(debt.days ?? 0)")
    }

    @ViewBuilder private var targetCard: some View {
        if sleep.targetBedtime != nil || sleep.targetWake != nil {
            PFCard("Target window", icon: "target") {
                VStack(alignment: .leading, spacing: 12) {
                    if sleep.targetWindow.count == 2 {
                        PFInsightRow(label: "Lights out between", value: "\(sleep.targetWindow[0]) to \(sleep.targetWindow[1])")
                            .accessibilityIdentifier("pf-sleep-target-window")
                    }
                    if let wake = sleep.targetWake { PFInsightRow(label: "Wake at", value: wake) }
                    if let inBed = sleep.timeInBedH { PFInsightRow(label: "Time in bed", value: hours(inBed)) }
                    if let shift = sleep.shiftMin, shift > 0 {
                        PFParagraph("That is \(shift) min earlier than your usual bedtime; move it 15 minutes every 3 days.")
                    }
                }
            }
            .containerIdentifier("pf-sleep-target")
        }
    }
}

/// One dot per night for bedtime (minutes after 18:00) or wake time (minutes after midnight), with the target.
private struct PFSleepClockChart: View {
    enum Kind { case bedtime, wake }

    let nights: [PFSleepWindow]
    let kind: Kind
    /// The bedtime window ("23:00", "23:30"), for the bedtime chart.
    let targetWindow: [String]
    /// The wake target ("06:45"), for the wake chart.
    let targetClock: String?

    private func value(_ night: PFSleepWindow) -> Double? { kind == .bedtime ? night.bedMin : night.wakeMin }

    private func clock(_ value: Double) -> String {
        kind == .bedtime ? PFSleepClock.clock(sinceEvening: value) : PFSleepClock.clock(minutesOfDay: value)
    }

    private var regular: [(date: Date, minutes: Double)] {
        nights.filter { !$0.isTravel }.compactMap { n in value(n).map { (date: PFFormat.date(n.date), minutes: $0) } }
    }

    private var travel: [(date: Date, minutes: Double)] {
        nights.filter { $0.isTravel }.compactMap { n in value(n).map { (date: PFFormat.date(n.date), minutes: $0) } }
    }

    /// The bedtime window as a band, for the bedtime chart.
    private var band: (low: Double, high: Double)? {
        guard kind == .bedtime, targetWindow.count == 2, let low = PFSleepClock.sinceEvening(targetWindow[0]),
              let high = PFSleepClock.sinceEvening(targetWindow[1]) else { return nil }
        return (min(low, high), max(low, high))
    }

    /// The wake target as a line, for the wake chart.
    private var line: Double? {
        kind == .wake ? PFSleepClock.minutes(of: targetClock).map { Double($0) } : nil
    }

    private var plotted: [(date: Date, minutes: Double)] { regular + travel }

    private var yDomain: ClosedRange<Double> {
        var all: [Double] = plotted.map { $0.minutes }
        if let band { all += [band.low, band.high] }
        if let line { all.append(line) }
        return ((all.min() ?? 0) - 20)...((all.max() ?? 60) + 20)
    }

    var body: some View {
        let first = plotted.map { $0.date }.min() ?? Date()
        let last = plotted.map { $0.date }.max() ?? Date()
        Chart {
            if let band {
                RectangleMark(xStart: .value("From", first), xEnd: .value("To", last),
                              yStart: .value("Target low", band.low), yEnd: .value("Target high", band.high))
                    .foregroundStyle(PFColor.positive.opacity(0.22))
            }
            if let line {
                RuleMark(y: .value("Target", line))
                    .foregroundStyle(PFColor.positive.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(Array(regular.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("Night", p.date), y: .value("Time", p.minutes))
                    .foregroundStyle(StrandPalette.accent)
                    .symbolSize(30)
            }
            ForEach(Array(travel.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("Night", p.date), y: .value("Time", p.minutes))
                    .foregroundStyle(StrandPalette.textTertiary.opacity(0.5))
                    .symbolSize(30)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(clock(minutes)).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }
}
