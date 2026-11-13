import SwiftUI
import Charts
import StrandDesign

/// A completed session's results, like the PaceForge web activity detail: summary, heart-rate and pace
/// charts, zones, splits, effort, planned-versus-actual and the coach's review.
struct PFResultsSheet: View {
    let workout: PFWorkout
    let snapshot: PFSnapshot
    var onAskCoach: ((String) -> Void)? = nil

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
        // A race recording (the server stamps `race` on its detail) gets the race layout; the run blocks below are gated on it.
        let race = detail?.race
        if let race {
            PFRaceResultCard(race: race)
            PFRaceSegmentsCard(race: race)
        }
        coachCard(results.analysis)
        if let onAskCoach, let sessionID = workout.coachSessionID {
            Button {
                dismiss()
                onAskCoach(sessionID)
            } label: {
                Label("Ask Coach about this workout", systemImage: "bubble.left.and.bubble.right")
                    .font(StrandFont.subhead.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(StrandPalette.accent)
            .accessibilityIdentifier("pf-ask-coach-workout")
        }
        if let activity { PFStatTiles(activity: activity) }
        if let detail {
            PFHeartRateCard(samples: detail.samples, splits: race == nil ? detail.splits : [], avgHr: activity?.avgHr, hrNote: race?.hrNote)
            if race == nil, !detail.zones.isEmpty { PFZonesCard(zones: detail.zones) }
            if race == nil, let split = detail.ltSplit { PFLtSplitCard(split: split) }
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
                     recovery: analysis?.recoveryReason, rank: detail?.effortRank)
        if race == nil, let explainer = detail?.runExplainer, workout.briefing == nil { PFRunExplainerCard(explainer: explainer) }
        if race == nil { PFPlanVersusActual(workout: workout, analysis: analysis) }
        if race == nil, let detail {
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
        PFResultsRating(workout: workout, rpe: rpe, photoSummary: workout.activityId.flatMap { snapshot.photoSummaries[$0] })
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
        } else if let status = workout.activityId.flatMap({ snapshot.analysisStatuses[$0] }) {
            PFCard(String(localized: "Coach review"), icon: "sparkles") {
                Text(status.reason ?? "Coach review is not available yet.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            PFCard(String(localized: "Coach review"), icon: "sparkles") {
                Text("No written Coach review is available for this session yet. The workout data below shows what was recorded.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                .font(StrandFont.scaled(13))
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
        put("avgHr", a.hasCorrectedHr ? String(localized: "Avg HR (corrected)") : "Avg HR", whole(positive(a.avgHr)), "bpm")
        put("maxHr", a.hasCorrectedHr ? String(localized: "Max HR (corrected)") : "Max HR", whole(positive(a.maxHr)), "bpm")
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
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                              alignment: .leading, spacing: 16) {
                        ForEach(items) { tile in
                            PFFigure(value: tile.value, unit: tile.unit, label: tile.label)
                        }
                    }
                    // The corrected figures lead; what the watch recorded stays beside them, never replaced.
                    if let recorded = activity.recordedHr {
                        Text("Recorded by the watch: avg \(recorded.avg), max \(recorded.peak) bpm")
                            .font(LookFont.text(12, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pf-results-recorded-hr")
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
    var hrNote: String? = nil

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
            if let hrNote { PFParagraph(hrNote) }
        }
    }
}

// MARK: Race layout

/// The race result: finish time, official or Garmin-only, the gap to goal and the field position.
private struct PFRaceResultCard: View {
    let race: PFRaceResult

    private var finish: String {
        race.timeDisplay ?? race.timeSeconds.map { PFFormat.clock(Double($0)) } ?? "\u{2013}"
    }

    private var goalLine: String? {
        guard let goal = race.goalSeconds else { return nil }
        var line = "Goal \(PFFormat.clock(Double(goal)))"
        if let delta = race.goalDeltaS {
            line += delta == 0 ? " \u{00B7} on goal" : " \u{00B7} \(delta > 0 ? "+" : "-")\(PFFormat.clock(Double(abs(delta)))) vs goal"
        }
        return line
    }

    private var rankLine: String? {
        var parts: [String] = []
        if let rank = race.rank, let field = race.fieldSize { parts.append("\(rank) of \(field)") }
        if let group = race.rankAgeGroup { parts.append("age group \(group)") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        PFCard(race.event ?? "Race", icon: "flag.checkered") {
            VStack(alignment: .leading, spacing: 6) {
                Text(finish)
                    .font(StrandFont.rounded(40))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(race.official ? "Official result" : "Garmin recording, official result pending")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(race.official ? PFColor.positive : StrandPalette.textSecondary)
                if let goalLine {
                    Text(goalLine)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if let rankLine {
                    Text(rankLine)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .containerIdentifier("pf-race-result")
    }
}

/// One row per race segment in the order the server sent: time, field position and the gap to his best.
private struct PFRaceSegmentsCard: View {
    let race: PFRaceResult

    private func color(_ kind: String?) -> Color {
        switch kind {
        case "run": return PFColor.sky
        case "station": return PFColor.violet
        default: return StrandPalette.textTertiary
        }
    }

    private func detail(_ s: PFRaceResult.Segment) -> String? {
        var parts: [String] = []
        if let rank = s.rank, let field = s.fieldSize, field > 0 {
            parts.append("top \((rank * 100 + field - 1) / field) %")
        }
        if let delta = s.deltaS {
            parts.append(delta > 0 ? "+\(PFFormat.clock(Double(delta))) vs best" : "best")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        if !race.segments.isEmpty {
            PFCard("Segments", icon: "list.number") {
                VStack(spacing: 10) {
                    ForEach(Array(race.segments.enumerated()), id: \.offset) { _, s in
                        HStack(alignment: .center, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(s.kind))
                                .frame(width: 4, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name)
                                    .font(StrandFont.subhead.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                if let line = detail(s) {
                                    Text(line)
                                        .font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(s.seconds.map { PFFormat.clock(Double($0)) } ?? "\u{2013}")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                    }
                }
            }
            .containerIdentifier("pf-race-segments")
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
    /// Where this session's load sits among the athlete's recent ones (2026-10-29); nil on an older document.
    var rank: PFEffortRank?

    var body: some View {
        PFCard("Effort", icon: "flame.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if let strain {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(PFFormat.oneDecimal(strain))
                            .font(StrandFont.rounded(30))
                            .foregroundStyle(StrandPalette.effortColor)
                        Text("of 21").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        if let word = rank?.chipWord ?? band { PFChip(text: word, color: StrandPalette.effortColor) }
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
                if let rank { rankRow(rank) }
            }
        }
        .containerIdentifier("pf-effort")
    }

    /// What the chip word means, and that morning's recovery as its own figure beside it (never folded into the effort).
    private func rankRow(_ rank: PFEffortRank) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PFParagraph(rankSentence(rank))
            if let score = rank.recovery {
                PFFigure(value: String(Safe.int(score)), unit: nil, label: "Recovery that morning")
                    .frame(width: 96)
            }
        }
    }

    private func rankSentence(_ rank: PFEffortRank) -> String {
        var line = PFFormat.capitalized(rank.chipWord ?? "")
        if let pct = rank.pct {
            line += ": this session's load beat \(pct) % of your"
            if let n = rank.n { line += " \(n)" }
            line += " earlier sessions"
            if let days = rank.days { line += " in the last \(days) days" }
            line += "."
        }
        if strain != nil, let band { line += " On the 0 to 21 day scale it reads as \(band.lowercased())." }
        return line
    }
}

/// Time against the Garmin lactate threshold, only when the server stamped `lt_split` on the run.
private struct PFLtSplitCard: View {
    let split: PFLtSplit

    var body: some View {
        PFCard("Against your threshold", icon: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 18) {
                    if let s = split.belowS { PFFigure(value: PFFormat.clock(s), unit: nil, label: "Below") }
                    if let s = split.atS { PFFigure(value: PFFormat.clock(s), unit: nil, label: "At") }
                    if let s = split.aboveS { PFFigure(value: PFFormat.clock(s), unit: nil, label: "Above") }
                    if let hr = split.ltHr { PFFigure(value: String(Safe.int(hr)), unit: "bpm", label: "Threshold HR") }
                }
                Text("Time spent below, within 5 bpm of, and above your lactate-threshold heart rate. Time above it is the hard part of the run.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A run no plan session was matched to: the server's best guess at what it was, shown as one.
private struct PFRunExplainerCard: View {
    let explainer: PFRunExplainer

    var body: some View {
        PFCard("What this run looks like", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                if let t = explainer.looksLike {
                    PFLabeled(label: "Best guess", text: "This looks like " + t + ". No plan session was matched, so this is inferred from the run itself.")
                }
                if let t = explainer.purpose { PFLabeled(label: "Why this session", text: t) }
                if let t = explainer.body { PFLabeled(label: "What it does", text: t) }
                if let t = explainer.energy { PFLabeled(label: "Lactate and VO2 effect", text: t) }
                if let t = explainer.shape { PFLabeled(label: "Why it is built this way", text: t) }
                if let t = explainer.payoff { PFLabeled(label: "What it buys you", text: t) }
                if let t = explainer.yours { PFLabeled(label: "Your lactate threshold", text: t) }
            }
        }
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
