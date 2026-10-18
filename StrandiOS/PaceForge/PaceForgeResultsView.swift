import SwiftUI
import Charts
import StrandDesign

/// A completed session's results, like the PaceForge web activity detail: summary, heart-rate and pace
/// charts, zones, splits, effort, planned-versus-actual and the coach's review.
struct PFResultsSheet: View {
    let workout: PFWorkout
    let snapshot: PFSnapshot

    @EnvironmentObject private var model: PFModel
    @Environment(\.dismiss) private var dismiss
    @State private var results: PFSessionResults?

    private var activity: PFActivity? { workout.activityId.flatMap { snapshot.activities[$0] } }
    private var analysis: PFAnalysisRow? { workout.activityId.flatMap { snapshot.analyses[$0] } }
    private var trimp: Double? { workout.activityId.flatMap { snapshot.trimp[$0] } }
    private var rpe: Double? { workout.userRpe ?? workout.activityId.flatMap { snapshot.rpe[$0] } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFResultsHeader(workout: workout, activity: activity, weather: results?.detail?.weather)
                    if let activity { PFStatTiles(activity: activity) }
                    if let results {
                        content(results)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading session results")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(workout.name ?? "Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
        .task {
            if let id = workout.activityId { results = await model.results(for: id) } else { results = PFSessionResults() }
        }
    }

    @ViewBuilder private func content(_ results: PFSessionResults) -> some View {
        let detail = results.detail
        if let detail {
            PFHeartRateCard(samples: detail.samples, splits: detail.splits, avgHr: activity?.avgHr)
            if !detail.zones.isEmpty { PFZonesCard(zones: detail.zones) }
        } else {
            PFCard("Heart rate", icon: "heart.fill") {
                PFParagraph("Heart-rate detail for this session is not synced. PaceForge keeps it for recent sessions only.")
            }
        }
        let hrr = detail?.hrr1 ?? activity?.hrr1
        let garmin = detail?.hrrGarmin ?? activity?.hrrGarmin
        if hrr != nil || garmin != nil {
            PFHRR1Card(hrr: hrr ?? PFHRR1(kind: PFHRR1.notMeasurable), garmin: garmin, tipsGarminWait: true)
        }
        PFEffortCard(strain: analysis?.strain, band: analysis?.strainBand, trimp: trimp,
                     recovery: analysis?.recoveryReason)
        PFPlanVersusActual(workout: workout, analysis: analysis)
        if let detail {
            PFPaceCard(samples: detail.samples, splits: detail.splits)
            PFSplitsCard(splits: detail.splits)
        }
        if !workout.exercises.isEmpty {
            PFCard("Strength movements", icon: "dumbbell") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, e in PFExerciseRow(exercise: e) }
                }
            }
        }
        coachCard(results.analysis)
        if let rpe {
            PFCard("How hard it felt", icon: "gauge.with.dots.needle.67percent") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(PFFormat.trimmed(rpe))
                        .font(StrandFont.rounded(30))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("RPE of 10").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    if let target = workout.targetRpe {
                        Spacer(minLength: 8)
                        Text("planned \(PFFormat.trimmed(target))")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func coachCard(_ markdown: String?) -> some View {
        if let markdown {
            PFCard("Coach analysis", icon: "sparkles") {
                PFMarkdown(text: markdown)
            }
            .containerIdentifier("pf-coach-analysis")
        } else if let headline = analysis?.headline {
            PFCard("Coach analysis", icon: "sparkles") {
                Text(headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let note = workout.completionAnalysis {
            PFCard("Coach analysis", icon: "sparkles") { PFParagraph(note) }
        }
    }
}

// MARK: Header and summary

private struct PFResultsHeader: View {
    let workout: PFWorkout
    let activity: PFActivity?
    let weather: PFWeather?

    var body: some View {
        PFCard(activity?.name ?? workout.name ?? "Session", icon: "checkmark.circle.fill") {
            VStack(alignment: .leading, spacing: 4) {
                Text(whenLine)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                if !noteLine.isEmpty {
                    Text(noteLine)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if let heat = activity?.heat { heatRow(heat) }
            }
        }
    }

    /// How warm it was and what it cost the pace, from the server's heat rating.
    private func heatRow(_ heat: PFHeat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: heat.isHot ? "thermometer.sun" : "thermometer.medium")
                .font(.system(size: 13))
                .foregroundStyle(heat.isHot ? PFColor.warning : PFColor.sky)
            PFChip(text: heat.chipText, color: heat.isHot ? PFColor.warning : PFColor.sky)
                .accessibilityIdentifier("pf-heat-chip")
            if let humidity = heat.humidity {
                Text("humidity \(Safe.int(humidity)) %")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            PFInfoButton(id: PFExplainerID.heat)
        }
        .padding(.top, 4)
    }

    private var whenLine: String {
        guard let start = activity?.startTime else { return PFFormat.dayTitle(workout.date) }
        var line = PFFormat.dayTitle(start)
        if start.count >= 16 {
            line += " \u{00B7} " + String(start.dropFirst(11).prefix(5))
        }
        return line
    }

    private var noteLine: String {
        var bits: [String] = []
        if let activity { bits.append(PFSport.label(activity.type)) }
        if let temp = weather?.tempC {
            bits.append("\(Safe.int(temp))\u{00B0}" + (weather?.desc.map { " " + $0 } ?? ""))
        }
        return bits.joined(separator: " \u{00B7} ")
    }
}

enum PFSport {
    static func label(_ type: String?) -> String {
        let t = (type ?? "").lowercased()
        switch t {
        case "running": return "Run"
        case "treadmill_running": return "Treadmill run"
        case "trail_running": return "Trail run"
        case "road_biking": return "Road ride"
        case "indoor_cycling": return "Indoor ride"
        case "cycling": return "Ride"
        case "indoor_cardio": return "Cardio / HYROX"
        case "strength_training": return "Strength"
        case "": return "Activity"
        default: return PFFormat.capitalized(PFFormat.words(t))
        }
    }
}

private struct PFStatTile: Identifiable {
    let label: String
    let value: String
    let unit: String?
    var id: String { label }
}

private struct PFStatTiles: View {
    let activity: PFActivity

    private var tiles: [PFStatTile] {
        let a = activity
        func whole(_ v: Double?) -> String? { v.map { String(Safe.int($0)) } }
        func positive(_ v: Double?) -> Double? { (v ?? 0) > 0 ? v : nil }

        let km = positive(a.distanceM).map { $0 / 1000 }
        var pace = a.avgPaceSecPerKm
        if pace == nil, a.isRun, let km, let dur = a.durationS { pace = dur / km }

        var all: [String: PFStatTile] = [:]
        func put(_ key: String, _ label: String, _ value: String?, _ unit: String? = nil) {
            if let value { all[key] = PFStatTile(label: label, value: value, unit: unit) }
        }
        put("time", "Time", positive(a.durationS).map { PFFormat.clock($0) })
        put("pace", "Pace", positive(pace).map { PFFormat.pace($0) }, "/km")
        put("avgHr", "Avg HR", whole(positive(a.avgHr)), "bpm")
        put("maxHr", "Max HR", whole(positive(a.maxHr)), "bpm")
        put("dist", "Distance", km.map { String(format: "%.2f", $0) }, "km")
        put("ate", "Aerobic TE", positive(a.teAerobic).map { PFFormat.oneDecimal($0) })
        put("ane", "Anaerobic TE", positive(a.teAnaerobic).map { PFFormat.oneDecimal($0) })
        put("kcal", "Calories", whole(positive(a.calories)), "kcal")
        put("cad", "Cadence", whole(positive(a.cadence)), a.isBike ? "rpm" : "spm")
        put("stride", "Stride", positive(a.strideCm).map { String(format: "%.2f", $0 / 100) }, "m")
        put("gct", "Ground contact", whole(positive(a.groundContactMs)), "ms")
        put("elev", "Elevation", whole(positive(a.elevationM)), "m")
        put("power", "Avg power", whole(positive(a.avgPower)), "W")

        let order: [String]
        if a.isRun {
            order = ["time", "pace", "avgHr", "maxHr", "dist", "ate", "kcal", "cad", "stride", "gct", "ane", "elev"]
        } else if a.isBike {
            order = ["time", "power", "avgHr", "dist", "kcal", "maxHr", "ate", "elev"]
        } else {
            order = ["time", "avgHr", "maxHr", "kcal", "ate", "ane", "dist", "pace", "elev"]
        }
        return order.compactMap { all[$0] }
    }

    var body: some View {
        let items = tiles
        if !items.isEmpty {
            PFCard("Summary", icon: "list.bullet.rectangle") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                          alignment: .leading, spacing: 16) {
                    ForEach(items) { tile in
                        PFFigure(value: tile.value, unit: tile.unit, label: tile.label)
                    }
                }
            }
            .containerIdentifier("pf-results-summary")
        }
    }
}

// MARK: Charts

private struct PFHeartRateCard: View {
    let samples: [PFSample]
    let splits: [PFSplit]
    let avgHr: Double?

    private var points: [(minutes: Double, hr: Double)] {
        samples.compactMap { s in s.hr.map { (minutes: s.t / 60, hr: $0) } }
    }

    private var splitPoints: [(km: Int, hr: Double)] {
        splits.compactMap { s in s.avgHr.map { (km: s.n, hr: $0) } }
    }

    var body: some View {
        PFCard(title: "Heart rate", icon: "heart.fill", trailing: {
            if let avgHr {
                Text("avg \(Safe.int(avgHr))")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }) {
            if points.count >= 3 {
                let values = points.map { $0.hr }
                let lo = (values.min() ?? 60) - 6, hi = (values.max() ?? 180) + 6
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Minutes", p.minutes), y: .value("Heart rate", p.hr))
                            .foregroundStyle(PFColor.critical)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let avgHr {
                        RuleMark(y: .value("Average", avgHr))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(StrandPalette.hairline)
                        AxisValueLabel {
                            if let m = value.as(Double.self) { Text("\(Safe.int(m, .towardZero)) min") }
                        }
                        .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(StrandPalette.hairline)
                        AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .frame(height: 180)
                .accessibilityIdentifier("pf-hr-chart")
            } else if splitPoints.count >= 2 {
                let values = splitPoints.map { $0.hr }
                Chart {
                    ForEach(Array(splitPoints.enumerated()), id: \.offset) { _, p in
                        BarMark(x: .value("Kilometre", p.km), y: .value("Heart rate", p.hr))
                            .foregroundStyle(PFColor.critical)
                    }
                }
                .chartYScale(domain: ((values.min() ?? 60) - 10)...((values.max() ?? 180) + 6))
                .frame(height: 150)
                .accessibilityIdentifier("pf-hr-chart")
            } else {
                PFParagraph("No heart-rate samples were recorded over this session.")
            }
        }
    }
}

private struct PFPaceCard: View {
    let samples: [PFSample]
    let splits: [PFSplit]

    // Pace is plotted negated so a faster pace draws higher; the axis labels flip it back.
    private var points: [(minutes: Double, pace: Double)] {
        samples.compactMap { s in
            guard let pace = s.pace, pace > 120, pace < 900 else { return nil }
            return (minutes: s.t / 60, pace: -pace)
        }
    }

    private var cadence: [(minutes: Double, cad: Double)] {
        samples.compactMap { s in
            guard let cad = s.cad, cad > 0 else { return nil }
            return (minutes: s.t / 60, cad: cad)
        }
    }

    var body: some View {
        if points.count >= 3 {
            PFCard("Pace over time", icon: "speedometer") {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Minutes", p.minutes), y: .value("Pace", p.pace))
                            .foregroundStyle(PFColor.sky)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(StrandPalette.hairline)
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(PFFormat.pace(-v)) }
                        }
                        .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(StrandPalette.hairline)
                        AxisValueLabel {
                            if let m = value.as(Double.self) { Text("\(Safe.int(m, .towardZero)) min") }
                        }
                        .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .frame(height: 160)
                .accessibilityIdentifier("pf-pace-chart")
            }
            if cadence.count >= 3 {
                PFCard("Cadence over time", icon: "figure.run") {
                    Chart {
                        ForEach(Array(cadence.enumerated()), id: \.offset) { _, p in
                            LineMark(x: .value("Minutes", p.minutes), y: .value("Cadence", p.cad))
                                .foregroundStyle(PFColor.violet)
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    .chartYScale(domain: 120...200)
                    .frame(height: 130)
                }
            }
        }
    }
}

private struct PFZonesCard: View {
    let zones: [PFZone]

    private static let colors: [Color] = [
        Color(hex: "#3FB6E0"), Color(hex: "#22C55E"), Color(hex: "#EAB308"), Color(hex: "#F97316"), Color(hex: "#EF4444"),
    ]
    private static let names = ["Recovery", "Easy", "Aerobic", "Threshold", "Max"]

    private var total: Double { zones.reduce(0) { $0 + $1.secs } }

    private func secs(_ zone: Int) -> Double { zones.first { $0.zone == zone }?.secs ?? 0 }

    var body: some View {
        if total > 0 {
            PFCard(title: "Heart-rate zones", icon: "chart.bar.fill", trailing: {
                Text("\(Safe.int((total / 60))) min in zone")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { zone in
                                if secs(zone) > 0 {
                                    Rectangle()
                                        .fill(Self.colors[zone - 1])
                                        .frame(width: max(3, geo.size.width * CGFloat(secs(zone) / total)))
                                }
                            }
                        }
                    }
                    .frame(height: 22)
                    .clipShape(Capsule())

                    HStack(alignment: .top, spacing: 4) {
                        ForEach(1...5, id: \.self) { zone in
                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    Circle().fill(Self.colors[zone - 1]).frame(width: 7, height: 7)
                                    Text("Z\(zone)").font(StrandFont.overline).foregroundStyle(StrandPalette.textTertiary)
                                }
                                Text("\(Safe.int((secs(zone) / total * 100)))%")
                                    .font(StrandFont.subhead.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(minutes(secs(zone)))
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                Text(Self.names[zone - 1])
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .containerIdentifier("pf-zones")
        }
    }

    private func minutes(_ seconds: Double) -> String {
        if seconds >= 30 { return "\(Safe.int((seconds / 60))) m" }
        return seconds > 0 ? "<1 m" : "0 m"
    }
}

// MARK: Effort, plan, splits

private struct PFEffortCard: View {
    let strain: Double?
    let band: String?
    let trimp: Double?
    let recovery: String?

    var body: some View {
        PFCard("Effort", icon: "flame.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if let strain {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(PFFormat.oneDecimal(strain))
                            .font(StrandFont.rounded(30))
                            .foregroundStyle(StrandPalette.effortColor)
                        Text("of 21").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        if let band { PFChip(text: band, color: StrandPalette.effortColor) }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(StrandPalette.surfaceInset)
                            Capsule()
                                .fill(StrandPalette.effortColor)
                                .frame(width: max(8, geo.size.width * CGFloat(min(max(strain / 21, 0), 1))))
                        }
                    }
                    .frame(height: 8)
                } else {
                    PFParagraph("Strain is not scored for this session yet. It appears once the coach has analysed it.")
                }
                if let trimp {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("TRIMP").font(StrandFont.overline).foregroundStyle(StrandPalette.textTertiary)
                        Text(String(Safe.int(trimp)))
                            .font(StrandFont.rounded(18))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("training impulse from heart rate")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if let recovery { PFParagraph(PFFormat.capitalized(recovery) + ".") }
            }
        }
        .containerIdentifier("pf-effort")
    }
}

private struct PFPlanVersusActual: View {
    let workout: PFWorkout
    let analysis: PFAnalysisRow?

    var body: some View {
        let hasPlan = workout.compliance != nil || analysis?.plannedKm != nil || analysis?.plannedMin != nil
        let hasTypical = analysis?.vsTypicalPercentile != nil
        if hasPlan || hasTypical {
            PFCard("Planned versus actual", icon: "checklist") {
                VStack(alignment: .leading, spacing: 12) {
                    if let name = workout.name {
                        Text("Planned: \(name)" + (workout.kind.map { " (\(PFFormat.words($0)))" } ?? ""))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let compliance = workout.compliance { PFComplianceView(compliance: compliance) }
                    if let analysis, analysis.plannedKm != nil || analysis.plannedMin != nil {
                        Text(planLine(analysis))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let analysis, let percentile = analysis.vsTypicalPercentile {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(ordinal(Safe.int(percentile)))")
                                .font(StrandFont.rounded(24))
                                .foregroundStyle(PFColor.sky)
                            Text("vs typical " + (analysis.vsTypicalLabel ?? ""))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let reason = analysis.vsTypicalReason {
                            Text(PFFormat.capitalized(reason))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            }
            .containerIdentifier("pf-plan-vs-actual")
        }
    }

    private func planLine(_ a: PFAnalysisRow) -> String {
        let planned = a.plannedKm.map { "\(PFFormat.trimmed($0)) km" } ?? a.plannedMin.map { "\(PFFormat.trimmed($0)) min" } ?? "\u{2014}"
        let actual = a.actualKm.map { "\(PFFormat.trimmed($0)) km" } ?? a.actualMin.map { "\(PFFormat.trimmed($0)) min" } ?? "\u{2014}"
        return "Planned \(planned), did \(actual)"
    }

    private func ordinal(_ n: Int) -> String {
        let tail = n % 100
        if (11...13).contains(tail) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}

private struct PFSplitsCard: View {
    let splits: [PFSplit]

    private var runSplits: [PFSplit] { splits.filter { $0.paceSec != nil } }

    var body: some View {
        if runSplits.count >= 2 {
            PFCard("Splits", icon: "ruler") {
                VStack(spacing: 8) {
                    row("#", "km", "Pace", "HR", "Elev", header: true)
                    ForEach(Array(splits.enumerated()), id: \.offset) { _, s in
                        row(String(s.n),
                            s.distanceM.map { String(format: "%.2f", $0 / 1000) } ?? "\u{2014}",
                            s.paceSec.map { PFFormat.pace($0) } ?? "\u{2014}",
                            s.avgHr.map { String(Safe.int($0)) } ?? "\u{2014}",
                            s.elevGain.map { "\(Safe.int($0)) m" } ?? "\u{2014}",
                            header: false)
                    }
                }
            }
            .containerIdentifier("pf-splits")
        }
    }

    private func row(_ n: String, _ km: String, _ pace: String, _ hr: String, _ elev: String, header: Bool) -> some View {
        HStack(spacing: 0) {
            cell(n, width: 30, header: header)
            cell(km, width: 56, header: header)
            cell(pace, width: 66, header: header)
            cell(hr, width: 50, header: header)
            cell(elev, width: nil, header: header)
        }
    }

    @ViewBuilder private func cell(_ text: String, width: CGFloat?, header: Bool) -> some View {
        let label = Text(text)
            .font(header ? StrandFont.overline : StrandFont.subhead)
            .monospacedDigit()
            .foregroundStyle(header ? StrandPalette.textTertiary : StrandPalette.textPrimary)
            .lineLimit(1)
        if let width {
            label.frame(width: width, alignment: .leading)
        } else {
            label.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
