import SwiftUI
import StrandDesign

// The three things that sit around the week's sessions (build 543, drawings 3.1, 3.9, 3.14): the strip above Monday that says what needs the
// athlete, the collapsed "Week notes" bar that holds everything that used to sit above Monday, and the one plus button.

private func pfIsOverlapKept543(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

// MARK: Needs you

/// "2 things need you. Answer the Coach \u{00B7} Review overlaps  Open". Nothing when nothing waits.
struct PFNeedsStripView543: View {
    let week: String
    let doc: PFPlanWeekDoc
    let hooks: PFWeekHooks529
    @ObservedObject var decisions: PFWeekDecisions529

    @ObservedObject private var model = PFUnified.model
    @State private var isOpen = false

    private var liveQuestions: [PFNeedsItem] { (model.snapshot?.needsYou ?? []).filter { $0.kind == .workoutQuestions } }
    private var entries: [PFNeedsEntry543] {
        PFNeedsStrip543.merged(PFNeedsStrip543.entries(doc, keptOverlap: pfIsOverlapKept543),
                               liveQuestionActivityIDs: liveQuestions.compactMap { $0.activityID })
    }
    /// The rows the sheet lists, nothing more: a larger count from the server never shows (the list is the truth).
    private var count: Int { entries.count }

    var body: some View {
        if count > 0 {
            let headline = PFNeedsStrip543.headline(count: count)
            let actions = PFNeedsStrip543.actionsLine(entries)
            Button { isOpen = true } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(PFPlanFont543.text(20, weight: .semibold))
                        .foregroundStyle(PFWeekColor529.amber)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(PFPlanFont543.text(17, weight: .bold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !actions.isEmpty {
                            Text(actions)
                                .font(PFPlanFont543.text(15, weight: .regular))
                                .foregroundStyle(NoopLook.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text("Open")
                        .font(PFPlanFont543.text(16, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                .overlay(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous)
                    .stroke(PFWeekColor529.amber.opacity(0.6), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headline + (actions.isEmpty ? "" : ". " + actions))
            .accessibilityHint("Opens the list")
            .accessibilityIdentifier("plan529-needs-strip")
            .background { Color.clear.sheet(isPresented: $isOpen) { PFNeedsYouSheet543(week: week, doc: doc, hooks: hooks, decisions: decisions) } }
        }
    }
}

/// The list behind the strip: the Coach's questions one at a time (drawings 3.4 and 3.5), the overlaps (3.12) and the changes waiting.
struct PFNeedsYouSheet543: View {
    let week: String
    let doc: PFPlanWeekDoc
    let hooks: PFWeekHooks529
    @ObservedObject var decisions: PFWeekDecisions529

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = PFUnified.model
    @State private var overlap: PFOverlapTarget543?

    private var liveQuestions: [PFNeedsItem] { (model.snapshot?.needsYou ?? []).filter { $0.kind == .workoutQuestions } }
    private var entries: [PFNeedsEntry543] {
        PFNeedsStrip543.merged(PFNeedsStrip543.entries(doc, keptOverlap: pfIsOverlapKept543),
                               liveQuestionActivityIDs: liveQuestions.compactMap { $0.activityID })
    }
    private var overlapEntries: [PFNeedsEntry543] { entries.filter { $0.kind == .overlap } }
    /// Every question the strip counts that the live flows above do not already answer: the served ones with a workout id too, not only those without.
    private var linkedQuestions: [PFNeedsEntry543] {
        let live = Set(liveQuestions.compactMap { $0.activityID })
        return entries.filter { $0.kind == .question && !live.contains($0.activityID ?? "") }
    }
    private var hasChanges: Bool { !(doc.changes ?? []).isEmpty || !(doc.decided ?? []).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(liveQuestions) { item in PFWorkoutQuestionFlow543(item: item) }
                    ForEach(linkedQuestions) { entry in questionLink(entry) }
                    ForEach(overlapEntries) { entry in overlapRow(entry) }
                    if hasChanges { PFWeekChanges529(changes: doc.changes ?? [], decided: doc.decided ?? [], decisions: decisions) }
                    // A change entry is a row of its own only when the changes block above is not drawn (no changes or decisions to show in it).
                    ForEach(entries.filter { $0.kind == .other || ($0.kind == .change && !hasChanges) }) { entry in
                        Text(entry.title)
                            .font(PFPlanFont543.text(16, weight: .regular))
                            .foregroundStyle(NoopLook.textPrimary)
                            .pfWeekCard()
                    }
                    if entries.isEmpty && !hasChanges {
                        Text("Nothing waits for you.")
                            .font(PFPlanFont543.text(16, weight: .regular))
                            .foregroundStyle(NoopLook.textSecondary)
                            .accessibilityIdentifier("plan529-needs-empty")
                    }
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle("Needs you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(PFPlanFont543.text(16, weight: .semibold))
                        .accessibilityIdentifier("plan529-needs-done")
                }
            }
            .background { Color.clear.sheet(item: $overlap) { PFOverlapSheet543(target: $0) } }
        }
        .containerIdentifier("plan529-needs-sheet")
    }

    private func overlapRow(_ entry: PFNeedsEntry543) -> some View {
        let found = target(for: entry)
        return PFPlanButton543(title: found.map { "Overlaps on \(PFFormat.dayTitle($0.day.date ?? "")): \($0.item.title ?? "")" } ?? entry.title,
                               isDisabled: found == nil, identifier: "plan529-needs-overlap-\(entry.id)") {
            overlap = found
        }
    }

    private func questionLink(_ entry: PFNeedsEntry543) -> some View {
        let sessionID = workoutSessionID(for: entry)
        return PFPlanButton543(title: entry.title + ": open the workout", isDisabled: sessionID == nil,
                               identifier: "plan529-needs-open-\(entry.id)") {
            if let id = sessionID {
                dismiss()
                hooks.openSession(id)
            }
        }
    }

    /// The session a question is about: the entry's own, else the one of the week's rows that carries the question's workout id.
    private func workoutSessionID(for entry: PFNeedsEntry543) -> String? {
        if let id = entry.sessionID { return id }
        guard let activity = entry.activityID else { return nil }
        for day in doc.days ?? [] {
            for item in day.items ?? [] where item.activityId == activity { return item.sessionId }
        }
        return nil
    }

    private func target(for entry: PFNeedsEntry543) -> PFOverlapTarget543? {
        for day in doc.days ?? [] {
            for item in day.items ?? [] where item.overlap != nil && item.sessionId == entry.sessionID && entry.sessionID != nil {
                return PFOverlapTarget543(week: week, day: day, item: item)
            }
        }
        return nil
    }
}

// MARK: Week notes

/// "0 of 12 done \u{00B7} coach sessions 0 of 6    Week notes": the week's progress and the way into everything that used to sit above Monday.
struct PFWeekNotesBar543: View {
    let week: String
    let doc: PFPlanWeekDoc
    @ObservedObject var decisions: PFWeekDecisions529
    let reload: () async -> PFPlanWeekDoc?

    @State private var isOpen = false

    var body: some View {
        let progress = PFWeekNotes543.progressLine(doc)
        HStack(alignment: .center, spacing: 8) {
            if let progress {
                Text(progress)
                    .font(PFPlanFont543.text(15, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-progress")
            }
            Spacer(minLength: 4)
            Button { isOpen = true } label: {
                HStack(spacing: 6) {
                    Text("Week notes").font(PFPlanFont543.text(16, weight: .semibold)).foregroundStyle(NoopLook.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Week notes")
            .accessibilityHint("Opens your coach's week, changes, hours and what you deleted")
            .accessibilityIdentifier("plan529-week-notes")
        }
        .padding(.horizontal, 4)
        .background { Color.clear.sheet(isPresented: $isOpen) { PFWeekNotesSheet543(week: week, doc: doc, decisions: decisions, reload: reload) } }
    }
}

/// Drawing 3.14.
struct PFWeekNotesSheet543: View {
    let week: String
    let doc: PFPlanWeekDoc
    @ObservedObject var decisions: PFWeekDecisions529
    let reload: () async -> PFPlanWeekDoc?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = PFUnified.model
    @ObservedObject private var coachStore = PFTrueCoachStore542.shared

    private var pills: [(text: String, color: Color)] {
        var out: [(text: String, color: Color)] = []
        if let pill = doc.phase?.pill { out.append((pill, PFWeekPhase529.color(doc.phase?.key))) }
        if let pill = doc.nextRace?.pill { out.append((pill, NoopLook.textSecondary)) }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if doc.state != "finished" { coachWeek }
                    changes
                    hours
                    season
                    easy
                    block("How this week runs") {
                        Text(PFWeekNotes543.rhythmLine(doc.notes)).noteText()
                            .accessibilityIdentifier("plan529-notes-rhythm")
                    }
                    deleted
                    if doc.state != "finished" {
                        VStack(alignment: .leading, spacing: 8) {
                            PFWeekOverline529(text: "Ask the Coach to change this week")
                            PFWeekTellCoach529(currentDoc: doc, reload: reload)
                        }
                        .pfWeekCard()
                    }
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle("Week notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(PFPlanFont543.text(16, weight: .semibold))
                        .accessibilityIdentifier("plan529-notes-done")
                }
            }
        }
        .containerIdentifier("plan529-notes")
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PFWeekOverline529(text: title)
            content()
        }
        .pfWeekCard()
    }

    /// The coach's week as the server reports it (read time, count, error, what the last replan did, Sync now); the document's own line when
    /// the server does not serve the status.
    @ViewBuilder private var coachWeek: some View {
        if coachStore.status != nil {
            PFCoachWeekCard542()
        } else {
            block(PFTrueCoachWording.title) {
                Text(PFWeekNotes543.coachWeekLine(doc.notes?.coachWeek)).noteText()
                    .accessibilityIdentifier("plan529-notes-coachweek")
            }
        }
    }

    @ViewBuilder private var changes: some View {
        if !(doc.changes ?? []).isEmpty || !(doc.decided ?? []).isEmpty {
            PFWeekChanges529(changes: doc.changes ?? [], decided: doc.decided ?? [], decisions: decisions)
        } else {
            block("Changes waiting") {
                Text(PFWeekNotes543.changesLine(count: PFWeekNotes543.changesCount(doc))).noteText()
                    .accessibilityIdentifier("plan529-notes-changes")
            }
        }
    }

    @ViewBuilder private var hours: some View {
        if let hours = doc.hours {
            VStack(alignment: .leading, spacing: 8) {
                Text(PFWeekNotes543.hoursLine(doc.notes?.hours, fallback: hours)).noteText()
                    .accessibilityIdentifier("plan529-notes-hours")
                PFWeekHours529(hours: hours)
            }
        } else {
            block("Hours") {
                Text(PFWeekNotes543.hoursLine(doc.notes?.hours, fallback: nil)).noteText()
                    .accessibilityIdentifier("plan529-notes-hours")
            }
        }
    }

    /// Where the week sits in the season and why, the seven days at once.
    private var season: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "This week in the season")
            PFWeekPills529(pills: pills)
            if let why = doc.why, !why.isEmpty { PFWeekBody529(text: why).accessibilityIdentifier("plan529-why") }
            PFWeekStrip529(days: doc.strip ?? [])
            PFWeekLegend529()
        }
        .pfWeekCard()
    }

    @ViewBuilder private var easy: some View {
        if let state = model.snapshot?.easyMode, !state.isIdle {
            Button { dismiss(); PFDeepLink529.open(.sheet(.changeToday)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "leaf").foregroundStyle(PFWeekColor529.teal).accessibilityHidden(true)
                    Text(easyText(state))
                        .font(PFPlanFont543.text(16, weight: .medium))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
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

    @ViewBuilder private var deleted: some View {
        let rows = doc.deleted ?? []
        if rows.isEmpty {
            block("Recently deleted") {
                Text(PFWeekNotes543.deletedLine(count: PFWeekNotes543.deletedCount(doc))).noteText()
                    .accessibilityIdentifier("plan529-notes-deleted")
            }
        } else {
            PFWeekRecentlyDeleted529(rows: rows)
        }
    }
}

private extension Text {
    /// The body line of a notes block.
    func noteText() -> some View {
        self.font(PFPlanFont543.text(16, weight: .regular))
            .foregroundStyle(NoopLook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Sessions the server still holds for restore, matching the Week document's 30-day deleted list.
struct PFWeekRecentlyDeleted529: View {
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
                            .font(PFPlanFont543.text(16, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
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

// MARK: The plus button

/// The one plus button of the week (drawing 3.9): plan a workout, or log what you did.
struct PFWeekAddButton543: View {
    /// The day a new workout starts on; empty falls back to today inside the form.
    let addDate: String

    @State private var showsChoice = false
    @State private var pending: PFOwnForm529?
    @State private var form: PFOwnForm529?

    var body: some View {
        Button { showsChoice = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: "#06231A"))
                .frame(width: 44, height: 44)
                .background(Circle().fill(PFWeekColor529.teal))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
        .accessibilityHint("Plan a workout, or log what you did")
        .accessibilityIdentifier("plan529-add")
        .background {
            Color.clear.sheet(isPresented: $showsChoice, onDismiss: {
                form = pending
                pending = nil
            }) {
                PFAddChoiceSheet543(onPlan: { pending = .addSession; showsChoice = false },
                                    onLog: { pending = .logWorkout; showsChoice = false })
            }
        }
        .background {
            Color.clear.sheet(item: $form) { form in
                switch form {
                case .addSession: PFAddSessionSheet529(startDate: addDate) { NotificationCenter.default.post(name: .pfPlan529Changed, object: nil) }
                case .logWorkout: PFLogWorkoutSheet529 { NotificationCenter.default.post(name: .pfPlan529Changed, object: nil) }
                }
            }
        }
        .containerIdentifier("plan529-add-menu")
    }
}

/// Drawing 3.9: two choices, each with one line under it.
struct PFAddChoiceSheet543: View {
    let onPlan: () -> Void
    let onLog: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    choice("Plan a workout", "For a day that has not happened", "calendar.badge.plus", id: "plan529-add-plan", action: onPlan)
                    choice("Log what I did", "Something you already finished", "checkmark.circle", id: "plan529-add-log", action: onLog)
                    Text("Both have a large description box and the same hint. A logged workout is assessed like a Garmin one.")
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
            }
            .lookScreenBackground()
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(PFPlanFont543.text(16, weight: .regular))
                        .accessibilityIdentifier("plan529-add-cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .containerIdentifier("plan529-add-choice")
    }

    private func choice(_ title: String, _ detail: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(PFPlanFont543.text(20, weight: .semibold))
                    .foregroundStyle(PFWeekColor529.teal)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PFPlanFont543.text(17, weight: .bold)).foregroundStyle(NoopLook.textPrimary)
                    Text(detail).font(PFPlanFont543.text(15, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .pfWeekCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityIdentifier(id)
    }
}
