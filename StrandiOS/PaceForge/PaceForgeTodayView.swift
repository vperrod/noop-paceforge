import SwiftUI
import StrandDesign

/// PaceForge "Today": its own recovery / strain / sleep, the push-today verdict, the day's sessions.
struct PFTodayView: View {
    let snapshot: PFSnapshot

    private var today: PFToday { snapshot.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            scoresCard
            verdictCard
            sessionsSection
            briefCard
            if let race = today.nextRace { raceCard(race) }
        }
    }

    // MARK: Scores

    private var scoresCard: some View {
        PFCard("Today", icon: "heart.fill") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    PFRing(value: today.recovery.score, maxValue: 100, color: StrandPalette.chargeColor,
                           display: String(Int(today.recovery.score.rounded())),
                           title: "Recovery", caption: today.recovery.confidence)
                    PFRing(value: today.strain.value, maxValue: 21, color: StrandPalette.effortColor,
                           display: PFFormat.oneDecimal(today.strain.value),
                           title: "Strain", caption: strainTarget)
                    PFRing(value: today.sleep.score, maxValue: 100, color: StrandPalette.restColor,
                           display: String(Int(today.sleep.score.rounded())),
                           title: "Sleep", caption: sleepNeed)
                }
                if let summary {
                    Divider().overlay(StrandPalette.hairline)
                    Text(summary)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private var strainTarget: String? {
        guard let lo = today.strain.targetLow, let hi = today.strain.targetHigh else { return nil }
        return "target \(Int(lo))\u{2013}\(Int(hi))"
    }

    private var sleepNeed: String? {
        guard let hours = today.sleep.hoursText, let need = today.sleep.needText else { return nil }
        return "\(hours) of \(need)"
    }

    private var summary: String? {
        let word = PFFormat.capitalized(today.verdict.word)
        guard let pct = today.sleep.sufficiencyPct else { return word }
        return "\(word) \u{00B7} " + (pct < 100 ? "sleep was short" : "sleep met your need")
    }

    // MARK: Verdict

    private var verdictCard: some View {
        PFCard("Should you push today?") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(verdictGlyph)
                        .font(StrandFont.rounded(18))
                    Text(PFFormat.capitalized(today.verdict.word))
                        .font(StrandFont.title2)
                }
                .foregroundStyle(verdictColor)
                if let advice = today.verdict.advice { PFParagraph(advice) }

                ForEach(Array((today.verdict.signals ?? []).enumerated()), id: \.offset) { _, s in
                    Divider().overlay(StrandPalette.hairline)
                    PFSignalRow(signal: s)
                }
                if let g = today.verdict.garmin, g.hold == true {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{25C7}").foregroundStyle(PFColor.warning)
                        Text("Garmin says \(g.reason ?? "hold")")
                            .font(StrandFont.subhead)
                            .foregroundStyle(PFColor.warning)
                    }
                }
            }
        }
    }

    private var verdictGlyph: String {
        switch today.verdict.word {
        case "primed": return "\u{25B2}"
        case "strained": return "\u{25BC}"
        case "rundown": return "\u{25BC}\u{25BC}"
        default: return "\u{25C6}"
        }
    }

    private var verdictColor: Color {
        switch today.verdict.word {
        case "primed": return PFColor.positive
        case "strained": return PFColor.warning
        case "rundown": return PFColor.critical
        default: return StrandPalette.accent
        }
    }

    // MARK: Sessions

    @ViewBuilder private var sessionsSection: some View {
        let sessions = today.sessions ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today's training", systemImage: "calendar")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                if !sessions.isEmpty {
                    let done = sessions.filter { $0.status == "done" || $0.status == "partial" }.count
                    Text("\(sessions.count) session\(sessions.count > 1 ? "s" : "")" + (done > 0 ? " \u{00B7} \(done) done" : ""))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            if sessions.isEmpty {
                PFCard("Nothing scheduled") {
                    PFParagraph("Enjoy the rest day \u{2014} recovery is training.")
                }
            } else {
                ForEach(sessions) { PFWorkoutRow(workout: $0) }
            }
        }
    }

    // MARK: Brief + race

    @ViewBuilder private var briefCard: some View {
        if let headline = today.briefHeadline {
            PFCard("Coach's morning read", icon: "sparkles") {
                Text(headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func raceCard(_ race: PFNextRace) -> some View {
        PFCard("Next race", icon: "flag.checkered") {
            HStack(alignment: .center, spacing: 18) {
                VStack(spacing: 0) {
                    Text("\(race.daysOut)")
                        .font(StrandFont.rounded(40))
                        .foregroundStyle(StrandPalette.accent)
                    Text("days")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(race.name)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PFFormat.dayTitle(race.date) + (race.goalTime.map { " \u{00B7} goal \($0)" } ?? ""))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: Pieces

private struct PFRing: View {
    let value: Double
    let maxValue: Double
    let color: Color
    let display: String
    let title: String
    let caption: String?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(value / maxValue, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(display)
                    .font(StrandFont.rounded(24))
                    .foregroundStyle(color)
            }
            .frame(width: 80, height: 80)
            Text(title).strandOverline()
            if let caption {
                Text(caption)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(display)")
    }
}

private struct PFSignalRow: View {
    let signal: PFSignal

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(glyph)
                .font(StrandFont.rounded(13))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.label)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let evidence = signal.evidence {
                    Text(evidence)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = signal.detail {
                    Text(detail)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var glyph: String {
        switch signal.flag {
        case "good": return "\u{25B2}"
        case "watch": return "\u{25C7}"
        case "bad": return "\u{25BC}"
        default: return "\u{25C6}"
        }
    }

    private var color: Color {
        switch signal.flag {
        case "good": return PFColor.positive
        case "watch": return PFColor.warning
        case "bad": return PFColor.critical
        default: return StrandPalette.textTertiary
        }
    }
}
