import Foundation

/// The `short` block inside data/reports/daily/<date>.json: the verdict first, one block per device (never merged), then what to do.
struct PFDailyShort: Codable, Equatable {
    var title: String?
    var verdict: String?
    var cause: String?
    /// Optional: the report in a few sentences, shown under the verdict (server stream B).
    var story: String?
    /// Optional: up to three small titled blocks under the story.
    var insights: [Insight]?
    var devicesTitle: String?
    var devices: [Device]?
    var devicesNote: String?
    /// Today, tonight, tomorrow, what would change this.
    var blocks: [Block]?

    /// The whole daily report document, of which only `short` is read here; everything else in it stays as it was.
    struct Document: Codable, Equatable {
        var short: PFDailyShort?
    }

    struct Device: Codable, Equatable {
        /// Garmin | WHOOP
        var source: String?
        var value: String?
        var label: String?
        var lines: [String]?
    }

    struct Insight: Codable, Equatable {
        var title: String?
        var text: String?
    }

    struct Block: Codable, Equatable {
        var title: String?
        var text: String?
    }
}
