import Foundation

// Build 530, APP-4: when the phone raises a local notification for an inbox item. One pure function decides, with no clock, store or
// notification centre of its own; Foundation only, so the macOS unit-test bundle compiles it (PFAlertDelivery530Tests).

enum PFAlertVerdict530: Equatable {
    /// Raise it now.
    case deliver
    /// Not now: ask again at the next contact (the id is not remembered as announced).
    case hold
    /// Never raise it: it is still listed in the inbox.
    case drop
}

enum PFAlertDelivery530 {
    /// At most this many alerts a day outside `capExemptKinds`. The server applies the same cap; the phone keeps it as well.
    static let dailyCap = 6
    /// The journal questions and the problems only the athlete can fix do not count toward the cap.
    static let capExemptKinds: Set<String> = ["journal", "problem"]
    /// What the phone assumes while the server sends no `quiet` block (fewer than seven recorded nights): the clock times of the proposal.
    static let fallbackBedtime = 23 * 60
    static let fallbackWake = 7 * 60
    static let fallbackWindDown = 21 * 60 + 30

    private static let morningEnd = 12 * 60
    private static let eveningStart = 17 * 60

    /// Whether to raise `item` now.
    ///
    /// `isAsleep` is the phone's own sleep state when it has one (true: asleep, false: awake). The app has no live sleep state, so the caller
    /// passes nil and the `quiet` block's clock times decide: quiet from the usual bedtime until the usual wake time.
    /// `raisedIDs` are the ids already raised on this phone; `raisedToday` counts today's raised alerts outside the cap-exempt kinds.
    static func verdict(item: PFInboxDoc.Item, now: Date, quiet: PFInboxDoc.Quiet?, isRecordingWorkout: Bool, isAsleep: Bool?,
                        enabledKinds: Set<String>, raisedIDs: Set<String>, raisedToday: Int, calendar: Calendar = .current) -> PFAlertVerdict530 {
        guard let id = item.id, !id.isEmpty, !raisedIDs.contains(id) else { return .drop }
        guard item.notify == true else { return .drop }
        guard let kind = item.kind, enabledKinds.contains(kind) else { return .drop }
        let written = PFAlertDates.parse(item.ts)
        if let written, now.timeIntervalSince(written) >= PFInboxLogic529.maxNotificationAge(kind: kind) { return .drop }
        if !capExemptKinds.contains(kind), raisedToday >= dailyCap { return .drop }

        let times = Times(quiet)
        let notBefore = PFAlertDates.parse(item.notBefore)
        // The window the item belongs to is the first one that ends after the item was written (and after its not_before): an item written
        // while the athlete slept waits for the morning window; one whose window has passed is never sent late.
        let reference = [written, notBefore].compactMap { $0 }.max() ?? now
        // Readiness, report and journal alerts are delivered at the next awake contact, even if their original
        // morning/evening window passed while iOS had not refreshed the app.
        var window = interval(of: item.window, after: reference, times: times, calendar: calendar)
        let reportKind = PFInboxLogic529.reportKinds.contains(kind) || kind == "journal"
        if let currentWindow = window, now >= currentWindow.end {
            if reportKind { window = nil } else { return .drop }
        }

        if isRecordingWorkout { return .hold }
        if isAsleep ?? isQuietByClock(now, times: times, calendar: calendar) { return .hold }
        if let notBefore, now < notBefore { return .hold }
        if let window, now < window.start { return .hold }
        return .deliver
    }

    struct Plan: Equatable {
        var deliver: [PFInboxDoc.Item]
        /// The ids to try again at the next contact.
        var held: Set<String>
    }

    /// `verdict` over a list, in the order the document lists it; each delivered item uses up one of today's alerts.
    static func plan(items: [PFInboxDoc.Item], now: Date, quiet: PFInboxDoc.Quiet?, isRecordingWorkout: Bool, isAsleep: Bool?,
                     enabledKinds: Set<String>, raisedIDs: Set<String>, raisedToday: Int, calendar: Calendar = .current) -> Plan {
        var plan = Plan(deliver: [], held: [])
        var count = raisedToday
        var raised = raisedIDs
        for item in items {
            let outcome = verdict(item: item, now: now, quiet: quiet, isRecordingWorkout: isRecordingWorkout, isAsleep: isAsleep,
                                  enabledKinds: enabledKinds, raisedIDs: raised, raisedToday: count, calendar: calendar)
            switch outcome {
            case .deliver:
                plan.deliver.append(item)
                if let id = item.id { raised.insert(id) }
                if let kind = item.kind, !capExemptKinds.contains(kind) { count += 1 }
            case .hold:
                if let id = item.id { plan.held.insert(id) }
            case .drop:
                break
            }
        }
        return plan
    }

    /// A recorded workout is under way when one started less than `staleAfter` ago (an older one was never ended).
    static func isRecording(startedAt starts: [Date], now: Date, staleAfter: TimeInterval = 12 * 3_600) -> Bool {
        starts.contains { now.timeIntervalSince($0) < staleAfter }
    }

    // MARK: Quiet hours

    /// The clock times of the `quiet` block as minutes after midnight, the proposal's own times where the server sent none.
    struct Times: Equatable {
        var bedtime: Int
        var wake: Int
        var windDown: Int

        init(_ quiet: PFInboxDoc.Quiet?) {
            let bed = PFAlertDelivery530.minutes(quiet?.usualBedtime) ?? PFAlertDelivery530.fallbackBedtime
            bedtime = bed
            wake = PFAlertDelivery530.minutes(quiet?.usualWake) ?? PFAlertDelivery530.fallbackWake
            windDown = PFAlertDelivery530.minutes(quiet?.windDown)
                ?? (quiet?.usualBedtime == nil ? PFAlertDelivery530.fallbackWindDown : max(0, bed - 90))
        }
    }

    /// "23:15" as 1395; nil when it is not a clock time.
    static func minutes(_ clock: String?) -> Int? {
        guard let clock else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// True from the usual bedtime until the usual wake time (a night that crosses midnight included).
    static func isQuietByClock(_ now: Date, times: Times, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let m = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return times.bedtime <= times.wake ? (m >= times.bedtime && m < times.wake) : (m >= times.bedtime || m < times.wake)
    }

    // MARK: Windows

    /// morning: from the usual wake time to noon. day: noon to the wind-down. evening: from 17:00 to the usual bedtime. any, or none: no limit.
    /// The first occurrence that ends after `reference` (today's, tomorrow's or the day after).
    static func interval(of window: String?, after reference: Date, times: Times, calendar: Calendar) -> DateInterval? {
        guard let window, ["morning", "day", "evening"].contains(window) else { return nil }
        let first = calendar.startOfDay(for: reference)
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let (from, to) = bounds(of: window, times: times)
            guard let start = calendar.date(byAdding: .minute, value: from, to: day),
                  let end = calendar.date(byAdding: .minute, value: to, to: day) else { continue }
            if end > reference { return DateInterval(start: start, end: end) }
        }
        return nil
    }

    /// Minutes after midnight of the day the window opens on; an end past 1440 falls after midnight.
    private static func bounds(of window: String, times: Times) -> (Int, Int) {
        switch window {
        case "morning":
            let start = min(times.wake, morningEnd - 60)
            return (start, morningEnd)
        case "day":
            return (morningEnd, max(times.windDown, morningEnd + 60))
        default:
            let end = times.bedtime < eveningStart ? times.bedtime + 1440 : times.bedtime
            return (eveningStart, end)
        }
    }
}

/// The notification categories of the inbox alerts.
enum PFAlertCategory530 {
    /// Every inbox alert but the afternoon question: the category carries the dismiss action, so a swipe is reported to the app.
    static let inbox = "paceforge.inbox"
    /// The afternoon journal question, with Yes / No actions on the lock screen. The journal stream registers it; the alert only names it.
    static let journalDay = "paceforge.journal.day"

    static func identifier(for item: PFInboxDoc.Item) -> String {
        item.kind == "journal" && item.window == "day" ? journalDay : inbox
    }
}
