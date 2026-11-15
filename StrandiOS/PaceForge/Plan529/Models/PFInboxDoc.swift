import Foundation

/// data/inbox.json: everything the athlete is told, newest first, kept 14 days.
struct PFInboxDoc: Codable, Equatable {
    var version: Int?
    var generatedAt: String?
    var items: [Item]?

    struct Item: Codable, Equatable {
        /// Stable across refreshes: the phone keeps unread marks by it.
        var id: String?
        var ts: String?
        /// today | workout | health | coach | report | plan | problem
        var kind: String?
        /// True when the item raises a phone notification once.
        var notify: Bool?
        var title: String?
        var body: String?
        var listTitle: String?
        var listSub: String?
        var link: Link?
    }

    /// Where a tap goes. `route` is one of week, changes, report_daily, report_month, race, workout, coach_noticed, stress, heart_rate,
    /// effort, needs_you, today; the other fields say which one.
    struct Link: Codable, Equatable {
        var route: String?
        var week: String?
        var id: String?
        var date: String?
        var key: String?
        var activityId: String?
    }
}
