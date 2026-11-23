import Foundation

// The Coach's questions about a finished workout (build 543), the asked-against-did table and the notes thread of a session. Foundation only, so
// it is compiled into the macOS unit-test bundle (PFPlanScreens543Tests). The server side is docs/app-job-contract.md, "Asked against did,
// workout questions and the piece cut": `GET workout-questions`, the Needs-you item of kind `workout_questions`, the answer kinds
// `workout_answer` / `workout_answer_skip` on `POST app/answer` (the same payload as the `workout-answer` job), `GET session-execution`.
// Every field is read leniently: a missing or odd one reads as absent, never as a failure of the whole card.

// MARK: Questions

struct PFWorkoutQuestion543: Equatable, Identifiable {
    enum Kind: Equatable { case number, choice, date }

    let key: String
    let modality: String
    let name: String
    let text: String
    let kind: Kind
    let unit: String?
    let min: Double?
    let max: Double?
    let choices: [String]
    let prefillNumber: Double?
    let prefillChoice: String?
    /// True when the prefill is the athlete's answer to his last similar workout, shown for him to confirm.
    let confirmsPrefill: Bool
    let why: String?
    /// The questions of one group sit on one page; a question without a group is its own page.
    let group: String?
    /// The question is hidden until another answer has this value (`{"segments.confirm": "adjust"}`).
    let showIf: [String: String]
    /// Hidden when the athlete answered "yes exactly" to the first question.
    let impliedByExact: Bool
    let proposedStartS: Double?
    let proposedEndS: Double?

    var id: String { key }
    var pageID: String { group ?? key }

    static func parse(_ j: PFJ) -> PFWorkoutQuestion543? {
        guard let key = j["key"].text, let text = j["text"].text else { return nil }
        let choices = j["choices"].strings
        let typeWord = (j["type"].text ?? "").lowercased()
        let kind: Kind
        if typeWord == "date" {
            kind = .date
        } else if typeWord == "choice" || (typeWord.isEmpty && !choices.isEmpty) {
            kind = .choice
        } else {
            kind = .number
        }
        let prefill = j["prefill"]
        let showIf = j["show_if"].dict.compactMapValues { $0.text ?? $0.idString }
        let name = j["name"].text ?? String(key.split(separator: ".").last ?? Substring(key))
        return PFWorkoutQuestion543(
            key: key, modality: j["modality"].text ?? String(key.split(separator: ".").first ?? Substring(key)), name: name, text: text,
            kind: kind, unit: j["unit"].text, min: j["min"].double, max: j["max"].double, choices: choices,
            prefillNumber: kind == .number ? prefill.double : nil,
            prefillChoice: kind == .choice ? prefill.text : nil,
            confirmsPrefill: j["confirm"].bool == true && prefill.exists,
            why: j["why"].text, group: j["group"].text, showIf: showIf,
            impliedByExact: j["implied_by_exact"].bool == true,
            proposedStartS: j["proposed"]["start_s"].double, proposedEndS: j["proposed"]["end_s"].double)
    }
}

/// The questions waiting about one workout: the first set (`round` 0) or a follow-up round.
struct PFWorkoutAsk543: Equatable {
    let activityID: String
    let name: String?
    let date: String?
    let round: Int
    let questions: [PFWorkoutQuestion543]

    /// One item of `GET workout-questions`, or the `metric` of a Needs-you item of kind `workout_questions` (both carry the same keys).
    static func parse(_ j: PFJ) -> PFWorkoutAsk543? {
        guard let activity = j["activity_id"].idString else { return nil }
        let questions = j["questions"].array.compactMap { PFWorkoutQuestion543.parse($0) }
        guard !questions.isEmpty else { return nil }
        return PFWorkoutAsk543(activityID: activity, name: j["name"].text, date: j["date"].text, round: j["round"].int ?? 0,
                               questions: questions)
    }

    static func list(_ data: Data?) -> [PFWorkoutAsk543] {
        PFJ(data: data)["items"].array.compactMap { parse($0) }
    }
}

/// One screen of the question flow: a group of questions asked together.
struct PFQuestionPage543: Equatable, Identifiable {
    enum Style: Equatable { case exact, segments, piece }

    let id: String
    let questions: [PFWorkoutQuestion543]

    var style: Style {
        if id == PFQuestionFlow543.exactKey { return .exact }
        return id.hasPrefix("segments.") ? .segments : .piece
    }
}

/// How the athlete moves through the questions and what he typed. A value type: the screen keeps one in `@State`.
struct PFQuestionFlow543: Equatable {
    static let exactKey = "session.exact"
    static let yesExactly = "yes exactly"
    static let segmentsKey = "segments.confirm"
    static let segmentStartKey = "segments.piece_start_s"
    static let segmentEndKey = "segments.piece_end_s"
    static let skipTitle = "Skip, judge from Garmin only"
    static let unknownTitle = "I don't know"

    let ask: PFWorkoutAsk543
    private(set) var typed: [String: String] = [:]
    private(set) var chosen: [String: String] = [:]
    private(set) var unknown: Set<String> = []
    private(set) var pageIndex = 0

    init(ask: PFWorkoutAsk543) {
        self.ask = ask
        for question in ask.questions where question.confirmsPrefill {
            if let number = question.prefillNumber { typed[question.key] = Self.numberText(number) }
            if let choice = question.prefillChoice, question.choices.contains(choice) { chosen[question.key] = choice }
        }
    }

    // MARK: What was typed

    mutating func setText(_ key: String, _ text: String) {
        unknown.remove(key)
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { typed.removeValue(forKey: key) } else { typed[key] = text }
    }

    mutating func choose(_ key: String, _ value: String) {
        unknown.remove(key)
        chosen[key] = value
    }

    mutating func markUnknown(_ key: String) {
        typed.removeValue(forKey: key)
        chosen.removeValue(forKey: key)
        unknown.insert(key)
    }

    mutating func clear(_ key: String) {
        typed.removeValue(forKey: key)
        chosen.removeValue(forKey: key)
        unknown.remove(key)
    }

    // MARK: Pages

    /// "yes exactly" hides the questions the first answer already settles.
    var exactIsYes: Bool { chosen[Self.exactKey] == Self.yesExactly }

    func isVisible(_ question: PFWorkoutQuestion543) -> Bool {
        if exactIsYes, question.impliedByExact { return false }
        for (key, value) in question.showIf where chosen[key] != value && typed[key] != value { return false }
        return true
    }

    /// The pages the athlete goes through now, in the server's order. They change as he answers (yes exactly, adjust).
    var pages: [PFQuestionPage543] {
        var order: [String] = []
        var byID: [String: [PFWorkoutQuestion543]] = [:]
        for question in ask.questions where isVisible(question) {
            if byID[question.pageID] == nil { order.append(question.pageID) }
            byID[question.pageID, default: []].append(question)
        }
        return order.map { PFQuestionPage543(id: $0, questions: byID[$0] ?? []) }
    }

    var currentIndex: Int { Swift.min(pageIndex, Swift.max(0, pages.count - 1)) }
    var currentPage: PFQuestionPage543? { pages.isEmpty ? nil : pages[currentIndex] }
    var isLastPage: Bool { currentIndex >= pages.count - 1 }
    var canGoBack: Bool { currentIndex > 0 }

    /// "1 of 3".
    var positionLine: String { "\(currentIndex + 1) of \(Swift.max(pages.count, 1))" }

    mutating func next() { if !isLastPage { pageIndex = currentIndex + 1 } }
    mutating func back() { if canGoBack { pageIndex = currentIndex - 1 } }

    // MARK: Values

    /// True for a question answered in seconds ("s"): a benchmark or time-trial result such as a 2 km SkiErg time.
    static func isSecondsQuestion(_ question: PFWorkoutQuestion543) -> Bool {
        (question.unit ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "s"
    }

    /// "7:18" is 438 s, "1:02:05" is 3725 s. Minutes and seconds are two digits once there is a larger part; nil for anything else.
    static func clockSeconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let first = Int(parts[0]), let last = Int(parts[parts.count - 1]) else { return nil }
        guard parts[parts.count - 1].count == 2, last < 60 else { return nil }
        if parts.count == 2 { return Double(first * 60 + last) }
        guard parts[1].count == 2, let minutes = Int(parts[1]), minutes < 60 else { return nil }
        return Double(first * 3600 + minutes * 60 + last)
    }

    /// "= 438 s" under a time typed as m:ss or h:mm:ss, so he sees what will be sent; nil otherwise.
    func parsedSecondsLine(_ question: PFWorkoutQuestion543) -> String? {
        guard Self.isSecondsQuestion(question), typed[question.key]?.contains(":") == true, let value = numberValue(question) else { return nil }
        return "= \(Self.numberText(value)) s"
    }

    /// The number a question holds: "5" is 5, "2:05" on a pace per distance is 125 seconds, "7:18" on a time in seconds is 438. nil when empty or not a number.
    func numberValue(_ question: PFWorkoutQuestion543) -> Double? {
        guard let text = typed[question.key]?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.contains(":"), Self.isSecondsQuestion(question) { return Self.clockSeconds(text) }
        let unit = (question.unit ?? "").lowercased()
        if text.contains(":"), unit.hasPrefix("s per") || unit.contains("from the start") {
            return PFTreadmillInput.paceSeconds(text).map { Double($0) }
        }
        return PFTreadmillInput.number(text)
    }

    func dateValue(_ question: PFWorkoutQuestion543) -> String? {
        guard let text = typed[question.key]?.trimmingCharacters(in: .whitespaces), PFJobInputs.isDay(text) else { return nil }
        return text
    }

    /// The sentence that says what is wrong with what he typed for one question, or nil (also nil while it is empty).
    func problem(_ question: PFWorkoutQuestion543) -> String? {
        guard let text = typed[question.key]?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        switch question.kind {
        case .choice:
            return nil
        case .date:
            return PFJobInputs.isDay(text) ? nil : "Give the date as YYYY-MM-DD."
        case .number:
            guard let value = numberValue(question) else { return "Type a number." }
            if let low = question.min, let high = question.max, value < low || value > high {
                let unit = question.unit.map { " (\($0))" } ?? ""
                return "Give a number from \(Self.numberText(low)) to \(Self.numberText(high))\(unit)."
            }
            return nil
        }
    }

    func isAnswered(_ question: PFWorkoutQuestion543) -> Bool {
        if unknown.contains(question.key) { return true }
        switch question.kind {
        case .choice: return chosen[question.key] != nil
        case .date: return dateValue(question) != nil
        case .number: return numberValue(question) != nil && problem(question) == nil
        }
    }

    /// Why Next is off on this page, or nil. The first question must be answered; typed text must be valid; an adjusted cut needs both times.
    func blocker(_ page: PFQuestionPage543) -> String? {
        for question in page.questions {
            if let issue = problem(question) { return issue }
        }
        if page.style == .exact, !page.questions.contains(where: { isAnswered($0) }) { return "Choose one to go on." }
        let adjustsCut = page.questions.contains { $0.key == Self.segmentStartKey || $0.key == Self.segmentEndKey }
        if adjustsCut, chosen[Self.segmentsKey] == "adjust" {
            let start = page.questions.first { $0.key == Self.segmentStartKey }.flatMap { numberValue($0) }
            let end = page.questions.first { $0.key == Self.segmentEndKey }.flatMap { numberValue($0) }
            guard let start, let end, start < end else { return "To adjust, give when the piece started and ended (start before end)." }
        }
        return nil
    }

    // MARK: What is sent

    /// The `answers` object of `workout_answer`: only questions that are shown and answered; "I don't know" is null. Empty when nothing was answered.
    func answers() -> [String: Any] {
        var out: [String: Any] = [:]
        for question in ask.questions where isVisible(question) {
            if unknown.contains(question.key) {
                out[question.key] = NSNull()
                continue
            }
            switch question.kind {
            case .choice:
                if let value = chosen[question.key] { out[question.key] = value }
            case .date:
                if let value = dateValue(question) { out[question.key] = value }
            case .number:
                if let value = numberValue(question), problem(question) == nil { out[question.key] = value }
            }
        }
        return out
    }

    /// The answer to post: the typed answers, or the final skip when nothing was answered.
    var finalAnswer: PFNeedsAnswer {
        let given = answers()
        return given.isEmpty ? .workoutSkip(activityID: ask.activityID) : .workoutAnswers(activityID: ask.activityID, answers: given)
    }

    /// The words on a choice button: "Yes, exactly" for `yes exactly`, else the choice with a capital.
    static func choiceTitle(_ raw: String) -> String {
        raw == yesExactly ? "Yes, exactly" : PFFormat.capitalized(raw)
    }

    /// The unit written beside a typed number ("s per 500 m" reads "seconds per 500 m"), or nil.
    static func unitWords(_ unit: String?) -> String? {
        guard let unit = PFPlanRow543.clean(unit) else { return nil }
        if unit.hasPrefix("s per") { return "seconds" + String(unit.dropFirst(1)) }
        if unit == "s from the start" { return "seconds from the start (or m:ss)" }
        if unit == "s" { return "seconds, or type m:ss or h:mm:ss" }
        return unit
    }

    /// The grey hint inside the empty field: "m:ss" for a time in seconds.
    static func placeholder(_ question: PFWorkoutQuestion543) -> String {
        if question.kind == .date { return "YYYY-MM-DD" }
        return isSecondsQuestion(question) ? "m:ss" : "Type a number"
    }

    /// "5" for 5.0, "2.5" for 2.5.
    static func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

// MARK: Where the pieces ran

/// The bar of drawing 3.5: warm-up, the piece, cooldown, as shares of the recording.
enum PFPieceTimeline543 {
    struct Shares: Equatable {
        let before: Double
        let piece: Double
        let after: Double
    }

    /// Shares of the whole recording. Without its length the part after the piece is taken as long as the part before it.
    static func shares(startS: Double, endS: Double, totalS: Double?) -> Shares? {
        guard startS >= 0, endS > startS else { return nil }
        let total = Swift.max(totalS ?? (endS + startS), endS)
        guard total > 0 else { return nil }
        return Shares(before: startS / total, piece: (endS - startS) / total, after: (total - endS) / total)
    }

    /// 600 -> "10:00", 3725 -> "1:02:05".
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: Asked against did

/// `GET session-execution?activity_id=`: the pieces the description asked for and what the recording shows for each, with the verdict as a word.
struct PFSessionExecution543: Equatable {
    struct Row: Equatable {
        let index: Int
        let asked: String
        let did: String
        /// Under | On target | Over | Not judged | Not enough data
        let verdict: String
        let why: String?
    }

    let isAvailable: Bool
    let reason: String?
    let whatHappened: String?
    let rows: [Row]
    let limits: [String]

    static func parse(_ data: Data?) -> PFSessionExecution543? {
        let j = PFJ(data: data)
        guard j.exists, j["available"].bool != nil || !j["blocks"].array.isEmpty else { return nil }
        let rows = j["blocks"].array.enumerated().map { offset, block in
            Row(index: block["index"].int ?? offset, asked: askedLine(block), did: didLine(block["actual"]),
                verdict: verdictWord(block["verdict"].text), why: block["why"].text)
        }
        let limits = j["limits"].array.isEmpty ? (j["limits"].text.map { [$0] } ?? []) : j["limits"].strings
        return PFSessionExecution543(isAvailable: j["available"].bool != false && !rows.isEmpty, reason: j["reason"].text,
                                     whatHappened: j["what_happened"].text, rows: rows, limits: limits)
    }

    static func verdictWord(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "under": return "Under"
        case "on": return "On target"
        case "over": return "Over"
        case "not_enough_data": return "Not enough data"
        default: return "Not judged"
        }
    }

    /// The piece's text with the band it is judged against: "Warm-up 2 km \u{00B7} heart rate under 140".
    static func askedLine(_ block: PFJ) -> String {
        var parts: [String] = [block["text"].text ?? "Piece"]
        let expected = block["expected"]
        if let band = bandText(expected) { parts.append(band) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private static func bandText(_ expected: PFJ) -> String? {
        let order: [(String, String)] = [("hr", "heart rate"), ("power", "power"), ("pace", "pace"), ("rpe", "effort")]
        for (key, label) in order {
            let pair = expected[key]["band"].array
            guard pair.count == 2, let low = pair[0].double, let high = pair[1].double else { continue }
            let unit = key == "hr" ? " bpm" : (key == "power" ? " W" : (key == "rpe" ? " of 10" : ""))
            func value(_ number: Double) -> String { key == "pace" ? PFFormat.pace(number) : PFQuestionFlow543.numberText(number.rounded()) }
            if high >= 999 { return "\(label) \(value(low)) or more\(unit)" }
            if low <= 0 { return "\(label) under \(value(high))\(unit)" }
            return "\(label) \(value(low)) to \(value(high))\(unit)"
        }
        return nil
    }

    /// What the recording shows for the piece: "average heart rate 138, peak 146" and pace or power when it has them.
    static func didLine(_ actual: PFJ) -> String {
        var parts: [String] = []
        if let avg = actual["avg_hr"].double {
            var text = "average heart rate \(Int(avg.rounded()))"
            if let peak = actual["peak_hr"].double { text += ", peak \(Int(peak.rounded()))" }
            parts.append(text)
        }
        if let power = actual["avg_power_w"].double { parts.append("power \(Int(power.rounded())) W") }
        if let pace = actual["avg_pace_s_per_km"].double { parts.append("pace \(PFFormat.pace(pace))") }
        return parts.isEmpty ? "Nothing recorded for this piece" : parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: Notes thread

/// `GET session-thread?session_id=`: the versions of the assessment, the athlete's notes and the Coach's replies, and whether it is reassessing.
struct PFSessionThread543: Equatable {
    struct Version: Equatable {
        let number: Int
        let at: String?
        let whatChanged: String?
        let text: String?
    }

    struct Message: Equatable {
        let at: String?
        let from: String
        let text: String
    }

    let status: String
    let versions: [Version]
    let messages: [Message]
    let pendingQuestions: Int

    var isReassessing: Bool { ["reassessing", "pending", "running", "queued"].contains(status.lowercased()) }

    var latestVersion: Version? { versions.max { $0.number < $1.number } }

    static func parse(_ data: Data?) -> PFSessionThread543? {
        let j = PFJ(data: data)
        guard j.exists, j["status"].exists || !j["versions"].array.isEmpty || !j["messages"].array.isEmpty else { return nil }
        let versions = j["versions"].array.enumerated().map { offset, row in
            Version(number: row["n"].int ?? offset + 1, at: row["at"].text, whatChanged: row["what_changed"].text, text: row["text"].text)
        }
        let messages = j["messages"].array.compactMap { row -> Message? in
            guard let text = row["text"].text else { return nil }
            return Message(at: row["at"].text, from: row["from"].text ?? "you", text: text)
        }
        let pending = j["pending_questions"]
        return PFSessionThread543(status: j["status"].text ?? "", versions: versions, messages: messages,
                                  pendingQuestions: pending.int ?? pending.array.count)
    }

    /// "Version 1 \u{00B7} Assessed 20:14", or "Version 2 \u{00B7} what changed: the first km is judged against the hill".
    static func versionLine(_ version: Version) -> String {
        var line = "Version \(version.number)"
        if let change = version.whatChanged {
            line += " \u{00B7} what changed: " + change
        } else if let time = PFFormat.timeOfDay(version.at) {
            line += " \u{00B7} Assessed \(time)"
        }
        return line
    }

    /// "Coach" for the Coach's replies, "You" for the athlete's notes.
    static func speaker(_ from: String) -> String {
        ["coach", "assistant", "paceforge"].contains(from.lowercased()) ? "Coach" : "You"
    }
}

// MARK: Words of the session screen

enum PFSessionText543 {
    static let whatToDo = "What to do"
    static let whatYouDid = "What you did"
    static let assessment = "Assessment"
    static let notes = "Notes for the Coach"
    static let reassessing = "Reassessing\u{2026}"
    static let composerPlaceholder = "Write a detail or a comment\u{2026}"
    static let sendAndReassess = "Send and reassess"
    static let sendNote = "Send note"
    static let versionsHint = "Version 1 stays available. Each version says what changed."
    static let addDetail = "Add a detail or comment"

    /// "What to do \u{00B7} about 54 min, estimated". The duration is the plan's minutes; "estimated" when the coach's text says it was.
    static func whatToDoHeader(_ item: PFPlanWeekDoc.Item) -> String {
        guard let minutes = item.minutes, minutes > 0 else { return whatToDo }
        let texts = [item.description, item.coachDetails, item.do].compactMap { $0 }.joined(separator: " ").lowercased()
        return whatToDo + " \u{00B7} about \(minutes) min" + (texts.contains("duration is estimated") ? ", estimated" : "")
    }

    /// "Easy" for `easy`, "All out" for `all_out`.
    static func effortWord(_ effort: String?) -> String? {
        guard let raw = PFPlanRow543.clean(effort) else { return nil }
        return PFFormat.capitalized(raw.replacingOccurrences(of: "_", with: " "))
    }

    /// The text of the workout shown once: the pieces carry it when there are some, else the session's own description.
    static func fallbackText(_ item: PFPlanWeekDoc.Item) -> String? {
        if !(item.pieces ?? []).isEmpty { return nil }
        let text = PFSessionDescription.currentText(description: item.description, coachDetails: item.coachDetails, do: item.do)
        return text.isEmpty ? nil : text
    }

    /// The numbered pieces that carry something to show (a piece the server could not read still shows its text).
    static func pieces(_ item: PFPlanWeekDoc.Item) -> [PFPlanWeekDoc.Piece] {
        (item.pieces ?? []).filter { PFPlanRow543.clean($0.label) != nil || PFPlanRow543.clean($0.text) != nil }
    }
}
