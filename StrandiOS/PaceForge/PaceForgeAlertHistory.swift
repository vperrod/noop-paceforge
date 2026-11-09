import Foundation

// The Alerts history behind the bell on NOOP Today: the PaceForge alerts the server still keeps and the Needs you items this phone
// announced, merged into one list, grouped, and counted as read or unread. This file is Foundation-only: the merging, the grouping,
// the unread count and the seen-ids bookkeeping, all with the clock and the calendar passed in. Where the lists are stored and how
// they look is in PaceForgeAlertHistoryStore.swift and PaceForgeAlertsHistoryView.swift.

// MARK: Status and kind

/// Where an alert or a Needs you item stands, when that is known.
enum PFAlertStatus: String, Equatable {
    case open
    case dismissed
    case done
    case answered

    /// The server's `status` for an alert; nil for a word this build does not know.
    init?(server: String?) {
        guard let server, let status = PFAlertStatus(rawValue: server.lowercased()) else { return nil }
        self = status
    }
}

/// The short kind label on a row.
enum PFAlertTag: Equatable {
    case inputNeeded, loadSpike, loadRamp, sleepDebt, hrvLow, restingHeartRate, lowReadiness, poorRecharge
    case weighIn, hydration, heartRateRecovery, healthMonitor, live, other

    /// From the server's alert `kind` (alerts.py, live_alerts.py).
    static func tag(alertKind: String?) -> PFAlertTag {
        guard let kind = alertKind else { return .other }
        if kind.hasPrefix("live_") { return .live }
        switch kind {
        case "load_spike": return .loadSpike
        case "load_ramp": return .loadRamp
        case "sleep_debt": return .sleepDebt
        case "hrv_below": return .hrvLow
        case "rhr_up": return .restingHeartRate
        case "readiness_low": return .lowReadiness
        case "recharge_low": return .poorRecharge
        case "weigh_in_missed": return .weighIn
        case "hydration": return .hydration
        case "hrr2_flag": return .heartRateRecovery
        case "health_monitor": return .healthMonitor
        default: return .other
        }
    }
}

// MARK: Dates

enum PFAlertDates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// An alert's `created_at`: ISO with or without fractions and an offset, or a bare local time (read in this phone's time zone).
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        return fractional.date(from: text) ?? plain.date(from: text) ?? local.date(from: String(text.prefix(19)))
    }
}

// MARK: Entries

/// A Needs you item this phone announced with a notification, kept so the history can show it after it leaves the card.
struct PFAnnouncedNeed: Codable, Equatable {
    var id: String
    var kind: String
    var title: String
    var activityID: String?
    var date: Date

    static func encode(_ list: [PFAnnouncedNeed]) -> Data? { try? JSONEncoder().encode(list) }

    /// An empty or unreadable record reads as no items.
    static func decode(_ data: Data?) -> [PFAnnouncedNeed] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PFAnnouncedNeed].self, from: data)) ?? []
    }
}

/// One line of the history, from an alert or from an announced Needs you item.
struct PFAlertEntry: Equatable, Identifiable {
    enum Source: String, Equatable {
        case alert
        case needsYou
    }

    /// Unique across both sources, and what the seen list holds.
    let id: String
    let source: Source
    /// The server's own id (the alert's, or the Needs you item's).
    let rawID: String
    var kind: String?
    var severity: String?
    var title: String
    var body: String?
    var date: Date?
    var status: PFAlertStatus?
    var activityID: String?

    var tag: PFAlertTag { source == .needsYou ? .inputNeeded : PFAlertTag.tag(alertKind: kind) }

    /// The payload a notification of this line would carry, so a tap routes exactly as a tap on that notification does.
    var userInfo: [AnyHashable: Any] {
        PFAlertRoute.userInfo(kind: source == .alert ? PFAlertRoute.alertKind : PFAlertRoute.needsYouKind,
                              id: rawID, activityID: activityID)
    }

    var route: PFAlertRoute { PFAlertRoute(userInfo: userInfo) ?? .needsYou }
}

enum PFAlertGroup: Int, Equatable {
    case unread, today, yesterday, earlier
}

struct PFAlertSection: Equatable {
    let group: PFAlertGroup
    let entries: [PFAlertEntry]
}

// MARK: Merging, grouping, reading

enum PFAlertHistory {
    static let announcedCap = 100
    static let seenCap = 300

    static func entryID(_ source: PFAlertEntry.Source, _ rawID: String) -> String { "\(source.rawValue):\(rawID)" }

    /// Both sources in one list, newest first. A line without a date goes last; equal dates keep a fixed order by id. An alert listed
    /// twice shows once. `openNeedsIDs` is the Needs you ids the server lists now: an announced item missing from it was answered; nil
    /// (not loaded yet) claims nothing.
    static func entries(alerts: [PFAlert], announced: [PFAnnouncedNeed], openNeedsIDs: Set<String>?) -> [PFAlertEntry] {
        var out: [PFAlertEntry] = []
        var seen: Set<String> = []
        for alert in alerts {
            let id = entryID(.alert, alert.id)
            guard seen.insert(id).inserted else { continue }
            out.append(PFAlertEntry(id: id, source: .alert, rawID: alert.id, kind: alert.kind, severity: alert.severity,
                                    title: alert.title, body: alert.body, date: PFAlertDates.parse(alert.createdAt),
                                    status: PFAlertStatus(server: alert.status), activityID: alert.activityID))
        }
        for need in announced {
            let id = entryID(.needsYou, need.id)
            guard seen.insert(id).inserted else { continue }
            let status: PFAlertStatus? = openNeedsIDs.map { $0.contains(need.id) ? PFAlertStatus.open : PFAlertStatus.answered }
            out.append(PFAlertEntry(id: id, source: .needsYou, rawID: need.id, kind: need.kind, severity: nil,
                                    title: need.title, body: nil, date: need.date, status: status, activityID: need.activityID))
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

    /// Unread lines first, then the read ones as Today, Yesterday and Earlier (a line without a date is Earlier). Empty groups are left
    /// out; the order inside a group is the order given.
    static func sections(_ entries: [PFAlertEntry], seen: Set<String>, now: Date, calendar: Calendar) -> [PFAlertSection] {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        var buckets: [PFAlertGroup: [PFAlertEntry]] = [:]
        for entry in entries {
            let group: PFAlertGroup
            if !seen.contains(entry.id) {
                group = .unread
            } else if let date = entry.date, calendar.isDate(date, inSameDayAs: now) {
                group = .today
            } else if let date = entry.date, let yesterday, calendar.isDate(date, inSameDayAs: yesterday) {
                group = .yesterday
            } else {
                group = .earlier
            }
            buckets[group, default: []].append(entry)
        }
        return [PFAlertGroup.unread, .today, .yesterday, .earlier].compactMap { (group: PFAlertGroup) -> PFAlertSection? in
            guard let list = buckets[group], !list.isEmpty else { return nil }
            return PFAlertSection(group: group, entries: list)
        }
    }

    static func unreadCount(_ entries: [PFAlertEntry], seen: Set<String>) -> Int {
        entries.filter { !seen.contains($0.id) }.count
    }

    /// The seen list with `ids` added at the end (no repeats), the newest `seenCap` kept.
    static func marking(_ seen: [String], read ids: [String]) -> [String] {
        var have = Set(seen)
        var out = seen
        for id in ids {
            guard have.insert(id).inserted else { continue }
            out.append(id)
        }
        return Array(out.suffix(seenCap))
    }

    /// Every line marked, oldest first: `entries` is newest first and `marking` keeps the last `seenCap`, so the newest lines survive the cap.
    static func markingAll(_ seen: [String], entries: [PFAlertEntry]) -> [String] {
        marking(seen, read: entries.reversed().map { $0.id })
    }

    /// The seen list to start from: the stored one, or, the first time this build runs (nothing stored), every line that exists now,
    /// so the day it arrives there is no pile of unread; only lines first seen afterwards are unread.
    static func adopting(stored: [String]?, entries: [PFAlertEntry]) -> [String] {
        stored ?? markingAll([], entries: entries)
    }

    /// The announced record with the items added (each id once, with `date`), the newest `announcedCap` kept.
    static func recording(_ announced: [PFAnnouncedNeed], adding items: [PFNeedsItem], at date: Date) -> [PFAnnouncedNeed] {
        var have = Set(announced.map { $0.id })
        var out = announced
        for item in items {
            guard have.insert(item.id).inserted else { continue }
            out.append(PFAnnouncedNeed(id: item.id, kind: item.kind.rawValue, title: item.title, activityID: item.activityID, date: date))
        }
        return Array(out.suffix(announcedCap))
    }
}
