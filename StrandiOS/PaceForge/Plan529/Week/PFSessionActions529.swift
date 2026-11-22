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

/// The change menu of one workout (build 543): the leading buttons the screen puts in front (Edit, Note) and a ··· menu with move, skip, swap,
/// make optional (or accept and drop on a draft), make it easier, change the length or effort, ask the Coach and how it was judged. Every
/// one is an existing job (`adjust-today`, `coach`, `calendar-edit`, `session-state`, `session-drop`); skipping and dropping ask first,
/// and a coach's session asks with its own wording. After a job the plan is read again by every Week page (`.pfPlan529Changed`).
struct PFSessionActionBar529<Leading: View>: View {
    let target: PFSessionTarget529
    let menu: [PFMenuItem543]
    let idPrefix: String
    let onChangeWorkout: () -> Void
    let onAskCoach: () -> Void
    let onJudged: () -> Void
    let leading: Leading

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

    init(target: PFSessionTarget529, menu: [PFMenuItem543], idPrefix: String,
         onChangeWorkout: @escaping () -> Void, onAskCoach: @escaping () -> Void, onJudged: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading) {
        self.target = target
        self.menu = menu
        self.idPrefix = idPrefix
        self.onChangeWorkout = onChangeWorkout
        self.onAskCoach = onAskCoach
        self.onJudged = onJudged
        self.leading = leading()
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

    /// The dialog's title and message: the coach's session asks in the words of drawing 3.13, any other confirmation in the server's.
    private var confirmTitle: String {
        pendingConfirm == .skipMandatory ? PFSkipCoachConfirm543.title : (pendingConfirm?.question ?? "")
    }
    private var confirmMessage: String {
        pendingConfirm == .skipMandatory ? PFSkipCoachConfirm543.message(sessionTitle: target.title) : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                leading
                menuButton
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
            Color.clear.confirmationDialog(confirmTitle, isPresented: asksToConfirm, titleVisibility: .visible) {
                if let confirm = pendingConfirm {
                    Button(confirm == .skipMandatory ? PFSkipCoachConfirm543.confirmTitle : confirm.confirmTitle, role: .destructive) {
                        Task { await resend(confirm) }
                    }
                    Button(PFSkipCoachConfirm543.keepTitle, role: .cancel) {}
                }
            } message: {
                if !confirmMessage.isEmpty { Text(confirmMessage) }
            }
        }
        .containerIdentifier("\(idPrefix)-actions")
    }

    // MARK: The three dots

    private var menuButton: some View {
        Menu {
            ForEach(menu, id: \.self) { item in
                Button(role: buttonRole(item)) { perform(item) } label: {
                    Text(PFSessionMenu543.title(item))
                }
                .disabled(isDisabled(item))
            }
        } label: {
            Text("\u{00B7}\u{00B7}\u{00B7}")
                .font(PFPlanFont543.text(20, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NoopLook.divider, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .accessibilityLabel("More actions")
        .accessibilityHint("Move, skip, swap, make optional or ask the Coach")
        .accessibilityIdentifier("\(idPrefix)-menu")
    }

    private func buttonRole(_ item: PFMenuItem543) -> ButtonRole? {
        (item == .skip || item == .drop) ? .destructive : nil
    }

    private func isDisabled(_ item: PFMenuItem543) -> Bool {
        switch item {
        case .swap, .askCoach, .judged: return item == .swap ? isBusy : false
        default: return isBusy || !canEdit
        }
    }

    private func perform(_ item: PFMenuItem543) {
        switch item {
        case .move:
            withAnimation(.easeInOut(duration: 0.2)) { isMoving.toggle() }
        case .skip:
            if target.isMandatory {
                // The coach's session: ask the coach's question at once; the delete is sent only with the athlete's confirmation.
                refusedInputs = PFJobInputs.calendarDelete(sessionID: target.sessionId)
                refusedDone = PFSkipCoachConfirm543.doneNote
                pendingConfirm = .skipMandatory
            } else {
                asksToSkip = true
            }
        case .swap: onChangeWorkout()
        case .optional: Task { await run(.sessionState, PFJobInputs.sessionOptional(sessionID: target.sessionId), done: "Now optional.") }
        case .accept: Task { await run(.sessionState, PFJobInputs.sessionAccept(sessionID: target.sessionId), done: "Accepted.") }
        case .drop: asksToDrop = true
        case .easier: Task { await makeEasier() }
        case .details: isEditing = true
        case .askCoach: onAskCoach()
        case .judged: onJudged()
        }
    }

    private var moveRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Move to", selection: $newDate, in: window, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(PFPlanFont543.text(16, weight: .regular))
            Text("Moving to another day of the same week needs no question.")
                .font(PFPlanFont543.text(15, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PFPlanButton543(title: "Move session", isProminent: true, isDisabled: isBusy || newDay == target.date,
                            identifier: "\(idPrefix)-move-go") {
                Task { await move() }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            Text("Working on it")
                .font(PFPlanFont543.text(15, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
        case .failed(let message):
            Text(message)
                .font(PFPlanFont543.text(15, weight: .regular))
                .foregroundStyle(PFWeekColor529.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(idPrefix)-failed")
        case .done:
            if let note {
                HStack {
                    Text(note)
                        .font(PFPlanFont543.text(15, weight: .regular))
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
