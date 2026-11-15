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
        /// ready | pending
        var state: String?
        var ts: String?
    }
}
