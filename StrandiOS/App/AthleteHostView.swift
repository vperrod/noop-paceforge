#if os(iOS)
import SwiftUI
import Charts
import StrandDesign

// MARK: - Athlete: the fourth tab with the unified navigation
//
// The athlete's profile header, the metric tiles with their change over four weeks, the strengths / weaknesses / areas to work on, and a
// row to the full "Where you stand" scorecard. A tile (or a row's link) opens a detail sheet: the history chart, what the number is and
// where its norms are. Everything is made from the PaceForge snapshot (`PFAthleteBuild`), so this screen reads no document of its own.
// NOOP's strap scores are not here; every tile names the system it comes from.
//
// Built small on purpose (builds 465 to 478): the tiles sit in a LazyVGrid, a sparkline is a Canvas (no GeometryReader or ViewThatFits),
// nothing here reads a live strap value, and only this one screen is mounted for the tab.

/// The Athlete tab's root.
struct AthleteHostView: View {
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        ScreenScaffold(title: "Athlete", subtitle: "Your profile, your numbers and what to work on.",
                       onRefresh: { await PFUnified.model.refresh() }, lazy: true, topBackground: liquidScaffoldSky()) {
            AthleteColumn(maxHr: profile.hrMaxOverride > 0 ? profile.hrMaxOverride : nil, avatar: profile.avatarImageData)
        }
    }
}

/// The PaceForge snapshot around the screen: the lock, the load states and the offline banner.
private struct AthleteColumn: View {
    let maxHr: Int?
    let avatar: Data?

    var body: some View {
        PFSnapshotHost(content: { snapshot in
            AnyView(UnifiedChipMount(host: "athlete", name: "main", content: AnyView(
                AthleteScreen(athlete: PFAthleteBuild.make(snapshot, maxHr: maxHr), standing: snapshot.standing, avatar: avatar)
            )))
        })
        .containerIdentifier("athlete-host")
    }
}

/// What a tap on the screen opens.
private enum AthleteSheet: Identifiable {
    case tile(String)
    case standing(String)
    case plan(String)
    case hyrox
    case predictions
    case zones

    var id: String {
        switch self {
        case .tile(let id): return "tile-\(id)"
        case .standing(let id): return "standing-\(id)"
        case .plan(let id): return "plan-\(id)"
        case .hyrox: return "hyrox"
        case .predictions: return "predictions"
        case .zones: return "zones"
        }
    }
}

private enum AthleteLook {
    static func symbol(_ direction: PFAthleteChange.Direction) -> String {
        switch direction {
        case .up: return "arrowtriangle.up.fill"
        case .down: return "arrowtriangle.down.fill"
        case .flat: return "minus"
        }
    }

    /// Green when the move is toward better, amber when away from it, grey when flat or when the metric has no better side.
    static func tone(_ change: PFAthleteChange) -> Color {
        guard let favourable = change.isFavourable else { return NoopLook.textTertiary }
        return favourable ? NoopLook.trendUp : NoopLook.trendDown
    }

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous)
    }
}

// MARK: - The screen

private struct AthleteScreen: View {
    let athlete: PFAthlete
    let standing: PFStanding?
    let avatar: Data?
    @State private var sheet: AthleteSheet?
    @Environment(\.pfOpenStanding) private var openStanding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AthleteHeader(athlete: athlete, avatar: avatar)
            if athlete.isEmpty {
                PFCard("Nothing here yet", icon: "person.crop.circle") {
                    PFParagraph("Your numbers appear here once PaceForge has synced your watch and your scale.")
                }
                .accessibilityIdentifier("athlete-empty")
            } else {
                metrics
                recordsCard
                findings
                scorecardRow
            }
        }
        .sheet(item: $sheet) { sheetContent($0) }
    }

    // MARK: Metrics

    @ViewBuilder private var metrics: some View {
        if !athlete.tiles.isEmpty || !athlete.runTimes.isEmpty || athlete.hasHyrox || athlete.predictions != nil || athlete.zones != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("My metrics").lookCaps(11).foregroundStyle(NoopLook.textTertiary)
                    Spacer(minLength: 8)
                    Text("Change").font(LookFont.text(11, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                }
                if !athlete.tiles.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(athlete.tiles) { tile in
                            Button { sheet = .tile(tile.id) } label: { AthleteTile(tile: tile) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("athlete-tile-\(tile.id)")
                        }
                    }
                }
                if let predictions = athlete.predictions {
                    AthletePredictionsCard(predictions: predictions) { sheet = .predictions }
                }
                if let zones = athlete.zones {
                    AthleteZonesCard(zones: zones) { sheet = .zones }
                }
                if !athlete.runTimes.isEmpty {
                    AthleteRunTimes(times: athlete.runTimes) { time in
                        if let id = time.standingId { sheet = .standing(id) }
                    }
                }
                if athlete.hasHyrox {
                    Button { sheet = .hyrox } label: { AthleteHyroxTile(card: athlete.hyroxCard, hyrox: athlete.hyrox) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("athlete-hyrox")
                }
            }
            .containerIdentifier("athlete-metrics")
        }
    }

    // MARK: Records

    @ViewBuilder private var recordsCard: some View {
        if !athlete.records.isEmpty {
            AthleteRecordsCard(records: athlete.records)
        }
    }

    // MARK: Strengths, weaknesses, areas

    @ViewBuilder private var findings: some View {
        group("Strengths", icon: "arrow.up.right.circle", rows: athlete.strengths)
        group("Weaknesses", icon: "arrow.down.right.circle", rows: athlete.weaknesses)
        group("Areas to work on", icon: "scope", rows: athlete.areas)
    }

    @ViewBuilder private func group(_ title: String, icon: String, rows: [PFAthleteFinding]) -> some View {
        if !rows.isEmpty {
            PFCard(title, icon: icon) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        AthleteFindingRow(finding: row, onOpen: { open($0) }, onPlan: { sheet = .plan($0) })
                        if row.id != rows.last?.id { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
            .containerIdentifier("athlete-group-\(rows[0].group.rawValue)")
        }
    }

    /// A row's link: the tile of the same metric when there is one, else its Standing sheet.
    private func open(_ finding: PFAthleteFinding) {
        if let id = finding.standingId, let tile = athlete.tiles.first(where: { $0.standingId == id }) {
            sheet = .tile(tile.id)
        } else if let id = finding.standingId {
            sheet = .standing(id)
        } else if let id = finding.tileId {
            sheet = .tile(id)
        }
    }

    // MARK: Scorecard

    @ViewBuilder private var scorecardRow: some View {
        if let line = athlete.scorecardLine {
            Button { openStanding() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full scorecard").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
                        Text(line).font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(AthleteLook.cardShape.fill(NoopLook.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlete-scorecard")
        }
    }

    // MARK: Sheets

    @ViewBuilder private func sheetContent(_ sheet: AthleteSheet) -> some View {
        switch sheet {
        case .tile(let id):
            if let tile = athlete.tile(id) {
                AthleteMetricSheet(tile: tile, standing: standing)
            }
        case .standing(let id):
            if let metric = standing?.metric(id) {
                PFStandingMetricSheet(metric: metric, plan: standing?.plan(metric.planId))
            }
        case .plan(let id):
            if let plan = standing?.plan(id) {
                PFStandingPlanSheet(plan: plan)
            }
        case .hyrox:
            AthleteHyroxSheet(card: athlete.hyroxCard, hyrox: athlete.hyrox)
        case .predictions:
            if let predictions = athlete.predictions {
                AthletePredictionsSheet(predictions: predictions)
            }
        case .zones:
            if let zones = athlete.zones {
                AthleteZonesSheet(zones: zones)
            }
        }
    }
}

// MARK: - Header

private struct AthleteHeader: View {
    let athlete: PFAthlete
    let avatar: Data?
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProfileAvatarView(imageData: avatar, size: 56)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Athlete profile").lookCaps(11).foregroundStyle(NoopLook.textTertiary)
                    if let title = athlete.goalTitle {
                        Text(title)
                            .font(StrandFont.rounded(22))
                            .foregroundStyle(NoopLook.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if let line = athlete.goalLine {
                            Text(line).font(LookFont.text(13, weight: .medium)).foregroundStyle(NoopLook.textSecondary).lineLimit(1)
                        }
                    } else {
                        Text("No event set")
                            .font(StrandFont.rounded(22))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            factRow(Array(athlete.facts.prefix(4)))
            factRow(Array(athlete.facts.dropFirst(4).prefix(4)))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AthleteLook.cardShape.fill(NoopLook.card))
        .containerIdentifier("athlete-header")
    }

    private func factRow(_ facts: [PFAthleteFact]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.hidesWithBody ? hiding.shown(fact.text, .body) : fact.text)
                        .font(LookFont.numeral(18))
                        .foregroundStyle(fact.text == "\u{2014}" ? NoopLook.textTertiary : NoopLook.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(fact.label).lookCaps(10, weight: .semibold).foregroundStyle(NoopLook.textTertiary).lineLimit(1)
                    if let note = fact.note {
                        Text(note).font(LookFont.text(10, weight: .medium)).foregroundStyle(NoopLook.textTertiary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Tiles

private struct AthleteTile: View {
    let tile: PFAthleteMetric
    private let hiding = PFHiding()

    private var isHidden: Bool { tile.hidesWithBody && hiding.hides(.body) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.label)
                .lookCaps(10.5, weight: .semibold)
                .foregroundStyle(NoopLook.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(isHidden ? PFRedact.placeholder : tile.valueText)
                    .font(LookFont.numeral(24))
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !isHidden && !tile.unit.isEmpty {
                    Text(tile.unit)
                        .font(LookFont.text(12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .lineLimit(1)
                }
            }
            changeLine
            Spacer(minLength: 0)
            if tile.sparkValues.count >= 2 && !isHidden {
                AthleteSparkline(values: tile.sparkValues, color: PFColor.sky)
            } else if let secondary = tile.secondary, !isHidden {
                Text(secondary)
                    .font(LookFont.text(11, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .bottomLeading)
            } else {
                Color.clear.frame(height: 24)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(AthleteLook.cardShape.fill(NoopLook.card))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var changeLine: some View {
        if let change = tile.change, !isHidden {
            HStack(spacing: 4) {
                Image(systemName: AthleteLook.symbol(change.direction))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AthleteLook.tone(change))
                Text(tile.changeText ?? "")
                    .font(LookFont.text(11, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            Text(isHidden ? " " : (tile.datedText ?? "no change history yet"))
                .font(LookFont.text(11, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .lineLimit(1)
        }
    }
}

/// A line over a few values. A Canvas, not the shared Sparkline: that one measures itself with a GeometryReader and a dozen of them
/// in a grid is what the stall notes above warn about.
private struct AthleteSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, let low = values.min(), let high = values.max() else { return }
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let fraction: Double = high > low ? (value - low) / (high - low) : 0.5
                let point = CGPoint(x: CGFloat(index) * step, y: size.height - CGFloat(fraction) * size.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - Running times and HYROX

private struct AthleteRunTimes: View {
    let times: [PFAthleteRunTime]
    let onTap: (PFAthleteRunTime) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Running").lookCaps(10.5, weight: .semibold).foregroundStyle(NoopLook.textTertiary)
            HStack(alignment: .top, spacing: 8) {
                ForEach(times) { time in
                    Button { onTap(time) } label: { cell(time) }
                        .buttonStyle(.plain)
                        .disabled(time.standingId == nil)
                        .accessibilityIdentifier("athlete-run-\(time.id)")
                }
            }
            Text("Best recent times from your runs, and the half marathon your current shape equals.")
                .font(LookFont.text(11, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AthleteLook.cardShape.fill(NoopLook.card))
    }

    private func cell(_ time: PFAthleteRunTime) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time.text)
                .font(LookFont.numeral(20))
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(time.label).lookCaps(10, weight: .semibold).foregroundStyle(NoopLook.textTertiary).lineLimit(1)
            if time.band != nil {
                PFBandBar(band: time.band, height: 4)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct AthleteHyroxTile: View {
    let card: PFHyroxFinishCard?
    let hyrox: PFHyrox?

    private var predicted: String { card?.finish.central ?? hyrox?.predicted ?? "\u{2014}" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HYROX projection").lookCaps(10.5, weight: .semibold).foregroundStyle(NoopLook.textTertiary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(predicted).font(LookFont.numeral(24)).foregroundStyle(NoopLook.textPrimary).lineLimit(1)
                Text("predicted finish").font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
            }
            if let gap = card?.finish.gapText {
                Text(gap).font(LookFont.text(11, weight: .medium)).foregroundStyle(NoopLook.textSecondary).lineLimit(1)
            }
            if let best = card?.personalBest {
                Text("Best race \(best)").font(LookFont.text(11, weight: .medium)).foregroundStyle(NoopLook.textTertiary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AthleteLook.cardShape.fill(NoopLook.card))
        .contentShape(Rectangle())
    }
}

// MARK: - A strength, weakness or area

private struct AthleteFindingRow: View {
    let finding: PFAthleteFinding
    let onOpen: (PFAthleteFinding) -> Void
    let onPlan: (String) -> Void
    @State private var isOpen = false
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() } } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title)
                            .font(LookFont.text(15, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .lineLimit(1)
                        Text(hiding.text(finding.evidence))
                            .font(LookFont.text(12.5, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let tag = finding.tag {
                        PFChip(text: tag, color: NoopLook.textTertiary)
                    } else if finding.band != nil {
                        Circle().fill(PFBandColor.color(for: finding.band)).frame(width: 10, height: 10)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlete-finding-\(finding.id)")
            if isOpen { why }
        }
    }

    @ViewBuilder private var why: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rule = finding.ruleWhy {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rule").strandOverline()
                    PFParagraph(rule)
                }
            }
            if let coach = finding.coachWhy {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coach").strandOverline()
                    PFParagraph(coach)
                }
            }
            HStack(spacing: 10) {
                if finding.standingId != nil || finding.tileId != nil {
                    Button { onOpen(finding) } label: { Label("Open the number", systemImage: "chart.line.uptrend.xyaxis") }
                        .buttonStyle(.bordered)
                        .tint(StrandPalette.accent)
                        .accessibilityIdentifier("athlete-open-\(finding.id)")
                }
                if let plan = finding.planId {
                    Button { onPlan(plan) } label: { Label("See the plan", systemImage: "list.bullet.clipboard") }
                        .buttonStyle(.bordered)
                        .tint(StrandPalette.accent)
                        .accessibilityIdentifier("athlete-plan-\(finding.id)")
                }
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Metric detail

private enum AthleteSpan: Int, CaseIterable, Identifiable {
    case month = 28
    case quarter = 84
    case year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .month: return "4 weeks"
        case .quarter: return "12 weeks"
        case .year: return "1 year"
        }
    }
}

private struct AthleteMetricSheet: View {
    let tile: PFAthleteMetric
    let standing: PFStanding?
    @Environment(\.dismiss) private var dismiss
    @State private var span: AthleteSpan?
    @State private var showStanding = false
    @State private var showPlan = false
    private let hiding = PFHiding()

    private var isHidden: Bool { tile.hidesWithBody && hiding.hides(.body) }

    private var standingMetric: PFStandingMetric? { tile.standingId.flatMap { standing?.metric($0) } }

    private var coverageDays: Int {
        guard let first = tile.series.first, let last = tile.series.last else { return 0 }
        return PFFormat.daysBetween(first.date, last.date)
    }

    /// The ranges the history is long enough to fill: 4 weeks always, 12 weeks and 1 year once it reaches past 4 and 12 weeks.
    private var spans: [AthleteSpan] {
        AthleteSpan.allCases.filter { option in
            switch option {
            case .month: return true
            case .quarter: return coverageDays > AthleteSpan.month.rawValue
            case .year: return coverageDays > AthleteSpan.quarter.rawValue
            }
        }
    }

    private var activeSpan: AthleteSpan {
        if let span, spans.contains(span) { return span }
        return spans.contains(.quarter) ? .quarter : .month
    }

    private var shown: [PFAthletePoint] {
        guard let last = tile.series.last else { return [] }
        let cutoff = PFFormat.addDays(last.date, -activeSpan.rawValue)
        return tile.series.filter { $0.date >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFRevealBar()
                    headerCard
                    if !tile.rows.isEmpty { relatedCard }
                    if tile.hasSeries && !isHidden { historyCard }
                    if standingMetric != nil { standingCard }
                    PFCard("What it is", icon: "questionmark.circle") {
                        VStack(alignment: .leading, spacing: 8) {
                            PFParagraph(tile.what)
                            Text("Source: \(tile.source)")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(tile.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("athlete-metric-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showStanding) {
            if let metric = standingMetric {
                PFStandingMetricSheet(metric: metric, plan: standing?.plan(metric.planId))
            }
        }
        .sheet(isPresented: $showPlan) {
            if let metric = standingMetric, let plan = standing?.plan(metric.planId) {
                PFStandingPlanSheet(plan: plan)
            }
        }
        .containerIdentifier("athlete-metric-sheet")
    }

    private var headerCard: some View {
        PFCard(tile.label, icon: "gauge.with.dots.needle.33percent") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isHidden ? PFRedact.placeholder : tile.valueText)
                        .font(LookFont.numeral(44))
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !isHidden && !tile.unit.isEmpty {
                        Text(tile.unit).font(LookFont.text(15, weight: .semibold)).foregroundStyle(NoopLook.textTertiary)
                    }
                }
                if let change = tile.change, !isHidden {
                    HStack(spacing: 6) {
                        Image(systemName: AthleteLook.symbol(change.direction))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AthleteLook.tone(change))
                        Text(tile.changeText ?? "").font(LookFont.text(14, weight: .medium)).foregroundStyle(NoopLook.textSecondary)
                    }
                }
                if let dated = tile.datedText {
                    Text(dated.prefix(1).uppercased() + dated.dropFirst()).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityIdentifier("athlete-metric-header")
    }

    /// The figures of the same family (Garmin's VO2max beside the one from the runs, the threshold's pace and heart rate), each with its own
    /// source and date.
    private var relatedCard: some View {
        PFCard("Related figures", icon: "list.bullet") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(tile.rows) { row in AthleteFigureRow(label: row.label, value: row.text, note: row.note) }
            }
        }
        .accessibilityIdentifier("athlete-metric-rows")
    }

    private var historyCard: some View {
        PFCard("History", icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 12) {
                if spans.count > 1 {
                    Picker("Range", selection: Binding(get: { activeSpan }, set: { span = $0 })) {
                        ForEach(spans) { option in Text(option.title).tag(option) }
                    }
                    .pickerStyle(.segmented)
                }
                Chart {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", PFFormat.date(point.date)), y: .value(tile.label, point.value))
                            .foregroundStyle(PFColor.sky)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(StrandPalette.hairline)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(StrandPalette.hairline)
                        AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .frame(height: 180)
                .accessibilityIdentifier("athlete-metric-chart")
            }
        }
    }

    @ViewBuilder private var standingCard: some View {
        if let metric = standingMetric {
            PFCard("Where you stand", icon: "chart.bar.xaxis", info: PFExplainerID.standing) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        PFChip(text: metric.bandName, color: PFBandColor.color(for: metric.band))
                        if metric.isLowConfidence { PFChip(text: "low confidence", color: StrandPalette.textTertiary) }
                    }
                    PFBandBar(band: metric.band, height: 10)
                    HStack(spacing: 10) {
                        Button { showStanding = true } label: { Label("Norms and source", systemImage: "tablecells") }
                            .buttonStyle(.bordered)
                            .tint(StrandPalette.accent)
                            .accessibilityIdentifier("athlete-metric-norms")
                        if standing?.plan(metric.planId) != nil {
                            Button { showPlan = true } label: { Label("What moves it", systemImage: "list.bullet.clipboard") }
                                .buttonStyle(.bordered)
                                .tint(StrandPalette.accent)
                                .accessibilityIdentifier("athlete-metric-plan")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Race predictions, heart-rate zones, records

/// One labelled figure with its source line, as on the detail pages.
private struct AthleteFigureRow: View {
    let label: String
    let value: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                if let note, !note.isEmpty {
                    Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(LookFont.numeral(18))
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct AthletePredictionsCard: View {
    let predictions: PFAthletePredictions
    let onTap: () -> Void

    private var shown: [PFAthletePrediction] { predictions.garmin.isEmpty ? predictions.model : predictions.garmin }

    private var caption: String {
        if predictions.garmin.isEmpty { return "PaceForge's own forecast, from your runs" }
        guard let date = predictions.garminDate else { return "Garmin's forecast" }
        return "Garmin's forecast \u{00B7} as of " + PFFormat.shortDate(date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Race predictions").lookCaps(10.5, weight: .semibold).foregroundStyle(NoopLook.textTertiary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(shown) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                                .font(LookFont.numeral(20))
                                .foregroundStyle(NoopLook.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(item.label).lookCaps(10, weight: .semibold).foregroundStyle(NoopLook.textTertiary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(caption)
                    .font(LookFont.text(11, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AthleteLook.cardShape.fill(NoopLook.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlete-predictions")
    }
}

private struct AthleteZonesCard: View {
    let zones: PFAthleteZones
    let onTap: () -> Void

    private var caption: String {
        var text = "Garmin "
        if let sport = zones.sport { text += sport.lowercased() + " " }
        text += "zones, beats per minute"
        if let date = zones.date { text += " \u{00B7} as of " + PFFormat.shortDate(date) }
        return text
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Heart-rate zones").lookCaps(10.5, weight: .semibold).foregroundStyle(NoopLook.textTertiary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                HStack(alignment: .top, spacing: 6) {
                    ForEach(zones.zones) { zone in
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(PFColor.sky.opacity(0.2 + 0.16 * Double(zone.zone)))
                                .frame(height: 6)
                            Text("\(zone.low)\u{2013}\(zone.high)")
                                .font(LookFont.numeral(13))
                                .foregroundStyle(NoopLook.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("Z\(zone.zone)").lookCaps(10, weight: .semibold).foregroundStyle(NoopLook.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(caption)
                    .font(LookFont.text(11, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AthleteLook.cardShape.fill(NoopLook.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlete-zones")
    }
}

private struct AthleteRecordsCard: View {
    let records: [PFAthleteRecord]

    private func line(_ record: PFAthleteRecord) -> String {
        let source = PFFormat.capitalized(record.source)
        guard let date = record.date else { return source }
        return source + ", " + PFFormat.shortDate(date)
    }

    var body: some View {
        PFCard("Personal records", icon: "trophy") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(records) { record in AthleteFigureRow(label: record.label, value: record.text, note: line(record)) }
            }
        }
        .containerIdentifier("athlete-records")
    }
}

private struct AthletePredictionsSheet: View {
    let predictions: PFAthletePredictions
    @Environment(\.dismiss) private var dismiss

    private func paceNote(_ item: PFAthletePrediction) -> String? {
        item.paceSecPerKm.map { PFFormat.pace($0) + " /km" }
    }

    /// Pace and confidence on one line; nil (no caption drawn) when the forecast has neither.
    private func modelNote(_ item: PFAthletePrediction) -> String? {
        let parts = [paceNote(item), item.confidence.map { "confidence " + $0.lowercased() }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !predictions.garmin.isEmpty { garminCard }
                    if !predictions.model.isEmpty { modelCard }
                    PFCard("What it is", icon: "questionmark.circle") {
                        PFParagraph("An estimate of the finish time your current fitness points to. Garmin's comes from the watch; PaceForge's is its own model, worked out from your runs. They are shown apart and never averaged, and neither is a promise. PaceForge holds only the latest forecast of each, so no change over time is shown.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Race predictions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("athlete-predictions-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .containerIdentifier("athlete-predictions-sheet")
    }

    private var garminCard: some View {
        PFCard("Garmin forecast", icon: "applewatch") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(predictions.garmin) { item in AthleteFigureRow(label: item.label, value: item.text, note: paceNote(item)) }
                if let date = predictions.garminDate {
                    Text("As of " + PFFormat.shortDate(date)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private var modelCard: some View {
        PFCard("PaceForge forecast", icon: "function") {
            VStack(alignment: .leading, spacing: 12) {
                if let vdot = predictions.vdot {
                    Text("VDOT " + PFFormat.oneDecimal(vdot)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(predictions.model) { item in
                    AthleteFigureRow(label: item.label, value: item.text, note: modelNote(item))
                }
            }
        }
    }
}

private struct AthleteZonesSheet: View {
    let zones: PFAthleteZones
    @Environment(\.dismiss) private var dismiss

    private func bpm(_ value: Double) -> String { String(format: "%.0f", value) + " bpm" }

    private var sourceLine: String {
        var text = "Garmin "
        if let sport = zones.sport { text += sport.lowercased() + " " }
        text += "zones"
        if let date = zones.date { text += ", as of " + PFFormat.shortDate(date) }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFCard("Zones", icon: "heart") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(zones.zones) { zone in
                                AthleteFigureRow(label: "Zone \(zone.zone)", value: "\(zone.low) to \(zone.high) bpm", note: nil)
                            }
                            Text(sourceLine)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    .accessibilityIdentifier("athlete-zones-table")
                    if zones.ltHr != nil || zones.maxHr != nil || zones.maxHrSeen != nil || zones.restingHr != nil { referenceCard }
                    PFCard("What it is", icon: "questionmark.circle") {
                        PFParagraph("Five heart-rate bands from your watch, from easy to maximal. The maximum above is the one the watch is set to; the highest heart rate it saw in recent activities is shown apart, because the two differ. PaceForge keeps the last zones it received if a sync fails, so check the date.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Heart-rate zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("athlete-zones-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .containerIdentifier("athlete-zones-sheet")
    }

    private var referenceCard: some View {
        PFCard("Reference points", icon: "scope") {
            VStack(alignment: .leading, spacing: 12) {
                if let ltHr = zones.ltHr { AthleteFigureRow(label: "Lactate threshold", value: bpm(ltHr), note: "Garmin watch") }
                if let maxHr = zones.maxHr { AthleteFigureRow(label: "Maximum, as set", value: bpm(maxHr), note: "Garmin zone setting") }
                if let seen = zones.maxHrSeen { AthleteFigureRow(label: "Highest seen", value: bpm(seen), note: "Garmin, recent activities") }
                if let resting = zones.restingHr { AthleteFigureRow(label: "Resting", value: bpm(resting), note: "Garmin watch") }
            }
        }
    }
}

// MARK: - HYROX detail

private struct AthleteHyroxSheet: View {
    let card: PFHyroxFinishCard?
    let hyrox: PFHyrox?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFRevealBar()
                    projectionCard
                    if let card, !card.races.isEmpty { racesCard(card) }
                    if let stations = hyrox?.stations, !stations.isEmpty { stationsCard(stations) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("HYROX projection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("athlete-hyrox-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .containerIdentifier("athlete-hyrox-sheet")
    }

    private var projectionCard: some View {
        PFCard("Predicted finish", icon: "target") {
            VStack(alignment: .leading, spacing: 8) {
                Text(card?.finish.central ?? hyrox?.predicted ?? "\u{2014}")
                    .font(LookFont.numeral(44))
                    .foregroundStyle(NoopLook.textPrimary)
                if let low = card?.finish.low, let high = card?.finish.high {
                    Text("Range \(low) to \(high)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if let goal = card?.finish.goal {
                    PFChip(text: "Goal \(goal)" + (card?.finish.gapText.map { " \u{00B7} \($0)" } ?? ""), color: PFColor.warning)
                }
                if let method = card?.finish.method {
                    PFParagraph(method.prefix(1).uppercased() + method.dropFirst() + ".")
                } else if let basis = hyrox?.basis {
                    PFParagraph(basis)
                }
            }
        }
    }

    private func racesCard(_ card: PFHyroxFinishCard) -> some View {
        PFCard("Your last races", icon: "flag.checkered") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(card.races.reversed()) { race in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(race.label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Text(race.date).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Text(race.display).font(LookFont.numeral(18)).foregroundStyle(NoopLook.textPrimary)
                        if race.isPersonalBest { PFChip(text: "Best", color: PFColor.positive) }
                    }
                }
            }
        }
    }

    private func stationsCard(_ stations: [PFStation]) -> some View {
        PFCard("Stations furthest from the top 3", icon: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(stations) { station in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Text("You \(station.athlete) \u{00B7} top 3 average \(station.top3)")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Text(PFNumber.signed(station.gapSec, decimals: 0) + " s")
                            .font(LookFont.numeral(16))
                            .foregroundStyle(NoopLook.textSecondary)
                    }
                }
            }
        }
    }
}
#endif
