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

/// Two local reminders, planned after every PaceForge fetch (foreground or the background refresh):
///
/// - 09:00, only when it would still be true by then: today's brief is not in yet, or nothing has
///   refreshed since yesterday. A refresh that finds today's brief before 09:00 removes it again.
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
        // The slot is today and today's brief is already here and complete: nothing to say.
        if PFFormat.isoString(fire) == s.todayISO, let brief = s.today.brief,
           brief.date == s.todayISO, !brief.partial {
            center.removePendingNotificationRequests(withIdentifiers: [morningId])
            return
        }
        await schedule(id: morningId, at: fire, title: "PaceForge needs a look",
                       body: "Today's brief is not in yet or still waiting on data, or PaceForge has not refreshed. Open NOOP to update.",
                       center: center)
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
        let todo = day.workouts.filter { $0.status != "optional" && $0.status != "done" && $0.status != "partial" }
        let lines = todo.map(describe)
        let body = lines.isEmpty ? "Tomorrow is a rest day. Recovery is training." : lines.joined(separator: "\n")
        await schedule(id: eveningId, at: fire, title: "Tomorrow on PaceForge", body: body, center: center)
    }

    private static func describe(_ w: PFWorkout) -> String {
        let bits = [w.name ?? "Workout", PFSummaryWriter.detail(w), PFSummaryWriter.primaryTarget(w)]
        return bits.compactMap { $0 }.joined(separator: " \u{00B7} ")
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
