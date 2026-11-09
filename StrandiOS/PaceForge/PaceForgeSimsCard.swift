import SwiftUI
import StrandDesign

/// PaceForge Insights: the latest HYROX race simulation against the goal, its 8 run and 8 station
/// splits against the goal and the previous simulation, run fade, compromised runs, the pacing check and
/// the two stations to work on. Deltas are signed numbers in neutral colours: faster or slower is not
/// good or bad on its own here. A simulation is logged from the button under the card (PaceForgeSimLogSheet.swift).
struct PFSimulationsCard: View {
    let sims: PFHyroxSims

    private var hasShownData: Bool { sims.hasData && (sims.latest != nil || !sims.segments.isEmpty) }

    var body: some View {
        PFCard(title: "Race simulations", icon: "stopwatch", info: PFExplainerID.raceSims, trailing: {
            if sims.count > 0 {
                Text("\(sims.count) logged")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                if hasShownData {
                    if let latest = sims.latest { totalBlock(latest) }
                    if let fresh = sims.freshRun { freshRunLine(fresh) }
                    if let latest = sims.latest { fadeBlock(latest) }
                    if !sims.segments.isEmpty { splitsTable }
                    if !sims.weakest.isEmpty { weakestBlock }
                    if let note = sims.note { PFParagraph(note) }
                } else {
                    emptyBlock
                }
                if sims.unmappedCount > 0 { unmappedNote }
                PFSimLogButton()
            }
        }
        .containerIdentifier("pf-sims-card")
    }

    // MARK: Empty state

    private var emptyBlock: some View {
        Text("No simulation logged yet.")
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(StrandPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("pf-sims-empty")
    }

    private var unmappedNote: some View {
        let count = sims.unmappedCount
        let text: String = count == 1 ? "1 Garmin race simulation could not be split into stations yet."
                                      : "\(count) Garmin race simulations could not be split into stations yet."
        return Label(text, systemImage: "questionmark.circle")
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("pf-sims-unmapped")
    }

    // MARK: Total against the goal

    private func totalBlock(_ latest: PFHyroxSims.Latest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latest.totalDisplay ?? latest.totalSeconds.map { PFSimFormat.clock($0) } ?? "\u{2013}")
                    .font(StrandFont.rounded(34))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityIdentifier("pf-sims-total")
                Text(latest.date.map { "simulation on \(PFFormat.dayTitle($0))" } ?? "latest simulation")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            HStack(spacing: 8) {
                if let goal = sims.goal, let display = goal.goalDisplay ?? goal.goalSeconds.map({ PFSimFormat.clock($0) }) {
                    PFChip(text: "Goal \(display)", color: StrandPalette.textSecondary)
                    if let delta = sims.totalVsGoalS {
                        PFChip(text: PFSimFormat.signed(delta) + " vs goal", color: StrandPalette.accent)
                            .accessibilityIdentifier("pf-sims-vs-goal")
                    }
                }
                if !latest.complete { PFChip(text: "Incomplete", color: StrandPalette.textTertiary) }
            }
            if let goal = sims.goal, let basis = goal.basis {
                Text(basis)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notes = latest.notes { PFParagraph(notes) }
        }
    }

    private func freshRunLine(_ fresh: PFHyroxSims.FreshRun) -> some View {
        Group {
            if let text = freshRunText(fresh) {
                Text(text)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func freshRunText(_ fresh: PFHyroxSims.FreshRun) -> String? {
        guard let pace = fresh.display ?? fresh.paceSec.map({ PFFormat.pace($0) }) else { return nil }
        var text = "Fresh run pace \(pace)/km"
        if let runs = fresh.nRuns { text += " from \(runs) run" + (runs == 1 ? "" : "s") }
        if let basis = fresh.basis { text += ". \(basis)" }
        return text
    }

    // MARK: Run fade, compromised runs, pacing

    private func fadeBlock(_ latest: PFHyroxSims.Latest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                if let fade = latest.runFadePct {
                    PFFigure(value: PFSimFormat.signedPct(fade), unit: nil, label: "Run fade")
                        .accessibilityIdentifier("pf-sims-fade")
                }
                if let compromised = latest.compromisedPct {
                    PFFigure(value: PFSimFormat.signedPct(compromised), unit: nil, label: "Compromised runs")
                        .accessibilityIdentifier("pf-sims-compromised")
                }
                if let deviation = latest.maxDevPct {
                    PFFigure(value: PFSimFormat.signedPct(deviation), unit: nil, label: "Biggest pacing drift")
                }
            }
            if !latest.compromisedRuns.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(latest.compromisedRuns) { run in
                        Text(compromisedText(run))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .containerIdentifier("pf-sims-compromised-runs")
            }
            if let within = latest.withinBand {
                HStack(alignment: .top, spacing: 8) {
                    PFChip(text: within ? "Within the 5 % band" : "Outside the 5 % band",
                           color: StrandPalette.textSecondary)
                        .accessibilityIdentifier("pf-sims-band")
                    if let note = latest.pacingNote {
                        Text(note)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if let note = latest.pacingNote {
                PFParagraph(note)
            }
        }
    }

    private func compromisedText(_ run: PFHyroxSims.CompromisedRun) -> String {
        var text = "Run \(run.run)"
        if let seconds = run.seconds { text += " \u{00B7} " + PFSimFormat.clock(seconds) }
        if let pct = run.pctSlower { text += " \u{00B7} " + PFSimFormat.signedPct(pct) + " slower" }
        return text
    }

    // MARK: Splits

    private var splitsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Split").strandOverline().frame(maxWidth: .infinity, alignment: .leading)
                Text("Time").strandOverline().frame(width: 52, alignment: .trailing)
                Text("vs goal").strandOverline().frame(width: 56, alignment: .trailing)
                Text("vs last").strandOverline().frame(width: 56, alignment: .trailing)
            }
            .padding(.bottom, 6)
            ForEach(sims.segments) { segment in
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: segment.isRun ? "figure.run" : "dumbbell")
                            .font(.system(size: 11))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 14)
                        Text(segment.name)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    cell(time(segment), width: 52, strong: true)
                    cell(delta(segment.deltaGoalS ?? difference(segment.simSeconds, segment.goalSeconds)), width: 56)
                    cell(delta(segment.deltaPrevS ?? difference(segment.simSeconds, segment.prevSeconds)), width: 56)
                }
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
                .containerIdentifier("pf-sims-row-\(segment.index)")
                if segment.id != sims.segments.last?.id { Divider().overlay(StrandPalette.hairline) }
            }
        }
        .containerIdentifier("pf-sims-table")
    }

    private func cell(_ text: String, width: CGFloat, strong: Bool = false) -> some View {
        Text(text)
            .font(StrandFont.caption.weight(strong ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(strong ? StrandPalette.textPrimary : StrandPalette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, alignment: .trailing)
    }

    private func time(_ segment: PFHyroxSims.Segment) -> String {
        segment.display ?? segment.simSeconds.map { PFSimFormat.clock($0) } ?? "\u{2013}"
    }

    private func difference(_ sim: Double?, _ other: Double?) -> Double? {
        guard let sim, let other else { return nil }
        return sim - other
    }

    private func delta(_ seconds: Double?) -> String {
        seconds.map { PFSimFormat.signed($0) } ?? "\u{2013}"
    }

    // MARK: Weakest stations

    private var weakestBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where the time is").strandOverline()
            ForEach(Array(sims.weakest.prefix(2))) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.station)
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 8)
                        Text(weakFigures(item))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let suggestion = item.suggestion { PFParagraph(suggestion) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
                .accessibilityElement(children: .combine)
                .containerIdentifier("pf-sims-weak-\(item.id)")
            }
        }
    }

    private func weakFigures(_ item: PFHyroxSims.Weak) -> String {
        var bits: [String] = []
        if let display = item.display ?? item.simSeconds.map({ PFSimFormat.clock($0) }) { bits.append(display) }
        if let over = item.overS { bits.append(PFSimFormat.signed(over) + " vs goal") }
        if let pct = item.overPct { bits.append(PFSimFormat.signedPct(pct)) }
        return bits.joined(separator: " \u{00B7} ")
    }
}
