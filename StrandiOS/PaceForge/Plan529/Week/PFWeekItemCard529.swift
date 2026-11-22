import SwiftUI
import StrandDesign

/// What a card needs from the page around it.
struct PFWeekHooks529 {
    var openResults: (PFResultsTarget529) -> Void
    var openSession: (String) -> Void
    var openSwap: (PFSwapTarget529) -> Void
    var askCoach: (String) -> Void
}

/// One day of the week: its title, the tag ("Day 2 after the race") and every workout of the day written out as a card.
struct PFWeekDay529: View {
    let week: String
    let day: PFPlanWeekDoc.Day
    let isToday: Bool
    let hooks: PFWeekHooks529
    /// False in a finished week: its sessions are history, so no edit is offered.
    var allowsEdits = true

    @ObservedObject private var model = PFUnified.model

    private var items: [PFPlanWeekDoc.Item] { day.items ?? [] }
    private var keyedItems: [(key: String, item: PFPlanWeekDoc.Item)] {
        items.enumerated().map { offset, item in
            (item.sessionId ?? "\(day.date ?? "")-\(item.kind ?? "")-\(item.raceDate ?? String(offset))", item)
        }
    }
    /// Bike rides of the day from the ride metrics: they are not planned sessions, so they sit beside the cards as before.
    private var rides: [PFRide] { model.snapshot?.rides(on: day.date ?? "") ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.title ?? day.dow ?? "")
                    .lookCaps(13, weight: .bold)
                    .foregroundStyle(isToday ? PFWeekColor529.teal : NoopLook.textSecondary)
                if let tag = day.tag, !tag.isEmpty {
                    Text(tag).font(LookFont.text(12, weight: .regular)).foregroundStyle(NoopLook.textTertiary)
                }
            }
            .padding(.horizontal, 2)
            // Keyed by the session id (a race by its date, else the position): a card keeps its own state when its neighbour changes.
            ForEach(keyedItems, id: \.key) { entry in
                PFWeekItemCard529(week: week, day: day, item: entry.item, isToday: isToday, hooks: hooks, allowsEdits: allowsEdits)
                    .id(entry.key)
            }
            if let snapshot = model.snapshot {
                ForEach(rides) { PFRideRow(ride: $0, snapshot: snapshot) }
            }
            if items.isEmpty && rides.isEmpty { PFWeekSub529(text: "Nothing planned.") }
        }
        .containerIdentifier("plan529-day-\(day.date ?? "")")
    }
}

/// A workout, a race or a rest day, written out: the title and its effort, the pills, the change waiting, then Why / How hard / Do /
/// If you wake up red, and the actions. Nothing to tap to understand the week.
struct PFWeekItemCard529: View {
    let week: String
    let day: PFPlanWeekDoc.Day
    let item: PFPlanWeekDoc.Item
    let isToday: Bool
    let hooks: PFWeekHooks529
    var allowsEdits = true

    @ObservedObject private var model = PFUnified.model
    private let hiding = PFHiding()

    private var kind: String { item.kind ?? "session" }
    private var date: String { day.date ?? "" }
    private var key: String { item.sessionId ?? "\(date)-\(kind)" }
    private var isDone: Bool { ["done", "partial"].contains(item.status ?? "") }
    private var color: Color { PFWeekColor529.effort(kind == "race" ? "race" : item.effort) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            pills
            if !isDone, kind != "race", kind != "rest" { PFWatchChip529(sessionID: item.sessionId) }
            if let thin = thinWorkout, let snapshot = model.snapshot, PFWorkoutBadges.hasAny(thin, snapshot) {
                PFWorkoutBadges(workout: thin, snapshot: snapshot)
            }
            lines
            if let done = item.done?.line, !done.isEmpty {
                Label(hiding.text(done), systemImage: "checkmark.circle")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(PFWeekColor529.teal)
                    .accessibilityIdentifier("plan529-done-\(key)")
            }
            if let result = item.result { raceResult(result) }
            review
            actions
        }
        .pfWeekCard()
        .containerIdentifier("plan529-item-\(key)")
    }

    // MARK: Header

    private var headerRow: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(item.title ?? "")
                    .font(LookFont.text(17, weight: .bold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let label = item.effortLabel, !label.isEmpty {
                    PFChip(text: label, color: color)
                }
                if opensSomething {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!opensSomething)
        .accessibilityIdentifier(openIdentifier)
    }

    /// A session keeps the identifier its row had (`pf-workout-<id>`), a race too (`pf-week-race-<date>`).
    private var openIdentifier: String {
        if kind == "race" { return "pf-week-race-\(item.raceDate ?? date)" }
        return item.sessionId.map { "pf-workout-\($0)" } ?? "plan529-open-\(key)"
    }

    private var opensSomething: Bool { kind != "rest" && (item.activityId != nil || item.sessionId != nil) }

    /// A finished workout or race opens the existing results sheet; a planned session opens its sheet (W2).
    private func open() {
        if isDone || (kind == "race" && item.activityId != nil), let id = item.activityId {
            hooks.openResults(PFResultsTarget529(id: id, title: item.title, date: date, isRace: kind == "race"))
        } else if let id = item.sessionId {
            hooks.openSession(id)
        }
    }

    // MARK: Pills

    private var pills: some View {
        PFWeekPills529(pills: pillList)
    }

    private var pillList: [(text: String, color: Color)] {
        var out: [(text: String, color: Color)] = []
        switch item.status ?? "" {
        case "done": out.append(("Done", PFWeekColor529.teal))
        case "partial": out.append(("Partial", PFWeekColor529.amber))
        case "missed": out.append(("Missed", PFWeekColor529.red))
        default: break
        }
        for pill in item.pills ?? [] { out.append((pill, NoopLook.textTertiary)) }
        if let change = item.changePill, !change.isEmpty { out.append((change, PFWeekColor529.amber)) }
        return out
    }

    private var thinWorkout: PFWorkout? {
        guard let id = item.sessionId else { return nil }
        return PFWorkout(id: id, date: date, status: item.status ?? "planned", name: item.title, activityId: item.activityId)
    }

    // MARK: Lines

    @ViewBuilder private var lines: some View {
        if let text = item.why, !text.isEmpty { PFWeekLine529(label: "Why", text: text) }
        if let text = item.howHard, !text.isEmpty { PFWeekLine529(label: "How hard", text: text) }
        if let text = item.do, !text.isEmpty { PFWeekLine529(label: "Do", text: text) }
        if let text = item.ifRed, !text.isEmpty { PFWeekLine529(label: "If you wake up red", text: text, tint: PFWeekColor529.red) }
    }

    private func raceResult(_ result: PFPlanWeekDoc.RaceResult) -> some View {
        HStack(spacing: 8) {
            Text(result.time ?? "").font(LookFont.text(15, weight: .bold)).foregroundStyle(NoopLook.textPrimary)
            if let delta = result.delta { Text(delta).font(LookFont.text(12.5, weight: .regular)).foregroundStyle(NoopLook.textSecondary) }
            if let goal = result.goal { Text("Goal \(goal)").font(LookFont.text(12.5, weight: .regular)).foregroundStyle(NoopLook.textTertiary) }
        }
        .accessibilityIdentifier("plan529-race-result-\(key)")
    }

    /// The coach's review of a finished workout: the verdict when it is ready, "pending" while it is being written, nothing when silent.
    @ViewBuilder private var review: some View {
        switch item.review?.state ?? "" {
        case "ready":
            Text(hiding.text("Coach: \(item.review?.verdict ?? "reviewed")"))
                .font(LookFont.text(13, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .accessibilityIdentifier("plan529-review-\(key)")
            if let meaning = item.review?.meaning, !meaning.isEmpty {
                PFWeekSub529(text: meaning).accessibilityIdentifier("plan529-review-meaning-\(key)")
            }
        case "pending":
            Text("Coach review: on its way")
                .font(LookFont.text(13, weight: .regular))
                .foregroundStyle(NoopLook.textTertiary)
                .accessibilityIdentifier("plan529-review-\(key)")
        default:
            EmptyView()
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if allowsEdits, kind == "session", !isDone, let id = item.sessionId {
            PFSessionActionBar529(target: PFSessionTarget529(sessionId: id, title: item.title ?? "", date: date,
                                                             status: item.status ?? "planned", isToday: isToday,
                                                             minutes: item.minutes, rpe: item.rpe),
                                  actions: cardActions, idPrefix: "plan529-act-\(id)",
                                  onMore: { hooks.openSession(id) },
                                  onChangeWorkout: { hooks.openSwap(swapTarget(sessionId: id)) },
                                  onAskCoach: { hooks.askCoach(coachQuestion) })
        } else if allowsEdits, kind == "rest" {
            PFWeekButton529(title: "Add a workout", identifier: "plan529-add-\(date)") {
                hooks.openSwap(PFSwapTarget529(week: week, date: date, sessionId: nil, title: nil, minutes: nil))
            }
        }
    }

    /// The actions the server lists for the session, with More as the way into the session sheet.
    private var cardActions: [PFSessionAction529] {
        PFSessionAction529.forSession(status: item.status ?? "planned", isOptional: item.optional == true, includesMore: true, includesAskCoach: false)
    }

    private func swapTarget(sessionId: String) -> PFSwapTarget529 {
        PFSwapTarget529(week: week, date: date, sessionId: sessionId, title: item.title, minutes: item.minutes)
    }

    private var coachQuestion: String {
        "About \(item.title ?? "this workout") on \(PFFormat.dayTitle(date)): why is it in my plan, and what happens if I change it?"
    }
}
