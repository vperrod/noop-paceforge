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
        case .weekly: return ["headline", "review", "held_slipped", "plan_review", "goals", "proposed_plan"]
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
        return PFReport(kind: kind, key: key, label: doc["label"].text ?? key, date: doc["date"].text,
                        generatedAt: doc["generated_at"].text, isStale: doc["stale"].bool ?? false,
                        wholeSource: doc["head_coach"]["text_source"].text, stages: stages, experts: experts,
                        proposals: proposals, notChecked: doc["not_checked"].strings)
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
}
