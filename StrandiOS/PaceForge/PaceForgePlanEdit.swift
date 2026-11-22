import Foundation

// Editing one planned session from the app: move it to another day, skip it, accept an optional draft or drop it. Foundation only, so
// it is compiled into the macOS unit-test bundle. The jobs are `calendar-edit`, `session-state` and `session-drop` (PaceForgeJob.swift).
// The contract has no separate "skip": the web's Remove, which the app calls Skip, is `calendar-edit` with `delete`.

enum PFPlanEdit {
    /// The sessions the edits apply to: planned, missed or optional, with the real planned/calendar session id (an activity-only row has none).
    static func applies(status: String, sessionID: String?) -> Bool {
        guard ["planned", "missed", "optional"].contains(status) else { return false }
        return PFJobInputs.sessionID(sessionID) != nil
    }

    /// What `session-state` sets; the app only accepts (`active`).
    static let acceptedState = "active"
}

/// The three confirmations the server asks for before it touches a coach-assigned (mandatory) session. The raw value is the input flag; it is
/// only ever sent as `true`, and only after the athlete tapped the matching confirm button.
enum PFMandatoryConfirm: String, Equatable, CaseIterable {
    /// `calendar-edit` reschedule to a day outside the coach's week.
    case leaveWeek = "confirm_leave_week"
    /// `calendar-edit` delete (Skip): the session stays as skipped_mandatory and counts as missed.
    case skipMandatory = "confirm_skip_mandatory"
    /// `session-swap` on the session: the content is replaced, the session stays the coach's.
    case replaceMandatory = "confirm_replace_mandatory"

    /// Which confirmation a refusal asks for, or nil when it is some other refusal. The server's reason names the flag it wants
    /// ("... Send confirm_skip_mandatory: true to skip it."), so the flag name is the signal, not the wording around it.
    static func needed(by error: PFJobError) -> PFMandatoryConfirm? {
        guard case .refused(let text) = error else { return nil }
        return allCases.first { text.contains($0.rawValue) }
    }

    /// The question the confirmation sheet asks.
    var question: String {
        switch self {
        case .leaveWeek: return "This is your coach's session. Move it out of its week anyway?"
        case .skipMandatory: return "Skip your coach's session? It will be recorded as missed."
        case .replaceMandatory: return "This is your coach's session. Replace it anyway? It stays your coach's session."
        }
    }

    var confirmTitle: String {
        switch self {
        case .leaveWeek: return "Move anyway"
        case .skipMandatory: return "Skip anyway"
        case .replaceMandatory: return "Replace anyway"
        }
    }
}

extension PFJobInputs {
    /// The same inputs with the confirmation flag the athlete just gave. Nil stays nil: a request that could not be built is never confirmed.
    static func confirmed(_ inputs: [String: Any]?, _ confirm: PFMandatoryConfirm) -> [String: Any]? {
        guard var inputs else { return nil }
        inputs[confirm.rawValue] = true
        return inputs
    }

    /// `truecoach-sync`: read the coach's plan now. No inputs.
    static func truecoachSync() -> [String: Any] { [:] }

    /// `truecoach-replan-undo`: put back the draft sessions the last replan removed. No inputs.
    static func truecoachReplanUndo() -> [String: Any] { [:] }

    /// A session id as the server reads it: at most 80 characters of letters, digits and `_ . : -`.
    static func sessionID(_ id: String?) -> String? {
        guard let id, !id.isEmpty, id.count <= 80 else { return nil }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-")
        return id.allSatisfy { allowed.contains($0) } ? id : nil
    }

    /// `calendar-edit` with `reschedule`: the session and the day (`YYYY-MM-DD`) to move it to. Nothing else goes with it.
    static func calendarMove(sessionID id: String?, to date: String) -> [String: Any]? {
        guard let id = sessionID(id), isDay(date) else { return nil }
        return ["session_id": id, "action": "reschedule", "new_date": date]
    }

    /// `calendar-edit` with `delete` (Skip): the session only.
    static func calendarDelete(sessionID id: String?) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        return ["session_id": id, "action": "delete"]
    }

    static func calendarRestore(sessionID id: String?) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        return ["session_id": id, "action": "restore"]
    }

    /// `session-state`: accept an optional draft (`active`).
    static func sessionAccept(sessionID id: String?) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        return ["session_id": id, "state": PFPlanEdit.acceptedState]
    }

    /// `session-drop`: drop an optional draft.
    static func sessionDrop(sessionID id: String?) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        return ["session_id": id]
    }

    /// `YYYY-MM-DD`, digits only.
    static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
}
