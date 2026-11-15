import Foundation

/// The `short` block inside data/reports/monthly/<month>.json.
struct PFMonthlyShort: Codable, Equatable {
    var title: String?
    var verdict: String?
    var summary: String?
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
