import Foundation

/// The `short` block inside data/reports/monthly/<month>.json.
struct PFMonthlyShort: Codable, Equatable {
    var title: String?
    var verdict: String?
    var summary: String?
    /// Optional: the month in a few sentences, shown under the verdict and summary (server stream B).
    var story: String?
    /// Optional: up to three small titled blocks under the story.
    var insights: [Insight]?
    var held: [String]?
    var slipped: [String]?
    var compareTitle: String?
    var tiles: [Tile]?
    var trend: Trend?
    var focusTitle: String?
    var focus: String?

    /// The whole monthly report document, of which only `short` is read here.
    struct Document: Codable, Equatable {
        var short: PFMonthlyShort?
    }

    struct Insight: Codable, Equatable {
        var title: String?
        var text: String?
    }

    struct Tile: Codable, Equatable {
        var value: String?
        var label: String?
        var sub: String?
    }

    struct Trend: Codable, Equatable {
        var title: String?
        var points: [Point]?
    }

    struct Point: Codable, Equatable {
        var label: String?
        var value: Double?
    }
}
