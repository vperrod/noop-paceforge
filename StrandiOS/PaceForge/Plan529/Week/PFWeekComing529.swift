import SwiftUI
import StrandDesign

/// W1: the coming (or current) week. Top to bottom: where the week sits in the season and why, the seven days at once, the hours, the
/// changes waiting, then every workout of the week written out as its own card, the coach field and the three buttons.
struct PFWeekComing529: View {
    let week: String
    let doc: PFPlanWeekDoc
    let header: PFWeekHeader529
    let hooks: PFWeekHooks529
    @ObservedObject var decisions: PFWeekDecisions529
    let reload: () async -> PFPlanWeekDoc?

    @ObservedObject private var model = PFUnified.model
    @State private var ownForm: PFOwnForm529?

    private var days: [PFPlanWeekDoc.Day] { doc.days ?? [] }
    private var hasChanges: Bool { !(doc.changes ?? []).isEmpty || !(doc.decided ?? []).isEmpty }

    /// The day the week document marks as today (the server's own clock), when this week holds it.
    private var todayDate: String? { doc.strip?.first(where: { $0.today == true })?.date }

    /// Edits are offered on sessions that are still ahead: all of a coming week, today and later in the current week, nothing in a finished one.
    private func allowsEdits(_ day: PFPlanWeekDoc.Day) -> Bool {
        switch doc.state ?? "" {
        case "finished": return false
        case "current": return (day.date ?? "") >= (todayDate ?? PFAPI.todayISO)
        default: return true
        }
    }

    /// Where "+ Add" puts a workout: the first day of a coming week, today in the current one, nowhere in a finished week.
    private var addDate: String {
        switch doc.state ?? "" {
        case "finished": return ""
        case "current": return todayDate ?? (PFAPI.todayISO >= (doc.from ?? "") && PFAPI.todayISO <= (doc.to ?? "") ? PFAPI.todayISO : "")
        default: return doc.from ?? ""
        }
    }

    /// "2 of 4 sessions done · 1 h 30 of 3 h": the current or a finished week's progress, from its own items. Nothing for a coming week.
    private var progressLine: String? {
        guard ["current", "finished"].contains(doc.state ?? "") else { return nil }
        let sessions = days.flatMap { $0.items ?? [] }.filter { $0.kind == "session" }
        guard !sessions.isEmpty else { return nil }
        let done = sessions.filter { ["done", "partial"].contains($0.status ?? "") }.count
        var line = "\(done) of \(sessions.count) sessions done"
        if let hours = doc.hours, let did = hours.done, let of = hours.planned ?? hours.target {
            line += " \u{00B7} \(PFHours529.text(did)) of \(PFHours529.text(of))"
        }
        return line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            top
            PFWeekAddRow529(addDate: addDate)
            if let hours = doc.hours { PFWeekHours529(hours: hours) }
            easyBanner
            if doc.state != "finished" { PFCoachWeekCard542() }
            if hasChanges {
                PFWeekChanges529(changes: doc.changes ?? [], decided: doc.decided ?? [], decisions: decisions)
            }
            if let deleted = doc.deleted, !deleted.isEmpty {
                PFWeekRecentlyDeleted529(rows: deleted)
            }
            // Keyed by the day's date, not its position: a card keeps its own state (Skipped, a moved date) when the list around it changes.
            ForEach(days, id: \.date) { day in
                PFWeekDay529(week: week, day: day, isToday: isToday(day), hooks: hooks, allowsEdits: allowsEdits(day))
                    .id(day.date ?? "")
            }
            PFWeekTellCoach529(currentDoc: doc, reload: reload)
            buttons
        }
    }

    private func isToday(_ day: PFPlanWeekDoc.Day) -> Bool {
        doc.strip?.first(where: { $0.date == day.date })?.today == true
    }

    // MARK: Top card

    private var top: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let progress = progressLine {
                Text(progress)
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("plan529-progress")
            }
            PFWeekPills529(pills: pills)
            if let why = doc.why, !why.isEmpty {
                PFWeekBody529(text: why).accessibilityIdentifier("plan529-why")
            }
            PFWeekStrip529(days: doc.strip ?? [])
            PFWeekLegend529()
        }
        .pfWeekCard()
    }

    private var pills: [(text: String, color: Color)] {
        var out: [(text: String, color: Color)] = []
        if let pill = doc.phase?.pill { out.append((pill, PFWeekPhase529.color(doc.phase?.key))) }
        if let pill = doc.nextRace?.pill { out.append((pill, NoopLook.textTertiary)) }
        return out
    }

    // MARK: Easy mode

    /// The easy-mode row of the old Week screen, as one line: its state at a glance, a tap opens Change today where it is started,
    /// accepted and ended.
    @ViewBuilder private var easyBanner: some View {
        if let easy = model.snapshot?.easyMode, !easy.isIdle {
            Button { PFDeepLink529.open(.sheet(.changeToday)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "leaf").foregroundStyle(PFWeekColor529.teal).accessibilityHidden(true)
                    Text(easyText(easy))
                        .font(LookFont.text(14, weight: .medium))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .pfWeekCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan529-easy-banner")
        }
    }

    private func easyText(_ easy: PFEasyMode) -> String {
        guard let mode = easy.mode else { return "Easy mode \u{00B7} proposal waiting for your answer" }
        var text = "Easy mode \u{00B7} level \(mode.level)"
        if let day = mode.dayText { text += " \u{00B7} " + day.lowercased() }
        return text
    }

    // MARK: Buttons

    private var buttons: some View {
        LookFlowLayout(spacing: 6, lineSpacing: 6) {
            PFWeekButton529(title: "Not feeling 100 %", identifier: "plan529-not-100") {
                PFDeepLink529.open(.sheet(.changeToday))
            }
            PFWeekButton529(title: "Log a niggle", identifier: "plan529-niggle") {
                PFDeepLink529.open(.sheet(.changeToday))
            }
            PFWeekButton529(title: "+ Add", isDisabled: addDate.isEmpty, identifier: "plan529-add") {
                hooks.openSwap(PFSwapTarget529(week: week, date: addDate, sessionId: nil, title: nil, minutes: nil))
            }
            PFWeekButton529(title: "Add my own", identifier: "plan529-add-own") { ownForm = .addSession }
            PFWeekButton529(title: "Log a workout", identifier: "plan529-log-workout") { ownForm = .logWorkout }
        }
        .sheet(item: $ownForm) { form in
            switch form {
            case .addSession: PFAddSessionSheet529(startDate: addDate) { NotificationCenter.default.post(name: .pfPlan529Changed, object: nil) }
            case .logWorkout: PFLogWorkoutSheet529 { NotificationCenter.default.post(name: .pfPlan529Changed, object: nil) }
            }
        }
        .containerIdentifier("plan529-bottom-buttons")
    }
}

/// Sessions the server still holds for restore, matching the Week document's 30-day deleted list.
private struct PFWeekRecentlyDeleted529: View {
    let rows: [PFPlanWeekDoc.DeletedSession]
    @StateObject private var tracker = PFJobTracker()
    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "Recently deleted")
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title ?? "Session")
                            .font(LookFont.text(14, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                        PFWeekSub529(text: [row.dow, row.date].compactMap { $0 }.joined(separator: " "))
                    }
                    Spacer(minLength: 8)
                    PFWeekButton529(title: "Undo", isDisabled: isBusy,
                                    identifier: "plan529-deleted-undo-\(row.sessionId ?? "")") {
                        Task { await restore(row.sessionId) }
                    }
                }
                if row.sessionId != rows.last?.sessionId { PFDivider529() }
            }
            if case .failed(let message) = tracker.phase { PFWeekSub529(text: message) }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-recently-deleted")
    }

    @MainActor private func restore(_ id: String?) async {
        guard let inputs = PFJobInputs.calendarRestore(sessionID: id) else { return }
        if case .success = await tracker.run(.calendarEdit, inputs: inputs) {
            await PFUnified.model.refresh()
            NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        }
    }
}
