import SwiftUI
import Charts
import StrandDesign

/// PaceForge "Body": the Hume scale page the web app shows, trend and score first, then the
/// composition bands, mass breakdown, segmental analysis, goals and every reading.
struct PFBodyView: View {
    let snapshot: PFSnapshot

    @State private var metric = "weight_kg"

    var body: some View {
        if let doc = snapshot.body {
            VStack(alignment: .leading, spacing: 16) {
                if let progress = snapshot.bodyProgress { PFProgressCard(progress: progress) }
                PFTrendCard(doc: doc, progress: snapshot.bodyProgress, metric: $metric)
                if let muscle = snapshot.muscle { PFMuscleCheckCard(check: muscle) }
                PFTapeCard(tape: snapshot.tape ?? PFTape())
                PFScoreCard(doc: doc)
                if !doc.assessment.isEmpty { compositionCard(doc) }
                massCard(doc)
                if !doc.segments.isEmpty { PFSegmentalCard(doc: doc) }
                goalsCard(doc)
                readingsCard(doc)
            }
        } else {
            PFCard("No scale readings yet", icon: "scalemass") {
                PFParagraph("Step on the Hume Body Pod. The next reading lands here automatically with weight, impedance and the full body-composition breakdown.")
            }
        }
    }

    // MARK: Composition

    private func compositionCard(_ doc: PFBodyDoc) -> some View {
        PFCard("Composition", icon: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(doc.assessment) { PFRangeRow(range: $0) }
                Text("Bands are published reference ranges. Body Score is PaceForge's own composite of how the reading sits in those bands, not a clinical measure.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .containerIdentifier("pf-body-composition")
    }

    // MARK: Mass breakdown

    private static let massOrder = [
        "weight_kg", "bmi", "body_fat_pct", "fat_mass_kg", "subcutaneous_fat_kg", "ffm_kg", "lean_mass_kg",
        "muscle_mass_kg", "skeletal_muscle_kg", "bone_mass_kg", "organ_mass_kg", "total_body_water_kg",
        "total_body_water_pct", "ecw_kg", "icw_kg", "body_cell_mass_kg", "visceral_fat_index", "metabolic_age",
        "bmr_kcal", "whole_body_impedance_ohm", "android_gynoid_ratio",
    ]

    private func massCard(_ doc: PFBodyDoc) -> some View {
        let keys = Self.massOrder.filter { doc.latest[$0] != nil }
        return PFCard(title: "Body breakdown", icon: "scalemass", trailing: {
            Text(PFFormat.dayTitle(doc.date)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 16) {
                ForEach(keys, id: \.self) { key in
                    let info = doc.metrics[key]
                    PFFigure(value: PFBodyFormat.number(doc.latest[key] ?? 0, dp: info?.dp ?? 1),
                             unit: (info?.unit.isEmpty ?? true) ? nil : info?.unit,
                             label: info?.label ?? key)
                }
            }
        }
        .containerIdentifier("pf-body-breakdown")
    }

    // MARK: Goals

    @ViewBuilder private func goalsCard(_ doc: PFBodyDoc) -> some View {
        PFCard("Goals", icon: "target") {
            if doc.goals.isEmpty {
                PFParagraph("No goals yet. Set targets for weight, body fat, muscle and more in PaceForge, and progress is tracked against your latest reading.")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(doc.goals) { PFGoalRow(goal: $0) }
                }
            }
        }
    }

    // MARK: Readings

    @ViewBuilder private func readingsCard(_ doc: PFBodyDoc) -> some View {
        let readings = Array(doc.series.reversed())
        if !readings.isEmpty {
            PFCard("Readings \u{00B7} \(readings.count)", icon: "list.bullet") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(readings) { reading in
                        HStack(alignment: .top, spacing: 12) {
                            Text(PFFormat.dayTitle(reading.date))
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .frame(width: 86, alignment: .leading)
                            Text(readingBits(reading, doc))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)
                        Divider().overlay(StrandPalette.hairline)
                    }
                }
            }
            .containerIdentifier("pf-body-readings")
        }
    }

    private func readingBits(_ reading: PFBodyReading, _ doc: PFBodyDoc) -> String {
        ["weight_kg", "body_fat_pct", "muscle_mass_kg", "visceral_fat_index"].compactMap { key in
            guard let value = reading.values[key] else { return nil }
            let info = doc.metrics[key]
            return "\(info?.label ?? key) \(PFBodyFormat.number(value, dp: info?.dp ?? 1))"
        }.joined(separator: " \u{00B7} ")
    }
}

enum PFBodyFormat {
    static func number(_ value: Double, dp: Int) -> String { String(format: "%.\(max(0, dp))f", value) }

    static func value(_ key: String, _ value: Double, _ doc: PFBodyDoc) -> String {
        let info = doc.metrics[key]
        let text = number(value, dp: info?.dp ?? 1)
        guard let unit = info?.unit, !unit.isEmpty else { return text }
        return text + " " + unit
    }
}

// MARK: Trend

private struct PFTrendCard: View {
    let doc: PFBodyDoc
    let progress: PFBodyProgress?
    @Binding var metric: String
    @State private var lookRange = LookRange.month
    @State private var lookEnd = Calendar.current.startOfDay(for: Date())

    private static let metricKeys = [
        "weight_kg", "body_fat_pct", "muscle_mass_kg", "total_body_water_pct", "visceral_fat_index",
        "bmi", "metabolic_age", "bmr_kcal",
    ]

    private var options: [String] { Self.metricKeys.filter { doc.metrics[$0] != nil } }

    private static func icon(_ key: String) -> String {
        switch key {
        case "body_fat_pct": return "percent"
        case "muscle_mass_kg": return "figure.strengthtraining.traditional"
        case "total_body_water_pct": return "drop"
        case "bmi", "visceral_fat_index": return "figure.stand"
        case "metabolic_age", "bmr_kcal": return "flame"
        default: return "scalemass"
        }
    }

    /// Every metric the scale reports, as a look trend; the server says which direction is good for each.
    private var lookMetrics: [LookTrendMetric] {
        options.map { key in
            let info = doc.metrics[key]
            let rows = doc.series.compactMap { r in r.values[key].map { (date: r.date, value: $0) } }
            let better: Bool? = info?.good == "up" ? true : (info?.good == "down" ? false : nil)
            return PFLook.metric(id: key, title: info?.label ?? key, icon: Self.icon(key), unit: info?.unit ?? "",
                                 decimals: info?.dp ?? 1, higherIsBetter: better, rows: rows)
        }
    }

    var body: some View {
        let info = doc.metrics[metric]
        let goal = doc.goals.first { $0.metric == metric }
        PFCard(title: "Trend", icon: "chart.line.uptrend.xyaxis",
               info: metric == "body_fat_pct" ? PFExplainerID.bodyFatTrend : PFExplainerID.bodyWeightTrend, trailing: {
            Text("Synced \(PFFormat.shortDate(doc.date))")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info?.label ?? "").strandOverline()
                        Text(currentText).font(StrandFont.rounded(26)).foregroundStyle(StrandPalette.textPrimary)
                    }
                    if let goal {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Goal").strandOverline()
                            Text(PFBodyFormat.value(metric, goal.target, doc))
                                .font(StrandFont.rounded(26))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                if lookMetrics.isEmpty {
                    Text("Two or more readings are needed for a trend. Keep stepping on the scale.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    LookTrendView(metrics: lookMetrics, metricID: $metric, range: $lookRange, endDate: $lookEnd,
                                  today: Calendar.current.startOfDay(for: Date()),
                                  footer: { AnyView(PFWhatMovedSection(metricID: $0.id)) })
                        .padding(.horizontal, -16)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pf-body-trend-chart")
                }
                noiseLegend
                deltaRow
            }
        }
        .containerIdentifier("pf-body-trend")
    }

    private var currentText: String {
        guard let last = doc.series.last(where: { $0.values[metric] != nil }), let v = last.values[metric] else {
            return "\u{2014}"
        }
        return PFBodyFormat.value(metric, v, doc)
    }

    /// The scale's day-to-day noise around the current value, for the metrics the server measures it for.
    private var noiseBand: (low: Double, high: Double)? {
        guard let progress else { return nil }
        let half: Double?
        switch metric {
        case "weight_kg": half = progress.noiseWeightKg
        case "body_fat_pct": half = progress.noiseBodyFatPct
        default: half = nil
        }
        let goalCurrent = progress.goals.first(where: { $0.metric == metric })?.current7d
        guard let half, let centre = goalCurrent ?? doc.series.last(where: { $0.values[metric] != nil })?.values[metric] else {
            return nil
        }
        return (centre - half, centre + half)
    }

    /// Names the shaded band, with its "how it works" button.
    @ViewBuilder private var noiseLegend: some View {
        if noiseBand != nil, lookMetrics.contains(where: { $0.id == metric }) {
            HStack(spacing: 4) {
                Text("Shaded band = the scale's usual morning-to-morning noise")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                PFInfoButton(id: PFExplainerID.bodyNoiseBand)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var deltaRow: some View {
        if let delta = doc.deltas[metric], let info = doc.metrics[metric] {
            HStack(spacing: 8) {
                chip(delta.d7, "7d", info)
                chip(delta.d30, "30d", info)
                chip(delta.d90, "90d", info)
            }
        }
    }

    @ViewBuilder private func chip(_ value: Double?, _ label: String, _ info: PFBodyMetric) -> some View {
        if let value {
            let improving = (info.good == "up" && value > 0) || (info.good == "down" && value < 0)
            let color: Color = abs(value) < 1e-9 ? StrandPalette.textTertiary : (improving ? PFColor.positive : PFColor.critical)
            PFChip(text: (value > 0 ? "+" : "") + PFBodyFormat.number(value, dp: info.dp) + " / " + label, color: color)
        }
    }
}

// MARK: Score

private struct PFScoreCard: View {
    let doc: PFBodyDoc

    private static let spectrum: [Color] = [
        Color(hex: "#E5484D"), Color(hex: "#F5A524"), Color(hex: "#3FB950"),
        Color(hex: "#2BB6A3"), Color(hex: "#3B82F6"), Color(hex: "#8B5CF6"),
    ]

    var body: some View {
        PFCard("Overview", icon: "heart.text.square") {
            VStack(spacing: 16) {
                gauge
                Divider().overlay(StrandPalette.hairline)
                HStack(alignment: .top, spacing: 8) {
                    stat("Age", doc.age.map { String($0) }, "yrs")
                    stat("Metabolic age", doc.latest["metabolic_age"].map { String(Safe.int($0)) }, "yrs")
                    stat("Height", doc.heightCm.map { PFFormat.trimmed($0) }, "cm")
                }
            }
        }
        .containerIdentifier("pf-body-score")
    }

    private var gauge: some View {
        let score = doc.score ?? 0
        let angle = Double.pi * (1 - min(max(score, 0), 100) / 100)
        let radius = 103.0
        return ZStack(alignment: .top) {
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 206, height: 206)
                .frame(width: 220, height: 118, alignment: .top)
                .padding(.top, 7)
            if doc.score != nil {
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(StrandPalette.surfaceBase, lineWidth: 3))
                    .frame(width: 20, height: 20)
                    .position(x: 110 + radius * cos(angle), y: 110 - radius * sin(angle))
                    .frame(width: 220, height: 124)
            }
            VStack(spacing: 2) {
                Text("Body score").strandOverline()
                Text(doc.score.map { String(Safe.int($0)) } ?? "\u{2014}")
                    .font(StrandFont.rounded(46))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let band = doc.band { PFChip(text: band, color: PFColor.positive) }
            }
            .padding(.top, 52)
        }
        .frame(width: 220, height: 130)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String?, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label).strandOverline()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "\u{2014}").font(StrandFont.rounded(22)).foregroundStyle(StrandPalette.textPrimary)
                if value != nil { Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Composition range rows

private struct PFRangeRow: View {
    let range: PFBodyRange

    private static let ends: [String: (String, String)] = [
        "body_fat_pct": ("Low", "High"), "visceral_fat_index": ("Low", "High"),
        "total_body_water_pct": ("Low", "High"), "bmi": ("Under", "Over"),
        "metabolic_age": ("Younger", "Older"), "ffmi": ("Low", "High"),
    ]

    private var statusColor: Color {
        switch range.status {
        case "standard": return PFColor.positive
        case "low": return PFColor.sky
        case "high": return PFColor.warning
        default: return StrandPalette.textTertiary
        }
    }

    private var statusText: String {
        switch range.status {
        case "standard": return "Standard"
        case "low": return "Low"
        case "high": return "High"
        default: return "\u{2014}"
        }
    }

    var body: some View {
        let end = Self.ends[range.key] ?? ("Low", "High")
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(range.label)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 8)
                PFChip(text: statusText, color: statusColor)
            }
            Text(PFBodyFormat.number(range.value, dp: range.dp) + (range.unit.isEmpty ? "" : " " + range.unit))
                .font(StrandFont.rounded(24))
                .foregroundStyle(StrandPalette.textPrimary)
            GeometryReader { geo in
                let span = max(range.scaleHi - range.scaleLo, 0.0001)
                let lo = min(max((range.low - range.scaleLo) / span, 0), 1)
                let hi = min(max((range.high - range.scaleLo) / span, 0), 1)
                let pos = min(max(range.pos, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    Capsule()
                        .fill(PFColor.positive.opacity(0.55))
                        .frame(width: max(6, geo.size.width * CGFloat(hi - lo)))
                        .offset(x: geo.size.width * CGFloat(lo))
                    Capsule()
                        .fill(StrandPalette.textPrimary)
                        .frame(width: 3, height: 16)
                        .offset(x: max(0, geo.size.width * CGFloat(pos) - 1))
                }
            }
            .frame(height: 8)
            HStack {
                Text(end.0)
                Spacer()
                Text(end.1)
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
        }
    }
}

// MARK: Segmental

private struct PFSegmentalCard: View {
    let doc: PFBodyDoc

    /// The healthy fat band comes from the body-fat assessment row, as on the web.
    private var band: (lo: Double, hi: Double) {
        if let fat = doc.assessment.first(where: { $0.key == "body_fat_pct" }) { return (fat.low, fat.high) }
        return (10, 25)
    }

    private func status(_ seg: PFBodySegment) -> String {
        guard let p = seg.fatPct else { return "none" }
        return p < band.lo ? "low" : (p > band.hi ? "high" : "standard")
    }

    private func tint(_ seg: PFBodySegment?) -> Color {
        guard let seg else { return StrandPalette.surfaceInset }
        switch status(seg) {
        case "low": return PFColor.sky
        case "high": return PFColor.warning
        case "standard": return PFColor.positive
        default: return StrandPalette.surfaceInset
        }
    }

    private func segment(_ key: String) -> PFBodySegment? { doc.segments.first { $0.key == key } }

    private func estimateNote(_ meta: PFSegmentalMeta) -> String {
        var text = "Left and right are our estimate."
        if let note = meta.note {
            text += " " + note
        } else if let method = meta.method {
            text += " Method: " + method + "."
        }
        return text
    }

    /// The four limbs are left or right; the server says whether that split is an estimate. No label when
    /// it says it is not, or says nothing.
    private func isEstimate(_ key: String) -> Bool {
        key != "trunk" && doc.segmentalMeta?.estimate == true
    }

    var body: some View {
        PFCard("Segmental analysis", icon: "figure.arms.open", info: PFExplainerID.bodyEstimates) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 12) {
                        card("right_arm")
                        card("right_leg")
                    }
                    figure
                    VStack(spacing: 12) {
                        card("left_arm")
                        card("left_leg")
                    }
                }
                HStack {
                    Spacer()
                    card("trunk").frame(maxWidth: 190)
                    Spacer()
                }
                Text("Segmental fat % from the four-pad impedance reading"
                     + (doc.latest["whole_body_impedance_ohm"].map { ". Whole-body impedance \(String(format: "%.1f", $0)) \u{03A9}." } ?? "."))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = doc.segmentalMeta, meta.estimate {
                    Text(estimateNote(meta))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-body-estimate-note")
                }
            }
        }
        .containerIdentifier("pf-body-segmental")
    }

    @ViewBuilder private func card(_ key: String) -> some View {
        if let seg = segment(key) {
            VStack(alignment: .leading, spacing: 3) {
                Text(seg.name).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(seg.fatPct.map { PFFormat.oneDecimal($0) } ?? "\u{2014}")
                        .font(StrandFont.rounded(20))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("% fat").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                if let muscle = seg.muscleKg {
                    Text("Muscle \(PFFormat.oneDecimal(muscle)) kg")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                PFChip(text: status(seg) == "none" ? "\u{2014}" : PFFormat.capitalized(status(seg)), color: tint(seg))
                if isEstimate(key) {
                    PFChip(text: "Estimate", color: StrandPalette.textTertiary)
                        .accessibilityIdentifier("pf-body-estimate-\(key)")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
        }
    }

    private var figure: some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(StrandPalette.surfaceInset).frame(width: 26, height: 26).offset(x: 25, y: 0)
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint(segment("trunk")))
                .frame(width: 40, height: 80).offset(x: 18, y: 32)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint(segment("right_arm")))
                .frame(width: 13, height: 72).offset(x: 1, y: 34)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint(segment("left_arm")))
                .frame(width: 13, height: 72).offset(x: 62, y: 34)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint(segment("right_leg")))
                .frame(width: 16, height: 100).offset(x: 19, y: 118)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint(segment("left_leg")))
                .frame(width: 16, height: 100).offset(x: 41, y: 118)
        }
        .frame(width: 76, height: 220, alignment: .topLeading)
    }
}

// MARK: Goals

private struct PFGoalRow: View {
    let goal: PFBodyGoal

    private var color: Color { goal.reached ? PFColor.positive : PFColor.sky }
    private var progress: Double { min(max(goal.progress ?? 0, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.label)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text("\(format(goal.current)) \u{2192} ")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                + Text("\(format(goal.target)) \(goal.unit)")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    Capsule()
                        .fill(color)
                        .frame(width: max(8, proxy.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 8)
            HStack {
                Text(goal.reached ? "Target reached"
                     : (goal.remaining.map { "\(format(abs($0))) \(goal.unit) to go" } ?? ""))
                Spacer()
                Text(goal.progress.map { "\(Safe.int(($0 * 100)))%" } ?? "")
                    + Text(goal.targetDate.map { " \u{00B7} by \($0)" } ?? "")
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func format(_ v: Double) -> String { String(format: "%.\(max(0, goal.dp))f", v) }
}
