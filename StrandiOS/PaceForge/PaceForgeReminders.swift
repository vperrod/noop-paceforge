import Foundation
import UserNotifications

/// UserDefaults keys for the PaceForge reminder and lock settings. Plain constants, not main-actor
/// isolated, so a SwiftUI `@AppStorage` can name them.
enum PFPrefs {
    static let morningKey = "noop.paceforge.remind.morning"
    static let eveningKey = "noop.paceforge.remind.evening"
    static let lockKey = "noop.paceforge.faceIDLock"
    static let alertsKey = "noop.paceforge.notify.alerts"
}

/// Local reminders, planned after every PaceForge fetch (foreground or background):
///
/// - 09:00, a check-in only when today's complete brief is already in the fetched snapshot and the
///   athlete has not answered how they feel. Missing data is not scheduled as a notification because
///   a local notification cannot re-check the server when it fires.
/// - 20:00, a preview of tomorrow's session and its target.
///
/// Both are plain local notifications riding the existing background refresh; no push is involved.
@MainActor
enum PFReminders {
    private static let morningId = "paceforge.reminder.morning"
    private static let eveningId = "paceforge.reminder.evening"
    private static let morningHour = 9
    private static let eveningHour = 20

    static var morningOn: Bool { UserDefaults.standard.object(forKey: PFPrefs.morningKey) as? Bool ?? true }
    static var eveningOn: Bool { UserDefaults.standard.object(forKey: PFPrefs.eveningKey) as? Bool ?? true }

    static func update(for snapshot: PFSnapshot, now: Date = Date()) async {
        guard !PFAPI.isFixture else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        await planMorning(snapshot, now: now, center: center)
        await planEvening(snapshot, now: now, center: center)
    }

    /// Called when a toggle goes off: drops what is already queued.
    static func removePending() {
        var ids: [String] = []
        if !morningOn { ids.append(morningId) }
        if !eveningOn { ids.append(eveningId) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func nextFire(hour: Int, after now: Date) -> Date? {
        Calendar.current.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime)
    }

    private static func planMorning(_ s: PFSnapshot, now: Date, center: UNUserNotificationCenter) async {
        guard morningOn, let fire = nextFire(hour: morningHour, after: now) else {
            center.removePendingNotificationRequests(withIdentifiers: [morningId])
            return
        }
        // A pending local notification cannot check whether the server's brief became ready before
        // its fire time. Schedule only a check-in for a brief already complete in today's snapshot;
        // never queue a factual "brief missing" alert from data that can be stale by delivery.
        guard PFFormat.isoString(fire) == s.todayISO,
              let brief = s.today.brief,
              brief.date == s.todayISO,
              !brief.partial,
              feelIsUnanswered(s) else {
            center.removePendingNotificationRequests(withIdentifiers: [morningId])
            return
        }
        await schedule(id: morningId, at: fire, title: "Good morning",
                       body: "Tell me how you feel. One tap, 1 to 5, on PaceForge Today.", center: center)
    }

    /// Today's check-in is open: the server serves the feel summary and it has no answer for today yet.
    /// A server without the file never gets the question.
    private static func feelIsUnanswered(_ s: PFSnapshot) -> Bool {
        guard let feel = s.feel else { return false }
        return !(feel.answered && (feel.date ?? s.todayISO) == s.todayISO)
    }

    private static func planEvening(_ s: PFSnapshot, now: Date, center: UNUserNotificationCenter) async {
        guard eveningOn, let fire = nextFire(hour: eveningHour, after: now) else {
            center.removePendingNotificationRequests(withIdentifiers: [eveningId])
            return
        }
        let target = PFFormat.addDays(PFFormat.isoString(fire), 1)
        guard let day = s.weeks.flatMap(\.days).first(where: { $0.date == target }) else {
            // Beyond the plan the app knows about: better silent than a guess.
            center.removePendingNotificationRequests(withIdentifiers: [eveningId])
            return
        }
        // Optional sessions are still on the plan and must appear in the preview. Hiding them
        // made a day containing only optional sessions look like a rest day.
        let todo = day.workouts.filter { $0.status != "done" && $0.status != "partial" }
        let lines = s.races(on: target).map { "Race: \($0.name)" } + todo.map(describe)
        let body = lines.isEmpty ? "Tomorrow is a rest day. Recovery is training." : lines.joined(separator: "\n")
        await schedule(id: eveningId, at: fire, title: "Tomorrow on PaceForge", body: body, center: center)
    }

    private static func describe(_ w: PFWorkout) -> String {
        let bits = [w.name ?? "Workout", PFSummaryWriter.detail(w), PFSummaryWriter.primaryTarget(w)]
        let description = bits.compactMap { $0 }.joined(separator: " \u{00B7} ")
        return w.status == "optional" ? "Optional: \(description)" : description
    }

    private static func schedule(id: String, at date: Date, title: String, body: String,
                                 center: UNUserNotificationCenter) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // The brief notification's category: a tap opens PaceForge Today.
        content.categoryIdentifier = PaceForgeBackground.notificationCategory
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
