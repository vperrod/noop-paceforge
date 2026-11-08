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
    /// The server-built report (build 513): key numbers, what held the week back, chart names and the ordered sections.
    /// An older server sends none of them, and the card then draws `contentMD` whole.
    var summary: PFWeekSummary? = nil
    var limiters: [String] = []
    var charts: [String] = []
    var chartsAt: String? = nil
    var sections: [PFWeekSection] = []

    /// "9\u{2013}15 Nov"; nil without both ends of the period.
    var periodLabel: String? {
        guard let periodStart, let periodEnd else { return nil }
        return PFFormat.span(periodStart, periodEnd)
    }
}

/// The key numbers of the week; any of them can be missing.
struct PFWeekSummary: Equatable {
    var sessions: Int?
    var hours: Double?
    var runKm: Double?
    var avgRecovery: Int?
    var redNights: Int?
    var greenNights: Int?
    var avgSleepH: Double?
    var hrvFirst: Double?
    var hrvLast: Double?
}

/// One number of the week as a tile; `note` is the small line under it.
struct PFSummaryTile: Equatable {
    let label: String
    let value: String
    let note: String?
}

/// One block of the report, in the order the server sent it.
struct PFWeekSection: Equatable, Identifiable {
    enum Kind: String { case summary, plan, charts, md }

    let id: String
    let title: String
    let intro: String
    let md: String
    let open: Bool
    let kind: Kind
}

/// One day of the plan: the heading line and the text under it.
struct PFPlanDay: Equatable, Identifiable {
    let title: String
    let body: String

    var id: String { title }
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
                            periodStart: period["start"].text, periodEnd: period["end"].text,
                            summary: summary(root["summary"]), limiters: root["limiters"].strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                            charts: root["charts"].strings.filter(isChartKey), chartsAt: root["charts_at"].text,
                            sections: root["sections"].array.compactMap(section))
    }

    private static func summary(_ j: PFJ) -> PFWeekSummary? {
        guard j.dict.isEmpty == false else { return nil }
        return PFWeekSummary(sessions: j["sessions"].int, hours: j["hours"].double, runKm: j["run_km"].double,
                             avgRecovery: j["avg_recovery"].int, redNights: j["red_nights"].int, greenNights: j["green_nights"].int,
                             avgSleepH: j["avg_sleep_h"].double, hrvFirst: j["hrv_first"].double, hrvLast: j["hrv_last"].double)
    }

    /// A row without an id or a title is dropped; a kind this build does not know reads as plain markdown.
    private static func section(_ j: PFJ) -> PFWeekSection? {
        guard let id = j["id"].idString, !id.isEmpty, let title = j["title"].text else { return nil }
        return PFWeekSection(id: id, title: title, intro: j["intro"].text ?? "", md: j["md"].string ?? "",
                             open: j["open"].bool ?? false, kind: PFWeekSection.Kind(rawValue: j["kind"].string ?? "") ?? .md)
    }

    /// The chart name goes into a URL path: letters, digits, "-" and "_" only.
    static func isChartKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func chartPath(_ key: String) -> String { "api/charts/\(key).png" }

    static func chartCaption(_ key: String) -> String {
        switch key {
        case "pmc": return "Fitness, fatigue and form"
        case "progression": return "Eight-week progression"
        default: return PFFormat.capitalized(PFFormat.words(key))
        }
    }

    // MARK: Report sections

    /// The tiles of the summary section, in order; a number the server did not send has no tile.
    static func summaryTiles(_ s: PFWeekSummary) -> [PFSummaryTile] {
        var tiles: [PFSummaryTile] = []
        if let v = s.sessions { tiles.append(PFSummaryTile(label: "Sessions", value: String(v), note: nil)) }
        if let v = s.hours { tiles.append(PFSummaryTile(label: "Training time", value: PFFormat.trimmed(v) + " h", note: nil)) }
        if let v = s.runKm { tiles.append(PFSummaryTile(label: "Running", value: PFFormat.trimmed(v) + " km", note: nil)) }
        if let v = s.avgRecovery { tiles.append(PFSummaryTile(label: "Avg strap recovery", value: "\(v)%", note: nil)) }
        if let v = s.redNights {
            tiles.append(PFSummaryTile(label: "Red nights", value: String(v), note: s.greenNights.map { "\($0) green" }))
        }
        if let v = s.avgSleepH {
            var note: String?
            if let a = s.hrvFirst, let b = s.hrvLast { note = "HRV \(PFFormat.trimmed(a)) \u{2192} \(PFFormat.trimmed(b)) ms" }
            tiles.append(PFSummaryTile(label: "Avg sleep", value: PFFormat.trimmed(v) + " h", note: note))
        }
        return tiles
    }

    /// The text under "### One thing to NOT do" up to the next "### " heading; nil when the review has none.
    static func oneThingNotToDo(_ markdown: String) -> String? {
        var found = false
        var lines: [Substring] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("### ") {
                if found { break }
                found = line.dropFirst(4).trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("one thing to not do")
            } else if found {
                lines.append(line)
            }
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The plan cut into its days at each "### " heading. `preamble` is the text before the first one.
    static func planDays(_ markdown: String) -> (preamble: String, days: [PFPlanDay]) {
        var preamble: [Substring] = []
        var days: [(title: String, body: [Substring])] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("### ") {
                days.append((line.dropFirst(4).trimmingCharacters(in: .whitespaces), []))
            } else if days.isEmpty {
                preamble.append(line)
            } else {
                days[days.count - 1].body.append(line)
            }
        }
        func trimmed(_ lines: [Substring]) -> String { lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        return (trimmed(preamble), days.map { PFPlanDay(title: $0.title, body: trimmed($0.body)) })
    }

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Puts each proposal under the plan day it is about: by the date in the heading (yyyy-MM-dd or dd-MM-yyyy), then by the
    /// heading starting with the weekday or "Mon 09", then by the weekday anywhere in it. `byDay` lines up with `days`.
    static func assign(_ proposals: [PFPendingProposal], to days: [PFPlanDay]) -> (byDay: [[PFPendingProposal]], unmatched: [PFPendingProposal]) {
        var byDay = Array(repeating: [PFPendingProposal](), count: days.count)
        var unmatched: [PFPendingProposal] = []
        let titles = days.map { $0.title.lowercased() }
        for proposal in proposals {
            guard let iso = proposal.day.map({ String($0.prefix(10)) }), iso.count == 10, iso.filter({ $0 == "-" }).count == 2 else {
                unmatched.append(proposal)
                continue
            }
            let parts = iso.split(separator: "-")
            let dmy = parts.count == 3 ? "\(parts[2])-\(parts[1])-\(parts[0])" : iso
            let weekday = weekdayNames[Calendar(identifier: .gregorian).component(.weekday, from: PFFormat.date(iso)) - 1].lowercased()
            let short = "\(weekday.prefix(3)) \(parts.count == 3 ? String(parts[2]) : "")"
            let index = titles.firstIndex { $0.contains(iso) || $0.contains(dmy) }
                ?? titles.firstIndex { $0.hasPrefix(weekday) || $0.hasPrefix(short) || $0.contains(short) }
                ?? titles.firstIndex { $0.contains(weekday) }
            if let index { byDay[index].append(proposal) } else { unmatched.append(proposal) }
        }
        return (byDay, unmatched)
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
