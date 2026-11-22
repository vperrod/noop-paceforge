import Foundation

// Editing the description of any session from the iPhone (and writing one's own with a description): the limits, the `calendar-edit` inputs
// (`description`, `name`, `reassess`, action `restore_coach_text`), the draft kept on the phone, and how the result reads. Foundation only, so it is
// compiled into the macOS unit-test bundle. The contract is docs/app-job-contract.md (`calendar-edit`, `add-session`); every limit is the server's own,
// counted in characters the way the server counts them (Unicode scalars), so the app never sends what would be refused.

enum PFSessionDescription {
    static let maxLength = 4_000
    static let maxNameLength = 120

    static let savedNote = "Saved."
    static let reassessingNote = "Saved. The Coach is reassessing this workout."
    static let partialNote = "Saved \u{2014} the Coach could not be reached yet, saving again retries."
    static let restoredNote = "The Coach's text is back."
    static let editedLine = "Edited by you"
    static let restoreTitle = "Restore your coach's text"
    static let restoreQuestion = "Replace your text with the one your coach wrote? What you wrote is lost."
    static let restoreConfirmTitle = "Restore your coach's text"
    /// The example in the Plan a workout form (drawing 3.10).
    static let planHint = "Example: 10 min easy, then 5 x 4 min hard on the SkiErg with 2 min rest, cooldown 5 min."
    /// The hint in the Log what I did form (drawing 3.11).
    static let logHint = "What you did, piece by piece. The Coach reads it and may ask you a question."
    static let addHint = "Write what the workout is: warm-up, sets x reps, intervals, effort, anything the Coach should know"

    /// Length as the server counts it: characters (code points), not what the keyboard shows as one letter.
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    /// Line breaks as `\n`, outer blank space gone. Breaks inside the text stay.
    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The full text the edit sheet starts from: the session's own description, else the coach's text, else the written-out "do" line. Never cut.
    static func currentText(description: String?, coachDetails: String?, do doLine: String?) -> String {
        for candidate in [description, coachDetails, doLine] {
            let clean = normalized(candidate ?? "")
            if !clean.isEmpty { return clean }
        }
        return ""
    }

    /// What is wrong with a description about to be sent, or nil. Empty is refused: the server takes a non-empty description only.
    static func descriptionProblem(_ text: String) -> String? {
        let clean = normalized(text)
        if clean.isEmpty { return "The description cannot be empty." }
        if length(clean) > maxLength { return "The description is too long (4000 characters at most)." }
        return nil
    }

    static func nameProblem(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "The name cannot be empty." }
        if length(clean) > maxNameLength { return "The name is too long (120 characters at most)." }
        return nil
    }

    /// The `reassess` value to send. A finished workout is always sent an explicit yes or no (the server's default for one is yes, so a plain
    /// Save has to say no); a session that is not done is never sent the flag, there is nothing to reassess.
    static func reassessFlag(isDone: Bool, wantsReassess: Bool) -> Bool? {
        isDone ? wantsReassess : nil
    }

    /// "Restore coach text" is offered on a session the coach assigned.
    static func canRestoreCoachText(isCoachAssigned: Bool) -> Bool { isCoachAssigned }

    static func draftKey(sessionID: String) -> String { "noop.paceforge.sessionDescription.\(sessionID)" }
}

// MARK: Job inputs

extension PFJobInputs {
    /// `calendar-edit` with `edit` carrying the description and/or the name (any session, a coach's too). Only what is given is sent; `reassess` goes
    /// when it is not nil. nil when nothing is given or a value is outside the server's limits.
    static func calendarDescribe(sessionID id: String?, description: String? = nil, name: String? = nil, reassess: Bool? = nil) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        var inputs: [String: Any] = ["session_id": id, "action": "edit"]
        if let description {
            guard PFSessionDescription.descriptionProblem(description) == nil else { return nil }
            inputs["description"] = PFSessionDescription.normalized(description)
        }
        if let name {
            guard PFSessionDescription.nameProblem(name) == nil else { return nil }
            inputs["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard inputs.count > 2 else { return nil }
        if let reassess { inputs["reassess"] = reassess }
        return inputs
    }

    /// `calendar-edit` with `restore_coach_text`: the coach's original text back on the session. The session only.
    static func calendarRestoreCoachText(sessionID id: String?) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        return ["session_id": id, "action": "restore_coach_text"]
    }
}

// MARK: The edit form

/// The edit-description form of one session: the text and the name as typed, and what the server had when the sheet opened. Codable so what was
/// typed can stay on the phone until the server takes it.
struct PFSessionDescriptionDraft: Codable, Equatable {
    let sessionID: String
    var originalDescription: String
    var originalName: String
    var description: String
    var name: String

    init(sessionID: String, description: String, name: String) {
        self.sessionID = sessionID
        originalDescription = description
        originalName = name
        self.description = description
        self.name = name
    }

    var changedDescription: Bool { PFSessionDescription.normalized(description) != PFSessionDescription.normalized(originalDescription) }
    var changedName: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines) != originalName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasChanges: Bool { changedDescription || changedName }

    /// The sentence that says what is wrong with the form, or nil when it can be sent. Only a field that changed is checked.
    var problem: String? {
        if changedDescription, let issue = PFSessionDescription.descriptionProblem(description) { return issue }
        if changedName, let issue = PFSessionDescription.nameProblem(name) { return issue }
        return nil
    }

    var canSend: Bool { hasChanges && problem == nil }

    /// The `calendar-edit` inputs: the changed fields only. nil when nothing changed or the form has a problem.
    func inputs(reassess: Bool?) -> [String: Any]? {
        guard canSend else { return nil }
        return PFJobInputs.calendarDescribe(sessionID: sessionID, description: changedDescription ? description : nil,
                                            name: changedName ? name : nil, reassess: reassess)
    }

    /// The same words on top of what the server has now: a draft kept on the phone is shown again over the session's present text.
    func rebased(description current: String, name currentName: String) -> PFSessionDescriptionDraft {
        var out = PFSessionDescriptionDraft(sessionID: sessionID, description: current, name: currentName)
        out.description = description
        out.name = name
        return out
    }

    /// Back to what the server has.
    func startedOver() -> PFSessionDescriptionDraft {
        PFSessionDescriptionDraft(sessionID: sessionID, description: originalDescription, name: originalName)
    }
}

/// What stays on the phone between two openings of the sheet: an unsent edit, kept until the server takes it.
enum PFSessionDescriptionKeeping {
    static func encode(_ draft: PFSessionDescriptionDraft) -> Data? { try? JSONEncoder().encode(draft) }

    static func decode(_ data: Data?) -> PFSessionDescriptionDraft? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PFSessionDescriptionDraft.self, from: data)
    }

    /// The form the sheet opens with: a kept edit of this session that still differs from the session's present text, else the present text.
    static func opening(kept: Data?, sessionID: String, description: String, name: String) -> PFSessionDescriptionDraft {
        let fresh = PFSessionDescriptionDraft(sessionID: sessionID, description: description, name: name)
        guard let old = decode(kept), old.sessionID == sessionID else { return fresh }
        let rebased = old.rebased(description: description, name: name)
        return rebased.hasChanges ? rebased : fresh
    }

    /// What to write to storage for the form as it stands: the data to keep, or nil when nothing is unsent (the stored copy is removed).
    static func toStore(_ draft: PFSessionDescriptionDraft) -> Data? {
        draft.hasChanges ? encode(draft) : nil
    }
}

// MARK: The result

/// The result of `calendar-edit` with a description: `{session_id, description_saved, analysis_id|null, partial}`.
struct PFSessionDescriptionResult: Equatable {
    let sessionID: String?
    let descriptionSaved: Bool?
    let analysisID: String?
    let partial: Bool

    init(_ result: PFJ) {
        sessionID = result["session_id"].text
        descriptionSaved = result["description_saved"].bool
        analysisID = result["analysis_id"].idString
        partial = result["partial"].bool == true
    }

    /// The sentence under the button after a save. The reassessing sentence only when a reassessment was asked for and the server queued one;
    /// a save whose reassessment could not be queued says so.
    func note(reassessAsked: Bool) -> String {
        if partial { return PFSessionDescription.partialNote }
        if reassessAsked, analysisID != nil { return PFSessionDescription.reassessingNote }
        return PFSessionDescription.savedNote
    }
}
