import SwiftUI
import StrandDesign

/// PaceForge Body: whether weight changes look like fat or lean mass, from the scale's readings. Lean
/// trend and weekly change against the scale's noise, the 14 and 28 day split with its quality label,
/// the flag state, strength trend, the tape cross-check and the advice lines. Figures are signed numbers
/// in neutral colours; only a raised flag uses the warning tint.
struct PFMuscleCheckCard: View {
    let check: PFMuscleCheck

    var body: some View {
        PFCard(title: "Muscle check", icon: "figure.strengthtraining.traditional", info: PFExplainerID.muscleCheck, trailing: {
            HStack(spacing: 6) {
                if check.stale { PFChip(text: "Out of date", color: StrandPalette.textTertiary) }
                if let chip = flagChip { chip }
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                if check.hasData || check.isCalibrating {
                    if let lean = check.lean { leanBlock(lean) }
                    if let weight = check.weight { weightLine(weight) }
                    if !check.splits.isEmpty { splitBlock }
                    flagBlock
                    if let strength = check.strength, strength.hasData { strengthBlock(strength) }
                    if let cm = check.tapeWaistChange28dCm, check.tapeHasData { tapeLine(cm) }
                    if !check.advice.isEmpty { adviceBlock }
                    if let protein = check.proteinText {
                        Text("Protein target \(protein) a day")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .accessibilityIdentifier("pf-muscle-protein")
                    }
                } else {
                    PFParagraph("Not enough scale readings yet to compare lean mass and fat. Step on the scale a few times a week and this fills in.")
                }
            }
        }
        .pfCardID("pf-muscle-card")
    }

    // MARK: Flag

    private var flagChip: PFChip? {
        switch check.flagStatus {
        case "flag": return PFChip(text: "Flag raised", color: PFColor.warning)
        case "calibrating": return PFChip(text: "Calibrating", color: PFColor.sky)
        case "ok": return PFChip(text: "No flag", color: StrandPalette.textSecondary)
        default: return nil
        }
    }

    @ViewBuilder private var flagBlock: some View {
        if check.flagRaised || check.isCalibrating, let rule = check.flagRule {
            VStack(alignment: .leading, spacing: 3) {
                Text(check.isCalibrating ? "Calibrating" : "Why it is flagged").strandOverline()
                PFParagraph(rule)
            }
            .accessibilityIdentifier("pf-muscle-flag")
        }
    }

    // MARK: Lean trend

    private func leanBlock(_ lean: PFMuscleCheck.Lean) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 14) {
                if let now = lean.currentTrendKg { PFFigure(value: PFNumber.trimmedOne(now), unit: "kg", label: "Lean trend") }
                if let week = lean.perWeekKg {
                    let pctText: String = lean.perWeekPct.map { " (\(PFNumber.signed($0)) %)" } ?? ""
                    let unit: String = "kg/week" + pctText
                    PFFigure(value: PFNumber.signed(week), unit: unit, label: "Weekly change")
                }
                if let noise = lean.noiseKg { PFFigure(value: "\u{00B1}" + PFNumber.trimmedOne(noise), unit: "kg", label: "Noise band") }
                if let readings = lean.readings { PFFigure(value: "\(readings)", unit: nil, label: "Readings") }
                if let d14 = lean.change14dKg { PFFigure(value: PFNumber.signed(d14), unit: "kg", label: "14 days") }
                if let d28 = lean.change28dKg { PFFigure(value: PFNumber.signed(d28), unit: "kg", label: "28 days") }
            }
            .accessibilityIdentifier("pf-muscle-lean")
            if let basis = lean.noiseBasis {
                Text(basis)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weightLine(_ weight: PFMuscleCheck.WeightTrend) -> some View {
        var bits: [String] = []
        if let now = weight.currentTrendKg { bits.append("Weight trend \(PFNumber.trimmedOne(now)) kg") }
        if let week = weight.perWeekKg {
            bits.append(PFNumber.signed(week) + " kg/week" + (weight.perWeekPct.map { " (\(PFNumber.signed($0)) %)" } ?? ""))
        }
        return Group {
            if !bits.isEmpty {
                Text(bits.joined(separator: " \u{00B7} "))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    // MARK: 14 and 28 day split

    private var splitBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where the change came from").strandOverline()
            ForEach(check.splits) { split in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Last \(split.windowTitle)")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 8)
                        if let quality = split.quality {
                            PFChip(text: PFFormat.capitalized(quality),
                                   color: quality == "noisy" ? PFColor.warning : StrandPalette.textSecondary)
                                .accessibilityIdentifier("pf-muscle-quality-\(split.window)")
                        }
                    }
                    Text(splitText(split))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-muscle-split-\(split.window)")
            }
        }
    }

    private func splitText(_ split: PFMuscleCheck.Split) -> String {
        var bits: [String] = []
        if let weight = split.weightKg { bits.append("weight \(PFNumber.signed(weight)) kg") }
        if let lean = split.leanKg { bits.append("lean \(PFNumber.signed(lean)) kg") }
        if let fat = split.fatKg { bits.append("fat \(PFNumber.signed(fat)) kg") }
        if let share = split.leanSharePct { bits.append("lean share \(Int(share.rounded())) %") }
        return bits.joined(separator: " \u{00B7} ")
    }

    // MARK: Strength, tape, advice

    private func strengthBlock(_ strength: PFMuscleCheck.Strength) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Strength").strandOverline()
            if let measure = strength.measure {
                Text(strengthTitle(measure, strength))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            ForEach(Array(strength.patterns.enumerated()), id: \.offset) { _, pattern in
                Text(PFFormat.capitalized(PFFormat.words(pattern)))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            if let basis = strength.basis {
                Text(basis)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("pf-muscle-strength")
    }

    private func strengthTitle(_ measure: String, _ strength: PFMuscleCheck.Strength) -> String {
        var text = PFFormat.capitalized(PFFormat.words(measure))
        if let pct = strength.pct { text += " " + PFNumber.signed(pct) + " %" }
        if let direction = strength.direction { text += " \u{00B7} " + PFFormat.words(direction) }
        return text
    }

    private func tapeLine(_ cm: Double) -> some View {
        Label("Tape cross-check: waist \(PFNumber.signed(cm)) cm over 28 days", systemImage: "ruler")
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
            .accessibilityIdentifier("pf-muscle-tape")
    }

    private var adviceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(check.advice) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: line.severity == "act" || line.severity == "watch" ? "exclamationmark.circle" : "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text(line.text)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("pf-muscle-advice")
    }
}

/// PaceForge Body: the tape measurements you logged, the latest per site with the change over 28 days.
struct PFTapeCard: View {
    let tape: PFTape

    var body: some View {
        PFCard("Tape measurements", icon: "ruler", info: PFExplainerID.tape) {
            VStack(alignment: .leading, spacing: 14) {
                if tape.sites.isEmpty {
                    PFParagraph("No tape measurements yet.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tape.sites) { site in
                            row(site)
                            if site.id != tape.sites.last?.id { Divider().overlay(StrandPalette.hairline) }
                        }
                    }
                    .accessibilityIdentifier("pf-tape-sites")
                    if let ratio = tape.waistToHip { waistToHipLine(ratio) }
                }
                if let note = tape.note {
                    Text(note)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label(PFTelegramHint.tape, systemImage: "paperplane")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityIdentifier("pf-tape-hint")
            }
        }
        .pfCardID("pf-tape-card")
    }

    private func row(_ site: PFTape.Site) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let date = site.latestDate {
                    Text(PFFormat.shortDate(date))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(site.latest.map { PFNumber.trimmedOne($0) + " cm" } ?? "\u{2013}")
                    .font(StrandFont.rounded(18))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(changeText(site))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-tape-\(site.key)")
    }

    private func changeText(_ site: PFTape.Site) -> String {
        guard site.enough, let change = site.change28dCm else { return "needs more readings" }
        return "\(PFNumber.signed(change)) cm in 28 days"
    }

    private func waistToHipLine(_ ratio: PFTape.WaistToHip) -> some View {
        var bits: [String] = []
        if let value = ratio.ratio { bits.append(String(format: "%.2f", value)) }
        if let waist = ratio.waist, let hips = ratio.hips {
            bits.append("waist \(PFNumber.trimmedOne(waist)) \u{00F7} hips \(PFNumber.trimmedOne(hips))")
        }
        if let date = ratio.date { bits.append(PFFormat.shortDate(date)) }
        return VStack(alignment: .leading, spacing: 3) {
            Text("Waist-to-hip").strandOverline()
            Text(bits.joined(separator: " \u{00B7} "))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .accessibilityIdentifier("pf-tape-waist-hip")
    }
}
