import SwiftUI
import StrandDesign

// The writes the Season, Calendar and plan-settings screens make, and the one place a past recording's results sheet is opened from.
//
// Server pending (build 529): the runner stream adds the narrow jobs `event-update`, `plan-hours`, `dayoff-add` and `dayoff-remove` to the
// app's job list, and `add-session` (the web's "Add activity") is not on it yet. Until they are deployed PaceForge answers
// "does not know that action" and the sheet shows it. Adding and cancelling a race go through `save-events`, which is live.

/// The `inputs` of the Plan section's jobs. Each builder returns nil when its values could not pass the server's own checks.
enum PFPlanInputs529 {
    /// `event-update`, `op: "set"`: one field of one race, matched by its date (and name).
    static func raceSet(date: String, name: String?, fields: [String: String]) -> [String: Any]? {
        guard PFJobInputs.isDay(date), !fields.isEmpty else { return nil }
        var match: [String: Any] = ["date": date]
        if let name, !name.isEmpty { match["name"] = name }
        return ["op": "set", "match": match, "fields": fields]
    }

    /// A goal time as the server reads it: 1:05:00 or 22:30, or empty to clear it.
    static func isGoalTime(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return false }
        return parts.enumerated().allSatisfy { index, part in
            let digits = part.allSatisfy { $0.isASCII && $0.isNumber }
            return digits && (index == 0 ? (1...2).contains(part.count) : part.count == 2)
        }
    }

    /// `plan-hours`: hours a week, above 0 and up to 40.
    static func hours(_ hours: Double) -> [String: Any]? {
        guard hours > 0, hours <= 40 else { return nil }
        return ["hours": (hours * 10).rounded() / 10]
    }

    /// `dayoff-add`: a day or a range, with a label and a kind (holiday, rest or travel).
    static func dayOffAdd(start: String, end: String?, label: String, kind: String = "holiday") -> [String: Any]? {
        guard PFJobInputs.isDay(start) else { return nil }
        var inputs: [String: Any] = ["start": start, "label": String(label.trimmingCharacters(in: .whitespaces).prefix(80)), "kind": kind]
        if let end, !end.isEmpty {
            guard PFJobInputs.isDay(end), end >= start else { return nil }
            inputs["end"] = end
        }
        return inputs
    }

    /// `add-session`: one session on a day, as the web's "Add activity" books it.
    static func addSession(date: String, sport: String, name: String, minutes: Int, rpe: Int) -> [String: Any]? {
        guard PFJobInputs.isDay(date), (5...600).contains(minutes), (1...10).contains(rpe) else { return nil }
        var inputs: [String: Any] = ["date": date, "sport": sport, "minutes": minutes, "target_rpe": rpe]
        let title = name.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { inputs["name"] = String(title.prefix(120)) }
        return inputs
    }
}

/// Runs one write at a time for a sheet and keeps the sentence to show when it did not go through.
@MainActor
final class PFPlanEditRunner529: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    private let tracker = PFJobTracker()

    func clear() { message = nil }

    func fail(_ text: String) { message = text }

    /// True when the server took the write.
    func run(_ job: PFJobName, inputs: [String: Any]?) async -> Bool {
        guard let inputs else {
            message = "That could not be sent. Check the values."
            return false
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        switch await tracker.run(job, inputs: inputs) {
        case .success:
            return true
        case .failure(let failure):
            message = failure.message
            return false
        }
    }

    /// Cancels one race through `save-events` (it replaces the whole list, so the list is read again just before and sent back with
    /// only that race gone). True when the race is off the list.
    func cancelRace(date: String, name: String) async -> Bool {
        isBusy = true
        message = nil
        defer { isBusy = false }
        guard let fresh = PFEvents.parse(await PFAPI.fetchOptional("data/events.json")) else {
            message = PFEventProblem.unreadable.message
            return false
        }
        guard case .success(let updated) = PFEvents.applying(.cancel(date: date, name: name), to: fresh) else { return false }
        if updated.count == fresh.count { return true }
        guard let inputs = PFEvents.inputs(updated) else {
            message = PFEventProblem.tooMany.message
            return false
        }
        switch await tracker.run(.saveEvents, inputs: inputs) {
        case .success:
            return true
        case .failure(let failure):
            message = failure.message
            return false
        }
    }
}

/// The inline line under a form or a list when a write did not go through.
struct PFEditMessage529: View {
    @ObservedObject var runner: PFPlanEditRunner529

    var body: some View {
        if let message = runner.message {
            Text(message)
                .font(LookFont.text(12.5))
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plan529-edit-message")
        }
    }
}

// MARK: A recording's results sheet

/// What the results sheet needs to open for a recording that is not one of the plan weeks the snapshot holds: its activity id and a name.
struct PFResultsTarget529: Identifiable, Equatable {
    let activityId: String
    var name: String?
    var date: String = ""
    var isRace = false

    var id: String { activityId }
}

/// Presents the existing results sheet (`PFResultsSheet`) for a recording by its activity id. The sheet reads `data/details/<id>.json`
/// itself, so any recording the server has opens, not only the ones in the three snapshot weeks.
@MainActor struct PFResultsSheetModifier529: ViewModifier {
    @Binding var target: PFResultsTarget529?
    @ObservedObject private var model = PFUnified.model
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            if let snapshot = model.snapshot {
                PFResultsSheet(workout: PFWorkout(id: target.activityId, date: target.date, status: "done", name: target.name,
                                                  kind: target.isRace ? "race" : nil, activityId: target.activityId),
                               snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router))
                    .environmentObject(model)
            } else {
                PFDocPlaceholder529(kind: .loading)
                    .padding(16)
            }
        }
    }
}

extension View {
    func resultsSheet529(_ target: Binding<PFResultsTarget529?>) -> some View {
        modifier(PFResultsSheetModifier529(target: target))
    }
}
