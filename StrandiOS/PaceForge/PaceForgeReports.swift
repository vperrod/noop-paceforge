import Foundation

// The expert reports: the daily reading, the weekly report and the monthly report PaceForge writes (data/reports/index.json lists
// them, data/reports/<kind>/<key>.json is one, data/expert-panel.json is the latest daily). Foundation only, so the parsing, the
// stage order, the tag handling and the freshness wording are compiled into the macOS unit-test bundle.
//
// The text is written on the server and checked there against the athlete's own data. The phone only lays it out: it never works
// out a figure, and the proposals are shown read-only (Accept and Dismiss live in the Needs you card on Today).

enum PFReportKind: String, CaseIterable, Identifiable {
    case daily, weekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    /// The stages in the order the report reads, headline first. A JSON object has no order once decoded, so the order is fixed here.
    var stageOrder: [String] {
        switch self {
        case .daily: return ["readiness", "preparedness", "decisions"]
        case .weekly: return ["headline", "detail", "review", "held_slipped", "plan_review", "goals", "proposed_plan"]
        case .monthly: return ["headline", "review", "training", "body", "race_goals", "next_month"]
        }
    }

    /// When the server writes this kind, for the empty state.
    var whenWritten: String {
        switch self {
        case .daily: return "The daily reading is written each morning after the Garmin sync."
        case .weekly: return "The weekly report is written on Sunday evening."
        case .monthly: return "The monthly report is written at the start of each month."
        }
    }
}

struct PFReportStage: Equatable, Identifiable {
    let id: String
    let title: String
    let text: String
    let source: String?
}

struct PFReportExpert: Equatable, Identifiable {
    let id: String
    let title: String
    let text: String
    let source: String?
}

struct PFReportProposal: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
}

/// How far a claim is backed, in the words the web shows beside it.
enum PFSureLevel: Equatable {
    case confirmed, partial, estimate

    var words: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .partial: return "Partly supported"
        case .estimate: return "Our estimate"
        }
    }

    /// The "how sure are we" line, as the web words it.
    var explain: String {
        switch self {
        case .confirmed: return "The research behind this was opened and it supports the statement."
        case .partial: return "The research supports part of this; the rest is our reading of it."
        case .estimate: return "Not proven by research we could check; this is our best reading, so treat it as a guide."
        }
    }

    /// From the words the server writes in a `sources` row; anything it does not know reads as an estimate, as on the web.
    init(words: String?) {
        switch words {
        case "Confirmed": self = .confirmed
        case "Partly supported": self = .partial
        default: self = .estimate
        }
    }
}

/// One term of a report's glossary.
struct PFReportGlossaryEntry: Equatable {
    let term: String
    let text: String
}

/// One source a report cites: how sure it is and the claim in one line.
struct PFReportSource: Equatable {
    let id: String
    let level: PFSureLevel
    let claim: String?
}

/// One session of the week, as the server listed it (`sessions[]` of a weekly report).
struct PFReportSession: Equatable, Identifiable {
    let id: Int
    let weekday: String
    let name: String
    let type: String?
    let minutes: Int?
    let km: Double?
    let pace: String?
    let avgHR: Int?
    let isHard: Bool
    /// "done", "partly done", "added" ... as the web words the plan status.
    let plan: String?
}

/// One day of the week table (`week_table[]`): its sessions and the night that ended that morning.
struct PFReportDay: Equatable, Identifiable {
    let id: Int
    let weekday: String
    let sessions: [String]
    let minutes: Int?
    let sleepHours: Double?
    let hrv: Double?
    let restingHR: Double?
}

struct PFReportTypeTotal: Equatable {
    let label: String
    let sessions: Int?
    let minutes: Int?
    let km: Double?
}

/// `week_totals` of a weekly report: totals by type, hard against easy and the change on the week before.
struct PFReportWeekTotals: Equatable {
    var byType: [PFReportTypeTotal] = []
    var sessions: Int?
    var minutes: Int?
    var runKm: Double?
    var hardSessions: Int?
    var hardMinutes: Int?
    var easySessions: Int?
    var easyMinutes: Int?
    var minutesChangePct: Double?
}

/// One run of the daily job (`expert-panel-runs.json`, keyed by the day).
struct PFReportRun: Equatable {
    let at: String?
    let runKind: String?
    let result: String
    let why: String?
}

/// What this athlete's devices give (`data/capabilities.json`). A flag the file does not carry is unknown, and unknown shows everything.
struct PFCapabilities: Equatable {
    var reportsScheduled: Bool?
    var reportReview: Bool?
    var dayOnly: Bool?
    var wearsOvernight: Bool?

    /// False only when the server says in so many words that this athlete has no reports. A missing file or flag keeps the screens.
    var showsReports: Bool { reportsScheduled != false && reportReview != false }
}

/// One line of the history list.
struct PFReportRow: Equatable, Identifiable {
    let key: String
    let label: String
    let isStale: Bool
    let headline: String?

    var id: String { key }
}

struct PFReport: Equatable {
    var kind: PFReportKind
    var key: String
    var label: String
    var date: String?
    var generatedAt: String?
    var isStale: Bool
    /// Where the head coach's text as a whole came from (free-model, mixed, fallback-rules ...).
    var wholeSource: String?
    var stages: [PFReportStage]
    var experts: [PFReportExpert]
    var proposals: [PFReportProposal]
    var notChecked: [String]
    /// When the Garmin sync the report read finished, and which run wrote it ("06:30", "manual" ...). Daily reports only.
    var dataAsOf: String?
    var runKind: String?
    /// The weekly report's tables. All empty on a report that carries none, so an older document still loads.
    var sessions: [PFReportSession] = []
    var days: [PFReportDay] = []
    var totals: PFReportWeekTotals?
    var glossary: [PFReportGlossaryEntry] = []
    var sources: [PFReportSource] = []

    var hasWeekNumbers: Bool { !sessions.isEmpty || !days.isEmpty }

    /// The first stage is the prominent one: the headline of a weekly or monthly report, the readiness stage of a daily one.
    var lead: PFReportStage? { stages.first }
    var otherStages: [PFReportStage] { Array(stages.dropFirst()) }
}

/// One paragraph of a stage with the claim tags taken out of it, so the tags can be drawn small underneath.
struct PFReportBlock: Equatable, Identifiable {
    let id: Int
    let text: String
    let tags: [String]
    let isHeading: Bool
}

enum PFReportParse {
    private static let expertOrder = ["sleep", "running", "health", "nutrition", "physio", "hybrid", "stress-mind"]
    private static let expertTitles = [
        "sleep": "Sleep", "running": "Running", "health": "Health and vitals", "nutrition": "Nutrition",
        "physio": "Physio", "hybrid": "Hybrid racing", "stress-mind": "Stress and mind",
    ]
    private static let stageTitles = [
        "readiness": "Readiness", "preparedness": "Preparedness", "decisions": "Decisions", "headline": "Headline",
        "detail": "The week, session by session",
    ]

    /// The history rows of one kind, newest first as the server wrote them.
    static func rows(_ index: PFJ, kind: PFReportKind) -> [PFReportRow] {
        index[kind.rawValue].array.compactMap { row -> PFReportRow? in
            guard let key = row["key"].text else { return nil }
            return PFReportRow(key: key, label: row["label"].text ?? key, isStale: row["stale"].bool ?? false,
                               headline: row["headline"].text)
        }
    }

    /// One report, or nil when it has no stage with text.
    static func report(_ doc: PFJ, kind: PFReportKind) -> PFReport? {
        let head = doc["head_coach"].dict
        let titles = doc["stage_titles"]
        let known = kind.stageOrder
        let extra = head.keys.filter { $0 != "text_source" && !known.contains($0) }.sorted()
        let stageIDs: [String] = known.filter { head[$0] != nil } + extra
        let stages = stageIDs.compactMap { id -> PFReportStage? in
            guard let part = head[id], let text = part["text"].text else { return nil }
            let title = titles[id].text ?? stageTitles[id] ?? PFFormat.capitalized(PFFormat.words(id))
            return PFReportStage(id: id, title: title, text: text, source: part["text_source"].text)
        }
        guard !stages.isEmpty else { return nil }

        let expertDict = doc["experts"].dict
        let expertExtra = expertDict.keys.filter { !expertOrder.contains($0) }.sorted()
        let expertIDs: [String] = expertOrder.filter { expertDict[$0] != nil } + expertExtra
        let experts = expertIDs.compactMap { id -> PFReportExpert? in
            guard let part = expertDict[id], let text = part["text"].text else { return nil }
            let title = expertTitles[id] ?? PFFormat.capitalized(PFFormat.words(id))
            return PFReportExpert(id: id, title: title, text: text, source: part["text_source"].text)
        }

        let proposals = doc["proposals"].array.compactMap { item -> PFReportProposal? in
            guard let title = item["title"].text else { return nil }
            return PFReportProposal(id: item["id"].idString ?? title, title: title, detail: item["description"].text ?? "")
        }

        let key = doc["key"].text ?? doc["date"].text ?? ""
        var out = PFReport(kind: kind, key: key, label: doc["label"].text ?? key, date: doc["date"].text,
                           generatedAt: doc["generated_at"].text, isStale: doc["stale"].bool ?? false,
                           wholeSource: doc["head_coach"]["text_source"].text, stages: stages, experts: experts,
                           proposals: proposals, notChecked: doc["not_checked"].strings)
        out.dataAsOf = doc["data_as_of"].text
        out.runKind = doc["run_kind"].text
        out.sessions = sessions(doc)
        out.days = days(doc)
        out.totals = totals(doc)
        out.glossary = glossary(doc)
        out.sources = sources(doc)
        return out
    }

    /// `sessions[]` of a weekly report, in the server's order. A row with no name is left out.
    static func sessions(_ doc: PFJ) -> [PFReportSession] {
        var out: [PFReportSession] = []
        for row in doc["sessions"].array {
            guard let name = row["name"].text else { continue }
            out.append(PFReportSession(id: out.count, weekday: row["weekday"].text ?? "", name: name, type: row["type"].text,
                                       minutes: row["minutes"].int, km: row["km"].double, pace: row["pace"].text,
                                       avgHR: row["avg_hr"].int, isHard: row["hard"].bool ?? false,
                                       plan: planWord(row["plan"]["status"].text)))
        }
        return out
    }

    /// The plan status in the web's words: "unplanned" reads "added", "partial" reads "partly done".
    private static func planWord(_ status: String?) -> String? {
        switch status {
        case nil: return nil
        case "unplanned": return "added"
        case "partial": return "partly done"
        default: return status
        }
    }

    /// `week_table[]`: one row per day with its sessions and the night that ended that morning.
    static func days(_ doc: PFJ) -> [PFReportDay] {
        var out: [PFReportDay] = []
        for row in doc["week_table"].array {
            guard let weekday = row["weekday"].text else { continue }
            out.append(PFReportDay(id: out.count, weekday: weekday, sessions: row["sessions"].strings, minutes: row["minutes"].int,
                                   sleepHours: row["sleep_h"].double, hrv: row["hrv"].double, restingHR: row["resting_hr"].double))
        }
        return out
    }

    /// `week_totals`, or nil when the document has none.
    static func totals(_ doc: PFJ) -> PFReportWeekTotals? {
        let node = doc["week_totals"]
        guard node.exists else { return nil }
        var out = PFReportWeekTotals()
        let types = node["totals_by_type"].dict.values.compactMap { value -> PFReportTypeTotal? in
            guard let label = value["label"].text else { return nil }
            return PFReportTypeTotal(label: label, sessions: value["sessions"].int, minutes: value["minutes"].int, km: value["km"].double)
        }
        // A JSON object has no order once decoded: the longest type first, ties by name.
        out.byType = types.sorted { lhs, rhs in
            let left = lhs.minutes ?? 0
            let right = rhs.minutes ?? 0
            if left != right { return left > right }
            return lhs.label < rhs.label
        }
        out.sessions = node["totals"]["sessions"].int
        out.minutes = node["totals"]["minutes"].int
        out.runKm = node["totals"]["run_km"].double
        out.hardSessions = node["hard_vs_easy"]["hard_sessions"].int
        out.hardMinutes = node["hard_vs_easy"]["hard_minutes"].int
        out.easySessions = node["hard_vs_easy"]["easy_sessions"].int
        out.easyMinutes = node["hard_vs_easy"]["easy_minutes"].int
        out.minutesChangePct = node["load_vs_previous_week"]["minutes_change_pct"].double
        return out
    }

    /// The glossary: the server's list of {term, text}, or a {term: text} object, in the order the report uses the terms.
    static func glossary(_ doc: PFJ) -> [PFReportGlossaryEntry] {
        let node = doc["glossary"]
        var out: [PFReportGlossaryEntry] = []
        for row in node.array {
            guard let term = row["term"].text, let text = row["text"].text else { continue }
            out.append(PFReportGlossaryEntry(term: term, text: text))
        }
        if out.isEmpty {
            for (term, value) in node.dict.sorted(by: { $0.key < $1.key }) {
                guard let text = value.text ?? value["text"].text else { continue }
                out.append(PFReportGlossaryEntry(term: term, text: text))
            }
        }
        return out
    }

    /// The sources a report cites: the server's list of {id, words, claim}, or an {id: words} object.
    static func sources(_ doc: PFJ) -> [PFReportSource] {
        let node = doc["sources"]
        var out: [PFReportSource] = []
        for row in node.array {
            let claim = row["claim"].text
            guard let id = row["id"].text ?? claim else { continue }
            out.append(PFReportSource(id: id, level: PFSureLevel(words: row["words"].text), claim: claim))
        }
        if out.isEmpty {
            for (id, value) in node.dict.sorted(by: { $0.key < $1.key }) {
                out.append(PFReportSource(id: id, level: PFSureLevel(words: value.text ?? value["words"].text), claim: value["claim"].text))
            }
        }
        return out
    }

    /// The day's runs of the daily job, keyed by the day. A run with no result is left out.
    static func runs(_ doc: PFJ) -> [String: [PFReportRun]] {
        var out: [String: [PFReportRun]] = [:]
        for (day, list) in doc.dict {
            var runs: [PFReportRun] = []
            for row in list.array {
                guard let result = row["result"].text else { continue }
                runs.append(PFReportRun(at: row["at"].text, runKind: row["run_kind"].text, result: result, why: row["why"].text))
            }
            out[day] = runs
        }
        return out
    }

    /// `data/capabilities.json`, or nil when the file is missing or not an object.
    static func capabilities(_ doc: PFJ) -> PFCapabilities? {
        guard !doc.dict.isEmpty else { return nil }
        return PFCapabilities(reportsScheduled: doc["reports_scheduled"].bool, reportReview: doc["report_review"].bool,
                              dayOnly: doc["day_only"].bool, wearsOvernight: doc["wears_overnight"].bool)
    }
}

enum PFReportText {
    private static let tagPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\[([^\[\]]*\b(?:VERIFIED|PARTIAL|UNVERIFIED|INFERENCE|SPECULATIVE)\b[^\[\]]*)\]"#)
    private static let statusWords: Set<String> = ["VERIFIED", "PARTIAL", "UNVERIFIED", "INFERENCE", "SPECULATIVE"]

    /// Where a stage's text came from, in words.
    static func sourceNote(_ source: String?) -> String {
        switch source {
        case "free-model": return "model text, checked"
        case "fallback-rules": return "rules text: the model text did not pass the checks"
        case "no-model": return "rules text: no model answered"
        default: return "rules text"
        }
    }

    /// Where the head coach's text as a whole came from.
    static func wholeNote(_ source: String?) -> String {
        switch source {
        case "free-model": return "model text"
        case "mixed": return "part model, part rules text"
        default: return "rules text"
        }
    }

    /// "health:C16, PARTIAL" becomes "health C16 (middle dot) partial": the claim id and its proof status.
    static func tagLabel(_ inner: String) -> String {
        inner.split(separator: ",").map { part -> String in
            let word = part.trimmingCharacters(in: .whitespaces)
            if statusWords.contains(word) { return word.lowercased() }
            return word.replacingOccurrences(of: ":", with: " ")
        }.joined(separator: " \u{00B7} ")
    }

    private static let estimateWords: Set<String> = ["unverified", "inference", "speculative"]

    /// What a tag label says about the claim: an estimate when it carries UNVERIFIED, INFERENCE or SPECULATIVE, partly supported
    /// with PARTIAL, otherwise confirmed. Same order of checks as the web.
    static func sureLevel(ofTag label: String) -> PFSureLevel {
        let words = Set(label.components(separatedBy: " \u{00B7} "))
        if !words.isDisjoint(with: estimateWords) { return .estimate }
        return words.contains("partial") ? .partial : .confirmed
    }

    /// The line without its claim tags, and the tags as labels. A line with no tag comes back as it was.
    static func splitTags(_ line: String) -> (text: String, tags: [String]) {
        guard let pattern = tagPattern else { return (line, []) }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        var tags: [String] = []
        for match in pattern.matches(in: line, options: [], range: full) where match.numberOfRanges > 1 {
            tags.append(tagLabel(ns.substring(with: match.range(at: 1))))
        }
        guard !tags.isEmpty else { return (line, []) }
        var text = pattern.stringByReplacingMatches(in: line, options: [], range: full, withTemplate: "")
        for (spaced, tight) in [("  ", " "), (" .", "."), (" ,", ","), (" ;", ";")] {
            text = text.replacingOccurrences(of: spaced, with: tight)
        }
        return (text.trimmingCharacters(in: .whitespaces), tags)
    }

    /// A stage's text as paragraphs: headings marked, bullets given a dot, table rows read as one line, claim tags split off.
    static func blocks(_ text: String) -> [PFReportBlock] {
        var out: [PFReportBlock] = []
        for raw in text.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.allSatisfy({ "|:- ".contains($0) }) { continue }
            var isHeading = false
            if line.hasPrefix("#") {
                isHeading = true
                line = "**" + line.drop(while: { $0 == "#" || $0 == " " }).replacingOccurrences(of: "*", with: "") + "**"
            } else if line.hasPrefix("|") {
                line = line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                    .replacingOccurrences(of: "|", with: "\u{00B7}")
            } else {
                for bullet in ["- ", "* ", "\u{2022} "] where line.hasPrefix(bullet) {
                    line = "\u{2022} " + line.dropFirst(bullet.count)
                    break
                }
            }
            let (clean, tags) = splitTags(line)
            if clean.isEmpty { continue }
            out.append(PFReportBlock(id: out.count, text: clean, tags: tags, isHeading: isHeading))
        }
        return out
    }
}

enum PFReportFreshness {
    /// A line to show above the text when this is not today's reading or the last run failed; nil when nothing needs saying.
    static func note(_ report: PFReport, today: String) -> String? {
        let written = (report.generatedAt ?? report.date).map { PFFormat.dayTitle($0) }
        if report.isStale {
            if report.kind == .daily, let date = report.date {
                return "Today's reading did not run, so this is the one from \(PFFormat.dayTitle(date))."
            }
            return "The last run failed, so this is the report written \(written ?? "earlier")."
        }
        if report.kind == .daily, let date = report.date, String(date.prefix(10)) != today {
            return "This is the reading from \(PFFormat.dayTitle(date)), not today's. Today's has not been written yet."
        }
        return nil
    }

    /// The report's own date for a header: the day of a daily reading, the period label of a weekly or monthly one.
    static func dateLine(_ report: PFReport) -> String {
        if report.kind == .daily, let date = report.date { return PFFormat.dayTitle(date) }
        return report.label
    }

    /// The daily reading's one state and the lines under it, in the web's words: Fresh, Older than today or Failed; when it was
    /// written and by which run; which Garmin sync it read; the day's runs. `runs` are the runs of the report's own day.
    static func status(_ report: PFReport, runs: [PFReportRun], today: String, now: Date) -> PFFreshness {
        let state: PFFreshness.State
        if report.isStale {
            state = .failed
        } else if let date = report.date, String(date.prefix(10)) == today {
            state = .fresh
        } else {
            state = .older
        }
        let day = report.date.map { PFFormat.dayTitle($0) } ?? "an earlier day"
        let headline: String
        switch state {
        case .failed: headline = "Failed: the last run did not work, showing \(day)'s reading"
        case .fresh: headline = "Fresh: written today, after the morning Garmin data arrived"
        case .older: headline = "Older than today: this is \(day)'s reading"
        }
        var written: String?
        if let stamp = report.generatedAt, let when = clock(stamp) {
            var line = "Written \(when)"
            if let elapsed = ago(stamp, now: now) { line += " (\(elapsed))" }
            if let kind = report.runKind { line += ", by " + (kind == "manual" ? "a manual run" : "the \(kind) scheduled run") }
            written = line
        }
        var synced: String?
        if let stamp = report.dataAsOf, let when = clock(stamp) {
            var line = "Garmin data synced \(when)"
            if let elapsed = ago(stamp, now: now) { line += " (\(elapsed))" }
            synced = line
        }
        return PFFreshness(state: state, headline: headline, written: written, dataSynced: synced,
                           runsTitle: "Runs today (\(runs.count))", runs: runs.map(runLine))
    }

    /// "06:30 manual: ok" or "11:00: failed (why)": when it ran, which run, what came of it.
    static func runLine(_ run: PFReportRun) -> String {
        var line = [run.at.flatMap { clock($0) }, run.runKind].compactMap { $0 }.joined(separator: " ")
        line += (line.isEmpty ? "" : ": ") + run.result
        if let why = run.why { line += " (\(why))" }
        return line
    }

    private static let weekdayClock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    private static func parse(_ stamp: String) -> Date? {
        PFFormat.isoWithFraction.date(from: stamp) ?? PFFormat.isoPlain.date(from: stamp) ?? PFFormat.isoLocalSeconds.date(from: stamp)
    }

    /// "Tue 06:42" in the phone's time zone; nil when the stamp cannot be read.
    private static func clock(_ stamp: String) -> String? {
        parse(stamp).map { weekdayClock.string(from: $0) }
    }

    /// "3 h ago": minutes under 90, hours under 36, then days. nil for a stamp in the future or one that cannot be read.
    private static func ago(_ stamp: String, now: Date) -> String? {
        guard let when = parse(stamp) else { return nil }
        let minutes = (now.timeIntervalSince(when) / 60).rounded()
        guard minutes >= 0 else { return nil }
        if minutes < 90 { return "\(Int(max(minutes, 1))) min ago" }
        if minutes < 36 * 60 { return "\(Int((minutes / 60).rounded())) h ago" }
        return "\(Int((minutes / 1440).rounded())) days ago"
    }
}

/// What the freshness block shows for a daily reading.
struct PFFreshness: Equatable {
    enum State: Equatable {
        case fresh, older, failed
    }

    var state: State
    var headline: String
    var written: String?
    var dataSynced: String?
    var runsTitle: String
    var runs: [String]
}

/// The weekly report's tables as lines of text. The figures are the server's; nothing is worked out here.
enum PFReportWeekText {
    /// "Easy run - 45 min - 8.2 km - 5:10 /km - avg HR 142 - done": whatever the row carries, in that order.
    static func sessionLine(_ session: PFReportSession) -> String {
        var parts: [String] = []
        if let type = session.type { parts.append(type) }
        if let minutes = session.minutes { parts.append("\(minutes) min") }
        if let km = session.km { parts.append(PFFormat.oneDecimal(km) + " km") }
        if let pace = session.pace { parts.append(pace + " /km") }
        if let hr = session.avgHR { parts.append("avg HR \(hr)") }
        if let plan = session.plan { parts.append(plan) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "Run: 3 sessions - 140 min - 24.5 km".
    static func typeLine(_ total: PFReportTypeTotal) -> String {
        var parts: [String] = []
        if let n = total.sessions { parts.append(count(n, "session")) }
        if let minutes = total.minutes { parts.append("\(minutes) min") }
        if let km = total.km { parts.append(PFFormat.oneDecimal(km) + " km") }
        return total.label + ": " + parts.joined(separator: " \u{00B7} ")
    }

    /// "6 sessions - 305 min - 24.5 km run" for the whole week; nil when the document gives none of it.
    static func totalLine(_ totals: PFReportWeekTotals) -> String? {
        var parts: [String] = []
        if let n = totals.sessions { parts.append(count(n, "session")) }
        if let minutes = totals.minutes { parts.append("\(minutes) min") }
        if let km = totals.runKm { parts.append(PFFormat.oneDecimal(km) + " km run") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// "Hard: 2 sessions (95 min). Easy: 4 sessions (210 min)."; nil unless all four figures are there.
    static func hardEasyLine(_ totals: PFReportWeekTotals) -> String? {
        guard let hs = totals.hardSessions, let hm = totals.hardMinutes,
              let es = totals.easySessions, let em = totals.easyMinutes else { return nil }
        return "Hard: \(count(hs, "session")) (\(hm) min). Easy: \(count(es, "session")) (\(em) min)."
    }

    /// "Training time up 12 % on the week before."; nil when the document has no change figure.
    static func changeLine(_ totals: PFReportWeekTotals) -> String? {
        guard let pct = totals.minutesChangePct else { return nil }
        if pct == 0 { return "Training time unchanged on the week before." }
        let direction = pct > 0 ? "up" : "down"
        return "Training time \(direction) \(PFFormat.trimmed(abs(pct))) % on the week before."
    }

    /// "Easy run, Strength - 75 min", or "rest".
    static func dayLine(_ day: PFReportDay) -> String {
        var parts = [day.sessions.isEmpty ? "rest" : day.sessions.joined(separator: ", ")]
        if let minutes = day.minutes, minutes > 0 { parts.append("\(minutes) min") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "sleep 7.4 h - HRV 62 - resting HR 48" for the night that ended that morning; nil when it has none of them.
    static func nightLine(_ day: PFReportDay) -> String? {
        var parts: [String] = []
        if let sleep = day.sleepHours { parts.append("sleep \(PFFormat.trimmed(sleep)) h") }
        if let hrv = day.hrv { parts.append("HRV \(PFFormat.trimmed(hrv))") }
        if let resting = day.restingHR { parts.append("resting HR \(PFFormat.trimmed(resting))") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)" + (n == 1 ? "" : "s") }
}
