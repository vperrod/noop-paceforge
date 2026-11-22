import SwiftUI
import StrandDesign

/// The session a row of actions applies to.
struct PFSessionTarget529: Equatable {
    let sessionId: String
    let title: String
    /// The day of the session, `yyyy-MM-dd`.
    let date: String
    /// planned | optional | missed | ...
    let status: String
    let isToday: Bool
    /// What the edit form starts from: the session's minutes and target effort (1 to 10), when the plan has them.
    var minutes: Int? = nil
    var rpe: Int? = nil
    /// A session from the athlete's coach: Skip and a move out of its week ask first and are recorded as such.
    var isMandatory = false
}

enum PFSessionAction529: String {
    case more, easier, move, edit, skip, optional, accept, drop, change, askCoach
}

/// The actions on one workout: Make it easier, Move, Edit details, Skip, Make optional (or Accept and Drop on an optional draft), Change workout, Ask
/// the coach. Every one is an existing job (`adjust-today`, `coach`, `calendar-edit`, `session-state`, `session-drop`); skipping and
/// dropping ask first. After a job the plan is read again by every Week page (`.pfPlan529Changed`).
struct PFSessionActionBar529: View {
    let target: PFSessionTarget529
    let actions: [PFSessionAction529]
    let idPrefix: String
    var onMore: (() -> Void)? = nil
    let onChangeWorkout: () -> Void
    let onAskCoach: () -> Void

    @StateObject private var tracker = PFJobTracker()
    @State private var isMoving = false
    @State private var isEditing = false
    @State private var newDate: Date
    @State private var asksToSkip = false
    @State private var asksToDrop = false
    @State private var note: String?
    @State private var canUndoSkip = false
    /// The confirmation the server asked for and the request it refused, kept apart from the dialog's own state so the confirm button still
    /// has them when the dialog has closed.
    @State private var pendingConfirm: PFMandatoryConfirm?
    @State private var refusedInputs: [String: Any]?
    @State private var refusedDone = ""

    init(target: PFSessionTarget529, actions: [PFSessionAction529], idPrefix: String, onMore: (() -> Void)? = nil,
         onChangeWorkout: @escaping () -> Void, onAskCoach: @escaping () -> Void) {
        self.target = target
        self.actions = actions
        self.idPrefix = idPrefix
        self.onMore = onMore
        self.onChangeWorkout = onChangeWorkout
        self.onAskCoach = onAskCoach
        _newDate = State(initialValue: PFFormat.date(target.date))
    }

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }
    private var newDay: String { PFFormat.isoString(newDate) }
    private var asksToConfirm: Binding<Bool> {
        Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } })
    }
    private var canEdit: Bool { PFPlanEdit.applies(status: target.status, sessionID: target.sessionId) }
    private var window: ClosedRange<Date> {
        let day: TimeInterval = 86_400
        return Date(timeIntervalSinceNow: -399 * day)...Date(timeIntervalSinceNow: 399 * day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(actions, id: \.rawValue) { action in button(action) }
            }
            if isMoving { moveRow }
            status
        }
        .sheet(isPresented: $isEditing) {
            PFSessionEditSheet529(sessionID: target.sessionId, title: target.title, date: target.date,
                                  minutes: target.minutes, rpe: target.rpe) {
                Task { await changed() }
            }
        }
        .confirmationDialog("Skip this session? It is removed from your plan.", isPresented: $asksToSkip, titleVisibility: .visible) {
            Button("Skip session", role: .destructive) { Task { await skip() } }
        }
        .confirmationDialog("Drop this optional session?", isPresented: $asksToDrop, titleVisibility: .visible) {
            Button("Drop session", role: .destructive) { Task { await drop() } }
        }
        // Its own host view: stacked presentation modifiers on one view can leave only the last one working.
        .background {
            Color.clear.confirmationDialog(pendingConfirm?.question ?? "", isPresented: asksToConfirm, titleVisibility: .visible) {
                if let confirm = pendingConfirm {
                    Button(confirm.confirmTitle, role: .destructive) { Task { await resend(confirm) } }
                }
            }
        }
        .containerIdentifier("\(idPrefix)-actions")
    }

    @ViewBuilder private func button(_ action: PFSessionAction529) -> some View {
        switch action {
        case .more:
            PFWeekButton529(title: "More", identifier: "\(idPrefix)-more") { onMore?() }
        case .easier:
            PFWeekButton529(title: "Make it easier", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-easier") {
                Task { await makeEasier() }
            }
        case .move:
            PFWeekButton529(title: "Move", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-move") {
                withAnimation(.easeInOut(duration: 0.2)) { isMoving.toggle() }
            }
        case .edit:
            PFWeekButton529(title: "Edit details", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-edit") { isEditing = true }
        case .skip:
            PFWeekButton529(title: "Skip", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-skip") {
                if target.isMandatory {
                    // The coach's session: ask the coach's question at once; the delete is sent only with the athlete's confirmation.
                    refusedInputs = PFJobInputs.calendarDelete(sessionID: target.sessionId)
                    refusedDone = PFSessionActionBar529.skippedCoachNote
                    pendingConfirm = .skipMandatory
                } else {
                    asksToSkip = true
                }
            }
        case .optional:
            PFWeekButton529(title: "Make optional", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-optional") {
                Task { await run(.sessionState, PFJobInputs.sessionOptional(sessionID: target.sessionId), done: "Now optional.") }
            }
        case .accept:
            PFWeekButton529(title: "Accept", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-accept") {
                Task { await run(.sessionState, PFJobInputs.sessionAccept(sessionID: target.sessionId), done: "Accepted.") }
            }
        case .drop:
            PFWeekButton529(title: "Drop", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-drop") { asksToDrop = true }
        case .change:
            PFWeekButton529(title: "Change workout", isDisabled: isBusy, identifier: "\(idPrefix)-change", action: onChangeWorkout)
        case .askCoach:
            PFWeekButton529(title: "Ask the coach", isDisabled: isBusy, identifier: "\(idPrefix)-ask", action: onAskCoach)
        }
    }

    private var moveRow: some View {
        HStack(spacing: 10) {
            DatePicker("Move to", selection: $newDate, in: window, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(LookFont.text(14, weight: .regular))
            PFWeekButton529(title: "Move session", isProminent: true, isDisabled: isBusy || newDay == target.date,
                            identifier: "\(idPrefix)-move-go") {
                Task { await move() }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            Text("Working on it")
                .font(LookFont.text(12, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
        case .failed(let message):
            Text(message)
                .font(LookFont.text(12, weight: .regular))
                .foregroundStyle(PFWeekColor529.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(idPrefix)-failed")
        case .done:
            if let note {
                HStack {
                    Text(note)
                        .font(LookFont.text(12.5, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(idPrefix)-result")
                    if canUndoSkip {
                        PFWeekButton529(title: "Undo", identifier: "\(idPrefix)-undo") {
                            Task { await undoSkip() }
                        }
                    }
                }
            }
        case .idle:
            EmptyView()
        }
    }

    // MARK: Jobs

    /// Today's session goes through `adjust-today` (Tired); any other day is an order to the coach, the job that changes the plan.
    @MainActor private func makeEasier() async {
        note = nil
        if target.isToday, let inputs = PFJobInputs.adjustToday(.tired) {
            if case .success(let result) = await tracker.run(.adjustToday, inputs: inputs) {
                note = PFFormat.capitalized(PFAdjustToday.confirmation(result))
                await changed()
            }
            return
        }
        let day = PFFormat.dayTitle(target.date)
        guard let inputs = PFJobInputs.coach("Make \(target.title) on \(day) easier") else { return }
        if case .success = await tracker.run(.coach, inputs: inputs) {
            note = "Done. The days that changed are on this page."
            await changed()
        }
    }

    @MainActor private func move() async {
        guard let inputs = PFJobInputs.calendarMove(sessionID: target.sessionId, to: newDay) else { return }
        isMoving = false
        await edit(inputs, done: "Moved to \(PFFormat.dayTitle(newDay)).")
    }

    @MainActor private func skip() async {
        guard let inputs = PFJobInputs.calendarDelete(sessionID: target.sessionId) else { return }
        await edit(inputs, done: "Skipped.", undoable: true)
    }

    /// A `calendar-edit` that the server may refuse until the athlete confirms (a coach's session moved out of its week or skipped): the
    /// refusal opens the confirmation instead of an error, and the request goes again with the flag only after the confirm tap.
    @MainActor private func edit(_ inputs: [String: Any], done: String, undoable: Bool = false) async {
        note = nil
        canUndoSkip = false
        switch await tracker.run(.calendarEdit, inputs: inputs) {
        case .success:
            note = done
            canUndoSkip = undoable
            await changed()
        case .failure(let error):
            guard let confirm = PFMandatoryConfirm.needed(by: error) else { return }
            tracker.reset()
            refusedInputs = inputs
            refusedDone = done
            pendingConfirm = confirm
        }
    }

    @MainActor private func resend(_ confirm: PFMandatoryConfirm) async {
        guard let inputs = PFJobInputs.confirmed(refusedInputs, confirm) else { return }
        await edit(inputs, done: refusedDone, undoable: confirm == .skipMandatory)
    }

    @MainActor private func undoSkip() async {
        guard let inputs = PFJobInputs.calendarRestore(sessionID: target.sessionId) else { return }
        if case .success = await tracker.run(.calendarEdit, inputs: inputs) {
            note = "Back on your plan."
            canUndoSkip = false
            await changed()
        }
    }

    @MainActor private func drop() async {
        await run(.sessionDrop, PFJobInputs.sessionDrop(sessionID: target.sessionId), done: "Dropped.")
    }

    @MainActor private func run(_ job: PFJobName, _ inputs: [String: Any]?, done: String) async {
        guard let inputs else { return }
        note = nil
        if case .success = await tracker.run(job, inputs: inputs) {
            note = done
            await changed()
        }
    }

    @MainActor private func changed() async {
        await PFUnified.model.refresh()
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
    }
}

extension PFSessionActionBar529 {
    static let skippedCoachNote = "Skipped. It counts as missed."
}

extension PFSessionAction529 {
    /// What a workout card or the session sheet offers a session in this state, in the order of the drawings.
    static func forSession(status: String, isOptional: Bool, includesMore: Bool = false, includesAskCoach: Bool) -> [PFSessionAction529] {
        var out: [PFSessionAction529] = []
        if includesMore { out.append(.more) }
        if ["planned", "optional", "missed"].contains(status) {
            out.append(.easier)
            out.append(.move)
            out.append(.edit)
            out.append(.skip)
            if isOptional || status == "optional" {
                out.append(contentsOf: [.accept, .drop])
            } else {
                out.append(.optional)
            }
        }
        out.append(.change)
        if includesAskCoach { out.append(.askCoach) }
        return out
    }
}
