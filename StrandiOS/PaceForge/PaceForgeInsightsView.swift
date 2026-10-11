import SwiftUI
import Charts
import StrandDesign

/// PaceForge "Insights": fitness / fatigue / form, load warnings, race cards, HYROX prognosis.
struct PFInsightsView: View {
    let snapshot: PFSnapshot
    @State private var showOtherRaces = false

    private var insights: PFInsights { snapshot.insights }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartCard
            warningsCard
            racesSection
            prognosisCard
        }
    }

    // MARK: Load chart

    private var chartCard: some View {
        PFCard("Fitness, fatigue and form", icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PFFigure(value: String(Int(insights.ctl.rounded())), unit: nil, label: "Fitness (CTL)")
                    PFFigure(value: String(Int(insights.atl.rounded())), unit: nil, label: "Fatigue (ATL)")
                    PFFigure(value: signed(insights.tsb), unit: nil, label: "Form (TSB)")
                }
                PFLoadChart(insights: insights)
                    .frame(height: 220)
                    .accessibilityIdentifier("pf-load-chart")
                HStack(spacing: 14) {
                    legend(StrandPalette.chargeColor, "Fitness")
                    legend(StrandPalette.effortColor, "Fatigue")
                    legend(StrandPalette.restColor, "Form")
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
        let r = Int(v.rounded())
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

    // MARK: Prognosis

    @ViewBuilder private var prognosisCard: some View {
        if let hyrox = insights.hyrox {
            PFCard("HYROX prognosis", icon: "target") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(hyrox.predicted)
                            .font(StrandFont.rounded(34))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("predicted finish")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if let basis = hyrox.basis {
                        PFParagraph(basis + (hyrox.trend.map { " Trend: \($0)." } ?? ""))
                    }
                    if let goal = insights.goalPrognosis {
                        HStack(spacing: 8) {
                            PFChip(text: "Goal \(PFFormat.clock(goal.goalSec)) \u{00B7} \(goal.verdict)", color: PFColor.warning)
                            Text("Running shape \(PFFormat.clock(goal.prognosisSec))")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    if let stations = hyrox.stations, !stations.isEmpty {
                        Text("Where the time is").strandOverline()
                        ForEach(stations) { s in
                            HStack(alignment: .firstTextBaseline) {
                                Text(s.name)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Spacer(minLength: 8)
                                Text("\(s.athlete) vs \(s.top3)")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                Text("+\(Int(s.gapSec)) s")
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(PFColor.warning)
                                    .frame(minWidth: 50, alignment: .trailing)
                            }
                        }
                    }
                    if let sentence = hyrox.sentence { PFParagraph(sentence) }
                }
            }
        }
    }
}

private struct PFRaceCard: View {
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
            series("ctl", StrandPalette.chargeColor, false, hist, \.ctl),
            series("atl", StrandPalette.effortColor, false, hist, \.atl),
            series("tsb", StrandPalette.restColor, false, hist, \.tsb),
            series("ctl-p", StrandPalette.chargeColor, true, proj, \.ctl),
            series("atl-p", StrandPalette.effortColor, true, proj, \.atl),
            series("tsb-p", StrandPalette.restColor, true, proj, \.tsb),
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
