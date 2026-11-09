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

extension PFJobInputs {
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
