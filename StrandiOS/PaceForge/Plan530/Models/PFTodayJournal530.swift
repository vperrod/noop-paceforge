import Foundation

/// The parts of data/journal-view.json the My Journal card on Today reads: the week's row, today's prompts, what the devices answered and
/// whether any behaviour has a clear result. Its own small reader, so the card does not depend on the journal sheets' model (it only reads
/// the keys named in the build-530 contract). Every field is optional, every list keeps its good elements.
struct PFTodayJournal530: Decodable, Equatable {
    var asOf: String? = nil
    var stale: Bool? = nil
    var week: [Day]?
    var prompts: [Prompt]?
    var list: [Question]?
    var auto: [AutoDay]?
    var insights: [Insight]?

    /// Monday to Sunday: was the journal logged that day.
    struct Day: Decodable, Equatable {
        var date: String?
        var logged: Bool?
    }

    /// Today's prompt for one window (morning | afternoon | evening); `open` is the number of questions still unanswered.
    struct Prompt: Decodable, Equatable {
        var window: String?
        var title: String?
        var body: String?
        var open: Int?
        var state: String?
        var selectedKeys: [String]? = nil
        var openKeys: [String]? = nil
    }

    struct Question: Decodable, Equatable {
        var key: String?
        var label: String?
        var prompt: String?
        var hint: String?
        var kind: String?
        var window: String?
        var about: String?
        var yes: String?
        var no: String?
    }

    struct AutoDay: Decodable, Equatable {
        var date: String?
        var answers: [AutoAnswer]?
    }

    /// `answer` is true / false when a device answered, null when it could not.
    struct AutoAnswer: Decodable, Equatable {
        var id: String?
        var label: String?
        var answer: Bool?
    }

    /// One behaviour x outcome x device x lag (the flat list of the contract); only `clear` and the name are read here.
    struct Insight: Decodable, Equatable {
        var behaviour: String?
        var label: String?
        var clear: Bool?
    }

    private enum CodingKeys: String, CodingKey {
        case week, prompts, list, auto, insights, asOf, stale
    }

    fileprivate enum DayKeys: String, CodingKey { case date, logged }
    fileprivate enum PromptKeys: String, CodingKey { case window, title, body, open, state, selectedKeys, openKeys }
    fileprivate enum QuestionKeys: String, CodingKey { case key, label, prompt, hint, kind, window, about, yes, no }
    fileprivate enum AutoDayKeys: String, CodingKey { case date, answers }
    fileprivate enum AutoAnswerKeys: String, CodingKey { case id, label, answer }
    fileprivate enum InsightKeys: String, CodingKey { case behaviour, label, clear }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOf = c.pfLossy(String.self, .asOf)
        stale = c.pfLossy(Bool.self, .stale)
        week = c.pfLossyList(Day.self, .week)
        prompts = c.pfLossyList(Prompt.self, .prompts)
        list = c.pfLossyList(Question.self, .list)
        auto = c.pfLossyList(AutoDay.self, .auto)
        insights = c.pfLossyList(Insight.self, .insights)
    }
}

extension PFTodayJournal530.Day {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PFTodayJournal530.DayKeys.self)
        date = c.pfLossy(String.self, .date)
        logged = c.pfLossy(Bool.self, .logged)
    }
}

extension PFTodayJournal530.Prompt {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PFTodayJournal530.PromptKeys.self)
        window = c.pfLossy(String.self, .window)
        title = c.pfLossy(String.self, .title)
        body = c.pfLossy(String.self, .body)
        open = c.pfLossy(Int.self, .open)
        state = c.pfLossy(String.self, .state)
        selectedKeys = c.pfLossy([String].self, .selectedKeys)
        openKeys = c.pfLossy([String].self, .openKeys)
    }
}

extension PFTodayJournal530.Question {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PFTodayJournal530.QuestionKeys.self)
        key = c.pfLossy(String.self, .key)
        label = c.pfLossy(String.self, .label)
        prompt = c.pfLossy(String.self, .prompt)
        hint = c.pfLossy(String.self, .hint)
        kind = c.pfLossy(String.self, .kind)
        window = c.pfLossy(String.self, .window)
        about = c.pfLossy(String.self, .about)
        yes = c.pfLossy(String.self, .yes)
        no = c.pfLossy(String.self, .no)
    }
}

extension PFTodayJournal530.AutoDay {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PFTodayJournal530.AutoDayKeys.self)
        date = c.pfLossy(String.self, .date)
        answers = c.pfLossyList(PFTodayJournal530.AutoAnswer.self, .answers)
    }
}

extension PFTodayJournal530.AutoAnswer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PFTodayJournal530.AutoAnswerKeys.self)
        id = c.pfLossy(String.self, .id)
        label = c.pfLossy(String.self, .label)
        answer = c.pfLossy(Bool.self, .answer)
    }
}

extension PFTodayJournal530.Insight {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PFTodayJournal530.InsightKeys.self)
        behaviour = c.pfLossy(String.self, .behaviour)
        label = c.pfLossy(String.self, .label)
        clear = c.pfLossy(Bool.self, .clear)
    }
}

// MARK: What the card says

/// Where the card's button goes: the morning sheet or the evening reflection.
enum PFTodayJournalTarget530: Equatable {
    case morning
    case evening
}

/// The decisions of the My Journal card, as pure functions of the document and today's date ("2030-03-13").
enum PFTodayJournalLogic530 {
    struct WeekDay: Equatable {
        var date: String
        /// "M" ... "S"
        var letter: String
        var isToday: Bool
        var isFuture: Bool
        var logged: Bool
    }

    struct DueAssignment: Equatable {
        let window: String
        let questions: [PFTodayJournal530.Question]
    }

    static func dueAssignment(_ doc: PFTodayJournal530?, today: String) -> DueAssignment? {
        guard let doc, doc.stale != true, doc.asOf == nil || doc.asOf == today,
              let due = (doc.prompts ?? []).first(where: { $0.state == "due" && ($0.open ?? 0) > 0 }),
              let window = due.window else { return nil }
        let assigned = due.openKeys ?? due.selectedKeys
        let questions = (doc.list ?? []).filter {
            $0.window == window && $0.key != nil && (assigned?.contains($0.key ?? "") ?? true)
        }
        return questions.isEmpty ? nil : DueAssignment(window: window, questions: questions)
    }

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    /// Monday to Sunday of the week holding `today`. A day is logged when the document says so or when the phone's own journal has it
    /// (`ownDays`: the phone writes its answers itself and the document follows after the next sync).
    static func weekRow(_ doc: PFTodayJournal530?, today: String, ownDays: Set<String>) -> [WeekDay] {
        let monday = PFFormat.monday(of: today)
        let served = Set((doc?.week ?? []).filter { $0.logged == true }.compactMap(\.date))
        return (0..<7).map { index in
            let date = PFFormat.addDays(monday, index)
            return WeekDay(date: date, letter: letters[index], isToday: date == today, isFuture: date > today,
                           logged: served.contains(date) || ownDays.contains(date))
        }
    }

    /// "About Saturday: 4 answered by your devices, 5 questions for you." (yesterday's devices, the morning prompt's open questions);
    /// nil when the document says neither.
    static func line(_ doc: PFTodayJournal530?, today: String) -> String? {
        guard let doc else { return nil }
        let yesterday = PFFormat.addDays(today, -1)
        let byDevices = (doc.auto ?? []).filter { $0.date == yesterday }.flatMap { $0.answers ?? [] }.filter { $0.answer != nil }.count
        let open = (doc.prompts ?? []).first { $0.window == "morning" }?.open
        var parts: [String] = []
        if byDevices > 0 { parts.append("\(byDevices) answered by your devices") }
        if let open { parts.append(open == 0 ? "nothing left for you" : "\(open) \(open == 1 ? "question" : "questions") for you") }
        guard !parts.isEmpty else { return nil }
        return "About \(weekdayName(yesterday)): " + parts.joined(separator: ", ") + "."
    }

    /// The sheet the "Fill out" button opens: the first window with open questions (morning, then the day's, then evening). The afternoon
    /// question is answered from the lock screen, so what is left of the day is in the evening reflection. Morning without a document.
    static func target(_ doc: PFTodayJournal530?) -> PFTodayJournalTarget530 {
        let open = openWindows(doc)
        if open.contains("morning") || open.isEmpty { return .morning }
        return .evening
    }

    /// True when the document lists prompts and none has an open question; false when anything is open or the document says nothing.
    static func isAllAnswered(_ doc: PFTodayJournal530?) -> Bool {
        guard let prompts = doc?.prompts, !prompts.isEmpty else { return false }
        return prompts.allSatisfy { ($0.open ?? 0) == 0 }
    }

    /// "1 clear so far: Bedtime after 23:30" / "No clear effect yet" / nil when the document has no insights list.
    static func insightsLine(_ doc: PFTodayJournal530?) -> String? {
        guard let insights = doc?.insights else { return nil }
        var seen: [String] = []
        for insight in insights where insight.clear == true {
            if let name = insight.label ?? insight.behaviour, !seen.contains(name) { seen.append(name) }
        }
        if seen.isEmpty { return "No clear effect yet" }
        return "\(seen.count) clear so far: " + seen.prefix(2).joined(separator: ", ")
    }

    private static func openWindows(_ doc: PFTodayJournal530?) -> [String] {
        (doc?.prompts ?? []).filter { ($0.open ?? 0) > 0 }.compactMap(\.window)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE"
        return f
    }()

    private static func weekdayName(_ iso: String) -> String { weekdayFormatter.string(from: PFFormat.date(iso)) }
}
