import Foundation

/// The decisions behind the build-530 journal screens, with no UI and no storage: which day an answer belongs to, which questions a window
/// asks, what "Same as yesterday" pre-fills, the writes that turn what is saved into what is staged, the device-answered rows and the
/// grouping of the behaviour insights. Foundation only, so it is unit tested (PFJournalLogic530Tests).
enum PFJournalLogic530 {
    typealias Question = PFJournalDoc530.Question
    typealias Insight = PFJournalDoc530.Insight

    static let morning = "morning"
    static let afternoon = "afternoon"
    static let evening = "evening"
    static let windows = [morning, afternoon, evening]

    /// The days with and without a behaviour a result needs.
    static let daysNeeded = 5

    /// The afternoon question's key when no saved document names one: the starter question the server asks at that time.
    static let starterAfternoonKey = "Did you have caffeine late in the day?"

    // MARK: Days

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// "Saturday 14 Nov" for "2026-11-14"; nil when `iso` is not a day.
    static func dayName(_ iso: String) -> String? {
        guard let date = formatter.date(from: iso) else { return nil }
        let names = DateFormatter()
        names.calendar = calendar
        names.timeZone = calendar.timeZone
        names.locale = Locale(identifier: "en_GB")
        names.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return names.string(from: date)
    }

    /// "2026-11-16" plus `days` ("2026-11-15" for -1); nil when `iso` is not a day.
    static func addDays(_ iso: String, _ days: Int) -> String? {
        guard let date = formatter.date(from: iso), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return formatter.string(from: moved)
    }

    /// A morning answer is about last night, any other answer about the day it is given on.
    static func defaultAbout(window: String) -> String {
        window == morning ? "yesterday" : "today"
    }

    /// The day an answer is saved on: the day the behaviour happened. `about` is the document's word for it ("yesterday" | "today").
    static func behaviourDay(about: String?, window: String, today: String) -> String {
        let word = about ?? defaultAbout(window: window)
        return word == "yesterday" ? (addDays(today, -1) ?? today) : today
    }

    /// The day a whole window of questions is about: what its first question says, else the window's usual.
    static func day(window: String, questions: [Question], today: String) -> String {
        behaviourDay(about: questions.first?.about, window: window, today: today)
    }

    // MARK: Questions

    /// The questions a window asks, in the document's order. A question without a key cannot be stored and is left out, and so is one the
    /// athlete hid in the journal's own editor. `extra` (the questions added on the phone) follow.
    static func questions(in list: [Question]?, window: String, hidden: Set<String> = [], extra: [Question] = [],
                          selectedKeys: [String]? = nil) -> [Question] {
        // nil supports older servers; an explicit empty assignment means no ask.
        // Local-only legacy questions remain editable until they are shared.
        let selected = selectedKeys.map(Set.init)
        let server = (list ?? []).filter { selected?.contains($0.key ?? "") ?? true }
        let all = server + extra
        let hiddenKeys = Set(hidden.map { norm($0) })
        var seen = Set<String>()
        let kept = all.filter { question in
            guard let key = question.key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return !hiddenKeys.contains(norm(key)) && seen.insert(norm(key)).inserted
        }
        // A question that names no window is asked in the evening.
        return kept.filter { ($0.window ?? evening) == window }
    }

    /// The identity of a question for matching: the journal catalog's own rule (case and spacing do not tell two questions apart).
    static func norm(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }

    /// The question's own wording for the screen: the server's prompt, else its label, else the key.
    static func prompt(_ question: Question) -> String {
        for text in [question.prompt, question.label, question.key] {
            if let text, !text.isEmpty { return text }
        }
        return ""
    }

    static func kind(_ question: Question) -> String {
        switch question.kind ?? "yes_no" {
        case "count", "time", "scale": return question.kind ?? "yes_no"
        default: return "yes_no"
        }
    }

    // MARK: Answers

    /// One answer as the journal stores it: yes or no, with the number a count, scale or time question carries (a time is minutes after
    /// midnight) and a note ("last 21:30").
    struct Answer: Equatable {
        var yes: Bool
        var number: Double?
        var note: String?

        init(yes: Bool, number: Double? = nil, note: String? = nil) {
            self.yes = yes
            self.number = number
            self.note = note
        }
    }

    /// What the athlete did to one question on the screen: chose an answer, or took the answer away.
    enum Edit: Equatable {
        case set(Answer)
        case cleared
    }

    enum Write: Equatable {
        case save(question: String, answer: Answer)
        case clear(question: String)
    }

    /// Tapping a chip: the other chip chooses it, the chosen chip again takes the answer away. A yes to a count starts at 1; a yes to a
    /// time starts at `defaultTime` (minutes after midnight).
    static func choose(kind: String, yes: Bool, current: Answer?, defaultTime: Double) -> Edit {
        if current?.yes == yes { return .cleared }
        guard yes else { return .set(Answer(yes: false)) }
        switch kind {
        case "count": return .set(Answer(yes: true, number: 1))
        case "time": return .set(Answer(yes: true, number: defaultTime))
        default: return .set(Answer(yes: true))
        }
    }

    /// The answer with a new number (a stepper, a 1 to 5 chip, a time); a no has none.
    static func withNumber(_ answer: Answer, _ number: Double?) -> Answer {
        guard answer.yes else { return answer }
        return Answer(yes: true, number: number, note: answer.note)
    }

    /// The answer with a note, or without one when `note` is empty.
    static func withNote(_ answer: Answer, _ note: String?) -> Answer {
        guard answer.yes else { return answer }
        return Answer(yes: true, number: answer.number, note: (note?.isEmpty ?? true) ? nil : note)
    }

    /// The answers on screen: what is saved; "Same as yesterday" adds the day before's answer to each question with none yet; the
    /// athlete's own edits come last and win.
    static func staged(saved: [String: Answer], previous: [String: Answer], usePrevious: Bool, keys: [String],
                       edits: [String: Edit]) -> [String: Answer] {
        var out = saved
        if usePrevious {
            for key in keys where saved[key] == nil {
                if let before = previous[key] { out[key] = Answer(yes: before.yes, number: before.number, note: nil) }
            }
        }
        for key in keys {
            switch edits[key] {
            case .set(let answer)?: out[key] = answer
            case .cleared?: out.removeValue(forKey: key)
            case nil: break
            }
        }
        return out
    }

    /// The writes that turn `saved` into `staged` for these questions, in key order. An answer already saved as it is staged is not
    /// written again, so a note the screen does not show stays.
    static func writes(saved: [String: Answer], staged: [String: Answer], keys: [String]) -> [Write] {
        var out: [Write] = []
        for key in Set(keys).sorted() {
            switch (saved[key], staged[key]) {
            case (nil, nil): break
            case (_?, nil): out.append(.clear(question: key))
            case (let old, let new?) where old != new: out.append(.save(question: key, answer: new))
            default: break
            }
        }
        return out
    }

    /// How many of these questions have a saved answer.
    static func answeredCount(keys: [String], saved: [String: Answer]) -> Int {
        keys.filter { saved[$0] != nil }.count
    }

    /// "last 21:30" for a time in minutes after midnight; nil for a minute that is not a time of day.
    static func note(lastAt minutes: Double) -> String? {
        guard minutes >= 0, minutes < 1440 else { return nil }
        let total = Int(minutes.rounded())
        return String(format: "last %02d:%02d", (total / 60) % 24, total % 60)
    }

    /// The minutes after midnight a "last 21:30" note holds.
    static func minutes(ofNote note: String?) -> Double? {
        guard let note, note.hasPrefix("last ") else { return nil }
        let parts = note.dropFirst("last ".count).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return Double(hour * 60 + minute)
    }

    // MARK: Answered by the devices

    struct AutoRow: Equatable {
        var id: String
        var label: String
        var evidence: String
        /// What the screen shows: the device's answer, or the athlete's correction of it.
        var yes: Bool
        var isCorrected: Bool
    }

    /// The device answers of one day with the athlete's corrections (the phone's own answer under the behaviour's id) applied.
    static func autoRows(_ doc: PFJournalDoc530?, date: String, corrections: [String: Bool]) -> [AutoRow] {
        let answers = (doc?.auto ?? []).first { $0.date == date }?.answers ?? []
        return answers.compactMap { answer in
            guard let id = answer.id, let label = answer.label, let device = answer.answer else { return nil }
            let corrected = corrections[id]
            return AutoRow(id: id, label: label, evidence: answer.evidence ?? "", yes: corrected ?? device, isCorrected: corrected != nil)
        }
    }

    /// Tapping a device answer: an answer the athlete corrected goes back to the device's; any other is corrected to the opposite.
    static func correction(for row: AutoRow) -> Write {
        row.isCorrected ? .clear(question: row.id) : .save(question: row.id, answer: Answer(yes: !row.yes))
    }

    // MARK: Prompts and notifications

    /// The key of the afternoon question in the document, else the starter question.
    static func afternoonKey(_ doc: PFJournalDoc530?) -> String {
        for question in doc?.list ?? [] where question.window == afternoon {
            if let key = question.key, !key.isEmpty { return key }
        }
        return starterAfternoonKey
    }

    /// "journal:2026-11-16:afternoon" is the inbox item of that window's questions on that day.
    static func journalItem(_ id: String?) -> (date: String, window: String)? {
        guard let id else { return nil }
        let parts = id.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "journal", addDays(parts[1], 0) != nil, windows.contains(parts[2]) else { return nil }
        return (parts[1], parts[2])
    }

    // MARK: Insights

    /// The outcomes published in the journal document, including performance and the component readings.
    static let outcomes = ["recovery", "sleep", "performance", "hrv", "resting_hr"]

    static func outcomeTitle(_ outcome: String) -> String {
        switch outcome {
        case "recovery": return "Recovery"
        case "sleep": return "Sleep"
        case "performance": return "Performance"
        case "hrv": return "HRV"
        case "resting_hr": return "Resting heart rate"
        default: return outcome.capitalized
        }
    }

    /// Recovery is read the morning after, sleep the night after.
    static func lagTitle(_ lag: Int, outcome: String = "recovery") -> String {
        if outcome == "sleep" { return lag == 2 ? "Two nights after" : "Night after" }
        if outcome == "performance" { return lag == 2 ? "Two days after" : "Next day" }
        return lag == 2 ? "Morning after" : "Next morning"
    }

    /// One measure of one device: the scores a behaviour is read against.
    struct Series: Equatable, Hashable {
        var outcome: String
        var device: String
        var measure: String
        var unit: String

        var id: String { "\(device)|\(measure)" }
        /// "Charge (WHOOP)": every number names its device.
        var title: String { "\(measure) (\(device))" }
    }

    /// The measures an outcome is read from, one per device and measure, in the document's order.
    static func series(_ insights: [Insight]?, outcome: String) -> [Series] {
        var out: [Series] = []
        for insight in insights ?? [] where insight.outcome == outcome {
            guard let device = insight.device, let measure = insight.measure else { continue }
            let entry = Series(outcome: outcome, device: device, measure: measure, unit: insight.unit ?? "")
            if !out.contains(where: { $0.id == entry.id }) { out.append(entry) }
        }
        return out
    }

    struct Split: Equatable {
        /// The behaviours with a clear effect, the strongest first.
        var clear: [Insight]
        /// The behaviours tested without a clear effect, by name.
        var noEffect: [Insight]
    }

    /// The behaviours read against one measure at one lag. An entry without its counts, means or lag is left out.
    static func split(_ insights: [Insight]?, series: Series, lag: Int) -> Split {
        let mine = (insights ?? []).filter { insight in
            guard insight.outcome == series.outcome, insight.device == series.device, insight.measure == series.measure else { return false }
            guard (insight.lag ?? 1) == lag else { return false }
            return insight.meanWith != nil && insight.meanWithout != nil && insight.nWith != nil && insight.nWithout != nil
        }
        let clear = mine.filter { $0.clear == true }.sorted { abs($0.diff ?? 0) > abs($1.diff ?? 0) }
        let rest = mine.filter { $0.clear != true }.sorted { ($0.label ?? "") < ($1.label ?? "") }
        return Split(clear: clear, noEffect: rest)
    }

    /// The questions still collecting: fewer than five days of yes or of no for a result.
    static func collecting(_ list: [Question]?) -> [Question] {
        (list ?? []).filter { $0.state == "collecting" && ($0.key ?? "").isEmpty == false }
    }

    /// How far a question is towards its first result, 0 to 1: up to five yes days and five no days.
    static func progress(yes: Int?, no: Int?) -> Double {
        let have = min(max(yes ?? 0, 0), daysNeeded) + min(max(no ?? 0, 0), daysNeeded)
        return Double(have) / Double(daysNeeded * 2)
    }

    /// Which side of a collecting question is short of a result, and by how many days; nil when neither is.
    static func missing(nYes: Int?, nNo: Int?) -> String? {
        let sides: [(count: Int, words: String)] = [(nYes ?? 0, "with it"), (nNo ?? 0, "without it")]
        let lines = sides.compactMap { side -> String? in
            let short = daysNeeded - side.count
            return short > 0 ? "Needs \(short) more \(short == 1 ? "day" : "days") \(side.words)" : nil
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// What the sheet behind one result row shows. A missing number reads as a dash.
    struct DetailModel: Equatable {
        /// Hurts | Helps | No clear effect
        var verdict: String
        var label: String
        var percent: String
        /// What the percent is of: the lag, the measure and the device.
        var measureLine: String
        var meanWith: String
        var meanWithout: String
        /// The two bars, 0 to 1 of the measure's range.
        var fractionWith: Double
        var fractionWithout: Double
        var daysWith: String
        var daysWithout: String
        /// The server's sentence, unchanged.
        var note: String?
    }

    static func detail(for insight: Insight) -> DetailModel {
        let dash = "\u{2013}"
        let unit = insight.unit ?? ""
        var verdict = "No clear effect"
        if insight.clear == true, let diff = insight.diff {
            verdict = diff < 0 ? "Hurts" : "Helps"
        }
        let lagWords = lagTitle(insight.lag ?? 1, outcome: insight.outcome ?? "recovery").lowercased()
        return DetailModel(verdict: verdict,
                           label: insight.label ?? insight.behaviour ?? dash,
                           percent: insight.pct.map { PFImpactFormat.pctText($0) } ?? dash,
                           measureLine: "\(lagWords) \(insight.measure ?? dash) (\(insight.device ?? dash))",
                           meanWith: insight.meanWith.map { valueText($0, unit: unit) } ?? dash,
                           meanWithout: insight.meanWithout.map { valueText($0, unit: unit) } ?? dash,
                           fractionWith: insight.meanWith.map { barFraction($0, unit: unit) } ?? 0,
                           fractionWithout: insight.meanWithout.map { barFraction($0, unit: unit) } ?? 0,
                           daysWith: insight.nWith.map { String($0) } ?? dash,
                           daysWithout: insight.nWithout.map { String($0) } ?? dash,
                           note: insight.note)
    }

    /// A mean as a bar: 0 to 1 of the measure's range.
    static func barFraction(_ value: Double, unit: String) -> Double {
        let top: Double
        switch unit {
        case "h": top = 10
        case "of 21": top = 21
        default: top = 100
        }
        return min(max(value / top, 0), 1)
    }

    /// A mean for the screen: 26 %, 6.9 h, 14.2 of 21, 72.
    static func valueText(_ value: Double, unit: String) -> String {
        switch unit {
        case "%": return String(format: "%.0f %%", value)
        case "h": return String(format: "%.1f h", value)
        case "of 21": return String(format: "%.1f of 21", value)
        default: return String(format: "%.0f", value)
        }
    }

    /// A mean without its unit, for "63 / 48".
    static func plainText(_ value: Double, unit: String) -> String {
        switch unit {
        case "h", "of 21": return String(format: "%.1f", value)
        default: return String(format: "%.0f", value)
        }
    }

    // MARK: Questions added on the phone

    /// A question the athlete added in Customise: its text is the key, stored verbatim.
    struct Custom: Codable, Equatable {
        var key: String
        /// yes_no | count | time | scale
        var kind: String
        /// morning | afternoon | evening
        var window: String

        var question: Question {
            Question(key: key, label: key, prompt: key, hint: nil, kind: kind, window: window, about: PFJournalLogic530.defaultAbout(window: window),
                     yes: "Yes", no: "No", state: "collecting", stateSource: nil, nYes: nil, nNo: nil)
        }
    }

    /// The text of a new question, trimmed; nil when it is empty or already in the list (compared ignoring case and spacing).
    static func newKey(_ text: String, existing: [String]) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !existing.contains(where: { norm($0) == norm(clean) }) else { return nil }
        return clean
    }
}
