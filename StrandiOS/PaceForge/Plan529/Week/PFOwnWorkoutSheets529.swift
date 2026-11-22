import SwiftUI
import StrandDesign

// The athlete's own hand on the plan: change a planned session's details, add a planned session, and log a workout he did himself.
// The inputs and their limits are in PaceForgeManualPlan.swift (unit-tested); these are the three sheets. A write that the server refuses
// keeps the sheet open with everything typed and shows the server's own sentence; the plan is read again after a write that went through.

/// Which of the two new-entry sheets the Week page has open.
enum PFOwnForm529: String, Identifiable {
    case addSession, logWorkout
    var id: String { rawValue }
}

private func pfDayBinding529(_ day: Binding<String>) -> Binding<Date> {
    Binding(get: { PFFormat.date(day.wrappedValue) }, set: { day.wrappedValue = PFFormat.isoString($0) })
}

private func pfWindow529(past: Bool, future: Bool) -> ClosedRange<Date> {
    let day: TimeInterval = 86_400
    let limit = TimeInterval(PFManualPlan.maxDaysAway - 1) * day
    return Date(timeIntervalSinceNow: past ? -limit : -day)...Date(timeIntervalSinceNow: future ? limit : 0)
}

/// After a write the plan and the day's numbers are read again: every Week page listens for `.pfPlan529Changed`.
@MainActor private func pfOwnChanged529() async {
    await PFUnified.model.refresh()
    NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
}

private struct PFOwnField529<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PFWeekOverline529(text: label)
            content
        }
    }
}

/// The sport as free text, with the usual ones one tap away.
private struct PFSportField529: View {
    @Binding var sport: String
    let idPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Sport", text: $sport)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("\(idPrefix)-sport")
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(PFManualPlan.sports, id: \.self) { name in chip(name) }
            }
        }
    }

    private func chip(_ name: String) -> some View {
        let isSelected = sport.trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased()
        return Button { sport = name } label: {
            Text(name)
                .lookCaps(11, weight: .semibold)
                .foregroundStyle(isSelected ? Color(hex: "#06231A") : NoopLook.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Capsule(style: .continuous).fill(isSelected ? PFWeekColor529.teal : Color.clear))
                .overlay(Capsule(style: .continuous).stroke(isSelected ? PFWeekColor529.teal : NoopLook.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("\(idPrefix)-sport-\(name.lowercased())")
    }
}

private extension View {
    /// The frame the three sheets share: a scrolling page with a title and a Cancel.
    func pfOwnSheet529(title: String, id: String, dismiss: DismissAction) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { self }
                    .padding(.horizontal, NoopLook.Metric.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .lookScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("\(id)-cancel")
                }
            }
        }
        .containerIdentifier(id)
    }
}

// MARK: Change a planned session

/// The details of one planned session: its day, minutes and target effort. Saves with `calendar-edit` (action `edit`), sending only what changed.
struct PFSessionEditSheet529: View {
    let sessionID: String
    let title: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var draft: PFSessionEditDraft

    init(sessionID: String, title: String, date: String, minutes: Int?, rpe: Int?, onSaved: @escaping () -> Void) {
        self.sessionID = sessionID
        self.title = title
        self.onSaved = onSaved
        _draft = State(initialValue: PFSessionEditDraft(date: date, minutes: minutes, rpe: rpe))
    }

    /// What is wrong with the form, shown while the athlete has changed something.
    private var liveProblem: String? { draft.hasChanges ? draft.problem(today: PFAPI.todayISO) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PFWeekSub529(text: "\(title). Change what you want and leave the rest; only what you change is sent.")
            PFOwnField529("Day") {
                DatePicker("Day", selection: pfDayBinding529($draft.date), in: pfWindow529(past: true, future: true), displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("plan529-edit-date")
            }
            PFOwnField529("Minutes (5 to 600)") {
                TextField("Minutes", text: $draft.minutesText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("plan529-edit-minutes")
            }
            PFOwnField529("How hard it should feel (1 to 10)") {
                TextField("Effort", text: $draft.rpeText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("plan529-edit-rpe")
            }
            if let liveProblem { PFWeekSub529(text: liveProblem) }
            PFEditMessage529(runner: runner)
            PFWeekButton529(title: runner.isBusy ? "Saving" : "Save changes", isProminent: true,
                            isDisabled: runner.isBusy || !draft.hasChanges || liveProblem != nil, identifier: "plan529-edit-save") {
                Task { await save() }
            }
        }
        .pfOwnSheet529(title: "Edit session", id: "plan529-edit", dismiss: dismiss)
    }

    @MainActor private func save() async {
        let today = PFAPI.todayISO
        guard await runner.run(.calendarEdit, inputs: draft.inputs(sessionID: sessionID, today: today)) else { return }
        onSaved()
        dismiss()
    }
}

// MARK: Add a planned session

/// Books one session on the plan (`add-session`): the day, the sport, the minutes, an optional name and, optionally, every week for a while.
struct PFAddSessionSheet529: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var draft: PFAddSessionDraft

    init(startDate: String, onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        _draft = State(initialValue: PFAddSessionDraft(date: startDate.isEmpty ? PFAPI.todayISO : startDate))
    }

    private var problem: String? { draft.problem(today: PFAPI.todayISO) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PFWeekSub529(text: "Your own session goes on the plan as you write it. The coach does not change it unless you ask.")
            PFOwnField529("Day") {
                DatePicker("Day", selection: pfDayBinding529($draft.date), in: pfWindow529(past: true, future: true), displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("plan529-add-date")
            }
            PFOwnField529("Sport") { PFSportField529(sport: $draft.sport, idPrefix: "plan529-add") }
            PFOwnField529("Minutes (5 to 480)") {
                TextField("Minutes", text: $draft.minutesText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("plan529-add-minutes")
            }
            PFOwnField529("Name (optional)") {
                TextField("e.g. Tempo on the canal", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("plan529-add-name")
            }
            Stepper(value: $draft.repeatWeeks, in: PFAddSessionDraft.repeatRange) {
                Text(draft.repeatWeeks == 1 ? "Just once" : "Every week for \(draft.repeatWeeks) weeks")
                    .font(LookFont.text(14, weight: .regular))
                    .foregroundStyle(NoopLook.textPrimary)
            }
            .accessibilityIdentifier("plan529-add-repeat")
            if let problem { PFWeekSub529(text: problem) }
            PFEditMessage529(runner: runner)
            PFWeekButton529(title: runner.isBusy ? "Adding" : "Add to my plan", isProminent: true,
                            isDisabled: runner.isBusy || problem != nil, identifier: "plan529-add-save") {
                Task { await save() }
            }
        }
        .pfOwnSheet529(title: "Add a session", id: "plan529-addsheet", dismiss: dismiss)
    }

    @MainActor private func save() async {
        guard await runner.run(.addSession, inputs: draft.inputs(today: PFAPI.todayISO)) else { return }
        await pfOwnChanged529()
        onSaved()
        dismiss()
    }
}

// MARK: Log a workout you did

/// Logs a workout the athlete did himself (`manual-workout`), so the coach reads it like a recorded one, and lists what he logged so he can
/// change (`manual-workout-edit`) or remove (`manual-workout-delete`) it. A failed send keeps the form, and the form is kept on the phone
/// until a send goes through.
struct PFLogWorkoutSheet529: View {
    let onSaved: () -> Void

    private static let draftKey = "noop.paceforge.manualWorkoutDraft"

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @ObservedObject private var model = PFUnified.model
    @State private var draft: PFManualWorkoutDraft
    @State private var editing: PFManualWorkout?
    @State private var logged: [PFManualWorkout] = []
    @State private var listFailed = false
    @State private var removing: PFManualWorkout?
    @State private var asksToRemove = false
    @State private var note: String?

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        let kept = PFDraftKeeping.decode(UserDefaults.standard.data(forKey: Self.draftKey))
        _draft = State(initialValue: kept ?? PFManualWorkoutDraft(date: PFAPI.todayISO))
    }

    private var problem: String? { draft.problem(today: PFAPI.todayISO) }

    /// The planned sessions on the chosen day that this workout can be linked to.
    private var candidates: [PFWorkout] {
        let day = model.snapshot?.weeks.flatMap { $0.days }.first { $0.date == draft.date }
        return (day?.workouts ?? []).filter { PFPlanEdit.applies(status: $0.status, sessionID: $0.coachSessionID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PFWeekSub529(text: editing == nil
                         ? "Something you did that is not on your watch or your plan. The coach reads it and adds it to your week."
                         : "Changing a workout you logged. The coach reads it again.")
            form
            if let problem { PFWeekSub529(text: problem) }
            PFEditMessage529(runner: runner)
            if let note {
                Text(note)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-log-note")
            }
            HStack(spacing: 8) {
                PFWeekButton529(title: runner.isBusy ? "Saving" : (editing == nil ? "Log workout" : "Save changes"), isProminent: true,
                                isDisabled: runner.isBusy || problem != nil, identifier: "plan529-log-save") {
                    Task { await submit() }
                }
                if editing != nil {
                    PFWeekButton529(title: "Stop editing", isDisabled: runner.isBusy, identifier: "plan529-log-stop") { stopEditing() }
                }
            }
            loggedList
        }
        .pfOwnSheet529(title: editing == nil ? "Log a workout" : "Edit workout", id: "plan529-log", dismiss: dismiss)
        .confirmationDialog("Remove this workout? The coach stops counting it.", isPresented: $asksToRemove, titleVisibility: .visible) {
            Button("Remove workout", role: .destructive) {
                if let removing { Task { await remove(removing) } }
            }
        }
        .task { await loadList() }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            PFOwnField529("Day") {
                DatePicker("Day", selection: pfDayBinding529($draft.date), in: pfWindow529(past: true, future: false), displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("plan529-log-date")
            }
            PFOwnField529("Start time (optional, like 07:30)") {
                TextField("07:30", text: $draft.startTime)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("plan529-log-start")
            }
            PFOwnField529("Sport") { PFSportField529(sport: $draft.sport, idPrefix: "plan529-log") }
            HStack(alignment: .top, spacing: 10) {
                number("Minutes", "45", $draft.minutesText, id: "minutes")
                number("Distance (km)", "optional", $draft.kmText, id: "km", decimal: true)
            }
            HStack(alignment: .top, spacing: 10) {
                number("Average heart rate", "optional", $draft.avgHRText, id: "avg")
                number("Max heart rate", "optional", $draft.maxHRText, id: "max")
            }
            number("How hard it felt (1 to 10)", "optional", $draft.rpeText, id: "rpe")
            PFOwnField529("Notes (optional)") {
                TextField("How it went", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("plan529-log-notes")
            }
            if !candidates.isEmpty || draft.planSessionID != nil { linkPicker }
        }
        .onChange(of: draft.date) { _, _ in
            if let link = draft.planSessionID, !candidates.contains(where: { $0.coachSessionID == link }) { draft.planSessionID = nil }
        }
    }

    private func number(_ label: String, _ placeholder: String, _ text: Binding<String>, id: String, decimal: Bool = false) -> some View {
        PFOwnField529(label) {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .accessibilityIdentifier("plan529-log-\(id)")
        }
    }

    private var linkPicker: some View {
        PFOwnField529("Counts as a planned session (optional)") {
            Picker("Planned session", selection: $draft.planSessionID) {
                Text("None").tag(String?.none)
                ForEach(candidates, id: \.id) { workout in
                    Text(workout.name ?? "Session").tag(workout.coachSessionID)
                }
                if let link = draft.planSessionID, !candidates.contains(where: { $0.coachSessionID == link }) {
                    Text("The session already linked").tag(Optional(link))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("plan529-log-link")
        }
    }

    // MARK: Logged workouts

    @ViewBuilder private var loggedList: some View {
        if !logged.isEmpty || listFailed {
            VStack(alignment: .leading, spacing: 10) {
                PFWeekOverline529(text: "Logged by you")
                if listFailed { PFWeekSub529(text: "Your logged workouts could not be loaded.") }
                ForEach(logged) { workout in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(workout.sport) \u{00B7} \(PFFormat.shortDate(workout.date)) \u{00B7} \(workout.minutes) min")
                            .font(LookFont.text(14, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                        if let line = detail(workout) { PFWeekSub529(text: line) }
                        HStack(spacing: 8) {
                            PFWeekButton529(title: "Edit", isDisabled: runner.isBusy, identifier: "plan529-log-edit-\(workout.id)") { startEditing(workout) }
                            PFWeekButton529(title: "Remove", isDisabled: runner.isBusy, identifier: "plan529-log-remove-\(workout.id)") {
                                removing = workout
                                asksToRemove = true
                            }
                        }
                    }
                    if workout.id != logged.last?.id { PFDivider529() }
                }
            }
            .pfWeekCard()
            .containerIdentifier("plan529-log-list")
        }
    }

    private func detail(_ workout: PFManualWorkout) -> String? {
        var parts: [String] = []
        if let km = workout.km { parts.append(String(format: "%.1f km", km)) }
        if let avg = workout.avgHR { parts.append("avg \(avg) bpm") }
        if let rpe = workout.rpe { parts.append("effort \(rpe) of 10") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Jobs

    @MainActor private func loadList() async {
        do {
            let data = try await PFAPI.fetch("manual-workouts")
            logged = PFManualWorkouts.parse(data)
            listFailed = false
        } catch {
            listFailed = true
        }
    }

    private func startEditing(_ workout: PFManualWorkout) {
        editing = workout
        draft = PFManualWorkoutDraft(editing: workout)
        runner.clear()
        note = nil
    }

    private func stopEditing() {
        editing = nil
        draft = PFDraftKeeping.decode(UserDefaults.standard.data(forKey: Self.draftKey)) ?? PFManualWorkoutDraft(date: PFAPI.todayISO)
        runner.clear()
    }

    private func keepDraft(_ kept: PFManualWorkoutDraft) {
        if let data = PFDraftKeeping.encode(kept) { UserDefaults.standard.set(data, forKey: Self.draftKey) }
    }

    @MainActor private func submit() async {
        let today = PFAPI.todayISO
        note = nil
        let tookIt: Bool
        if let editing {
            guard let inputs = draft.editInputs(from: editing, today: today) else {
                runner.fail("Nothing has changed.")
                return
            }
            tookIt = await runner.run(.manualWorkoutEdit, inputs: inputs)
        } else {
            tookIt = await runner.run(.manualWorkout, inputs: draft.inputs(today: today))
        }
        if let kept = PFDraftKeeping.afterSend(draft, tookIt: tookIt) {
            if editing == nil { keepDraft(kept) }
            return
        }
        if editing == nil { UserDefaults.standard.removeObject(forKey: Self.draftKey) }
        editing = nil
        draft = PFManualWorkoutDraft(date: today)
        note = "Saved. The coach is reading it; the analysis appears on that day."
        await loadList()
        await pfOwnChanged529()
        onSaved()
    }

    @MainActor private func remove(_ workout: PFManualWorkout) async {
        note = nil
        guard await runner.run(.manualWorkoutDelete, inputs: PFJobInputs.manualWorkoutDelete(id: workout.id)) else { return }
        if editing?.id == workout.id { stopEditing() }
        note = "Removed."
        await loadList()
        await pfOwnChanged529()
        onSaved()
    }
}
