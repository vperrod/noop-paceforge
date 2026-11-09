import SwiftUI
import Charts
import StrandDesign

/// PaceForge "Insights": fitness / fatigue / form, load warnings, race cards, his HYROX races.
struct PFInsightsView: View {
    let snapshot: PFSnapshot
    /// False under the Insights tab's Deep dives chip (New navigation, beta), where "Where you stand" and the insight items are
    /// on the Overview chip instead.
    var includesOverview = true
    @State private var showOtherRaces = false

    private var insights: PFInsights { snapshot.insights }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if includesOverview, let standing = snapshot.standing, standing.hasContent {
                PFDismissable(.standing, text: PFCardText.standing(standing), snapshot: snapshot) {
                    PFStandingInsightsCard(standing: standing)
                }
            }
            if includesOverview, let insights = snapshot.insightsV2, insights.hasContent { PFInsightsV2Section(doc: insights) }
            chartCard
            PFLoadPanels(insights: insights)
            warningsCard
            if let impact = snapshot.behaviour {
                PFDismissable(.behaviour, text: PFCardText.behaviour(impact), snapshot: snapshot) {
                    PFBehaviourCard(impact: impact)
                }
            }
            racesSection
            runningGoalCard
            hyroxCard
            if let sims = snapshot.simulations { PFSimulationsCard(sims: sims) }
            PFHowScoresWorkCard(explainers: snapshot.explainers)
        }
        // The batch D cards (weekly stress load, active hours) draw from this store; it is loaded here, on the screen that is always there.
        .task { await PFBatchDStore.shared.refreshIfStale() }
    }

    // MARK: Load chart

    private var chartCard: some View {
        PFCard("Fitness, fatigue and form", icon: "chart.xyaxis.line", info: PFExplainerID.load) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PFFigure(value: String(Safe.int(insights.ctl)), unit: nil, label: "Fitness (CTL)")
                    PFFigure(value: String(Safe.int(insights.atl)), unit: nil, label: "Fatigue (ATL)")
                    PFFigure(value: signed(insights.tsb), unit: nil, label: "Form (TSB)")
                }
                PFLoadChart(insights: insights)
                    .frame(height: 220)
                    .accessibilityIdentifier("pf-load-chart")
                HStack(spacing: 14) {
                    legend(PFColor.positive, "Fitness")
                    legend(PFColor.warning, "Fatigue")
                    legend(PFColor.violet, "Form")
                    Text("Dashed = projected")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if let sentence = insights.loadSentence { PFParagraph(sentence) }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func signed(_ v: Double) -> String {
        let r = Safe.int(v)
        return r > 0 ? "+\(r)" : "\(r)"
    }

    // MARK: Warnings

    @ViewBuilder private var warningsCard: some View {
        let warnings = insights.warnings ?? []
        if !warnings.isEmpty {
            PFCard("Load and recovery warnings", icon: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{25B2}")
                                .font(StrandFont.caption)
                                .foregroundStyle(PFColor.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PFFormat.dayTitle(w.date))
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                                Text(w.text)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Races

    @ViewBuilder private var racesSection: some View {
        if let first = insights.races.first {
            VStack(alignment: .leading, spacing: 10) {
                PFRaceCard(race: first)
                let rest = Array(insights.races.dropFirst())
                if !rest.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showOtherRaces.toggle() }
                    } label: {
                        Text(showOtherRaces ? "Hide other races" : "+\(rest.count) more race\(rest.count > 1 ? "s" : "")")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf-more-races")
                    if showOtherRaces {
                        ForEach(rest) { PFRaceCard(race: $0) }
                    }
                }
            }
        }
    }

    // MARK: Running goal and HYROX

    /// The running shape against a road-race goal. A HYROX goal has none (the server answers "not a running goal").
    @ViewBuilder private var runningGoalCard: some View {
        if let goal = insights.goalPrognosis {
            PFCard("Running goal", icon: "target") {
                HStack(spacing: 8) {
                    PFChip(text: "Goal \(PFFormat.clock(goal.goalSec)) \u{00B7} \(goal.verdict)", color: PFColor.warning)
                    Text("Running shape \(PFFormat.clock(goal.prognosisSec))")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    /// His own HYROX races, where his time is, and the way into the HYROX screen. No predicted finish, no top 3, no field comparison.
    @ViewBuilder private var hyroxCard: some View {
        if !insights.hyroxRaces.isEmpty { PFHyroxSummaryCard(races: insights.hyroxRaces) }
    }
}

struct PFRaceCard: View {
    let race: PFRace

    var body: some View {
        PFCard(title: race.name, icon: "flag.checkered", trailing: {
            PFChip(text: "\(race.daysOut) days", color: tone)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(race.headline)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                PFParagraph(race.readiness)
            }
        }
    }

    private var tone: Color {
        race.taperOk == true ? PFColor.positive : race.daysOut <= 21 ? PFColor.warning : StrandPalette.accent
    }
}

/// CTL / ATL / TSB history (solid) with the planned projection (dashed) and race markers.
private struct PFLoadChart: View {
    let insights: PFInsights

    private struct Line: Identifiable {
        let id: String
        let color: Color
        let dashed: Bool
        let points: [(date: Date, value: Double)]
    }

    private var lines: [Line] {
        let hist = insights.history
        let bridge = hist.last.map { [$0] } ?? []
        let proj = bridge + insights.projection
        func series(_ id: String, _ color: Color, _ dashed: Bool, _ rows: [PFLoadPoint], _ key: KeyPath<PFLoadPoint, Double>) -> Line {
            Line(id: id, color: color, dashed: dashed, points: rows.map { (date: PFFormat.date($0.date), value: $0[keyPath: key]) })
        }
        return [
            series("ctl", PFColor.positive, false, hist, \.ctl),
            series("atl", PFColor.warning, false, hist, \.atl),
            series("tsb", PFColor.violet, false, hist, \.tsb),
            series("ctl-p", PFColor.positive, true, proj, \.ctl),
            series("atl-p", PFColor.warning, true, proj, \.atl),
            series("tsb-p", PFColor.violet, true, proj, \.tsb),
        ]
    }

    var body: some View {
        Chart {
            ForEach(lines) { line in
                ForEach(Array(line.points.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Date", p.date), y: .value("Load", p.value),
                             series: .value("Series", line.id))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: line.id == "ctl" || line.id == "ctl-p" ? 2.6 : 1.8,
                                               dash: line.dashed ? [5, 4] : []))
                }
            }
            ForEach(Array((insights.markers ?? []).enumerated()), id: \.offset) { _, m in
                RuleMark(x: .value("Race", PFFormat.date(m.date)))
                    .foregroundStyle(StrandPalette.textTertiary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
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
