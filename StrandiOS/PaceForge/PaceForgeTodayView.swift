import SwiftUI
import StrandDesign

/// PaceForge "Today": the daily coach briefing, PaceForge's own recovery / strain / sleep and the day's sessions.
struct PFTodayView: View {
    let snapshot: PFSnapshot

    private var today: PFToday { snapshot.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let brief = today.brief {
                PFBriefCard(brief: brief, todayISO: snapshot.todayISO)
            }
            if today.recovery != nil || today.strain != nil || today.sleep != nil { scoresCard }
            sessionsSection
            if let race = today.nextRace { raceCard(race) }
        }
    }

    // MARK: Scores

    private var scoresCard: some View {
        PFCard("Today", icon: "heart.fill") {
            HStack(alignment: .top, spacing: 8) {
                if let recovery = today.recovery {
                    PFRing(value: recovery.score, maxValue: 100, color: StrandPalette.chargeColor,
                           display: String(Int(recovery.score.rounded())),
                           title: "Recovery", caption: recovery.confidence)
                }
                if let strain = today.strain {
                    PFRing(value: strain.value, maxValue: 21, color: StrandPalette.effortColor,
                           display: PFFormat.oneDecimal(strain.value),
                           title: "Strain", caption: strainTarget(strain))
                }
                if let sleep = today.sleep {
                    PFRing(value: sleep.score, maxValue: 100, color: StrandPalette.restColor,
                           display: String(Int(sleep.score.rounded())),
                           title: "Sleep", caption: sleepNeed(sleep))
                }
            }
        }
    }

    private func strainTarget(_ strain: PFStrain) -> String? {
        guard let lo = strain.targetLow, let hi = strain.targetHigh else { return nil }
        return "target \(Int(lo))\u{2013}\(Int(hi))"
    }

    private func sleepNeed(_ sleep: PFSleep) -> String? {
        guard let hours = sleep.hoursText, let need = sleep.needText else { return nil }
        return "\(hours) of \(need)"
    }

    // MARK: Sessions

    @ViewBuilder private var sessionsSection: some View {
        let sessions = today.sessions
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today's sessions", systemImage: "calendar")
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
                ForEach(sessions) { PFWorkoutRow(workout: $0, snapshot: snapshot) }
            }
        }
    }

    // MARK: Race

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

// MARK: Daily briefing

/// The coach's daily briefing with every field the PaceForge web Today card renders. Dimmed and
/// labelled when it was written on an earlier day.
private struct PFBriefCard: View {
    let brief: PFDailyBrief
    let todayISO: String

    private var isToday: Bool { brief.date == todayISO }

    var body: some View {
        PFCard(title: "Daily briefing", icon: "sparkles", trailing: {
            if !isToday, let date = brief.date {
                PFChip(text: "from \(PFFormat.shortDate(date))", color: StrandPalette.textTertiary)
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(brief.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(brief.notes.enumerated()), id: \.offset) { _, note in
                    PFCallout(text: note, color: PFColor.warning, label: nil)
                }
                ForEach(Array(brief.outlook.enumerated()), id: \.offset) { _, paragraph in
                    PFParagraph(paragraph)
                }
                section("Your body today", brief.bodyState)
                section("Today's training", brief.training)
                section("The last few days", brief.recent)

                if !brief.focus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Focus").strandOverline()
                        ForEach(Array(brief.focus.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\u{2022}").foregroundStyle(StrandPalette.accent)
                                Text(item)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                ForEach(Array(brief.pulses.enumerated()), id: \.offset) { _, pulse in
                    PFCallout(text: pulse.text, color: PFColor.sky,
                              label: "Day pulse" + (PFFormat.relative(pulse.at).map { " \u{00B7} \($0)" } ?? ""))
                }
            }
        }
        .opacity(isToday ? 1 : 0.7)
        .accessibilityIdentifier("pf-brief-card")
    }

    @ViewBuilder private func section(_ title: String, _ markdown: String?) -> some View {
        if let markdown {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).strandOverline()
                PFMarkdown(text: markdown)
            }
        }
    }
}

private struct PFCallout: View {
    let text: String
    let color: Color
    let label: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                if let label { Text(label).strandOverline() }
                Text(text)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
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
