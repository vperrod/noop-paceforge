import SwiftUI
import StrandDesign

/// The edits on a planned session's detail: move it to another day, skip it, or accept / drop an optional draft. Each is one job that
/// runs at once (`calendar-edit`, `session-state`, `session-drop`); skipping and dropping ask first, and the plan is read again when a
/// job is done. Draws nothing for a session that is done or has no planned-session id.
struct PFPlanEdits: View {
    let workout: PFWorkout

    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var newDate: Date
    @State private var asksToSkip = false
    @State private var asksToDrop = false

    init(workout: PFWorkout) {
        self.workout = workout
        _newDate = State(initialValue: PFFormat.date(workout.date))
    }

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }
    private var newDay: String { PFFormat.isoString(newDate) }
    private var window: ClosedRange<Date> {
        let day: TimeInterval = 86_400
        return Date(timeIntervalSinceNow: -399 * day)...Date(timeIntervalSinceNow: 399 * day)
    }

    var body: some View {
        if PFPlanEdit.applies(status: workout.status, sessionID: workout.coachSessionID) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DatePicker("Move to", selection: $newDate, in: window, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .font(StrandFont.subhead)
                    Button("Move") { Task { await move() } }
                        .buttonStyle(.bordered)
                        .disabled(isBusy || newDay == workout.date)
                        .accessibilityIdentifier("pf-plan-move")
                }
                HStack(spacing: 10) {
                    if workout.status == "optional" {
                        Button("Accept") { Task { await accept() } }
                            .buttonStyle(.bordered)
                            .disabled(isBusy)
                            .accessibilityIdentifier("pf-plan-accept")
                        Button("Drop", role: .destructive) { asksToDrop = true }
                            .buttonStyle(.bordered)
                            .disabled(isBusy)
                            .confirmationDialog("Drop this optional session?", isPresented: $asksToDrop, titleVisibility: .visible) {
                                Button("Drop session", role: .destructive) { Task { await drop() } }
                            }
                            .accessibilityIdentifier("pf-plan-drop")
                    }
                    Button("Skip", role: .destructive) { asksToSkip = true }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                        .confirmationDialog("Skip this session? It is removed from your plan.", isPresented: $asksToSkip, titleVisibility: .visible) {
                            Button("Skip session", role: .destructive) { Task { await skip() } }
                        }
                        .accessibilityIdentifier("pf-plan-skip")
                }
                status
            }
            .containerIdentifier("pf-plan-edits")
        }
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            Text("Working on it")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .done:
            EmptyView()
        }
    }

    @MainActor private func move() async {
        guard let inputs = PFJobInputs.calendarMove(sessionID: workout.coachSessionID, to: newDay) else { return }
        await run(.calendarEdit, inputs)
    }

    @MainActor private func skip() async {
        guard let inputs = PFJobInputs.calendarDelete(sessionID: workout.coachSessionID) else { return }
        await run(.calendarEdit, inputs)
    }

    @MainActor private func accept() async {
        guard let inputs = PFJobInputs.sessionAccept(sessionID: workout.coachSessionID) else { return }
        await run(.sessionState, inputs)
    }

    @MainActor private func drop() async {
        guard let inputs = PFJobInputs.sessionDrop(sessionID: workout.coachSessionID) else { return }
        await run(.sessionDrop, inputs)
    }

    @MainActor private func run(_ job: PFJobName, _ inputs: [String: Any]) async {
        if case .success = await tracker.run(job, inputs: inputs) { await model.refresh() }
    }
}
