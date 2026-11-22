import Foundation

// The coach's TrueCoach week on the iPhone (build 542): `GET api/truecoach-status` and the words around a coach-assigned session. Foundation
// only, so it is compiled into the macOS unit-test bundle. The jobs are `truecoach-sync` and `truecoach-replan-undo` (PaceForgeJob.swift),
// their inputs and the confirm flags are in PaceForgePlanEdit.swift. The contract is docs/app-job-contract.md, "Coach plan from TrueCoach".

/// `GET api/truecoach-status`, read leniently (a missing or odd field reads as absent, never as a failure of the whole card).
struct PFTrueCoachStatus: Equatable {
    struct Workout: Equatable {
        let date: String
        let title: String
        let externalID: String?
        let sessionID: String?
    }

    /// One coach session of the current week as the server reports where it stands.
    struct WeekRow: Equatable {
        let sessionID: String?
        /// done | moved | planned | missed | removed_by_coach
        let status: String?
        let skipped: Bool
    }

    /// What the last replan did around the coach's sessions: my own draft sessions it removed to make room, the ones it kept, the booked
    /// classes that overlap a coach session (the athlete checks those) and any warning in plain words.
    struct Replan: Equatable {
        let removed: Int
        let kept: Int
        let conflicts: [String]
        let warnings: [String]

        var isEmpty: Bool { removed == 0 && kept == 0 && conflicts.isEmpty && warnings.isEmpty }
    }

    let lastSync: String?
    let lastError: String?
    let count: Int
    let workouts: [Workout]
    let restDays: Int
    let week: [WeekRow]
    let replan: Replan?

    /// The row of the current week for one session, when the server lists it.
    func weekRow(sessionID: String?) -> WeekRow? {
        guard let sessionID, !sessionID.isEmpty else { return nil }
        return week.first { $0.sessionID == sessionID }
    }

    /// Nil when the body is not a JSON object (an old server answers 404 and never reaches here).
    static func parse(_ data: Data?) -> PFTrueCoachStatus? {
        let json = PFJ(data: data)
        guard json.dict.isEmpty == false else { return nil }
        let workouts = json["workouts"].array.compactMap { row -> Workout? in
            guard let date = row["date"].text, let title = row["title"].text else { return nil }
            return Workout(date: date, title: title, externalID: row["external_id"].text, sessionID: row["session_id"].text)
        }
        let week = json["week"].array.map {
            WeekRow(sessionID: $0["session_id"].text, status: $0["status"].text, skipped: $0["skipped"].bool == true)
        }
        return PFTrueCoachStatus(lastSync: json["last_sync"].text, lastError: json["last_error"].text,
                                 count: json["count"].int ?? workouts.count, workouts: workouts,
                                 restDays: json["rest_days"].array.count, week: week,
                                 replan: json["replan"].exists ? readReplan(json["replan"]) : nil)
    }

    /// `removed` and `kept` are counts, or the lists themselves (their length is the count); a conflict is a text or a row with a title and a day.
    private static func readReplan(_ json: PFJ) -> Replan {
        func count(_ field: PFJ) -> Int { field.int ?? field.array.count }
        return Replan(removed: max(0, count(json["removed"])), kept: max(0, count(json["kept"])),
                      conflicts: json["conflicts"].array.compactMap(conflictLine), warnings: json["warnings"].array.compactMap { $0.text })
    }

    private static func conflictLine(_ row: PFJ) -> String? {
        if let text = row.text { return text }
        guard let what = row["title"].text ?? row["name"].text ?? row["text"].text ?? row["summary"].text else { return nil }
        guard let day = row["date"].text else { return what }
        return "\(PFFormat.dayTitle(day)): \(what)"
    }
}

/// The words of the Coach week card.
enum PFTrueCoachWording {
    static let title = "Your coach's week"
    static let syncButton = "Sync now"
    static let undoButton = "Undo"
    static let checkThese = "Overlaps"

    /// "Last read 3 h ago" from the server's `last_sync`; "Not read yet" before the first read or when the time cannot be read.
    static func lastSync(_ timestamp: String?, now: Date = Date()) -> String {
        guard let when = PFSavedCopy.date(timestamp) else { return "Not read yet" }
        return "Last read " + PFSavedCopy.age(now.timeIntervalSince(when))
    }

    /// "3 sessions from your coach, 1 rest day".
    static func count(_ status: PFTrueCoachStatus) -> String {
        var line = status.count == 1 ? "1 session from your coach" : "\(status.count) sessions from your coach"
        if status.restDays > 0 { line += status.restDays == 1 ? ", 1 rest day" : ", \(status.restDays) rest days" }
        return line
    }

    /// The server's reason in plain words; nil when the last read worked.
    static func error(_ status: PFTrueCoachStatus) -> String? {
        guard let reason = status.lastError else { return nil }
        return "Could not read your TrueCoach plan: " + reason
    }

    /// Nil when nothing was removed.
    static func removed(_ replan: PFTrueCoachStatus.Replan) -> String? {
        guard replan.removed > 0 else { return nil }
        return "I removed \(replan.removed) of my own draft sessions to make room"
    }

    /// "I kept 2 that still fit"; nil when none were kept.
    static func kept(_ replan: PFTrueCoachStatus.Replan) -> String? {
        guard replan.kept > 0 else { return nil }
        return "I kept \(replan.kept) that still fit"
    }
}

/// The words around a coach-assigned session on a week card and in the session sheet.
enum PFCoachSession {
    static let badge = "Coach"
    static let skippedLine = "Skipped \u{2014} counts as missed"
    static let detailsTitle = "Your coach's plan"

    /// "Must be done this week (Mon 23 Nov to Sun 29 Nov)" from the Monday of the coach's week; the range is left out when the Monday is unknown.
    static func mustLine(weekStart: String?) -> String {
        guard let start = weekStart, PFJobInputs.isDay(start) else { return "Must be done this week" }
        return "Must be done this week (\(PFFormat.dayTitle(start)) to \(PFFormat.dayTitle(PFFormat.addDays(start, 6))))"
    }

    /// A skipped coach session: the item says so, or the status document's row for it does.
    static func isSkipped(itemFlag: Bool?, row: PFTrueCoachStatus.WeekRow?) -> Bool {
        itemFlag == true || row?.skipped == true
    }

    /// The coach's text as written (warm-up, lettered exercises with sets and reps, notes), line breaks kept; nil when there is none.
    static func details(_ text: String?) -> String? {
        let clean = (text ?? "").replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(8_000))
    }

    /// Whether the text is long enough to sit in a scrolling box of its own instead of stretching the sheet (more than 14 lines or 700 characters).
    static func needsScroll(_ text: String) -> Bool {
        text.count > 700 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 14
    }
}

/// The static weekly rhythm card (Plan settings).
enum PFWeeklyRhythm {
    static let title = "Weekly rhythm"

    static let text = "Sunday 19:00 week analysis \u{2192} 19:15 your TrueCoach week is read \u{2192} 19:30 next week is drafted from that analysis "
        + "and your coach's sessions \u{2192} 20:00 Coach review. Your coach's sessions are required in their week but can move to any day of it."

    /// "Your TrueCoach week was last read 3 h ago." from `last_sync`; nil when the server never read it.
    static func lastRead(_ timestamp: String?, now: Date = Date()) -> String? {
        guard PFSavedCopy.date(timestamp) != nil else { return nil }
        return "Your TrueCoach week was " + PFTrueCoachWording.lastSync(timestamp, now: now).lowercased() + "."
    }
}
