import SwiftUI
import StrandDesign

// The PaceForge section of the unified Today: six small cards in a fixed order (PFTodayCard), each reading the snapshot's
// `today-call.json` (or, when the server serves none, the same parts built from the snapshot's own data). The native NOOP blocks
// (rings, heart rate, key metrics) sit below them, folded.

/// Mounted by `LiquidTodayView` where the PaceForge blocks used to be. It brings its own snapshot host, so it shows the load, failed
/// and offline states on Today.
struct PFTodayCards: View {
    let onOpenNeedsYou: () -> Void
    let onReadWhy: () -> Void

    var body: some View {
        PFSnapshotHost(content: { snapshot in
            AnyView(PFTodayCardsColumn(snapshot: snapshot, onOpenNeedsYou: onOpenNeedsYou, onReadWhy: onReadWhy))
        })
        .containerIdentifier("pf-today-cards")
    }
}

private struct PFTodayCardsColumn: View {
    let snapshot: PFSnapshot
    let onOpenNeedsYou: () -> Void
    let onReadWhy: () -> Void

    var body: some View {
        let info = snapshot.todayCall ?? PFTodayCallParse.fallback(from: snapshot)
        let cards = PFTodayCard.present(call: info, needsYou: snapshot.needsYou.count, hasFeel: snapshot.feel != nil)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(cards, id: \.rawValue) { card in
                cardView(card, info: info)
            }
            PFHiddenCardsRow(snapshot: snapshot)
        }
    }

    /// One card, erased at its own boundary (see `PFTodayView`'s old note on the nested conditional type).
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
    private let hiding = PFHiding()

    var body: some View {
        if let call = info.call {
            PFDismissable(.todaysCall, text: call.verdict + call.reason, snapshot: snapshot) {
                Button { showBrief = true } label: {
                    PFCard(title: "The call", icon: "scope", trailing: {
                        Image(systemName: "chevron.right")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(hiding.text(call.verdict))
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("pf-the-call-verdict")
                            if !call.reason.isEmpty {
                                Text(hiding.text(call.reason))
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("pf-the-call-reason")
                            }
                        }
                    }
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
}

// MARK: - 2. Needs you

/// The existing Needs you row and proposals row, with the open live alerts under them; drawn only while something is open.
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
    @State private var showRace = false
    @State private var sessionToOpen: PFWorkout?

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
        .sheet(item: $sessionToOpen) { workout in PFTodaySessionSheet(workout: workout, snapshot: snapshot) }
    }

    @ViewBuilder private var todayRow: some View {
        switch info.today.kind {
        case "race":
            rowButton(icon: "flag.checkered", title: info.today.title ?? "Race day",
                      detail: info.today.detail.map { "Race day \u{00B7} \($0)" } ?? "Race day", id: "pf-today-race") { showRace = true }
        case "session":
            let workout = workout(for: info.today.sessionID)
            rowButton(icon: "figure.run", title: info.today.title ?? workout?.name ?? "Session",
                      detail: info.today.detail ?? "Planned for today", id: "pf-today-session",
                      isEnabled: workout != nil) { sessionToOpen = workout }
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

    private func rowButton(icon: String, title: String, detail: String, id: String, isEnabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(id)
    }

    /// The planned session the document names, from the weeks the snapshot holds.
    private func workout(for sessionID: String?) -> PFWorkout? {
        guard let sessionID else { return snapshot.today.sessions.first }
        let all = snapshot.weeks.flatMap { $0.days.flatMap { $0.workouts } } + snapshot.today.sessions
        return all.first { ($0.coachSessionID ?? $0.id) == sessionID || $0.id == sessionID }
    }
}

/// The existing workout screens in a sheet: the results of a done session, else the plan detail.
struct PFTodaySessionSheet: View {
    let workout: PFWorkout
    let snapshot: PFSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if workout.hasResults {
            PFResultsSheet(workout: workout, snapshot: snapshot)
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
                        column("Garmin", readiness.garmin)
                        column("WHOOP", readiness.strap)
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

    private func column(_ title: String, _ device: PFTodayCall.Device) -> some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-how-" + title.lowercased())
    }

    /// NOOP's own score and last night's sleep, as one quiet line.
    private var caption: String? {
        var parts: [String] = []
        if let own = readiness.own.score {
            let shown = HideScoresPrefs.shown(String(Safe.int(own)), hidden: hiding.hides(.scores))
            parts.append("Your own score \(shown)" + (readiness.own.band.map { " \u{00B7} \($0)" } ?? ""))
        }
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
            Text(agrees ? "Garmin and WHOOP agree" : "Garmin and WHOOP differ")
                .font(StrandFont.caption.weight(.semibold))
        }
        .foregroundStyle(agrees ? PFColor.positive : PFColor.warning)
    }

    /// "How this is judged": the readiness explainer the server serves, else the app's own short text.
    @ViewBuilder private var judgedSheet: some View {
        if let explainer = snapshot.explainer(PFExplainerID.readinessSources) ?? PFLocalExplainers.fallback[PFExplainerID.readinessSources] {
            PFExplainerSheet(explainer: explainer)
        } else {
            PFCallSheet(snapshot: snapshot)
        }
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
            .accessibilityIdentifier(PFTodayCard.feel.identifier)
        }
    }
}

// MARK: - 6. This week

private struct PFThisWeekCard: View {
    let days: [PFTodayCall.WeekDay]
    let todayISO: String

    var body: some View {
        Button { PFDeepLink.open(.week) } label: {
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
