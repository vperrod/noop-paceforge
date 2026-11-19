import Foundation

/// data/inbox.json: everything the athlete is told, newest first, kept 14 days.
struct PFInboxDoc: Codable, Equatable {
    var version: Int?
    var generatedAt: String?
    var items: [Item]?
    /// The current server-side automatic mutes, used to reconcile the phone after a web-side change.
    var muted: [String]? = nil
    /// Updated when the server changes the mute snapshot; stale in-flight inbox fetches are ignored.
    var mutedAt: String? = nil
    /// Build 530: the athlete's usual sleep times, so the phone stays quiet while asleep.
    var quiet: Quiet?

    struct Quiet: Codable, Equatable {
        /// "23:15"
        var usualBedtime: String?
        var usualWake: String?
        /// Usual bedtime minus 90 minutes.
        var windDown: String?
    }

    struct Item: Codable, Equatable {
        /// Stable across refreshes: the phone keeps unread marks by it.
        var id: String?
        var ts: String?
        /// today | workout | health | coach | report | plan | problem | progress | bedtime | journal | review
        var kind: String?
        /// True when the item raises a phone notification once.
        var notify: Bool?
        /// Explicit server retry after a previously silent item was reopened by the athlete.
        var retry: Bool? = nil
        var title: String?
        var body: String?
        var listTitle: String?
        var listSub: String?
        var link: Link?
        /// Build 530: morning | day | evening | any. The phone delivers inside the window.
        var window: String?
        /// Build 530: ISO time; nothing is delivered before it.
        var notBefore: String?
    }

    /// Where a tap goes. `route` is one of week, changes, report_daily, report_month, race, workout, coach_noticed, stress, heart_rate,
    /// effort, needs_you, today, review, journal_morning, journal_evening; the other fields say which one.
    struct Link: Codable, Equatable {
        var route: String?
        var week: String?
        var id: String?
        var date: String?
        var key: String?
        var activityId: String?
    }
}
