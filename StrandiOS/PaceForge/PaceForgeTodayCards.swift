import SwiftUI
import StrandDesign

// The PaceForge cards of the unified Today (PFTodayCard), each reading the snapshot's `today-call.json` (or, when the server serves
// none, the same parts built from the snapshot's own data). Today mounts the host several times, each with the cards of one slot (the
// call, how you are, the day, the week), with its own native blocks (monitor tiles, the day graph, the journal) between the slots.

/// Mounted by `LiquidTodayView` where the PaceForge blocks used to be. It brings its own snapshot host, so it shows the load, failed
/// and offline states on Today.
struct PFTodayCards: View {
    /// The cards this slot draws, in the order the slot lists them (a card the snapshot has nothing for is left out, as always).
    var cards: [PFTodayCard] = PFTodayCard.allCases
    /// Only the first slot on the screen draws the lock, load, failed and offline states.
    var drawsChrome = true
    /// The "Hidden cards" row closes the last slot.
    var showsHiddenRow = true
    /// The training row (next race and last workout side by side) closes this slot; `lastWorkout` is what Today already read.
    var showsTrainingRow = false
    var lastWorkout: PFTrainingLastWorkout?
    var containerID = "pf-today-cards"
    let onOpenNeedsYou: () -> Void
    let onReadWhy: () -> Void

    var body: some View {
        PFSnapshotHost(drawsChrome: drawsChrome, content: { snapshot in
            AnyView(PFTodayCardsColumn(snapshot: snapshot, cards: cards, showsHiddenRow: showsHiddenRow,
                                       trainingRow: showsTrainingRow ? PFTrainingSlot(lastWorkout: lastWorkout) : nil,
                                       onOpenNeedsYou: onOpenNeedsYou, onReadWhy: onReadWhy))
        })
        .containerIdentifier(containerID)
    }
}

private struct PFTodayCardsColumn: View {
    let snapshot: PFSnapshot
    let cards: [PFTodayCard]
    let showsHiddenRow: Bool
    let trainingRow: PFTrainingSlot?
    let onOpenNeedsYou: () -> Void
    let onReadWhy: () -> Void
    @ObservedObject private var dismissals = PFDismissStore.shared

    var body: some View {
        let info = snapshot.todayCall ?? PFTodayCallParse.fallback(from: snapshot)
        let hasLiveAlerts = snapshot.alerts.contains { alert in
            alert.isLive && !PFDismissLogic.isHidden(key: PFDismissKey.alertKey(alert), text: PFDismissKey.alertText(alert),
                                                     today: snapshot.todayISO, local: dismissals.local, server: snapshot.dismissed)
        }
        let present = PFTodayCard.present(call: info, needsYou: snapshot.needsYou.count, hasFeel: snapshot.feel != nil,
                                          hasLiveAlerts: hasLiveAlerts)
        let shown = cards.filter { present.contains($0) }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(shown, id: \.rawValue) { card in
                cardView(card, info: info)
            }
            if let trainingRow {
                // The Today card lists the next race on every day but race day, so the row repeats it only on race day.
                let race = info.today.kind == "race" ? info.nextRace : nil
                if race != nil || trainingRow.lastWorkout != nil {
                    // A race that was run today opens its results, as the Today card's race row does; the tile is only that race when the dates agree.
                    let todayRace = PFWorkoutMatch.todayRaceWorkout(info: info, snapshot: snapshot)
                    PFTrainingRow(nextRace: race, lastWorkout: trainingRow.lastWorkout, snapshot: snapshot,
                                  raceResults: race?.date == todayRace?.date ? todayRace : nil)
                }
            }
            if showsHiddenRow { PFHiddenCardsRow(snapshot: snapshot) }
        }
    }

    /// One card, erased at its own boundary (a single `@ViewBuilder` switch over every card made SwiftUI build one enormous nested conditional type at runtime).
    private func cardView(_ card: PFTodayCard, info: PFTodayCall) -> AnyView {
        switch card {
        case .theCall: return AnyView(PFTheCallCard(snapshot: snapshot, info: info))
        case .needsYou: return AnyView(PFNeedsYouSlot(onOpen: onOpenNeedsYou, onReadWhy: onReadWhy))
        case .today: return AnyView(PFTodaySlotCard(snapshot: snapshot, info: info))
        case .howYouAre: return AnyView(PFHowYouAreCard(snapshot: snapshot, readiness: info.readiness))
        case .feel: return AnyView(PFFeelSlot(snapshot: snapshot))
        case .thisWeek: return AnyView(PFThisWeekCard(days: info.week, todayISO: snapshot.todayISO))
        }
    }
}

// MARK: - 1. The call

private struct PFTheCallCard: View {
    let snapshot: PFSnapshot
    let info: PFTodayCall
    @State private var showBrief = false
    @ObservedObject private var intel = PFDailyIntelStore.shared
    private let hiding = PFHiding()

    /// The call's detail from daily-intel.json, drawn on the banner: the chip. Nothing while that document is not from today. The Effort
    /// target is on its own card (both targets, each named) and today's planned session on the Today card, so the banner states neither.
    private var detailLines: [String] {
        guard let current = intel.intel, current.isCurrent(for: snapshot.todayISO), let detail = current.call else { return [] }
        return [detail.call.spokenText]
    }

    /// WHOOP's banner: a rounded bar on the warm-to-cool gradient of the Daily Outlook row, white text, a chevron at the end.
    var body: some View {
        if let call = info.call {
            PFDismissable(.theCall, text: PFCardText.theCall(call), snapshot: snapshot) {
                Button { showBrief = true } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "scope")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.white)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hiding.text(call.verdict))
                                .font(LookFont.text(15, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("pf-the-call-verdict")
                            if !call.reason.isEmpty {
                                Text(hiding.text(call.reason))
                                    .font(LookFont.text(13, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.8))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("pf-the-call-reason")
                            }
                            ForEach(detailLines, id: \.self) { line in
                                Text(hiding.text(line))
                                    .font(LookFont.text(12.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.8))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("pf-the-call-detail")
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: NoopLook.outlookBar, startPoint: .leading, endPoint: .trailing))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(PFTodayCard.theCall.identifier)
            }
            .sheet(isPresented: $showBrief) { PFCallSheet(snapshot: snapshot) }
        }
    }
}

/// The full brief and both devices' evidence behind the call.
private struct PFCallSheet: View {
    let snapshot: PFSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFTodaysCallStoreHost()
                    bodySignalsLink
                    if let brief = snapshot.today.brief { PFBriefCard(brief: brief, todayISO: snapshot.todayISO) }
                    PFDualReadinessHost()
                    PFDailyReportRow()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("The call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-the-call-done")
                }
            }
        }
        .environment(\.pfExplainers, snapshot.explainerMap)
        .presentationDetents([.large])
        .containerIdentifier("pf-the-call-sheet")
    }

    private var bodySignalsLink: some View {
        NavigationLink {
            BodySignalsScreen(snapshot: snapshot)
        } label: {
            PFRow529(title: "Body signals", sub: "WHOOP, Garmin, PaceForge and how you feel, side by side", showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("body-signals-link")
        .planCard529()
    }
}

// MARK: - 2. Needs you

/// The existing Needs you row and proposals row, with the open live alerts under them; drawn only while an item or a live alert is open.
private struct PFNeedsYouSlot: View {
    let onOpen: () -> Void
    let onReadWhy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFTodayNeedsYouHost(onOpen: onOpen, onReadWhy: onReadWhy)
            PFTodayLiveAlertsHost()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PFTodayCard.needsYou.identifier)
    }
}

// MARK: - 3. Today / next race

private struct PFTodaySlotCard: View {
    let snapshot: PFSnapshot
    let info: PFTodayCall
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @State private var showRace = false
    @State private var sessionToOpen: PFWorkout?
    @State private var showRaceResults = false

    /// The recording of a race that was run today (as `PFRaceDayRow` does): the week strip's `activity_id`, else the recording of the day with
    /// the race in its name; nil while no recording is known, when the plan sheet opens instead.
    private var raceResultsWorkout: PFWorkout? {
        PFWorkoutMatch.todayRaceWorkout(info: info, snapshot: snapshot)
    }

    var body: some View {
        PFCard("Today", icon: "calendar") {
            VStack(alignment: .leading, spacing: 4) {
                todayRow
                if let race = info.nextRace, info.today.kind != "race" { raceRow(race) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PFTodayCard.today.identifier)
        .sheet(isPresented: $showRace) { PFHyroxSheet() }
        .sheet(isPresented: $showRaceResults) {
            if let workout = raceResultsWorkout {
                PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router))
            }
        }
        .sheet(item: $sessionToOpen) { workout in PFTodaySessionSheet(workout: workout, snapshot: snapshot) }
    }

    @ViewBuilder private var todayRow: some View {
        switch info.today.kind {
        case "race":
            rowButton(icon: "flag.checkered", title: info.today.title ?? "Race day",
                      detail: info.today.detail.map { "Race day \u{00B7} \($0)" } ?? "Race day", id: "pf-today-race") {
                if raceResultsWorkout != nil { showRaceResults = true } else { showRace = true }
            }
        case "session":
            let planned = plannedWorkout(for: info.today.sessionID)
            rowButton(icon: "figure.run", title: info.today.title ?? planned?.name ?? "Session",
                      detail: info.today.detail ?? "Planned for today", id: "pf-today-session",
                      isEnabled: planned != nil) { sessionToOpen = planned }
        default:
            rowButton(icon: "moon.zzz", title: "Rest day", detail: "Nothing scheduled. Recovery is training.", id: "pf-today-rest",
                      isEnabled: false) {}
        }
    }

    private func raceRow(_ race: PFTodayCall.Race) -> some View {
        let when = race.daysOut == 1 ? "tomorrow" : "in \(race.daysOut) days"
        let goal = race.goalTime.map { " \u{00B7} goal \($0)" } ?? ""
        return rowButton(icon: "flag.checkered", title: race.name,
                         detail: "Next race \u{00B7} \(when) \u{00B7} \(PFFormat.dayTitle(race.date))" + goal,
                         id: "pf-today-next-race") { showRace = true }
    }

    @ViewBuilder private func rowButton(icon: String, title: String, detail: String, id: String, isEnabled: Bool = true,
                                        action: @escaping () -> Void) -> some View {
        if isEnabled {
            Button(action: action) { rowContent(icon: icon, title: title, detail: detail, showsChevron: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier(id)
        } else {
            rowContent(icon: icon, title: title, detail: detail, showsChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(id)
        }
    }

    private func rowContent(icon: String, title: String, detail: String, showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The planned session the document names, from the weeks the snapshot holds.
    private func plannedWorkout(for sessionID: String?) -> PFWorkout? {
        guard let sessionID else { return snapshot.today.sessions.first }
        let all = snapshot.weeks.flatMap { $0.days.flatMap { $0.workouts } } + snapshot.today.sessions
        return all.first { ($0.coachSessionID ?? $0.id) == sessionID || $0.id == sessionID }
    }
}

/// The existing workout screens in a sheet: the results of a done session, else the plan detail.
struct PFTodaySessionSheet: View {
    let workout: PFWorkout
    let snapshot: PFSnapshot
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if workout.hasResults {
            PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router))
        } else {
            NavigationStack {
                ScrollView {
                    PFWorkoutDetail(workout: workout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationTitle(workout.name ?? "Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
            }
            .containerIdentifier("pf-today-session-sheet")
        }
    }
}

// MARK: - 4. How you are

private struct PFHowYouAreCard: View {
    let snapshot: PFSnapshot
    let readiness: PFTodayCall.Readiness
    @State private var showJudged = false
    private let hiding = PFHiding()

    var body: some View {
        Button { showJudged = true } label: {
            PFCard("How you are", icon: "heart.text.square") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        column("Garmin", readiness.garmin, lines: readiness.garminLines)
                        column("NOOP", readiness.strap)
                    }
                    if let line = caption { Text(line).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("pf-how-own") }
                    if readiness.agreement != "unknown" { agreementMark }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(PFTodayCard.howYouAre.identifier)
        .sheet(isPresented: $showJudged) { judgedSheet }
    }

    private func column(_ title: String, _ device: PFTodayCall.Device, lines: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textSecondary)
            if let score = device.score {
                Text(HideScoresPrefs.shown(String(Safe.int(score)), hidden: hiding.hides(.scores)))
                    .font(StrandFont.rounded(30))
                    .foregroundStyle(StrandPalette.textPrimary)
            } else {
                Text("\u{2013}").font(StrandFont.rounded(30)).foregroundStyle(StrandPalette.textTertiary)
            }
            if let band = device.band ?? device.label {
                Text(band).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            ForEach(lines, id: \.self) { line in
                Text(line).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-how-" + title.lowercased())
    }

    /// Last night's sleep, as one quiet line.
    private var caption: String? {
        var parts: [String] = []
        if let minutes = readiness.sleepMinutes {
            let slept = "\(minutes / 60) h \(minutes % 60) min"
            if let need = readiness.sleepNeedMinutes { parts.append("Slept \(slept) of \(need / 60) h \(need % 60) min") } else { parts.append("Slept \(slept)") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private var agreementMark: some View {
        let agrees = readiness.agreement == "agree"
        return HStack(spacing: 6) {
            Image(systemName: agrees ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(StrandFont.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(agrees ? "Garmin and NOOP agree" : "Garmin and NOOP differ")
                .font(StrandFont.caption.weight(.semibold))
        }
        .foregroundStyle(agrees ? PFColor.positive : PFColor.warning)
    }

    /// "How this is judged": the readiness explainer the server serves, else the app's own short text.
    @ViewBuilder private var judgedSheet: some View {
        if let explainer = snapshot.explainer(PFExplainerID.readinessSources) ?? PFLocalExplainers.fallback[PFExplainerID.readinessSources] {
            VStack(spacing: 0) {
                if !garminDetailRows.isEmpty { garminDetail }
                PFExplainerSheet(explainer: explainer)
            }
        } else if !garminDetailRows.isEmpty {
            garminDetail
        } else {
            PFCallSheet(snapshot: snapshot)
        }
    }

    /// The Garmin lines in full, plus the endurance score when the snapshot's profile has it.
    private var garminDetailRows: [String] {
        var rows = readiness.garminFactors
        rows += [readiness.recoveryLine, readiness.hrvLine].compactMap { $0 }
        if let endurance = snapshot.athleteDocs?.profile?.enduranceScore { rows.append("Endurance score \(Int(endurance.rounded()))") }
        return rows
    }

    private var garminDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Garmin").font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textSecondary)
            ForEach(garminDetailRows, id: \.self) { row in
                Text(row).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .accessibilityIdentifier("pf-how-garmin-detail")
    }
}

// MARK: - 5. Feel

private struct PFFeelSlot: View {
    let snapshot: PFSnapshot

    var body: some View {
        if let feel = snapshot.feel {
            PFDismissable(.feel, text: PFCardText.feel(feel), snapshot: snapshot) {
                PFFeelCard(feel: feel, todayISO: snapshot.todayISO)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(PFTodayCard.feel.identifier)
        }
    }
}

// MARK: - 6. This week

private struct PFThisWeekCard: View {
    let days: [PFTodayCall.WeekDay]
    let todayISO: String

    var body: some View {
        Button { PFDeepLink529.open(.chip(.week)) } label: {
            PFCard("This week", icon: "calendar") {
                HStack(spacing: 4) {
                    ForEach(days, id: \.date) { day in
                        let isToday = day.date == todayISO
                        VStack(spacing: 6) {
                            Text(day.dow.prefix(3))
                                .font(StrandFont.caption.weight(isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? StrandPalette.accent : StrandPalette.textTertiary)
                            Text(PFWeekGlyph.glyph(for: day))
                                .font(StrandFont.headline)
                                .foregroundStyle(isToday ? StrandPalette.accent : StrandPalette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label(day))
                        .accessibilityIdentifier("pf-week-day-\(day.date)")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(PFTodayCard.thisWeek.identifier)
    }

    private func label(_ day: PFTodayCall.WeekDay) -> String {
        if day.items.isEmpty { return "\(day.dow), rest" }
        return "\(day.dow), " + day.items.map { "\($0.title) \($0.status)" }.joined(separator: ", ")
    }
}

// MARK: - Training row

/// The newest workout Today already read (its `workouts` list, newest first), reduced to what the compact card prints.
struct PFTrainingLastWorkout {
    let title: String
    let detail: String
    /// The strap workout's start (unix seconds), to find the PaceForge recording behind it.
    var startTs: Int? = nil
}

/// Marks the slot that closes with the training row.
struct PFTrainingSlot {
    let lastWorkout: PFTrainingLastWorkout?
}

/// Next race and last workout as two compact cards side by side. Built only from what Today already has: the call's next race and the
/// newest workout of the strap's list. A half with no source is left out.
private struct PFTrainingRow: View {
    let nextRace: PFTodayCall.Race?
    let lastWorkout: PFTrainingLastWorkout?
    let snapshot: PFSnapshot
    /// The recording of the race when it was run today; nil for a race still ahead.
    var raceResults: PFWorkout?
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @State private var showRace = false
    @State private var showRaceResults = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let race = nextRace { raceTile(race) }
            if let lastWorkout { workoutTile(lastWorkout) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-training-row")
        .sheet(isPresented: $showRace) { PFHyroxSheet() }
        .sheet(isPresented: $showRaceResults) {
            if let raceResults {
                PFResultsSheet(workout: raceResults, snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router))
            }
        }
    }

    private func raceTile(_ race: PFTodayCall.Race) -> some View {
        let when = race.daysOut == 1 ? "tomorrow" : "in \(race.daysOut) days"
        let goal = race.goalTime.map { "Goal \($0)" }
        return Button { if raceResults != nil { showRaceResults = true } else { showRace = true } } label: {
            tile(title: "NEXT RACE", headline: race.name, lines: [when, PFFormat.dayTitle(race.date)] + (goal.map { [$0] } ?? []))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-training-next-race")
    }

    private func workoutTile(_ workout: PFTrainingLastWorkout) -> some View {
        Group {
            if let startTs = workout.startTs {
                // Opens that workout's results when a PaceForge recording matches it, else the Workouts list.
                PFWorkoutResultsLink(startTs: startTs) { tile(title: "LAST WORKOUT", headline: workout.title, lines: [workout.detail]) }
            } else {
                NavigationLink(value: TabRoute.workouts) {
                    tile(title: "LAST WORKOUT", headline: workout.title, lines: [workout.detail])
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-training-last-workout")
    }

    private func tile(title: String, headline: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(headline)
                .font(LookFont.text(17, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .contentShape(Rectangle())
    }
}
