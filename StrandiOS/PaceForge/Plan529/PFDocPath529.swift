import Foundation

/// The documents the Plan section reads, as paths under the PaceForge site root (the same form as `PFDocPath`). Foundation only.
/// A report document is fetched by its date or key and carries its `short` block (`PFDailyShort.Document`, `PFMonthlyShort.Document`).
enum PFDocPath529 {
    static let weekIndex = "data/plan-week/index.json"
    static let season = "data/season.json"
    static let settings = "data/plan-settings.json"
    static let reportsList = "data/reports/list.json"
    static let inbox = "data/inbox.json"
    static let journal = "data/journal-view.json"
    static let todayCards = "data/today-cards.json"
    /// Where each upcoming planned session stands on the way to the watch (read-only, no Garmin call).
    static let watchStatus = "api/watch-status"
    /// The coach's TrueCoach week: last read, count, any error and what the last replan did around it.
    static let trueCoachStatus = "api/truecoach-status"

    /// "2026-W47"
    static func week(_ isoWeek: String) -> String { "data/plan-week/\(isoWeek).json" }
    /// "2026-11-15"
    static func dailyReport(_ date: String) -> String { "data/reports/daily/\(date).json" }
    /// "2026-10"
    static func monthlyReport(_ key: String) -> String { "data/reports/monthly/\(key).json" }
}
