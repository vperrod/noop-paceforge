import Foundation

/// data/reports/list.json: today's report, the weeks, months, races and workouts that have one, each with a one-line verdict.
struct PFReportsListDoc: Codable, Equatable {
    var version: Int?
    var generatedAt: String?
    var today: Row?
    var weeks: [Row]?
    var months: [Row]?
    var races: [RaceRow]?
    var workouts: [WorkoutRow]?

    /// A day, week or month report.
    struct Row: Codable, Equatable {
        var key: String?
        var day: String?
        var verdict: String?
        var sub: String?
        var ts: String?
        /// Only on `today`: true when the report is finished and written from a device reading. The row is listed either way.
        var ready: Bool?
        /// Only on `today`: why it is not ready (null when it is).
        var reason: String?
    }

    struct RaceRow: Codable, Equatable {
        var date: String?
        var day: String?
        var name: String?
        var sub: String?
        var activityId: String?
        var ts: String?
    }

    struct WorkoutRow: Codable, Equatable {
        var activityId: String?
        var day: String?
        var name: String?
        var sub: String?
        /// Optional: one sentence on what the workout means, shown as a second line.
        var meaning: String?
        /// ready | pending
        var state: String?
        var ts: String?
    }
}
