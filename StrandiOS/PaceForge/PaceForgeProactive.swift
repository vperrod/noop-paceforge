import Foundation

// proactive.json: the coach's own short messages about trends, improvements, what works and what costs, written from the athlete's
// data. Foundation only (decoding, which messages Today shows, the groups of the Insights list), so the unit tests compile it
// (see project.yml, StrandTests). The text and source are shown as the server wrote them: Garmin's and the strap's numbers are
// never recomputed or merged here.

enum PFProactiveTone: Equatable {
    case good, watch, info

    /// An unknown value (the server may add kinds) reads as info.
    init(_ raw: String?) {
        switch raw {
        case "good": self = .good
        case "watch": self = .watch
        default: self = .info
        }
    }
}

enum PFProactiveFamily: Equatable {
    case trend, improvement, works, costs, rhythm, race, other

    init(_ raw: String?) {
        switch raw {
        case "trend": self = .trend
        case "improvement": self = .improvement
        case "works": self = .works
        case "costs": self = .costs
        case "rhythm": self = .rhythm
        case "race": self = .race
        default: self = .other
        }
    }
}

struct PFProactiveMessage: Equatable, Identifiable {
    let id: String
    let date: String
    let text: String
    var title: String?
    var family: PFProactiveFamily = .other
    var tone: PFProactiveTone = .info
    var source: String?
}

/// The headings of the Insights list, in the order they are drawn. A message of an unknown family has no group and is not listed there.
enum PFProactiveGroup: CaseIterable {
    case working, costing, trends, races

    var title: String {
        switch self {
        case .working: return "What is working"
        case .costing: return "What is costing you"
        case .trends: return "Trends to watch"
        case .races: return "Races"
        }
    }

    static func of(_ family: PFProactiveFamily) -> PFProactiveGroup? {
        switch family {
        case .works, .improvement: return .working
        case .costs: return .costing
        case .trend, .rhythm: return .trends
        case .race: return .races
        case .other: return nil
        }
    }
}

struct PFProactiveDoc: Equatable {
    var messages: [PFProactiveMessage] = []

    /// A message without an id, a date or a text is dropped; every other field is optional.
    static func parse(_ j: PFJ) -> PFProactiveDoc? {
        guard j.exists, let list = j["messages"].raw as? [Any] else { return nil }
        let messages = list.indices.compactMap { index -> PFProactiveMessage? in
            let m = j["messages"][index]
            guard let id = m["id"].string, let date = m["date"].string, let text = m["text"].string, !text.isEmpty else { return nil }
            return PFProactiveMessage(id: id, date: String(date.prefix(10)), text: text, title: m["title"].string,
                                      family: PFProactiveFamily(m["family"].string), tone: PFProactiveTone(m["tone"].string),
                                      source: m["source"].string)
        }
        return PFProactiveDoc(messages: messages)
    }

    /// Newest first; the order the server sent breaks ties.
    private var newestFirst: [PFProactiveMessage] {
        messages.enumerated().sorted { ($0.element.date, $1.offset) > ($1.element.date, $0.offset) }.map(\.element)
    }

    /// What Today's card shows: messages dated today or yesterday, newest first, at most two.
    func forToday(_ todayISO: String) -> [PFProactiveMessage] {
        let yesterday = PFFormat.addDays(todayISO, -1)
        return Array(newestFirst.filter { $0.date == todayISO || $0.date == yesterday }.prefix(2))
    }

    /// What the Insights list shows: the last 14 days, under their headings; a heading with nothing under it is left out.
    func groups(_ todayISO: String) -> [(group: PFProactiveGroup, messages: [PFProactiveMessage])] {
        let oldest = PFFormat.addDays(todayISO, -13)
        let recent = newestFirst.filter { $0.date >= oldest }
        return PFProactiveGroup.allCases.compactMap { group in
            let inGroup = recent.filter { PFProactiveGroup.of($0.family) == group }
            return inGroup.isEmpty ? nil : (group, inGroup)
        }
    }
}

/// Whose recording an activity is, from the tag the builder puts in its name ("... \u{00B7} NOOP strap" is the WHOOP strap,
/// "... \u{00B7} Apple Health via NOOP" is Apple Health); anything untagged came from Garmin. Foundation only, so the unit tests compile it.
enum PFRecordingSource {
    static func name(forActivityName name: String) -> String {
        if name.contains("Apple Health") { return "Apple Health" }
        if name.contains("NOOP strap") { return "WHOOP strap" }
        return name.contains("via NOOP") ? "NOOP" : "Garmin"
    }
}
