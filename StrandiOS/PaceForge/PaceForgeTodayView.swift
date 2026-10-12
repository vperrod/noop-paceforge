import SwiftUI
import StrandDesign

/// PaceForge "Today": the daily coach briefing, PaceForge's own recovery / strain / sleep and the day's sessions.
struct PFTodayView: View {
    let snapshot: PFSnapshot
    /// Settings > Hide numbers: the three scores read "Hidden".
    @AppStorage(HideScoresPrefs.scoresKey) private var hideScores = false

    private var today: PFToday { snapshot.today }

    /// A card with the "Not today" corner menu; nothing while it is hidden.
    private func dismissable<Content: View>(_ kind: PFCardKind, _ text: String,
                                            @ViewBuilder _ content: () -> Content) -> some View {
        PFDismissable(kind, text: text, snapshot: snapshot, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dismissable(.todaySoFar, PFCardText.todaySoFar(snapshot)) { PFTodaySoFarCard(snapshot: snapshot) }
            if let mode = snapshot.easyMode?.mode { PFEasyModeChip(mode: mode) }
            if let week = snapshot.raceWeek {
                dismissable(.raceWeek, PFCardText.raceWeek(week)) { PFRaceWeekCard(week: week, todayISO: snapshot.todayISO) }
            }
            if let brief = today.brief {
                dismissable(.brief, PFCardText.brief(brief)) { PFBriefCard(brief: brief, todayISO: snapshot.todayISO) }
            }
            if let easy = snapshot.easyMode, !easy.isIdle {
                dismissable(.easyMode, PFCardText.easyMode(easy)) { PFEasyModeCard(easy: easy) }
            }
            if let feel = snapshot.feel {
                dismissable(.feel, PFCardText.feel(feel)) { PFFeelCard(feel: feel, todayISO: snapshot.todayISO) }
            }
            if !snapshot.alerts.isEmpty {
                dismissable(.alerts, PFCardText.alerts(snapshot.alerts)) { PFAlertsCard(alerts: snapshot.alerts) }
            }
            if showsScores { dismissable(.scores, PFCardText.scores(today)) { scoresCard } }
            if let changes = snapshot.whatChanged {
                dismissable(.whatChanged, PFCardText.whatChanged(changes)) { PFWhatChangedCard(changes: changes) }
            }
            if let readiness = snapshot.readiness {
                dismissable(.readiness, PFCardText.readiness(readiness)) { PFReadinessCard(readiness: readiness) }
            }
            if let standing = snapshot.standing, standing.hasContent {
                dismissable(.standing, PFCardText.standing(standing)) { PFStandingTodayCard(standing: standing) }
            }
            sessionsSection
            if let easy = snapshot.easyMode, easy.isIdle { PFEasyModeHint() }
            // In race week the race-week card above carries the countdown.
            if let race = today.nextRace, snapshot.raceWeek == nil {
                dismissable(.nextRace, PFCardText.nextRace(race)) { raceCard(race) }
            }
            PFHiddenCardsRow(snapshot: snapshot)
        }
    }

    // MARK: Scores

    /// A score that is missing because the engine is still calibrating shows its "Day 3 of 5" line
    /// where the ring would be, instead of nothing.
    private var recoveryCalibration: String? {
        today.recovery == nil ? snapshot.calibrationLine(PFExplainerID.recovery) : nil
    }
    private var strainCalibration: String? {
        today.strain == nil ? snapshot.calibrationLine(PFExplainerID.strain) : nil
    }

    private var showsScores: Bool {
        today.recovery != nil || today.strain != nil || today.sleep != nil
            || recoveryCalibration != nil || strainCalibration != nil
    }

    private var scoresCard: some View {
        PFCard("Today", icon: "heart.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    if let recovery = today.recovery {
                        PFRing(value: hideScores ? 0 : recovery.score, maxValue: 100, color: StrandPalette.chargeColor,
                               display: HideScoresPrefs.shown(String(Int(recovery.score.rounded())), hidden: hideScores),
                               title: "Recovery", caption: hideScores ? nil : recovery.confidence, info: PFExplainerID.recovery)
                    } else if let line = recoveryCalibration {
                        PFRing(value: 0, maxValue: 100, color: StrandPalette.chargeColor, display: "\u{2013}",
                               title: "Recovery", caption: line, info: PFExplainerID.recovery)
                    }
                    if let strain = today.strain {
                        PFRing(value: hideScores ? 0 : strain.value, maxValue: 21, color: StrandPalette.effortColor,
                               display: HideScoresPrefs.shown(PFFormat.oneDecimal(strain.value), hidden: hideScores),
                               title: "Strain", caption: hideScores ? nil : strainTarget(strain), info: PFExplainerID.strain)
                    } else if let line = strainCalibration {
                        PFRing(value: 0, maxValue: 21, color: StrandPalette.effortColor, display: "\u{2013}",
                               title: "Strain", caption: line, info: PFExplainerID.strain)
                    }
                    if let sleep = today.sleep {
                        PFRing(value: hideScores ? 0 : sleep.score, maxValue: 100, color: StrandPalette.restColor,
                               display: HideScoresPrefs.shown(String(Int(sleep.score.rounded())), hidden: hideScores),
                               title: "Sleep", caption: hideScores ? nil : sleepNeed(sleep), info: PFExplainerID.sleepScore)
                    }
                }
                PFTrustNote(trust: today.recovery?.trust)
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
        let rides = snapshot.rides(on: snapshot.todayISO)
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
            if sessions.isEmpty && rides.isEmpty {
                PFCard("Nothing scheduled") {
                    PFParagraph("Enjoy the rest day \u{2014} recovery is training.")
                }
            } else {
                ForEach(sessions) { PFWorkoutRow(workout: $0, snapshot: snapshot) }
                ForEach(rides) { PFRideRow(ride: $0, snapshot: snapshot) }
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
                if let changes = brief.changes {
                    Label(changes, systemImage: "arrow.left.arrow.right")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-brief-changes")
                }
                if brief.partial && !brief.missing.isEmpty {
                    Label("Waiting for: " + brief.missing.joined(separator: ", "), systemImage: "hourglass")
                        .font(StrandFont.caption)
                        .foregroundStyle(PFColor.warning)
                        .accessibilityIdentifier("pf-brief-waiting")
                }
                if let updated = brief.updatedAt, let time = PFFormat.timeOfDay(updated) {
                    Text("Updated \(time)")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityIdentifier("pf-brief-updated")
                }

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
        .containerIdentifier("pf-brief-card")
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
    /// A metric-explainer id for the (i) beside the title.
    var info: String? = nil

    var body: some View {
        VStack(spacing: 2) {
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
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) \(display)")
            if let info { PFInfoButton(id: info) }
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
    }
}
