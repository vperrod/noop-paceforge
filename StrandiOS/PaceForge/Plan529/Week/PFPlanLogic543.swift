import Foundation

// The words and decisions behind the redesigned Plan screens (build 543): what a session row says, which badges it carries, what the "needs you"
// strip counts, the lines of the Week notes, the overlap sheet and the confirm wording. Foundation only, so it is compiled into the macOS
// unit-test bundle (PFPlanScreens543Tests). Every field it reads is optional on the week document: the server that serves them is deployed
// separately from the phone, so each rule has a fallback built from the fields the document has always carried.

// MARK: Badges

/// One badge on a session row or the session screen: its words and what kind of badge it is. The screen maps `tone` to a colour; the words always
/// carry the meaning, never the colour alone.
struct PFPlanBadge543: Equatable {
    enum Tone: Equatable {
        case coach, mine, classTone, draft, required, todo, done, moved, skipped, reassessing, needsYou, overlap
    }

    let text: String
    let tone: Tone
}

enum PFPlanRow543 {
    static let coachSource = "From your coach"
    static let mineSource = "Mine"
    static let classSource = "Class"
    static let draftSource = "Draft"
    static let requiredWord = "Required this week"
    static let needsYouWord = "Needs your answer"
    static let overlapWord = "Overlaps"

    private static let weekdays: [String: String] = [
        "mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "fri": "Friday", "sat": "Saturday", "sun": "Sunday",
    ]

    /// "Mon" or "Monday" or "monday" as the full weekday; the text unchanged when it is not a weekday.
    static func dayName(_ dow: String?) -> String? {
        guard let dow, !dow.isEmpty else { return nil }
        return weekdays[String(dow.lowercased().prefix(3))] ?? dow
    }

    static func isDone(_ item: PFPlanWeekDoc.Item) -> Bool { ["done", "partial"].contains(item.status ?? "") }

    static func isSession(_ item: PFPlanWeekDoc.Item) -> Bool { (item.kind ?? "session") == "session" }

    static func isCoach(_ item: PFPlanWeekDoc.Item) -> Bool { item.coachAssigned == true }

    /// Whether a coach session must be done this week: the server's `required_this_week`, else the older `mandatory` flag.
    static func isRequired(_ item: PFPlanWeekDoc.Item) -> Bool {
        (item.requiredThisWeek ?? item.mandatory) == true
    }

    static func isSkipped(_ item: PFPlanWeekDoc.Item) -> Bool { item.skippedMandatory == true }

    /// Who the session comes from, in the four words of the design: the server's `source_label`, else worked out from the item.
    static func source(_ item: PFPlanWeekDoc.Item) -> String? {
        guard isSession(item) else { return nil }
        if let label = clean(item.sourceLabel) { return label }
        if isCoach(item) { return coachSource }
        if item.proposed == true { return draftSource }
        if (item.pills ?? []).contains(where: { $0.lowercased().contains("class") }) { return classSource }
        return mineSource
    }

    /// The word for where the session stands. Always a word: "To do", "Done", "Partly done", "Moved", "Skipped", "Missed", "Optional".
    static func stateWord(_ item: PFPlanWeekDoc.Item) -> String? {
        guard isSession(item) else { return nil }
        if let label = clean(item.stateLabel) { return label }
        if isSkipped(item) { return "Skipped" }
        switch item.status ?? "" {
        case "done": return "Done"
        case "partial": return "Partly done"
        case "missed": return "Missed"
        case "optional": return "Optional"
        case "moved": return "Moved"
        case "skipped": return "Skipped"
        default: return item.optional == true ? "Optional" : "To do"
        }
    }

    /// The overlap chip's words: "Overlaps Strength A" for one other session, "Overlaps" for none or several.
    static func overlapText(_ overlap: PFPlanWeekDoc.Overlap) -> String {
        let names = (overlap.with ?? []).compactMap { clean($0) }
        return names.count == 1 ? "\(overlapWord) \(names[0])" : overlapWord
    }

    /// Every badge of a row, in reading order: source, required, state, needs your answer, overlap.
    static func badges(_ item: PFPlanWeekDoc.Item) -> [PFPlanBadge543] {
        guard isSession(item) else { return [] }
        var out: [PFPlanBadge543] = []
        if let word = source(item) { out.append(PFPlanBadge543(text: word, tone: tone(forSource: word))) }
        if isRequired(item), !isSkipped(item) { out.append(PFPlanBadge543(text: requiredWord, tone: .required)) }
        if let state = stateWord(item) { out.append(PFPlanBadge543(text: state, tone: tone(forState: item))) }
        if item.needsYou == true { out.append(PFPlanBadge543(text: needsYouWord, tone: .needsYou)) }
        if let overlap = item.overlap { out.append(PFPlanBadge543(text: overlapText(overlap), tone: .overlap)) }
        return out
    }

    private static func tone(forSource source: String) -> PFPlanBadge543.Tone {
        switch source {
        case coachSource: return .coach
        case classSource: return .classTone
        case draftSource: return .draft
        default: return .mine
        }
    }

    private static func tone(forState item: PFPlanWeekDoc.Item) -> PFPlanBadge543.Tone {
        if isSkipped(item) { return .skipped }
        switch item.status ?? "" {
        case "done", "partial": return .done
        case "moved": return .moved
        case "missed", "skipped": return .skipped
        default: return .todo
        }
    }

    // MARK: Summary line

    /// "2 km warm-up, 5 km, 2 km cooldown" for up to three pieces, "8 pieces, deadlift first" for more. nil without pieces.
    static func piecesSummary(_ pieces: [PFPlanWeekDoc.Piece]?) -> String? {
        let labels = (pieces ?? []).compactMap { clean($0.label) }
        guard let first = labels.first else { return nil }
        if labels.count <= 3 { return labels.joined(separator: ", ") }
        return "\(labels.count) pieces, \(first) first"
    }

    /// The second line of a row. A finished session says what was done; a workout with pieces its pieces; any other its length and effort.
    static func summary(_ item: PFPlanWeekDoc.Item) -> String? {
        guard isSession(item) else { return nil }
        if isDone(item), let line = clean(item.done?.line) { return line }
        if let pieces = piecesSummary(item.pieces) { return pieces }
        var parts: [String] = []
        if let minutes = item.minutes, minutes > 0 { parts.append("\(minutes) min") }
        if let km = item.km, km > 0 { parts.append(km.rounded() == km ? "\(Int(km)) km" : String(format: "%.1f km", km)) }
        if let effort = clean(item.effortLabel) { parts.append(effort) }
        if !parts.isEmpty, PFSessionEffort544.isSetByYou(item) { parts.append(PFSessionEffort544.setByYouWord) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: VoiceOver

    /// The whole row as one sentence: "Monday, run test, from your coach, required this week, to do". The overlap and a waiting question follow.
    static func sentence(_ item: PFPlanWeekDoc.Item, dow: String?) -> String {
        var parts: [String] = []
        if let day = dayName(dow) { parts.append(day) }
        parts.append((clean(item.title) ?? (item.kind == "rest" ? "Rest day" : "Workout")).lowercased())
        if let word = source(item) { parts.append(word.lowercased()) }
        if isSession(item), isRequired(item), !isSkipped(item) { parts.append(requiredWord.lowercased()) }
        if let state = stateWord(item) { parts.append(state.lowercased()) }
        if item.needsYou == true { parts.append(needsYouWord.lowercased()) }
        if let overlap = item.overlap { parts.append(overlapText(overlap).lowercased()) }
        return parts.joined(separator: ", ")
    }

    static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: The strip above Monday

/// What waits for the athlete: a Coach question on a finished workout, an overlap, a change to accept or keep. One strip, one list.
struct PFNeedsEntry543: Equatable, Identifiable {
    enum Kind: Equatable { case question, overlap, change, other }

    let id: String
    let kind: Kind
    let title: String
    let sessionID: String?
    let activityID: String?
}

enum PFNeedsStrip543 {
    static let questionTitle = "Answer the Coach"
    static let overlapTitle = "Review overlaps"
    static let changeTitle = "Review changes"

    static func kind(of raw: String?) -> PFNeedsEntry543.Kind {
        let word = (raw ?? "").lowercased()
        if word.contains("question") || word.contains("answer") { return .question }
        if word.contains("overlap") { return .overlap }
        if word.contains("change") || word.contains("proposal") { return .change }
        return .other
    }

    private static func defaultTitle(_ kind: PFNeedsEntry543.Kind) -> String {
        switch kind {
        case .question: return questionTitle
        case .overlap: return overlapTitle
        case .change: return changeTitle
        case .other: return "Needs you"
        }
    }

    /// The entries of one week. The server's `needs_you.items` when it sends them, else one entry per workout that waits for an answer and per
    /// overlapping pair of sessions; a change waiting to be accepted is always an entry too.
    /// `keptOverlap` says whether the athlete already chose "Keep both" for an overlap (the key is `PFOverlap543.keptKey`); such a pair is not listed.
    static func entries(_ doc: PFPlanWeekDoc, keptOverlap: (String) -> Bool = { _ in false }) -> [PFNeedsEntry543] {
        var out: [PFNeedsEntry543] = []
        if let served = doc.needsYou?.items, !served.isEmpty {
            for (index, row) in served.enumerated() {
                let entryKind = PFNeedsStrip543.kind(of: row.kind)
                out.append(PFNeedsEntry543(id: "served-\(index)-\(row.sessionId ?? row.activityId ?? "")", kind: entryKind,
                                           title: PFPlanRow543.clean(row.title) ?? defaultTitle(entryKind),
                                           sessionID: row.sessionId, activityID: row.activityId))
            }
        } else {
            var seenOverlaps = Set<String>()
            for day in doc.days ?? [] {
                for item in day.items ?? [] {
                    if item.needsYou == true {
                        out.append(PFNeedsEntry543(id: "question-\(item.sessionId ?? item.activityId ?? "")", kind: .question,
                                                   title: questionTitle, sessionID: item.sessionId, activityID: item.activityId))
                    }
                    if let overlap = item.overlap, !keptOverlap(PFOverlap543.keptKey(date: day.date, title: item.title, overlap: overlap)) {
                        let key = overlapKey(date: day.date, title: item.title, overlap: overlap)
                        if seenOverlaps.insert(key).inserted {
                            out.append(PFNeedsEntry543(id: "overlap-\(key)", kind: .overlap, title: overlapTitle,
                                                       sessionID: item.sessionId, activityID: nil))
                        }
                    }
                }
            }
        }
        if !(doc.changes ?? []).isEmpty, !out.contains(where: { $0.kind == .change }) {
            out.append(PFNeedsEntry543(id: "changes", kind: .change, title: changeTitle, sessionID: nil, activityID: nil))
        }
        return out
    }

    /// The same pair of sessions has one key whichever of the two is asked.
    static func overlapKey(date: String?, title: String?, overlap: PFPlanWeekDoc.Overlap) -> String {
        let names = ((overlap.with ?? []) + [title ?? ""]).sorted()
        return (date ?? "") + "|" + names.joined(separator: "|")
    }

    /// The entries to show now: one question entry per workout the live Needs-you list holds (it is what the athlete can answer), else the
    /// week document's own; then overlaps, changes and the rest. Questions come first.
    static func merged(_ entries: [PFNeedsEntry543], liveQuestionActivityIDs: [String]) -> [PFNeedsEntry543] {
        let questions: [PFNeedsEntry543]
        if liveQuestionActivityIDs.isEmpty {
            questions = entries.filter { $0.kind == .question }
        } else {
            questions = liveQuestionActivityIDs.map {
                PFNeedsEntry543(id: "live-\($0)", kind: .question, title: questionTitle, sessionID: nil, activityID: $0)
            }
        }
        let rest = entries.filter { $0.kind != .question }
        let order: [PFNeedsEntry543.Kind] = [.overlap, .change, .other]
        return questions + order.flatMap { kind in rest.filter { $0.kind == kind } }
    }

    /// The number the strip shows: the server's count when it is higher than what the phone can list.
    static func count(_ doc: PFPlanWeekDoc, keptOverlap: (String) -> Bool = { _ in false }) -> Int {
        max(doc.needsYou?.count ?? 0, entries(doc, keptOverlap: keptOverlap).count)
    }

    /// "2 things need you", "1 thing needs you".
    static func headline(count: Int) -> String {
        count == 1 ? "1 thing needs you" : "\(count) things need you"
    }

    /// "Answer the Coach \u{00B7} Review overlaps": each kind once, in the order the entries come.
    static func actionsLine(_ entries: [PFNeedsEntry543]) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        for entry in entries where seen.insert(entry.title).inserted { parts.append(entry.title) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: Week notes

enum PFWeekNotes543 {
    static let rhythmDefault = "Sunday 19:00 analysis, 19:15 coach week read, 19:30 next week drafted, 20:00 Coach review"

    /// "0 of 12 done \u{00B7} coach sessions 0 of 6": every session of the week, then the coach's. nil for a week without sessions.
    static func progressLine(_ doc: PFPlanWeekDoc) -> String? {
        let sessions = (doc.days ?? []).flatMap { $0.items ?? [] }.filter { PFPlanRow543.isSession($0) }
        guard !sessions.isEmpty else { return nil }
        let done = sessions.filter { PFPlanRow543.isDone($0) }.count
        var line = "\(done) of \(sessions.count) done"
        let coach = sessions.filter { PFPlanRow543.isCoach($0) }
        if !coach.isEmpty {
            line += " \u{00B7} coach sessions \(coach.filter { PFPlanRow543.isDone($0) }.count) of \(coach.count)"
        }
        return line
    }

    /// "Read from TrueCoach 3 h ago \u{00B7} 6 sessions", or the reason the last read failed.
    static func coachWeekLine(_ week: PFPlanWeekDoc.CoachWeek?, now: Date = Date()) -> String {
        guard let week else { return "Not read yet" }
        if let error = PFPlanRow543.clean(week.error) { return "Could not read your coach's week: " + error }
        var line = "Read from TrueCoach " + PFTrueCoachWording.lastSync(week.lastSync, now: now)
            .replacingOccurrences(of: "Last read ", with: "")
        if line.hasSuffix("Not read yet") { return "Not read yet" }
        if let count = week.count { line += count == 1 ? " \u{00B7} 1 session" : " \u{00B7} \(count) sessions" }
        return line
    }

    /// "Changes waiting: None" / "2 waiting for you".
    static func changesLine(count: Int?) -> String {
        guard let count, count > 0 else { return "None" }
        return count == 1 ? "1 waiting for you" : "\(count) waiting for you"
    }

    /// "Estimated, your coach gave no durations" or "Planned 5 h 30".
    static func hoursLine(_ hours: PFPlanWeekDoc.NotesHours?, fallback: PFPlanWeekDoc.Hours?) -> String {
        if hours?.estimated == true { return "Estimated, your coach gave no durations" }
        if let planned = hours?.plannedH ?? fallback?.planned { return "Planned " + hoursText(planned) }
        return "Not set"
    }

    /// 5.5 -> "5 h 30", 2 -> "2 h", 0.75 -> "45 min".
    static func hoursText(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }

    static func deletedLine(count: Int?) -> String {
        guard let count, count > 0 else { return "Nothing in the last 30 days" }
        return count == 1 ? "1 session in the last 30 days" : "\(count) sessions in the last 30 days"
    }

    static func rhythmLine(_ notes: PFPlanWeekDoc.Notes?) -> String {
        PFPlanRow543.clean(notes?.rhythm) ?? rhythmDefault
    }

    /// What the collapsed bar reads out: the progress and where the notes are.
    static func barLabel(progress: String?) -> String {
        (progress.map { $0 + ". " } ?? "") + "Week notes"
    }

    /// The number of sessions deleted in the last 30 days: the server's count, else the list it carries.
    static func deletedCount(_ doc: PFPlanWeekDoc) -> Int {
        doc.notes?.deleted?.count ?? (doc.deleted ?? []).count
    }

    static func changesCount(_ doc: PFPlanWeekDoc) -> Int {
        doc.notes?.changes?.count ?? (doc.changes ?? []).count
    }
}

// MARK: Overlap sheet

enum PFOverlap543 {
    static let keepBoth = "Keep both"
    static let moveClass = "Move the class to another day"
    static let skipClass = "Skip the class"

    /// The sessions of the day the overlap is about: the item itself and every session of that day it names.
    static func sessions(on day: PFPlanWeekDoc.Day, with item: PFPlanWeekDoc.Item) -> [PFPlanWeekDoc.Item] {
        let names = Set((item.overlap?.with ?? []).map { $0.lowercased() })
        return (day.items ?? []).filter { other in
            guard PFPlanRow543.isSession(other) else { return false }
            if other.sessionId != nil, other.sessionId == item.sessionId { return true }
            return names.contains((other.title ?? "").lowercased())
        }
    }

    /// The coach's session of the pair and the other one (the class, or the athlete's own session).
    static func split(_ pair: [PFPlanWeekDoc.Item]) -> (coach: PFPlanWeekDoc.Item?, other: PFPlanWeekDoc.Item?) {
        let coach = pair.first { PFPlanRow543.isCoach($0) }
        let other = pair.first { candidate in
            guard let coach else { return true }
            return candidate.sessionId != coach.sessionId || candidate.title != coach.title
        }
        return (coach, other)
    }

    /// "Two sessions on one day. Your coach's Strength A is required this week. The Cardio Class is yours."
    static func intro(coach: PFPlanWeekDoc.Item?, other: PFPlanWeekDoc.Item?) -> String {
        var text = "Two sessions on one day."
        if let coach, let title = PFPlanRow543.clean(coach.title) {
            text += PFPlanRow543.isRequired(coach) ? " Your coach's \(title) is required this week." : " Your coach's \(title) is one of the two."
        }
        if let other, let title = PFPlanRow543.clean(other.title) {
            text += coach == nil ? " \(title) is one of them." : " The \(title) is yours."
        }
        return text
    }

    /// The session that moves or is skipped: never the coach's required one. nil when the pair has no session the athlete may change.
    static func changeable(_ pair: [PFPlanWeekDoc.Item]) -> PFPlanWeekDoc.Item? {
        let parts = split(pair)
        guard let other = parts.other, other.sessionId != nil, !PFPlanRow543.isCoach(other) else { return nil }
        return other
    }

    /// The key the phone keeps for "Keep both", so the chip is not offered again for the same pair on that day.
    static func keptKey(date: String?, title: String?, overlap: PFPlanWeekDoc.Overlap) -> String {
        "noop.plan.overlapKept." + PFNeedsStrip543.overlapKey(date: date, title: title, overlap: overlap)
    }
}

// MARK: Confirm wording

/// What the athlete is asked before a coach's session is skipped (drawing 3.13).
enum PFSkipCoachConfirm543 {
    static let title = "Skip your coach's session?"
    static let confirmTitle = "Skip it, record as missed"
    static let keepTitle = "Keep it"

    static func message(sessionTitle: String?) -> String {
        let name = PFPlanRow543.clean(sessionTitle) ?? "This session"
        return "\(name) is required this week. If you skip it, it is recorded as missed and shows in the week analysis. You can undo this."
    }

    /// The sentence the screen shows once the skip went through.
    static let doneNote = "Skipped. It counts as missed. You can undo this."
}

// MARK: The three dots

/// What the ··· menu of a session offers, in the order of the drawing: move, skip, swap, make optional, then the rest.
enum PFMenuItem543: String, Equatable {
    case move, skip, swap, optional, accept, drop, easier, details, askCoach, judged
}

enum PFSessionMenu543 {
    /// A planned, optional or missed session gets every change; a finished one only how it was judged and a question for the Coach.
    static func items(status: String, isOptional: Bool, isDone: Bool) -> [PFMenuItem543] {
        if isDone { return [.judged, .askCoach] }
        var out: [PFMenuItem543] = []
        if ["planned", "optional", "missed"].contains(status) {
            out.append(contentsOf: [.move, .skip, .swap])
            out.append(contentsOf: (isOptional || status == "optional") ? [.accept, .drop] : [.optional])
            out.append(contentsOf: [.easier, .details])
        } else {
            out.append(.swap)
        }
        out.append(contentsOf: [.judged, .askCoach])
        return out
    }

    static func title(_ item: PFMenuItem543) -> String {
        switch item {
        case .move: return "Move to another day"
        case .skip: return "Skip"
        case .swap: return "Swap for another workout"
        case .optional: return "Make optional"
        case .accept: return "Accept this draft"
        case .drop: return "Drop this draft"
        case .easier: return "Make it easier"
        case .details: return "Change length or effort"
        case .askCoach: return "Ask the Coach about it"
        case .judged: return "How it was judged"
        }
    }
}

// MARK: Text sizes

/// The text styles Plan text maps to, so every size follows the phone's text setting and nothing carrying meaning is under 15 points.
enum PFPlanTextStyle543: String, Equatable {
    case subheadline, callout, body, title3, title2, title

    /// The size a design asked for, as the style it scales with. Anything under 15 is read as 15.
    static func style(forSize size: Double) -> PFPlanTextStyle543 {
        switch size {
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        default: return .title
        }
    }
}

// MARK: Finished week

/// One line of "Planned against done" in a finished week's report: the session and where it ended up.
struct PFReportRow543: Equatable {
    let title: String
    let day: String?
    let state: String
    let isCoach: Bool
    let sessionID: String?
    let activityID: String?

    /// "Run test, from your coach, done".
    var sentence: String {
        [title.lowercased(), isCoach ? PFPlanRow543.coachSource.lowercased() : nil, state.lowercased()].compactMap { $0 }.joined(separator: ", ")
    }
}

enum PFReportSessions543 {
    /// Every session of the finished week once, the coach's first. A session still "to do" in a finished week was not done.
    static func rows(_ doc: PFPlanWeekDoc) -> [PFReportRow543] {
        var out: [PFReportRow543] = []
        for day in doc.days ?? [] {
            for item in day.items ?? [] where PFPlanRow543.isSession(item) {
                var state = PFPlanRow543.stateWord(item) ?? "Not done"
                if state == "To do" { state = "Not done" }
                out.append(PFReportRow543(title: PFPlanRow543.clean(item.title) ?? "Session", day: PFPlanRow543.dayName(day.dow),
                                          state: state, isCoach: PFPlanRow543.isCoach(item), sessionID: item.sessionId,
                                          activityID: item.activityId))
            }
        }
        return out.filter { $0.isCoach } + out.filter { !$0.isCoach }
    }
}
