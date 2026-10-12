import SwiftUI
import StrandDesign

/// The Progress card at the top of PaceForge > Body: each goal against its pace, the day's one-liner, the
/// coach's note and the fuel, hydration, visceral and balance rows. Every part hides when its data is absent.
struct PFProgressCard: View {
    let progress: PFBodyProgress

    var body: some View {
        PFCard(title: "Progress", icon: "target", trailing: {
            if let date = progress.latestReadingDate {
                Text("Reading \(PFFormat.shortDate(date))")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                if let line = progress.dailyLine {
                    Text(line)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(progress.goals) { PFProgressGoalRow(goal: $0) }
                if progress.goals.isEmpty, let digest = progress.digest { PFParagraph(digest) }
                if let basis = progress.noiseBasis {
                    Text(basis)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let analysis = progress.analysis { analysisBlock(analysis) }
                detailRows
            }
        }
        .accessibilityIdentifier("pf-body-progress")
    }

    private func analysisBlock(_ analysis: PFProgressAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Coach analysis" + (analysis.generatedAt.map { " \u{00B7} \(PFFormat.shortDate($0))" } ?? ""))
                .strandOverline()
            PFMarkdown(text: analysis.text)
        }
    }

    @ViewBuilder private var detailRows: some View {
        let rows = detailItems
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(StrandPalette.hairline)
                ForEach(rows, id: \.title) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 8)
                            Text(row.value)
                                .font(StrandFont.subhead)
                                .foregroundStyle(row.flagged ? PFColor.warning : StrandPalette.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                        if let note = row.note {
                            Text(note)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private struct Row { var title: String; var value: String; var note: String?; var flagged = false }

    private var detailItems: [Row] {
        var out: [Row] = []
        if let fuel = progress.fuel {
            var value: [String] = []
            if let kcal = fuel.trainingDayKcal { value.append("\(Int(kcal.rounded())) kcal on a training day") }
            if let lo = fuel.proteinLow, let hi = fuel.proteinHigh {
                value.append("protein \(Int(lo.rounded()))\u{2013}\(Int(hi.rounded())) g")
            }
            if !value.isEmpty {
                out.append(Row(title: "Fuel", value: value.joined(separator: " \u{00B7} "),
                               note: fuel.trainingDayBasis ?? fuel.proteinBasis))
            }
        }
        if let hydration = progress.hydration, let flag = hydration.flag {
            let note = [hydration.reason, hydration.ownNormal.map { PFFormat.capitalized($0) }]
                .compactMap { $0 }.joined(separator: " ")
            out.append(Row(title: "Hydration", value: PFFormat.capitalized(PFFormat.words(flag)),
                           note: note.isEmpty ? nil : note, flagged: flag != "ok" && flag != "normal"))
        }
        if let visceral = progress.visceral, let value = visceral.value {
            let band = visceral.band.map { " \u{00B7} \(PFFormat.capitalized($0))" } ?? ""
            out.append(Row(title: "Visceral fat", value: PFFormat.trimmed(value) + band,
                           note: visceral.standardRange.map { "Standard range \($0)" }))
        }
        if let balance = progress.balance, balance.note != nil || balance.estimate == true {
            // Left and right are our estimate when the server says so; with no flag or a false one, no label.
            let value = [balance.estimate == true ? "Estimate" : nil,
                         balance.flag.map { PFFormat.capitalized(PFFormat.words($0)) }]
                .compactMap { $0 }.joined(separator: " \u{00B7} ")
            out.append(Row(title: "Balance", value: value,
                           note: balance.note, flagged: balance.flag != nil && balance.flag != "ok" && balance.flag != "balanced"))
        }
        return out
    }
}

private struct PFProgressGoalRow: View {
    let goal: PFProgressGoal
    @Environment(\.pfExplainers) private var explainers

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.label)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                PFChip(text: statusText, color: statusColor)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value(goal.current7d ?? goal.lastReading))
                    .font(StrandFont.rounded(26))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("7-day" + (goal.current7d == nil ? " (last reading)" : ""))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Text(targetLine)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(paceLine)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if goal.aggressive {
                Text("This target date asks for a faster pace than is usually sustainable.")
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func value(_ v: Double?) -> String {
        guard let v else { return "\u{2014}" }
        return PFFormat.oneDecimal(v) + (goal.unit.isEmpty ? "" : " \(goal.unit)")
    }

    private var targetLine: String {
        guard let target = goal.target else { return "No target set" }
        let date = goal.targetDate.map { " by \(PFFormat.shortDate($0))" } ?? ""
        return "Target \(value(target))\(date)"
    }

    private var paceLine: String {
        let needed = goal.neededPerWeek.map { "needs \(signed($0))/week" }
        let actual = goal.actualPerWeek.map { "now \(signed($0))/week" }
        let pace = [needed, actual].compactMap { $0 }.joined(separator: " \u{00B7} ")
        guard goal.actualPerWeek != nil else {
            // The explainer says how far along the metric is ("Day 2 of 5") when that is known.
            return (pace.isEmpty ? "" : pace + " \u{00B7} ") + (calibrationLine ?? "needs more readings for a pace")
        }
        let eta = goal.eta.map { " \u{00B7} on pace for \(PFFormat.shortDate($0))" } ?? ""
        return pace + eta
    }

    /// Body fat has its own trend calibration, weight its noise band; other goals have none.
    private var calibrationLine: String? {
        let id: String
        switch goal.metric {
        case "body_fat_pct": id = PFExplainerID.bodyFatTrend
        case "weight_kg": id = PFExplainerID.bodyNoiseBand
        default: return nil
        }
        guard let calibration = explainers[id]?.calibration, !calibration.ready else { return nil }
        return calibration.line
    }

    private func signed(_ v: Double) -> String {
        (v > 0 ? "+" : "") + PFFormat.oneDecimal(v) + (goal.unit.isEmpty ? "" : " \(goal.unit)")
    }

    private var statusText: String {
        switch goal.status {
        case "on_track": return "On track"
        case "ahead": return "Ahead"
        case "behind": return "Behind"
        default: return "Needs readings"
        }
    }

    private var statusColor: Color {
        switch goal.status {
        case "on_track", "ahead": return PFColor.positive
        case "behind": return PFColor.warning
        default: return StrandPalette.textTertiary
        }
    }
}
