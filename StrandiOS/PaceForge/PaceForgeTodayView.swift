import SwiftUI
import StrandDesign

/// PaceForge "Today": the daily coach briefing, PaceForge's own recovery / strain / sleep and the day's sessions.
struct PFTodayView: View {
    let snapshot: PFSnapshot
    /// Settings > Hide numbers: the three scores read "Hidden" (until the athlete taps to show them).
    private let hiding = PFHiding()
    private var hideScores: Bool { hiding.hides(.scores) }

    private var today: PFToday { snapshot.today }

    /// A card with the "Not today" corner menu; nothing while it is hidden.
    private func dismissable<Content: View>(_ kind: PFCardKind, _ text: String,
                                            @ViewBuilder _ content: () -> Content) -> some View {
        PFDismissable(kind, text: text, snapshot: snapshot, content: content)
    }

    // MARK: Order

    @ObservedObject private var layoutStore = PFTodayLayoutStore.shared
    @ObservedObject private var dismissStore = PFDismissStore.shared
    @State private var isArranging = false

    /// The cards that exist right now, in the app's default order. The layout then arranges them.
    private var presentCards: [PFTodayCard] {
        PFTodayCard.defaultOrder.filter { isPresent($0) }
    }

    private func isPresent(_ card: PFTodayCard) -> Bool {
        switch card {
        case .todaySoFar, .session: return true
        case .myPlan: return snapshot.intelDocs.myPlan.value != nil
        case .todaysCall: return snapshot.dailyIntel?.item(PFIntelID.todaysCall) != nil
        case .dayInReview:
            return PFIntelClock.isEvening() && snapshot.dailyIntel?.item(PFIntelID.dayInReview) != nil
        case .raceWeek: return snapshot.raceWeek != nil
        case .brief: return today.brief != nil
        case .nextBestAction: return snapshot.insightsV2?.todayCard != nil
        case .easy: return snapshot.easyMode.map { !$0.isIdle } ?? false
        case .feel: return snapshot.feel != nil
        case .alerts: return !snapshot.alerts.isEmpty
        case .daily: return showsScores
        case .whatChanged: return snapshot.whatChanged != nil
        case .readiness: return snapshot.readiness != nil
        case .standing: return snapshot.standing?.hasContent == true
        // In race week the race-week card carries the countdown.
        case .nextRace: return today.nextRace != nil && snapshot.raceWeek == nil
        }
    }

    /// The "Not today" kind of a card; the sessions section cannot be hidden.
    private func dismissKind(_ card: PFTodayCard) -> PFCardKind? {
        switch card {
        case .todaysCall: return .todaysCall
        case .dayInReview: return .dayInReview
        case .todaySoFar: return .todaySoFar
        case .myPlan: return nil
        case .raceWeek: return .raceWeek
        case .brief: return .brief
        case .nextBestAction: return .nextBestAction
        case .easy: return .easyMode
        case .feel: return .feel
        case .alerts: return .alerts
        case .daily: return .scores
        case .whatChanged: return .whatChanged
        case .readiness: return .readiness
        case .standing: return .standing
        case .session: return nil
        case .nextRace: return .nextRace
        }
    }

    /// The ids of the cards on screen: the ones present and not put away with "Not today".
    private var visibleIDs: Set<String> {
        let hidden = Set(PFCardText.hidden(snapshot, local: dismissStore.local).map { $0.card.kind })
        return Set(presentCards.filter { card in
            guard let kind = dismissKind(card) else { return true }
            return !hidden.contains(kind)
        }.map { $0.rawValue })
    }

    var body: some View {
        let ids = presentCards.map { $0.rawValue }
        let layout = layoutStore.layout(server: snapshot.todayLayout)
        let visible = visibleIDs
        let _ = NoopDiag.body("PFTodayView")
        LazyVStack(alignment: .leading, spacing: 16) {
            // Fixed above the arrangeable cards; absent while nothing is waiting on him.
            if !snapshot.needsYou.isEmpty { PFNeedsYouCard(items: snapshot.needsYou) }
            PFTodayCustomiseHeader(isArranging: $isArranging, hasLocalOrder: layoutStore.local != nil) {
                layoutStore.reset()
            }
            ForEach(PFTodayOrder.sorted(ids, layout: layout), id: \.self) { id in
                if let card = PFTodayCard(rawValue: id) {
                    slot(card, ids: ids, visible: visible, layout: layout)
                }
            }
            // Outside the arrangeable cards: steps are a separate signal and the card is simply absent until PaceForge publishes it.
            PFMovementCard()
            PFHiddenCardsRow(snapshot: snapshot)
        }
    }

    /// One card, with its Up / Down / Pin bar above it while Customise is on (cards put away have none).
    @ViewBuilder private func slot(_ card: PFTodayCard, ids: [String], visible: Set<String>,
                                   layout: PFTodayLayout) -> some View {
        if isArranging && visible.contains(card.rawValue) {
            VStack(alignment: .leading, spacing: 8) {
                PFArrangeBar(
                    card: card,
                    isPinned: layout.pinned.contains(card.rawValue),
                    canMoveUp: PFTodayOrder.canMove(card.rawValue, step: -1, ids: ids, visible: visible, layout: layout),
                    canMoveDown: PFTodayOrder.canMove(card.rawValue, step: 1, ids: ids, visible: visible, layout: layout),
                    onUp: { layoutStore.set(PFTodayOrder.moving(card.rawValue, step: -1, ids: ids, visible: visible, layout: layout)) },
                    onDown: { layoutStore.set(PFTodayOrder.moving(card.rawValue, step: 1, ids: ids, visible: visible, layout: layout)) },
                    onPin: { layoutStore.set(PFTodayOrder.togglingPin(card.rawValue, layout: layout)) })
                content(for: card)
            }
        } else {
            content(for: card)
        }
    }

    @ViewBuilder private func content(for card: PFTodayCard) -> some View {
        switch card {
        case .todaysCall:
            if let intel = snapshot.dailyIntel, intel.item(PFIntelID.todaysCall) != nil {
                // "Not today" only on a real call; the not-ready and unavailable notes are never hidden.
                if intel.isCurrent(for: snapshot.todayISO), let call = intel.call {
                    dismissable(.todaysCall, PFCardText.todaysCall(call)) {
                        PFTodaysCallHost(intel: intel, todayISO: snapshot.todayISO)
                    }
                } else {
                    PFTodaysCallHost(intel: intel, todayISO: snapshot.todayISO)
                }
            }
        case .dayInReview:
            if let intel = snapshot.dailyIntel, let review = intel.review, intel.isCurrent(for: snapshot.todayISO) {
                dismissable(.dayInReview, PFCardText.dayInReview(review)) {
                    PFDayReviewHost(intel: intel, todayISO: snapshot.todayISO)
                }
            } else if let intel = snapshot.dailyIntel {
                PFDayReviewHost(intel: intel, todayISO: snapshot.todayISO)
            }
        case .myPlan:
            if let plan = snapshot.intelDocs.myPlan.value {
                PFMyPlanCard(plan: plan)
            }
        case .todaySoFar:
            VStack(alignment: .leading, spacing: 16) {
                dismissable(.todaySoFar, PFCardText.todaySoFar(snapshot)) { PFTodaySoFarCard(snapshot: snapshot) }
                if let mode = snapshot.easyMode?.mode { PFEasyModeChip(mode: mode) }
            }
        case .raceWeek:
            if let week = snapshot.raceWeek {
                dismissable(.raceWeek, PFCardText.raceWeek(week)) { PFRaceWeekCard(week: week, todayISO: snapshot.todayISO) }
            }
        case .brief:
            if let brief = today.brief {
                dismissable(.brief, PFCardText.brief(brief)) { PFBriefCard(brief: brief, todayISO: snapshot.todayISO) }
            }
        case .nextBestAction:
            if let next = snapshot.insightsV2?.todayCard {
                dismissable(.nextBestAction, next.dismissText) { PFNextActionCard(item: next) }
            }
        case .easy:
            if let easy = snapshot.easyMode, !easy.isIdle {
                dismissable(.easyMode, PFCardText.easyMode(easy)) { PFEasyModeCard(easy: easy) }
            }
        case .feel:
            if let feel = snapshot.feel {
                dismissable(.feel, PFCardText.feel(feel)) { PFFeelCard(feel: feel, todayISO: snapshot.todayISO) }
            }
        case .alerts:
            if !snapshot.alerts.isEmpty {
                dismissable(.alerts, PFCardText.alerts(snapshot.alerts)) { PFAlertsCard(alerts: snapshot.alerts) }
            }
        case .daily:
            if showsScores { dismissable(.scores, PFCardText.scores(today)) { scoresCard } }
        case .whatChanged:
            if let changes = snapshot.whatChanged {
                dismissable(.whatChanged, PFCardText.whatChanged(changes)) { PFWhatChangedCard(changes: changes) }
            }
        case .readiness:
            if let readiness = snapshot.readiness {
                dismissable(.readiness, PFCardText.readiness(readiness)) { PFReadinessCard(readiness: readiness) }
            }
        case .standing:
            if let standing = snapshot.standing, standing.hasContent {
                dismissable(.standing, PFCardText.standing(standing)) { PFStandingTodayCard(standing: standing) }
            }
        case .session:
            VStack(alignment: .leading, spacing: 16) {
                sessionsSection
                if let easy = snapshot.easyMode, easy.isIdle { PFEasyModeHint() }
            }
        case .nextRace:
            if let race = today.nextRace, snapshot.raceWeek == nil {
                dismissable(.nextRace, PFCardText.nextRace(race)) { raceCard(race) }
            }
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
                        PFRing(value: hideScores ? 0 : recovery.score, maxValue: 100, color: hideScores ? NoopLook.textTertiary : NoopLook.chargeColor(recovery.score),
                               display: HideScoresPrefs.shown(String(Safe.int(recovery.score)), hidden: hideScores),
                               title: "Recovery", caption: hideScores ? nil : recovery.confidence, info: PFExplainerID.recovery)
                    } else if let line = recoveryCalibration {
                        PFRing(value: 0, maxValue: 100, color: NoopLook.chargeHigh, display: "\u{2013}",
                               title: "Recovery", caption: line, info: PFExplainerID.recovery)
                    }
                    if let strain = today.strain {
                        PFRing(value: hideScores ? 0 : strain.value, maxValue: 21, color: NoopLook.effort,
                               display: HideScoresPrefs.shown(PFFormat.oneDecimal(strain.value), hidden: hideScores),
                               title: "Strain", caption: hideScores ? nil : strainTarget(strain), info: PFExplainerID.strain,
                               target: hideScores ? nil : LookDial.targetArc(low: strain.targetLow, high: strain.targetHigh, max: 21))
                    } else if let line = strainCalibration {
                        PFRing(value: 0, maxValue: 21, color: NoopLook.effort, display: "\u{2013}",
                               title: "Strain", caption: line, info: PFExplainerID.strain)
                    }
                    if let sleep = today.sleep {
                        PFRing(value: hideScores ? 0 : sleep.score, maxValue: 100, color: NoopLook.rest,
                               display: HideScoresPrefs.shown(String(Safe.int(sleep.score)), hidden: hideScores),
                               title: "Sleep", caption: hideScores ? nil : sleepNeed(sleep), info: PFExplainerID.sleepScore)
                    }
                }
                PFTrustNote(trust: today.recovery?.trust)
            }
        }
    }

    private func strainTarget(_ strain: PFStrain) -> String? {
        guard let lo = strain.targetLow, let hi = strain.targetHigh else { return nil }
        return "target \(Safe.int(lo, .towardZero))\u{2013}\(Safe.int(hi, .towardZero))"
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
    private let hiding = PFHiding()

    private var isToday: Bool { brief.date == todayISO }
    /// The Daily Outlook bar opens and closes the briefing. Open by default, so the briefing reads as it always did.
    @State private var isOpen = true

    var body: some View {
        PFCard(title: "Daily briefing", icon: "sparkles", trailing: {
            if !isToday, let date = brief.date {
                PFChip(text: "from \(PFFormat.shortDate(date))", color: StrandPalette.textTertiary)
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                OutlookBar(isOpen ? "Your Daily Outlook" : hiding.text(brief.headline), isExpanded: isOpen) {
                    withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
                }
                .accessibilityIdentifier("pf-brief-outlook")
                if isOpen { briefBody }
            }
        }
        .opacity(isToday ? 1 : 0.7)
        .containerIdentifier("pf-brief-card")
    }

    private var briefBody: some View {
        PFBriefBody(brief: brief)
    }
}

/// The whole briefing, every field the web card renders. Split out of the card so the outlook bar can fold it.
private struct PFBriefBody: View {
    let brief: PFDailyBrief
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text(hiding.text(brief.headline))
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let changes = brief.changes {
                    Label(hiding.text(changes), systemImage: "arrow.left.arrow.right")
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
                                Text(hiding.text(item))
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
    private let hiding = PFHiding()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                if let label { Text(label).strandOverline() }
                Text(hiding.text(text))
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
    /// The target range as circle fractions (Strain); the dial draws its arc and tick.
    var target: (start: Double, end: Double)? = nil

    var body: some View {
        VStack(spacing: 2) {
            VStack(spacing: 8) {
                RingDial(fraction: LookDial.fraction(value, max: maxValue), color: color, valueText: display,
                         target: target, diameter: 92, accessibilityName: title)
                Text(title).lookCaps(13.5).foregroundStyle(NoopLook.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) \(display)")
            if let info { PFInfoButton(id: info) }
            if let caption {
                Text(caption)
                    .font(StrandFont.caption)
                    .foregroundStyle(NoopLook.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
