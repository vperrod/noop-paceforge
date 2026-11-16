import Foundation

/// data/journal-view.json: the questions asked, what the devices answered, the week's row, today's prompts and the behaviour insights.
/// Every field is optional; a key this build does not know is ignored.
struct PFJournalDoc530: Codable, Equatable {
    var version: Int?
    var generatedAt: String?
    var list: [Question]?
    var auto: [AutoDay]?
    var week: [WeekDay]?
    var prompts: [Prompt]?
    var insights: [Insight]?
    var suggestions: [Suggestion]?

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
        /// yesterday | today
        var about: String?
        var yes: String?
        var no: String?
        /// collecting | clear | no_effect
        var state: String?
    }

    /// The behaviours the devices answered for one day (the last 14 days).
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
    }

    /// One behaviour against its outcomes.
    struct Insight: Codable, Equatable {
        var behaviour: String?
        var label: String?
        var outcomes: [Outcome]?
    }

    /// `outcome`: recovery | sleep | performance. `source` names the device for recovery and sleep. `lag`: 1 = next morning, 2 = the
    /// morning after.
    struct Outcome: Codable, Equatable {
        var outcome: String?
        var source: String?
        var lags: [Lag]?
    }

    /// One lag of one outcome: days with the behaviour against days without, and for a count the same split by amount.
    struct Lag: Codable, Equatable {
        var lag: Int?
        var nWith: Int?
        var nWithout: Int?
        var meanWith: Double?
        var meanWithout: Double?
        var diff: Double?
        var clear: Bool?
        var note: String?
        var byAmount: [Bucket]?
    }

    /// A count behaviour split by amount, each bucket with at least five days.
    struct Bucket: Codable, Equatable {
        var amount: String?
        var n: Int?
        var mean: Double?
        var diff: Double?
    }

    /// A proposed change to the question list (add | drop | change); absent until the server turns suggestions on.
    struct Suggestion: Codable, Equatable {
        var action: String?
        var key: String?
        var title: String?
        var reason: String?
    }
}
