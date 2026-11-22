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
            PFWeekSub529(text: "Your own workout goes on the plan as you write it, with the description you give. The coach does not change it unless you ask.")
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
            PFOwnField529("What the workout is (optional)") {
                PFLargeTextField529(placeholder: PFSessionDescription.addHint, text: $draft.descriptionText,
                                    limit: PFSessionDescription.maxLength, height: 260, identifier: "plan529-add-description")
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
        .pfOwnSheet529(title: "Add a workout", id: "plan529-addsheet", dismiss: dismiss)
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
/// until a send goes through. Each logged workout also takes details and dated comments afterwards (`manual-workout-comment`), which the
/// coach reads again. With `focusID` the sheet shows only that logged workout (opened from its coach analysis), not the new-workout form.
struct PFLogWorkoutSheet529: View {
    let focusID: String?
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
    @State private var commenting: PFManualWorkout?
    @State private var listLoaded = false
    @State private var pollToken = 0

    init(focusID: String? = nil, onSaved: @escaping () -> Void) {
        self.focusID = focusID
        self.onSaved = onSaved
        let kept = PFDraftKeeping.decode(UserDefaults.standard.data(forKey: Self.draftKey))
        _draft = State(initialValue: kept ?? PFManualWorkoutDraft(date: PFAPI.todayISO))
    }

    private var problem: String? { draft.problem(today: PFAPI.todayISO) }

    /// The new-workout form shows unless the sheet was opened for one logged workout; changing that workout brings the form back.
    private var showsForm: Bool { focusID == nil || editing != nil }

    private var visibleLogged: [PFManualWorkout] { focusID.map { id in logged.filter { $0.id == id } } ?? logged }

    private var title: String {
        if editing != nil { return "Edit workout" }
        return focusID == nil ? "Log a workout" : "Your logged workout"
    }

    /// The planned sessions on the chosen day that this workout can be linked to.
    private var candidates: [PFWorkout] {
        let day = model.snapshot?.weeks.flatMap { $0.days }.first { $0.date == draft.date }
        return (day?.workouts ?? []).filter { PFPlanEdit.applies(status: $0.status, sessionID: $0.coachSessionID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PFWeekSub529(text: introText)
            if showsForm {
                form
                if let problem { PFWeekSub529(text: problem) }
            }
            PFEditMessage529(runner: runner)
            if let note {
                Text(note)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-log-note")
            }
            if showsForm {
                HStack(spacing: 8) {
                    PFWeekButton529(title: runner.isBusy ? "Saving" : (editing == nil ? "Log workout" : "Save changes"), isProminent: true,
                                    isDisabled: runner.isBusy || problem != nil, identifier: "plan529-log-save") {
                        Task { await submit() }
                    }
                    if editing != nil {
                        PFWeekButton529(title: "Stop editing", isDisabled: runner.isBusy, identifier: "plan529-log-stop") { stopEditing() }
                    }
                }
            }
            loggedList
        }
        .pfOwnSheet529(title: title, id: "plan529-log", dismiss: dismiss)
        .sheet(item: $commenting) { workout in
            PFWorkoutCommentSheet529(workout: workout) { sentNote in
                note = sentNote
                pollToken += 1
                Task {
                    await loadList()
                    await pfOwnChanged529()
                    onSaved()
                }
            }
        }
        .confirmationDialog("Remove this workout? The coach stops counting it.", isPresented: $asksToRemove, titleVisibility: .visible) {
            Button("Remove workout", role: .destructive) {
                if let removing { Task { await remove(removing) } }
            }
        }
        .task { await loadList() }
        .task(id: pollToken) { await pollForReview() }
    }

    private var introText: String {
        if editing != nil { return "Changing a workout you logged. The coach reads it again." }
        if focusID != nil { return "Edit this workout, or add details or a comment afterwards. The coach reads it again and updates its review." }
        return "Something you did that is not on your watch or your plan. The coach reads it and adds it to your week."
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
            PFOwnField529("Details (optional, up to 2000 characters)") {
                PFLargeTextField529(placeholder: "What you did, how it felt, anything the coach should know", text: $draft.detailsText,
                                    limit: PFManualWorkoutComments.maxDetailsLength, height: 200, identifier: "plan529-log-details")
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
        if !visibleLogged.isEmpty || listFailed || (focusID != nil && listLoaded) {
            VStack(alignment: .leading, spacing: 10) {
                PFWeekOverline529(text: focusID == nil ? "Logged by you" : "This workout")
                if listFailed { PFWeekSub529(text: "Your logged workouts could not be loaded.") }
                else if visibleLogged.isEmpty { PFWeekSub529(text: "This workout is no longer in your logged list.") }
                ForEach(visibleLogged) { workout in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(workout.sport) \u{00B7} \(PFFormat.shortDate(workout.date)) \u{00B7} \(workout.minutes) min")
                            .font(LookFont.text(14, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                        if let line = detail(workout) { PFWeekSub529(text: line) }
                        if let details = workout.details {
                            Text(details)
                                .font(LookFont.text(13, weight: .regular))
                                .foregroundStyle(NoopLook.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("plan529-log-details-\(workout.id)")
                        }
                        commentHistory(workout)
                        if let review = workout.reviewLine {
                            PFWeekSub529(text: review).accessibilityIdentifier("plan529-log-review-\(workout.id)")
                        }
                        HStack(spacing: 8) {
                            PFWeekButton529(title: "Edit", isDisabled: runner.isBusy, identifier: "plan529-log-edit-\(workout.id)") { startEditing(workout) }
                            PFWeekButton529(title: "Add details / comment",
                                            isDisabled: runner.isBusy || workout.comments.count >= PFManualWorkoutComments.maxCount,
                                            identifier: "plan529-log-comment-\(workout.id)") { commenting = workout }
                            PFWeekButton529(title: "Remove", isDisabled: runner.isBusy, identifier: "plan529-log-remove-\(workout.id)") {
                                removing = workout
                                asksToRemove = true
                            }
                        }
                        if workout.comments.count >= PFManualWorkoutComments.maxCount {
                            PFWeekSub529(text: "This workout has the most comments it can hold (50).")
                        }
                    }
                    if workout.id != visibleLogged.last?.id { PFDivider529() }
                }
            }
            .pfWeekCard()
            .containerIdentifier("plan529-log-list")
        }
    }

    @ViewBuilder private func commentHistory(_ workout: PFManualWorkout) -> some View {
        if !workout.comments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(workout.comments.enumerated()), id: \.offset) { _, comment in
                    VStack(alignment: .leading, spacing: 2) {
                        if !comment.whenText.isEmpty { PFWeekOverline529(text: comment.whenText) }
                        Text(comment.text)
                            .font(LookFont.text(13, weight: .regular))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("plan529-log-comments-\(workout.id)")
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
        listLoaded = true
    }

    /// After a comment the Coach writes its review again: read the list (its `analysed` flag) every few seconds until none is waiting, then
    /// read the plan and the analyses once more so the updated review shows. Ends with the sheet.
    @MainActor private func pollForReview() async {
        guard pollToken > 0 else { return }
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if Task.isCancelled { return }
            await loadList()
            if !logged.contains(where: { $0.analysed == false }) { break }
        }
        await pfOwnChanged529()
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
        pollToken += 1
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
        if focusID != nil { dismiss() }
    }
}


// MARK: Add details or a comment to a logged workout

/// One multiline comment on a logged workout (`manual-workout-comment`, 1 to 2000 characters, 50 per workout). The text stays on the phone
/// until the server takes it. A comment the server kept but whose Coach re-read it could not queue (`partial`) counts as sent, with its own note.
private struct PFWorkoutCommentSheet529: View {
    let workout: PFManualWorkout
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var draft: PFManualWorkoutCommentDraft

    private var draftKey: String { "noop.paceforge.manualWorkoutComment.\(workout.id)" }

    init(workout: PFManualWorkout, onSent: @escaping (String) -> Void) {
        self.workout = workout
        self.onSent = onSent
        let kept = UserDefaults.standard.string(forKey: "noop.paceforge.manualWorkoutComment.\(workout.id)") ?? ""
        _draft = State(initialValue: PFManualWorkoutCommentDraft(id: workout.id, text: kept))
    }

    private var problem: String? {
        draft.text.isEmpty ? nil : draft.problem(existing: workout.comments.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PFWeekSub529(text: "\(workout.sport) \u{00B7} \(PFFormat.shortDate(workout.date)) \u{00B7} \(workout.minutes) min. Add what you remember or what changed; the coach reads the workout again with it.")
            PFOwnField529("Details or comment (up to 2000 characters)") {
                TextField("e.g. Legs were heavy from the start, the last 10 minutes were easy", text: $draft.text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(5...12)
                    .accessibilityIdentifier("plan529-comment-text")
            }
            if let problem { PFWeekSub529(text: problem) }
            PFEditMessage529(runner: runner)
            PFWeekButton529(title: runner.isBusy ? "Sending" : "Send to the coach", isProminent: true,
                            isDisabled: runner.isBusy || draft.problem(existing: workout.comments.count) != nil,
                            identifier: "plan529-comment-send") {
                Task { await send() }
            }
        }
        .pfOwnSheet529(title: "Add details", id: "plan529-comment", dismiss: dismiss)
    }

    @MainActor private func send() async {
        let tookIt = await runner.run(.manualWorkoutComment, inputs: draft.inputs(existing: workout.comments.count))
        if let kept = PFDraftKeeping.afterSend(draft, tookIt: tookIt) {
            UserDefaults.standard.set(kept.text, forKey: draftKey)
            return
        }
        UserDefaults.standard.removeObject(forKey: draftKey)
        let sentNote = PFManualWorkoutComments.note(for: runner.lastResult)
        onSent(sentNote)
        dismiss()
    }
}
