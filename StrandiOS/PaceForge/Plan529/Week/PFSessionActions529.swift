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
}

enum PFSessionAction529: String {
    case more, easier, move, skip, optional, accept, drop, change, askCoach
}

/// The actions on one workout: Make it easier, Move, Skip, Make optional (or Accept and Drop on an optional draft), Change workout, Ask
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
    @State private var newDate: Date
    @State private var asksToSkip = false
    @State private var asksToDrop = false
    @State private var note: String?

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
        .confirmationDialog("Skip this session? It is removed from your plan.", isPresented: $asksToSkip, titleVisibility: .visible) {
            Button("Skip session", role: .destructive) { Task { await skip() } }
        }
        .confirmationDialog("Drop this optional session?", isPresented: $asksToDrop, titleVisibility: .visible) {
            Button("Drop session", role: .destructive) { Task { await drop() } }
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
        case .skip:
            PFWeekButton529(title: "Skip", isDisabled: isBusy || !canEdit, identifier: "\(idPrefix)-skip") { asksToSkip = true }
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
                Text(note)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(idPrefix)-result")
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
        await run(.calendarEdit, inputs, done: "Moved to \(PFFormat.dayTitle(newDay)).")
    }

    @MainActor private func skip() async {
        await run(.calendarEdit, PFJobInputs.calendarDelete(sessionID: target.sessionId), done: "Skipped.")
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

extension PFSessionAction529 {
    /// What a workout card or the session sheet offers a session in this state, in the order of the drawings.
    static func forSession(status: String, isOptional: Bool, includesMore: Bool = false, includesAskCoach: Bool) -> [PFSessionAction529] {
        var out: [PFSessionAction529] = []
        if includesMore { out.append(.more) }
        if ["planned", "optional", "missed"].contains(status) {
            out.append(.easier)
            out.append(.move)
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
