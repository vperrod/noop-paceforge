import Foundation

// The Coach screen's week card: the weekly report (`data/weekly.json`), the coach's pending proposals with the reason for each
// (`data/pending-changes.json`) and the race plans of the next two weeks (`data/events.json`, `data/race-packs/<date>.md`).
// Foundation only, so the parsing and the wording are compiled into the macOS unit-test bundle. The decision on a proposal goes
// through the Needs you answer (`PFNeedsAnswer.proposal`); nothing here writes.

/// One edit a proposal makes to the plan.
struct PFProposalChange: Equatable {
    let sessionID: String?
    let field: String
    /// The new value as text; nil when the server sent null or nothing.
    let to: String?

    /// The edit in plain words.
    var plainWords: String {
        switch field {
        case "session" where to == nil: return "Remove this session from the calendar"
        case "notes": return "Put this prescription in the session notes"
        case "name": return to.map { "Rename the session to: \($0)" } ?? "Rename the session"
        default:
            let what = PFFormat.words(field)
            return to.map { "Set the session's \(what) to \($0)" } ?? "Clear the session's \(what)"
        }
    }
}

struct PFPendingProposal: Equatable, Identifiable {
    let id: String
    let title: String
    let description: String
    /// The coach's reasoning (markdown); nil on the older proposals that have none.
    let why: String?
    /// The day the proposal is about (yyyy-MM-dd); nil when it is about no single day.
    let day: String?
    let changes: [PFProposalChange]

    /// The reasoning, or the one-line description where the proposal has no reasoning.
    var explanation: String { why ?? description }

    /// "Tue 10 Nov"; nil without a day.
    var dayLabel: String? { day.map(PFFormat.dayTitle) }

    /// What "Ask the coach about this" puts in the chat box.
    var askPrompt: String {
        "About your proposal \"\(title)\": why do you want this change, and what happens if I keep the session as it is?"
    }
}

struct PFWeekReport: Equatable {
    let headline: String
    let generatedAt: String?
    /// The whole report as markdown.
    let contentMD: String
    let periodStart: String?
    let periodEnd: String?

    /// "9\u{2013}15 Nov"; nil without both ends of the period.
    var periodLabel: String? {
        guard let periodStart, let periodEnd else { return nil }
        return PFFormat.span(periodStart, periodEnd)
    }
}

/// An event of the next two weeks and its race plan.
struct PFRacePack: Equatable, Identifiable {
    let date: String
    let name: String
    let markdown: String

    var id: String { date + "|" + name }
}

/// A piece of markdown: running text, or a table that the card lets scroll sideways.
enum PFMarkdownBlock: Equatable {
    case text(String)
    case table(String, columns: Int)
}

enum PFWeekPlan {
    static let raceWindowDays = 14

    // MARK: Parsing

    /// The proposals soonest day first (those without a day last, the server's order kept within a day). A row without an id is dropped.
    static func proposals(_ data: Data?) -> [PFPendingProposal] {
        let rows = PFJ(data: data).array.enumerated().compactMap { index, row -> (Int, PFPendingProposal)? in
            guard let id = row["id"].idString, !id.isEmpty else { return nil }
            let changes = row["changes"].array.compactMap { change -> PFProposalChange? in
                guard let field = change["field"].text else { return nil }
                return PFProposalChange(sessionID: change["session_id"].idString, field: field, to: value(change["to"]))
            }
            let proposal = PFPendingProposal(id: id, title: row["title"].text ?? "Plan change",
                                             description: row["description"].text ?? "", why: row["why"].text,
                                             day: row["day"].text, changes: changes)
            return (index, proposal)
        }
        return rows.sorted { ($0.1.day ?? "~", $0.0) < ($1.1.day ?? "~", $1.0) }.map { $0.1 }
    }

    /// nil when the report has neither a headline nor any text.
    static func weekly(_ data: Data?) -> PFWeekReport? {
        let root = PFJ(data: data)
        let headline = root["headline"].text ?? ""
        let content = root["content_md"].text ?? ""
        guard !headline.isEmpty || !content.isEmpty else { return nil }
        let period = root["source_context"]["period"]
        return PFWeekReport(headline: headline, generatedAt: root["generated_at"].text, contentMD: content,
                            periodStart: period["start"].text, periodEnd: period["end"].text)
    }

    /// The events dated today up to `raceWindowDays` from now, soonest first.
    static func upcomingEvents(_ data: Data?, today: String) -> [PFEventRow] {
        guard let list = PFEvents.parse(data) else { return [] }
        let last = PFFormat.addDays(today, raceWindowDays)
        return PFEvents.rows(list).filter { String($0.date.prefix(10)) >= today && String($0.date.prefix(10)) <= last }
    }

    private static func value(_ j: PFJ) -> String? {
        guard j.exists, let raw = j.raw else { return nil }
        if let text = raw as? String { return text }
        if let number = j.double { return PFFormat.trimmed(number) }
        guard JSONSerialization.isValidJSONObject(raw), let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Needs you

    /// Proposals leave Needs you for the week card; everything else stays there.
    static func split(_ items: [PFNeedsItem]) -> (proposals: [PFNeedsItem], others: [PFNeedsItem]) {
        (items.filter { $0.kind == .proposal }, items.filter { $0.kind != .proposal })
    }

    /// The one Today row that stands for every open proposal.
    static func todayLine(_ count: Int) -> String {
        "Your coach wants to change \(count) \(count == 1 ? "thing" : "things") in your plan"
    }

    static func cardTitle(_ count: Int) -> String {
        "The coach wants to change \(count) \(count == 1 ? "thing" : "things")"
    }

    // MARK: Markdown

    /// The markdown cut into running text and tables, in order. A table is two or more lines in a row that start with "|".
    static func blocks(_ markdown: String) -> [PFMarkdownBlock] {
        var out: [PFMarkdownBlock] = []
        var text: [Substring] = []
        var table: [Substring] = []

        func flushText() {
            let joined = text.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.text(joined)) }
            text = []
        }
        func flushTable() {
            if table.count >= 2 {
                flushText()
                out.append(.table(table.joined(separator: "\n"), columns: columns(of: table[0])))
            } else {
                text.append(contentsOf: table)
            }
            table = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                table.append(line)
            } else {
                flushTable()
                text.append(line)
            }
        }
        flushTable()
        flushText()
        return out
    }

    private static func columns(of row: Substring) -> Int {
        var cells = row.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false)
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return max(cells.count, 1)
    }

    /// The first section of a race plan: everything before its second "## " heading (a "# " title does not count as one). A plan with
    /// text before its first "## " heading ends that first section there. `hasMore` is false when the plan is one section.
    static func firstSection(_ markdown: String) -> (text: String, hasMore: Bool) {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let headings = lines.indices.filter { lines[$0].hasPrefix("## ") }
        guard let first = headings.first else { return (markdown, false) }
        let preamble = lines[..<first].contains {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !($0.hasPrefix("# "))
        }
        let cut = preamble ? first : (headings.count > 1 ? headings[1] : nil)
        guard let cut else { return (markdown, false) }
        return (lines[..<cut].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), true)
    }
}
