import Foundation

/// When Today shows the Sunday review row, and for which week. Pure, so it is tested without a screen.
enum PFTodayReviewWindow530 {
    /// Used when the inbox has not told the phone the athlete's usual wind-down time.
    static let fallbackWindDownMinutes = 21 * 60
    static let mondayEndMinutes = 12 * 60

    /// Sunday from the wind-down time on, and Monday until 12:00 local.
    static func isOpen(now: Date, windDownMinutes: Int?, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        switch parts.weekday {
        case 1: return minutes >= (windDownMinutes ?? fallbackWindDownMinutes)
        case 2: return minutes < mondayEndMinutes
        default: return false
        }
    }

    /// The most recently finished week: the one with the latest end date on or before `today` ("yyyy-MM-dd").
    static func latestFinishedWeek(_ weeks: [PFPlanWeekIndexDoc.Week]?, today: String) -> String? {
        (weeks ?? [])
            .compactMap { week -> (String, String)? in
                guard let id = week.week, let to = week.to, to.count >= 10, String(to.prefix(10)) <= today else { return nil }
                return (id, String(to.prefix(10)))
            }
            .max { $0.1 < $1.1 }?.0
    }
}
