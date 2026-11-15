import Foundation

/// data/plan-week/index.json: every week the Week chip can page through, 8 finished weeks back to the end of the last race block.
struct PFPlanWeekIndexDoc: Codable, Equatable {
    var version: Int?
    var generatedAt: String?
    /// ISO week of today ("2026-W47").
    var current: String?
    var weeks: [Week]?

    struct Week: Codable, Equatable {
        var week: String?
        var from: String?
        var to: String?
        /// finished | current | coming
        var state: String?
        var phase: String?
        var phaseLabel: String?
        var label: String?
        var reportReady: Bool?
        var verdict: String?
    }
}
