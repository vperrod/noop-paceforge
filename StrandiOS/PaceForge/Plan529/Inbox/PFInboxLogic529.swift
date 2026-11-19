import Foundation

// The inbox behind the bell on Today (build 529): the decisions, with no UI and no clock of their own. Foundation only, so the macOS
// unit-test bundle compiles it (PFInboxLogic529Tests). The store, the notifier and the screen are the files next to it.

// MARK: - Kinds and filters

/// The kinds the server puts on an inbox item (`data/inbox.json`). Each has one switch under "Choose what you are told about".
enum PFInboxKind529: String, CaseIterable, Identifiable {
    case today, workout, health, coach, report, plan, problem, progress, bedtime, journal, review

    var id: String { rawValue }

    var switchTitle: String {
        switch self {
        case .today: return "Your morning verdict"
        case .workout: return "Workout reviews"
        case .health: return "Health alerts"
        case .coach: return "Coach notes"
        case .report: return "Reports"
        case .plan: return "Plan changes"
        case .problem: return "Problems only you can fix"
        case .progress: return "Progress in your week"
        case .bedtime: return "Bedtime reminder"
        case .journal: return "Journal questions"
        case .review: return "Sunday review"
        }
    }

    var switchDetail: String {
        switch self {
        case .today: return "Rest, ease or go, once your night is processed."
        case .workout: return "When the coach has reviewed a workout or a race."
        case .health: return "Stress, resting heart rate and other signs during the day."
        case .coach: return "When your performance changes. Two a day at most."
        case .report: return "When a week or a month report is ready."
        case .plan: return "When the coach proposes changes to your plan."
        case .problem: return "For example when Garmin needs you to sign in again."
        case .progress: return "When half of your week's sessions, or all of them, are done."
        case .bedtime: return "When your sleep is short, a nudge at your wind-down time."
        case .journal: return "Your journal questions, in the morning, afternoon and evening."
        case .review: return "When your Sunday review and the week ahead are ready."
        }
    }
}

/// The chips above the list. A kind this build does not know is shown under All only.
enum PFInboxFilter529: String, CaseIterable, Identifiable {
    case all, coach, reports, plan, health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .coach: return "Coach"
        case .reports: return "Reports"
        case .plan: return "Plan"
        case .health: return "Health"
        }
    }

    func includes(kind: String?) -> Bool {
        switch self {
        case .all: return true
        case .coach: return kind == "coach" || kind == "workout"
        case .reports: return kind == "report" || kind == "today"
        case .plan: return kind == "plan"
        case .health: return kind == "health" || kind == "problem"
        }
    }
}

// MARK: - Rows

/// One line of the inbox: an item of `data/inbox.json`, or a line of the earlier alert history (an alert the server still keeps, a
/// Needs you item the phone announced) that the document does not carry.
struct PFInboxRow529: Identifiable, Equatable {
    let id: String
    var date: Date?
    var kind: String?
    var title: String
    var subtitle: String?
    var link: PFInboxDoc.Link?
    /// The earlier history line this row came from; its tap routes as a tap on that notification does.
    var legacy: PFAlertEntry?
}

enum PFInboxLogic529 {
    static let reportKinds: Set<String> = ["today", "report", "review"]

    /// The unread dot on the Plan tab: a plan change, a report, or the morning verdict (which opens the daily report).
    static let planDotKinds: Set<String> = ["plan", "report", "today"]
    /// The unread dot on the Coach button: a coach note or a workout review.
    static let coachDotKinds: Set<String> = ["coach", "workout"]

    /// The document's items and the earlier history, newest first. A history line whose id the document already has is dropped (the
    /// document's item wins). A line without a date goes last; equal dates keep a fixed order by id.
    static func rows(items: [PFInboxDoc.Item], legacy: [PFAlertEntry]) -> [PFInboxRow529] {
        var out: [PFInboxRow529] = []
        var have: Set<String> = []
        for item in items {
            guard let id = item.id, !id.isEmpty, have.insert(id).inserted else { continue }
            let title = nonEmpty(item.listTitle) ?? nonEmpty(item.title) ?? ""
            out.append(PFInboxRow529(id: id, date: PFAlertDates.parse(item.ts), kind: item.kind, title: title,
                                     subtitle: nonEmpty(item.listSub) ?? nonEmpty(item.body), link: resolvedLink(of: item), legacy: nil))
        }
        for entry in legacy {
            guard have.insert(entry.id).inserted else { continue }
            out.append(PFInboxRow529(id: entry.id, date: entry.date, kind: entry.source == .needsYou ? "coach" : "health",
                                     title: entry.title, subtitle: nonEmpty(entry.body), link: nil, legacy: entry))
        }
        return out.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?): return l != r ? l > r : lhs.id < rhs.id
            case (nil, nil): return lhs.id < rhs.id
            case (_?, nil): return true
            case (nil, _?): return false
            }
        }
    }

    static func filtered(_ rows: [PFInboxRow529], by filter: PFInboxFilter529) -> [PFInboxRow529] {
        rows.filter { filter.includes(kind: $0.kind) }
    }

    /// The rows not in `seen`. `seen` nil (no baseline taken yet) reads as everything seen: a phone that gets this build starts with an
    /// inbox that has nothing unread.
    static func unread(_ rows: [PFInboxRow529], seen: Set<String>?) -> [PFInboxRow529] {
        guard let seen else { return [] }
        return rows.filter { !seen.contains($0.id) }
    }

    static func hasUnread(_ unreadRows: [PFInboxRow529], kinds: Set<String>) -> Bool {
        unreadRows.contains { $0.kind.map(kinds.contains) ?? false }
    }

    /// The seen list with `ids` added at the end (no repeats), the newest `cap` kept.
    static func marking(_ seen: [String], read ids: [String], cap: Int = 300) -> [String] {
        var have = Set(seen)
        var out = seen
        for id in ids where have.insert(id).inserted { out.append(id) }
        return Array(out.suffix(cap))
    }

    /// The item's link with a journal route made specific: the server sends `{"route": "journal"}` and the item's `window` says which sheet.
    /// Each journal alert opens the window it names.
    static func resolvedLink(of item: PFInboxDoc.Item) -> PFInboxDoc.Link? {
        guard var link = item.link, link.route == "journal" else { return item.link }
        switch item.window {
        case "morning": link.route = "journal_morning"
        case "day", "afternoon": link.route = "journal_afternoon"
        default: link.route = "journal_evening"
        }
        return link
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    // MARK: Notifications

    /// At most one check every `interval` seconds. A last check in the future (a clock that was set back) counts as due.
    static func isDue(last: Date?, now: Date, interval: TimeInterval = 600) -> Bool {
        guard let last else { return true }
        let age = now.timeIntervalSince(last)
        return age < 0 || age >= interval
    }

    struct NotifyDecision: Equatable {
        /// The items to raise a notification for, in the order the document lists them.
        var toNotify: [PFInboxDoc.Item]
        /// The ids to remember from now on: every id seen, the newest `cap`.
        var notified: [String]
    }

    static func maxNotificationAge(kind: String) -> TimeInterval {
        switch kind {
        case "today": return 18 * 3_600
        case "report", "review": return 14 * 86_400
        default: return 2 * 86_400
        }
    }

    /// The newest item of each report kind, chosen by timestamp even if the document's array order changes.
    /// If either timestamp is unreadable, preserve the first item in document order for that kind.
    static func latestReportIDs(items: [PFInboxDoc.Item]) -> Set<String> {
        var latest: [String: PFInboxDoc.Item] = [:]
        for item in items {
            guard let id = item.id, !id.isEmpty, let kind = item.kind, reportKinds.contains(kind) else { continue }
            guard let current = latest[kind] else { latest[kind] = item; continue }
            guard let currentDate = PFAlertDates.parse(current.ts), let candidateDate = PFAlertDates.parse(item.ts),
                  candidateDate > currentDate else { continue }
            latest[kind] = item
        }
        return Set(latest.values.compactMap(\.id))
    }

    /// Which items raise a local notification. `notified` nil is the first run: every id is only recorded, so installing this build
    /// does not replay the 14 days. An eligible item is announced when `notify` is true, its kind is switched on, it is recent, and it
    /// was not already announced through the earlier alert path (`legacyNotified`: the ids that path remembers). A report item already
    /// seen on this phone is reconsidered only when the server marks that item `retry`; among those, only the newest of each kind can retry.
    /// Other items retain their one-shot seen-id behavior. The delivery ledger prevents repeats.
    static func decide(items: [PFInboxDoc.Item], notified: [String]?, enabledKinds: Set<String>, legacyNotified: Set<String>,
                       raisedIDs: Set<String> = [],
                       now: Date, cap: Int = 300) -> NotifyDecision {
        let ids = items.compactMap { item -> String? in
            guard let id = item.id, !id.isEmpty else { return nil }
            return id
        }
        guard let notified else { return NotifyDecision(toNotify: [], notified: Array(ids.suffix(cap))) }
        var have = Set(notified)
        var fresh: [PFInboxDoc.Item] = []
        var newIDs: [String] = []
        var processed: Set<String> = []
        let latestIDs = latestReportIDs(items: items)
        for item in items {
            guard let id = item.id, !id.isEmpty, processed.insert(id).inserted else { continue }
            let isNew = have.insert(id).inserted
            if isNew { newIDs.append(id) }
            guard let kind = item.kind else { continue }
            let shouldCheck = isNew || (reportKinds.contains(kind) && latestIDs.contains(id) && item.retry == true)
            guard shouldCheck else { continue }
            guard !raisedIDs.contains(id) else { continue }
            guard item.notify == true, enabledKinds.contains(kind) else { continue }
            guard !isAnnouncedByEarlierPath(id: id, legacyNotified: legacyNotified) else { continue }
            if let when = PFAlertDates.parse(item.ts), now.timeIntervalSince(when) >= maxNotificationAge(kind: kind) { continue }
            fresh.append(item)
        }
        let remembered = Array((notified + newIDs).suffix(cap))
        return NotifyDecision(toNotify: fresh, notified: remembered)
    }

    /// The earlier alert path remembers an alert by its own id. An inbox id "alert:<id>" counts as announced when that path has the bare
    /// id. (Needs you items are not in the inbox: they stay on their own path.)
    static func isAnnouncedByEarlierPath(id: String, legacyNotified: Set<String>) -> Bool {
        if legacyNotified.contains(id) { return true }
        guard id.hasPrefix("alert:") else { return false }
        return legacyNotified.contains(String(id.dropFirst("alert:".count)))
    }

    /// How long after the server wrote an item the phone first saw it; nil when the item has no readable time.
    static func delay(of item: PFInboxDoc.Item, now: Date) -> TimeInterval? {
        guard let when = PFAlertDates.parse(item.ts) else { return nil }
        return max(0, now.timeIntervalSince(when))
    }

    /// "4 min", "2 h 10 min", "1 day": the delay as the diagnostics row prints it.
    static func delayText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        return hours < 48 ? "1 day" : "\(hours / 24) days"
    }
}

// MARK: - Where a tap goes

/// What a tapped inbox row or notification opens. `link.route` is one of week, changes, report_daily, report_month, race, workout,
/// coach_noticed, stress, heart_rate, effort, needs_you, today; a route this build does not know, no link, or a workout link
/// without its activity opens the inbox itself.
enum PFInboxRoute529: Equatable {
    /// Plan > Week, on this ISO week; nil opens the Week chip as it was.
    case week(String?)
    case dailyReport(date: String?)
    case monthReport(key: String?)
    case race(date: String?)
    case workout(activityID: String?, date: String?)
    case coachNoticed(id: String?)
    case stress
    case heartRate
    case effort
    case needsYou
    case today
    /// The Sunday review of this ISO week; nil opens the last finished week.
    case review(week: String?)
    case journalMorning
    case journalAfternoon
    case journalEvening
    /// The inbox itself: nothing more specific can be opened.
    case inbox

    init(link: PFInboxDoc.Link?) {
        guard let link, let route = link.route else { self = .inbox; return }
        switch route {
        case "week", "changes": self = .week(link.week)
        case "report_daily": self = .dailyReport(date: link.date)
        case "report_month": self = .monthReport(key: link.key)
        case "race": self = .race(date: link.date)
        case "workout":
            if let activity = link.activityId, !activity.isEmpty { self = .workout(activityID: activity, date: link.date) } else { self = .inbox }
        case "coach_noticed": self = .coachNoticed(id: link.id)
        case "stress": self = .stress
        case "heart_rate": self = .heartRate
        case "effort": self = .effort
        case "needs_you": self = .needsYou
        case "today": self = .today
        case "review": self = .review(week: link.week)
        case "journal_morning": self = .journalMorning
        case "journal_afternoon": self = .journalAfternoon
        case "journal_evening", "journal": self = .journalEvening
        default: self = .inbox
        }
    }
}

/// The payload of a local notification for an inbox item: what a tap on it needs to route. Strings only, so it survives the round trip
/// through the notification centre. `pf.kind` is the key `NotificationPresenter` looks for.
enum PFInboxPayload529 {
    static let kindKey = "pf.kind"
    static let inboxKind = "inbox"
    /// The item's kind, so a dismissal or an open of the notification can be counted per kind without the document.
    static let itemKindKey = "pf.item_kind"
    private static let keys: [(String, KeyPath<PFInboxDoc.Link, String?>)] = [
        ("pf.route", \.route), ("pf.week", \.week), ("pf.link_id", \.id), ("pf.date", \.date), ("pf.key", \.key),
        ("pf.activity_id", \.activityId),
    ]

    static func userInfo(for item: PFInboxDoc.Item) -> [AnyHashable: Any] {
        var out: [AnyHashable: Any] = [kindKey: inboxKind, "pf.id": item.id ?? ""]
        if let kind = item.kind, !kind.isEmpty { out[itemKindKey] = kind }
        let link = PFInboxLogic529.resolvedLink(of: item)
        for (key, path) in keys {
            if let value = link?[keyPath: path], !value.isEmpty { out[key] = value }
        }
        return out
    }

    /// nil when the payload is not an inbox item's.
    static func link(from userInfo: [AnyHashable: Any]) -> PFInboxDoc.Link? {
        guard userInfo[kindKey] as? String == inboxKind else { return nil }
        func text(_ key: String) -> String? { userInfo[key] as? String }
        return PFInboxDoc.Link(route: text("pf.route"), week: text("pf.week"), id: text("pf.link_id"), date: text("pf.date"),
                               key: text("pf.key"), activityId: text("pf.activity_id"))
    }
}
