import SwiftUI
import StrandDesign

// The writes the Season, Calendar and plan-settings screens make, and the one place a past recording's results sheet is opened from.
//
// Jobs: server-jobs-529.md. A refusal comes back with the server's own sentence and the sheet shows it. "Add an activity" has no phone job yet
// (server pending): the Calendar row opens the change-today sheet, which has the coach field.

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

    /// `event-update`, `op: "cancel"`: the race on that date (and name).
    static func raceCancel(date: String, name: String?) -> [String: Any]? {
        guard PFJobInputs.isDay(date) else { return nil }
        var match: [String: Any] = ["date": date]
        if let name, !name.isEmpty { match["name"] = name }
        return ["op": "cancel", "match": match]
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

}

/// Runs one write at a time for a sheet and keeps the sentence to show when it did not go through (the server's own sentence for a refusal).
@MainActor
final class PFPlanEditRunner529: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    private let tracker = PFJobTracker()
    /// The `id` the last successful job's result carried (a day off the server just made), if any.
    private(set) var lastResultID: String?

    func clear() { message = nil }

    func fail(_ text: String) { message = text }

    /// True when the server took the write. `isAlreadyDone` names a refusal that means the write's effect is already there (a day off that
    /// is gone), which counts as taken.
    func run(_ job: PFJobName, inputs: [String: Any]?, isAlreadyDone: ((String) -> Bool)? = nil) async -> Bool {
        guard let inputs else {
            message = "That could not be sent. Check the values."
            return false
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        lastResultID = nil
        switch await tracker.run(job, inputs: inputs) {
        case .success(let result):
            lastResultID = result["id"].idString
            return true
        case .failure(let failure):
            if let isAlreadyDone, isAlreadyDone(failure.message) { return true }
            message = failure.message
            return false
        }
    }

    /// Cancels one race (`event-update`, `op: "cancel"`). A race that is over is refused with the server's sentence. True when it is off the list.
    func cancelRace(date: String, name: String?) async -> Bool {
        await run(.eventUpdate, inputs: PFPlanInputs529.raceCancel(date: date, name: name))
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
