import Foundation

/// data/journal-view.json: the questions asked, what the devices answered, the week's row, today's prompts and the behaviour insights.
/// Every field is optional; a key this build does not know is ignored. Each block decodes on its own, and inside a list each entry on
/// its own, so a field the server changes costs that entry, never the document.
/// Shapes follow the server (`journal_doc.py`, build 530): `insights` is one flat entry per behaviour, outcome, device and lag.
struct PFJournalDoc530: Codable, Equatable {
    var stale: Bool? = nil
    var version: Int?
    var generatedAt: String?
    var asOf: String?
    var list: [Question]?
    var auto: [AutoDay]?
    var week: [WeekDay]?
    var prompts: [Prompt]?
    var insights: [Insight]?
    var suggestions: [Suggestion]?
    var proposals: [Suggestion]? = nil

    /// One active question. `key` is the question text exactly as the phone stores it.
    struct Question: Codable, Equatable {
        var key: String?
        var label: String?
        var prompt: String?
        var hint: String?
        /// yes_no | count | time | scale
        var kind: String?
        /// morning | afternoon | evening
        var window: String?
        /// yesterday | today: the day an answer belongs to (the day the behaviour happened)
        var about: String?
        var yes: String?
        var no: String?
        /// collecting | clear | no_effect
        var state: String?
        /// The device(s) behind `state`, for example "NOOP".
        var stateSource: String?
        /// Days in the last 90 answered yes and no.
        var nYes: Int?
        var nNo: Int?
    }

    /// The behaviours the devices answered for one day (the last 14 days). Today lists yes answers only.
    struct AutoDay: Codable, Equatable {
        var date: String?
        var answers: [AutoAnswer]?
    }

    struct AutoAnswer: Codable, Equatable {
        var id: String?
        var label: String?
        var answer: Bool?
        var evidence: String?
    }

    /// Monday to Sunday: was the journal logged that day.
    struct WeekDay: Codable, Equatable {
        var date: String?
        var logged: Bool?
    }

    /// Today's prompt for one window; `open` is the number of questions still unanswered.
    struct Prompt: Codable, Equatable {
        var window: String?
        var title: String?
        var body: String?
        var open: Int?
        var state: String?
        /// The server's stable assignment for this day, after cooldown/context selection.
        var selectedKeys: [String]? = nil
        var openKeys: [String]? = nil
    }

    /// One behaviour against one outcome on one device at one lag: days with the behaviour against days without, and for a count the same
    /// split by amount. `outcome`: recovery | sleep. `device`: NOOP | Garmin. `lag`: 1 = the first morning or night after, 2 = the one after that.
    /// `unit`: "%" (NOOP Charge), "" (a Garmin score out of 100), "h" (hours asleep).
    struct Insight: Codable, Equatable {
        var behaviour: String?
        var label: String?
        var outcome: String?
        var device: String?
        var measure: String?
        var unit: String?
        var lag: Int?
        var nWith: Int?
        var nWithout: Int?
        var meanWith: Double?
        var meanWithout: Double?
        var diff: Double?
        /// The difference in percent as the server works it out (-9.9); the phone never computes it.
        var pct: Double?
        var clear: Bool?
        var note: String?
        var byAmount: [Bucket]?
    }

    /// A count behaviour split by amount ("1", "2", "3+"), each bucket with at least five days.
    struct Bucket: Codable, Equatable {
        var amount: String?
        var n: Int?
        var mean: Double?
    }

    /// A proposed change to the question list (add | drop | change); absent until the server turns suggestions on.
    struct Suggestion: Codable, Equatable {
        var id: String? = nil
        var canAccept: Bool? = nil
        var action: String?
        var key: String?
        var title: String?
        var reason: String?
    }

    private enum CodingKeys: String, CodingKey {
        case version, generatedAt, asOf, list, auto, week, prompts, insights, suggestions, proposals, stale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stale = try? c.decodeIfPresent(Bool.self, forKey: .stale)
        version = try? c.decodeIfPresent(Int.self, forKey: .version)
        generatedAt = try? c.decodeIfPresent(String.self, forKey: .generatedAt)
        asOf = try? c.decodeIfPresent(String.self, forKey: .asOf)
        list = (try? c.decodeIfPresent(PFLossyList530<Question>.self, forKey: .list))?.items
        auto = (try? c.decodeIfPresent(PFLossyList530<AutoDay>.self, forKey: .auto))?.items
        week = (try? c.decodeIfPresent(PFLossyList530<WeekDay>.self, forKey: .week))?.items
        prompts = (try? c.decodeIfPresent(PFLossyList530<Prompt>.self, forKey: .prompts))?.items
        insights = (try? c.decodeIfPresent(PFLossyList530<Insight>.self, forKey: .insights))?.items
        suggestions = (try? c.decodeIfPresent(PFLossyList530<Suggestion>.self, forKey: .suggestions))?.items
        proposals = (try? c.decodeIfPresent(PFLossyList530<Suggestion>.self, forKey: .proposals))?.items
    }

    init(version: Int? = nil, generatedAt: String? = nil, asOf: String? = nil, list: [Question]? = nil, auto: [AutoDay]? = nil,
         week: [WeekDay]? = nil, prompts: [Prompt]? = nil, insights: [Insight]? = nil, suggestions: [Suggestion]? = nil) {
        self.version = version
        self.generatedAt = generatedAt
        self.asOf = asOf
        self.list = list
        self.auto = auto
        self.week = week
        self.prompts = prompts
        self.insights = insights
        self.suggestions = suggestions
    }
}

/// A list that keeps the entries that decode and skips the rest.
struct PFLossyList530<Element: Decodable>: Decodable {
    let items: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var kept: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                kept.append(element)
            } else {
                _ = try? container.decode(PFSkipped530.self)
            }
        }
        items = kept
    }
}

/// Decodes from any value and keeps nothing: moves a container past an entry that failed.
private struct PFSkipped530: Decodable {
    init(from decoder: Decoder) throws {}
}
