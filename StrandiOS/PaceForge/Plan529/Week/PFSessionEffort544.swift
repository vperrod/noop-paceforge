import Foundation

// The athlete's last word on how hard a session is and how long it takes (build 544): the four choices, the minutes limits, whether a shown value is
// "Your choice" or the app's estimate, the form of the "How hard" card and the `session-effort` inputs. Foundation only, so it is compiled into the
// macOS unit-test bundle (PFSessionEffort544Tests). The week document carries the choice in `effort_choice` / `minutes_choice`; the older server that
// does not send them leaves both nil and the form simply starts without a choice.

/// The four words the athlete can pick, with the value the server takes for each.
enum PFEffortChoice544: String, CaseIterable, Equatable {
    case easy
    case moderate
    case hard
    case allOut = "all_out"

    var title: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .allOut: return "All out"
        }
    }

    /// A word the server sent ("hard", "all_out", "All out") as a choice; nil for anything else (a race, a made-up word).
    init?(server word: String?) {
        let clean = (word ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        self.init(rawValue: clean)
    }
}

enum PFSessionEffort544 {
    static let minMinutes = 1
    static let maxMinutes = 360
    static let minutesStep = 5
    /// Where the stepper starts when the session has no minutes at all.
    static let defaultMinutes = 30

    static let sectionTitle = "How hard"
    static let yourChoiceWord = "Your choice"
    static let estimatedWord = "Estimated"
    static let plannedWord = "Planned"
    static let setByYouWord = "set by you"
    static let resetTitle = "Reset to estimate"
    static let saveTitle = "Save"
    static let savedNote = "Saved. The plan now uses your choice."
    static let resetNote = "Back to the estimate."
    static let notSetWord = "Not set"
    static let minutesOutOfRange = "Minutes must be between 1 and 360."

    /// Whose value is on screen.
    enum Source: Equatable {
        case yours, estimated, planned
    }

    /// The athlete's own value wins; else the server's `*_estimated` flag says "Estimated"; a value that is not an estimate (a coach's written
    /// effort) is "Planned". A server that sends no flag at all reads as "Planned" too, never as a guess.
    static func source(hasChoice: Bool, isEstimated: Bool?) -> Source {
        if hasChoice { return .yours }
        return isEstimated == true ? .estimated : .planned
    }

    static func label(_ source: Source) -> String {
        switch source {
        case .yours: return yourChoiceWord
        case .estimated: return estimatedWord
        case .planned: return plannedWord
        }
    }

    /// Nil when the minutes can be sent (or are not sent at all); else the sentence that says why not.
    static func minutesProblem(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        return (minMinutes...maxMinutes).contains(minutes) ? nil : minutesOutOfRange
    }

    /// The athlete set the effort or the minutes of this session himself.
    static func isSetByYou(_ item: PFPlanWeekDoc.Item) -> Bool {
        item.effortChoice != nil || item.minutesChoice != nil
    }
}

// MARK: Job inputs

extension PFJobInputs {
    /// `session-effort`: `{session_id, effort: easy|moderate|hard|all_out|null, minutes: 1...360|null}`. Both keys are always present; a nil goes
    /// out as JSON null, and both null clears the choice ("Reset to estimate"). nil when the session id or the minutes are outside the contract.
    static func sessionEffort(sessionID id: String?, effort: PFEffortChoice544?, minutes: Int?) -> [String: Any]? {
        guard let id = sessionID(id), PFSessionEffort544.minutesProblem(minutes) == nil else { return nil }
        return ["session_id": id, "effort": orNull(effort?.rawValue), "minutes": orNull(minutes)]
    }

    private static func orNull(_ value: Any?) -> Any { value ?? NSNull() }
}

// MARK: The form

/// The "How hard" card of one session: the choice as typed, what the server had when the card opened, and the estimate shown while there is no choice.
struct PFSessionEffortForm544: Equatable {
    let sessionID: String
    /// The app's value for the session (what `effort_label` / `minutes` carry when no choice is set).
    let shownEffortWord: String?
    let shownMinutes: Int?
    let isEffortEstimated: Bool?
    let isMinutesEstimated: Bool?
    private(set) var originalEffort: PFEffortChoice544?
    private(set) var originalMinutes: Int?
    /// "Reset to estimate" is offered only while the server holds a choice.
    private(set) var hasChoice: Bool
    var effort: PFEffortChoice544?
    var minutes: Int?

    init(item: PFPlanWeekDoc.Item, sessionID: String) {
        self.sessionID = sessionID
        let word = (item.effortLabel ?? item.effort ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        shownEffortWord = word.isEmpty ? nil : word
        shownMinutes = item.minutes
        isEffortEstimated = item.effortEstimated
        isMinutesEstimated = item.minutesEstimated
        originalEffort = PFEffortChoice544(server: item.effortChoice)
        originalMinutes = item.minutesChoice
        hasChoice = PFSessionEffort544.isSetByYou(item)
        effort = originalEffort
        minutes = originalMinutes
    }

    // MARK: What the card shows

    /// The effort word on screen: the chosen one, else the estimate.
    var effortWord: String? { effort?.title ?? shownEffortWord }
    /// The minutes on screen: the chosen ones, else the estimate.
    var minutesShown: Int? { minutes ?? shownMinutes }
    var effortSource: PFSessionEffort544.Source { PFSessionEffort544.source(hasChoice: effort != nil, isEstimated: isEffortEstimated) }
    var minutesSource: PFSessionEffort544.Source { PFSessionEffort544.source(hasChoice: minutes != nil, isEstimated: isMinutesEstimated) }
    var effortLabel: String { PFSessionEffort544.label(effortSource) }
    var minutesLabel: String { PFSessionEffort544.label(minutesSource) }

    // MARK: What can be sent

    var hasChanges: Bool { effort != originalEffort || minutes != originalMinutes }
    var problem: String? { PFSessionEffort544.minutesProblem(minutes) }
    var canSend: Bool { hasChanges && problem == nil }

    /// The `session-effort` inputs for what the card shows. nil when nothing changed or the minutes are out of range.
    func inputs() -> [String: Any]? {
        guard canSend else { return nil }
        return PFJobInputs.sessionEffort(sessionID: sessionID, effort: effort, minutes: minutes)
    }

    /// The `session-effort` inputs that clear the choice.
    func resetInputs() -> [String: Any]? {
        PFJobInputs.sessionEffort(sessionID: sessionID, effort: nil, minutes: nil)
    }

    /// The same card after the server took what it shows: the shown values are now the server's.
    func afterSaving() -> PFSessionEffortForm544 {
        var out = self
        out.originalEffort = effort
        out.originalMinutes = minutes
        out.hasChoice = effort != nil || minutes != nil
        return out
    }

    /// The same card with no choice (after "Reset to estimate" was taken).
    func afterReset() -> PFSessionEffortForm544 {
        var out = self
        out.effort = nil
        out.minutes = nil
        return out.afterSaving()
    }
}
