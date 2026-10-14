import SwiftUI
import StrandDesign

// Bike rides in the PaceForge tab and My Day: a ride row, and the ride screen with the key numbers, power and
// heart-rate zones, the power / heart-rate / cadence chart, the mean-maximal power table, the laps, the
// compliance note, heart-rate recovery and the coach's analysis. The data is ride-metrics.json, the ride's
// stream file and its analysis (all optional, all cached on the phone for offline). Colours are neutral:
// nothing on a ride is graded good or bad here.

// MARK: - Loading

/// The files behind one open ride screen.
struct PFRideDetail {
    var stream: PFRideStream?
    var analysis: String?
}

enum PFRideLoader {
    /// The ride's stream and analysis: from the server when it answers, else the copy saved on the phone.
    static func detail(for ride: PFRide) async -> PFRideDetail {
        async let streamData = fetchWithCache(ride.streamPath)
        async let analysisData = fetchWithCache(ride.analysisPath)
        var out = PFRideDetail()
        if ride.hasStream, let data = await streamData { out.stream = PFRideParse.stream(PFJ(data: data)) }
        if let data = await analysisData, let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.analysis = trimmed }
        }
        return out
    }

    /// One ride by id, for a screen opened without the PaceForge tab (My Day). The saved copy is read first.
    static func ride(id: String) async -> PFRide? {
        let path = "data/ride-metrics.json"
        if !PFAPI.isFixture, let saved = PFStore.read(path: path),
           let found = PFRideParse.metrics(PFJ(data: saved)).first(where: { $0.id == id }) { return found }
        guard let data = await PFAPI.fetchOptional(path) else { return nil }
        return PFRideParse.metrics(PFJ(data: data)).first { $0.id == id }
    }

    /// The athlete's RPE for a ride, from `state.rpe.entries` (the activity id is the ride id).
    static func rpe(for id: String) async -> Double? {
        let path = "api/state"
        var data = PFAPI.isFixture ? nil : PFStore.read(path: path)
        if data == nil { data = await PFAPI.fetchOptional(path) }
        for entry in PFJ(data: data)["rpe"]["entries"].array where entry["activity_id"].idString == id {
            return entry["rpe"].double
        }
        return nil
    }

    private static func fetchWithCache(_ path: String) async -> Data? {
        if let data = await PFAPI.fetchOptional(path) { return data }
        return PFAPI.isFixture ? nil : PFStore.read(path: path)
    }
}

// MARK: - Row

/// A ride in the day's list, beside the planned sessions. Opens the ride screen.
struct PFRideRow: View {
    let ride: PFRide
    let snapshot: PFSnapshot
    @State private var isShowing = false
    private let hiding = PFHiding()

    var body: some View {
        StrandCard(padding: 14) {
            Button { isShowing = true } label: {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PFColor.sky)
                        .frame(width: 4)
                        .frame(minHeight: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ride.title)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !ride.rowLine.isEmpty {
                            Text(hiding.text(ride.rowLine))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        if let line = ride.summaryLine {
                            Text(hiding.text(line))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 6) {
                        PFChip(text: "ride", color: PFColor.sky)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pf-ride-\(ride.id)")
        }
        .sheet(isPresented: $isShowing) {
            PFRideSheet(ride: ride, rpe: snapshot.rpe[ride.id])
                .environment(\.pfExplainers, snapshot.explainerMap)
        }
    }
}

// MARK: - My Day host

/// The ride screen as My Day opens it: finds the ride by id in the saved (or fetched) ride metrics.
struct PFRideHost: View {
    let rideId: String
    @State private var ride: PFRide?
    @State private var rpe: Double?
    @State private var explainers: [String: PFExplainer] = [:]
    @State private var didLoad = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let ride {
                PFRideSheet(ride: ride, rpe: rpe)
                    .environment(\.pfExplainers, explainers)
            } else {
                NavigationStack {
                    VStack(spacing: 12) {
                        if didLoad {
                            Text("This ride's details are not available on this iPhone yet.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .multilineTextAlignment(.center)
                        } else {
                            ProgressView()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .navigationTitle("Ride")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }.foregroundStyle(StrandPalette.accent)
                        }
                    }
                }
            }
        }
        .task {
            ride = await PFRideLoader.ride(id: rideId)
            rpe = await PFRideLoader.rpe(for: rideId)
            var explainerData = PFAPI.isFixture ? nil : PFStore.read(path: "data/metric-explainers.json")
            if explainerData == nil { explainerData = await PFAPI.fetchOptional("data/metric-explainers.json") }
            if let data = explainerData {
                explainers = Dictionary(PFWave2Parse.explainers(PFJ(data: data)).map { ($0.id, $0) },
                                        uniquingKeysWith: { first, _ in first })
            }
            didLoad = true
        }
    }
}

// MARK: - Screen

struct PFRideSheet: View {
    let ride: PFRide
    var rpe: Double? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var detail: PFRideDetail?
    @State private var chart: PFRideChartData?
    private let hiding = PFHiding()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFRevealBar()
                    headerCard
                    numbersCard
                    if !ride.powerZones.isEmpty { PFRideZonesCard(title: "Power zones", icon: "bolt.fill", zones: ride.powerZones, unit: "W", isPower: true) }
                    if !ride.hrZones.isEmpty { PFRideZonesCard(title: "Heart-rate zones", icon: "heart.fill", zones: ride.hrZones, unit: "bpm", isPower: false) }
                    chartSection
                    if !ride.mmp.isEmpty { mmpCard }
                    if !laps.isEmpty { lapsCard }
                    if let text = ride.compliance { complianceCard(text) }
                    if let hrr = PFBuilder.hrr1(ride.hrr1) { PFHRR1Card(hrr: hrr) }
                    analysisSection
                    if let rpe { rpeCard(rpe) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(ride.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-ride-done")
                }
            }
        }
        .containerIdentifier("pf-ride-sheet")
        .task {
            let loaded = await PFRideLoader.detail(for: ride)
            detail = loaded
            chart = loaded.stream.map { PFRideChartData($0) }
        }
    }

    private var laps: [PFRideLap] { ride.laps.isEmpty ? (detail?.stream?.laps ?? []) : ride.laps }

    // MARK: Header

    private var headerCard: some View {
        PFCard(ride.title, icon: "bicycle", info: PFExplainerID.ride) {
            VStack(alignment: .leading, spacing: 10) {
                Text(PFFormat.dayTitle(ride.date))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                HStack(spacing: 8) {
                    if let type = ride.type { PFChip(text: PFFormat.words(type), color: StrandPalette.accent) }
                    if let seconds = ride.durationS, seconds > 0 {
                        PFChip(text: PFRideFormat.clock(seconds), color: StrandPalette.textSecondary)
                    }
                    PFChip(text: ride.resolutionNote, color: StrandPalette.textSecondary)
                        .accessibilityIdentifier("pf-ride-resolution")
                }
                if let line = ride.summaryLine { PFParagraph(line) }
                if let ftp = ride.ftp {
                    Text("FTP \(Int(ftp.rounded())) W")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .containerIdentifier("pf-ride-header")
    }

    // MARK: Key numbers

    private struct Tile: Identifiable {
        let label: String
        let value: String
        let unit: String?
        /// The Hide-numbers switch that blanks this figure, if any.
        var kind: PFRedact.Kind?
        var id: String { label }
    }

    private var tiles: [Tile] {
        var out: [Tile] = []
        func add(_ label: String, _ value: Double?, _ unit: String?, kind: PFRedact.Kind? = nil, _ format: (Double) -> String) {
            if let value { out.append(Tile(label: label, value: format(value), unit: unit, kind: kind)) }
        }
        func whole(_ v: Double) -> String { String(Int(v.rounded())) }
        add("Avg power", ride.avgPower, "W", whole)
        add("Normalized power", ride.np, "W", whole)
        add("Intensity factor", ride.intensityFactor, nil, PFRideFormat.twoDecimals)
        add("TSS", ride.tss, nil, kind: .scores, whole)
        add("Variability index", ride.vi, nil, PFRideFormat.twoDecimals)
        add("Work", ride.kj, "kJ", whole)
        add("Efficiency factor", ride.ef, nil, PFRideFormat.twoDecimals)
        add("Avg HR", ride.avgHr, "bpm", whole)
        if let decoupling = ride.decoupling {
            out.append(Tile(label: "Decoupling", value: decoupling.text, unit: nil))
        }
        return out
    }

    @ViewBuilder private var numbersCard: some View {
        let items = tiles
        if !items.isEmpty {
            PFCard("Key numbers", icon: "list.bullet.rectangle") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                          alignment: .leading, spacing: 16) {
                    ForEach(items) { tile in
                        PFFigure(value: tile.kind.map { hiding.shown(tile.value, $0) } ?? tile.value,
                                 unit: tile.kind.map { hiding.hides($0) } == true ? nil : tile.unit, label: tile.label)
                    }
                }
            }
            .containerIdentifier("pf-ride-numbers")
        }
    }

    // MARK: Chart

    @ViewBuilder private var chartSection: some View {
        if let chart, chart.hasAnySeries {
            PFCard("Power, heart rate and cadence", icon: "chart.xyaxis.line") {
                VStack(alignment: .leading, spacing: 14) {
                    if chart.hasPower {
                        PFRidePanel(title: "Power", unit: "W", color: StrandPalette.effortColor, points: chart.power,
                                    target: chart.hasTarget ? chart.target : [], laps: laps, pauses: chart.pauses,
                                    duration: chart.duration, zeroBased: true)
                    }
                    if chart.hasHr {
                        PFRidePanel(title: "Heart rate", unit: "bpm", color: StrandPalette.liquidHeart, points: chart.hr,
                                    target: [], laps: laps, pauses: chart.pauses, duration: chart.duration, zeroBased: false)
                    }
                    if chart.hasCadence {
                        PFRidePanel(title: "Cadence", unit: "rpm", color: StrandPalette.restColor, points: chart.cadence,
                                    target: [], laps: laps, pauses: chart.pauses, duration: chart.duration, zeroBased: false)
                    }
                    HStack {
                        Text("0:00").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        Spacer()
                        Text(PFRideFormat.clock(chart.duration)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                    Text(legend(chart))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .containerIdentifier("pf-ride-chart")
        } else if detail != nil {
            PFCard("Power, heart rate and cadence", icon: "chart.xyaxis.line") {
                PFParagraph("The chart for this ride is not synced to this iPhone.")
            }
            .containerIdentifier("pf-ride-chart-missing")
        }
    }

    private func legend(_ chart: PFRideChartData) -> String {
        var bits: [String] = []
        if chart.hasTarget { bits.append("Dashed line: target power") }
        if !laps.isEmpty { bits.append("Shaded bands: laps") }
        if !chart.pauses.isEmpty { bits.append("Hatched: paused") }
        if ride.isLowResolution { bits.append("A 240-point sample of the ride") }
        return bits.joined(separator: " \u{00B7} ")
    }

    // MARK: Mean-maximal power

    private var mmpCard: some View {
        PFCard("Best power by duration", icon: "bolt.horizontal") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                      alignment: .leading, spacing: 14) {
                ForEach(ride.mmp, id: \.seconds) { entry in
                    PFFigure(value: String(Int(entry.watts.rounded())), unit: "W", label: PFRideFormat.duration(entry.seconds))
                }
            }
        }
        .containerIdentifier("pf-ride-mmp")
    }

    // MARK: Laps

    private var lapsCard: some View {
        PFCard("Laps", icon: "flag") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(laps) { lap in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(lap.name.map { "\(lap.n). \($0)" } ?? "Lap \(lap.n)")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 8)
                            if let secs = lap.secs {
                                Text(PFRideFormat.clock(secs))
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        Text(lapLine(lap))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pf-ride-lap-\(lap.n)")
                    if lap.n != laps.last?.n { Divider().overlay(StrandPalette.hairline) }
                }
            }
        }
        .containerIdentifier("pf-ride-laps")
    }

    private func lapLine(_ lap: PFRideLap) -> String {
        var bits: [String] = []
        if let power = lap.avgPower { bits.append("\(Int(power.rounded())) W") }
        if let pct = lap.pctFtp { bits.append("\(Int(pct.rounded())) % of FTP") }
        if let target = lap.targetPower { bits.append("target \(Int(target.rounded())) W") }
        if let versus = lap.vsTargetPct { bits.append("vs target " + PFRideFormat.signedPercent(versus)) }
        if let hr = lap.avgHr { bits.append("\(Int(hr.rounded())) bpm") }
        return bits.joined(separator: " \u{00B7} ")
    }

    // MARK: Compliance, analysis, effort

    private func complianceCard(_ text: String) -> some View {
        PFCard("Versus the plan", icon: "checkmark.seal") {
            PFParagraph(text)
        }
        .containerIdentifier("pf-ride-compliance")
    }

    @ViewBuilder private var analysisSection: some View {
        if let markdown = detail?.analysis {
            PFCard("Coach analysis", icon: "sparkles") {
                VStack(alignment: .leading, spacing: 10) {
                    PFMarkdown(text: markdown)
                    if let note = ride.estimateNote {
                        Text(note)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityIdentifier("pf-ride-estimate-note")
                    }
                }
            }
            .containerIdentifier("pf-ride-analysis")
        } else if detail == nil {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading ride details")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    private func rpeCard(_ rpe: Double) -> some View {
        PFCard("How hard it felt", icon: "gauge.with.dots.needle.67percent") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hiding.shown(PFFormat.trimmed(rpe), .scores))
                    .font(StrandFont.rounded(30))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("RPE of 10").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

// MARK: - Zones

/// One bar per zone: its name and range, its share of the ride as a bar, and the time spent. The bars share one
/// neutral hue (power) or the heart-rate zone colours; none of them is a verdict.
struct PFRideZonesCard: View {
    let title: String
    let icon: String
    let zones: [PFRideZone]
    let unit: String
    let isPower: Bool

    var body: some View {
        let fractions = PFRideZones.fractions(zones)
        PFCard(title, icon: icon) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(zones.enumerated()), id: \.element.zone) { index, zone in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Z\(zone.zone)").font(StrandFont.overline).foregroundStyle(StrandPalette.textTertiary)
                            Text(zone.name ?? "")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            if let range = zone.rangeText {
                                Text("\(range) \(unit)")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            Spacer(minLength: 6)
                            Text(valueText(zone, fraction: fractions[index]))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(StrandPalette.surfaceInset)
                                Capsule()
                                    .fill(color(zone.zone))
                                    .frame(width: max(fractions[index] > 0 ? 4 : 0, geo.size.width * CGFloat(fractions[index])))
                            }
                        }
                        .frame(height: 8)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pf-ride-zone-\(isPower ? "power" : "hr")-\(zone.zone)")
                }
            }
        }
        .containerIdentifier(isPower ? "pf-ride-power-zones" : "pf-ride-hr-zones")
    }

    private func valueText(_ zone: PFRideZone, fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        return zone.secs > 0 ? "\(PFRideFormat.clock(zone.secs)) \u{00B7} \(percent) %" : "\(percent) %"
    }

    private func color(_ zone: Int) -> Color {
        isPower ? StrandPalette.effortColor.opacity(min(1, 0.3 + 0.1 * Double(zone))) : StrandPalette.hrZoneColor(zone)
    }
}

// MARK: - Chart panel

/// One series drawn on a Canvas: lap bands behind, hatching where the ride was paused, an optional dashed
/// target line and the series itself, broken wherever a reading is missing.
struct PFRidePanel: View {
    let title: String
    let unit: String
    let color: Color
    let points: [PFRidePoint]
    let target: [PFRidePoint]
    let laps: [PFRideLap]
    let pauses: [PFRidePause]
    let duration: Double
    let zeroBased: Bool

    private var range: ClosedRange<Double>? {
        PFRideChart.bounds((points + target).map { $0.v }, zeroBased: zeroBased)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).strandOverline()
                Spacer()
                if let range {
                    Text("\(Int(range.lowerBound.rounded()))\u{2013}\(Int(range.upperBound.rounded())) \(unit)")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            canvas
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceInset))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityIdentifier("pf-ride-panel-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        }
    }

    private var accessibilityText: String {
        guard let range else { return "\(title) chart, no readings." }
        return "\(title) chart from \(Int(range.lowerBound.rounded())) to \(Int(range.upperBound.rounded())) \(unit) over \(PFRideFormat.clock(duration))."
    }

    private var canvas: some View {
        Canvas { context, size in
            guard duration > 0, let range, range.upperBound > range.lowerBound, size.width > 0, size.height > 0 else { return }
            let span = range.upperBound - range.lowerBound
            func x(_ t: Double) -> CGFloat { CGFloat(min(max(t / duration, 0), 1)) * size.width }
            func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - range.lowerBound) / span) * size.height }

            // Lap bands: every other lap is shaded, so the boundaries read without labels.
            for (index, lap) in laps.enumerated() where index % 2 == 0 {
                guard let start = lap.startS, let end = lap.endS, end > start else { continue }
                let band = CGRect(x: x(start), y: 0, width: max(1, x(end) - x(start)), height: size.height)
                context.fill(Path(band), with: .color(StrandPalette.textTertiary.opacity(0.12)))
            }

            // Three faint guide lines.
            for fraction in [0.25, 0.5, 0.75] {
                var guide = Path()
                guide.move(to: CGPoint(x: 0, y: size.height * CGFloat(fraction)))
                guide.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(fraction)))
                context.stroke(guide, with: .color(StrandPalette.hairline), lineWidth: 0.5)
            }

            // Paused stretches are hatched.
            for pause in pauses {
                let rect = CGRect(x: x(pause.start), y: 0, width: max(1, x(pause.end) - x(pause.start)), height: size.height)
                var inner = context
                inner.clip(to: Path(rect))
                var hatch = Path()
                var start = rect.minX - size.height
                while start < rect.maxX {
                    hatch.move(to: CGPoint(x: start, y: size.height))
                    hatch.addLine(to: CGPoint(x: start + size.height, y: 0))
                    start += 6
                }
                inner.stroke(hatch, with: .color(StrandPalette.textTertiary.opacity(0.55)), lineWidth: 1)
            }

            // The target, dashed, then the series.
            for run in PFRideChart.runs(target, pauses: []) {
                context.stroke(linePath(run, x: x, y: y), with: .color(StrandPalette.textSecondary),
                               style: StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: [5, 4]))
            }
            for run in PFRideChart.runs(points, pauses: pauses) {
                context.stroke(linePath(run, x: x, y: y), with: .color(color),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func linePath(_ run: [PFRidePoint], x: (Double) -> CGFloat, y: (Double) -> CGFloat) -> Path {
        var path = Path()
        for (index, point) in run.enumerated() {
            guard let value = point.v else { continue }
            let location = CGPoint(x: x(point.t), y: y(value))
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        return path
    }
}
