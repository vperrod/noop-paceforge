import BackgroundTasks
import Foundation
import UserNotifications

extension Notification.Name {
    static let pfOpenToday = Notification.Name("noop.paceforge.openToday")
}

/// Opens the app on PaceForge > Today from a widget tap, a notification tap or the Control Center control.
@MainActor
enum PFDeepLink {
    /// Held until the tab shell exists, so a cold launch from a widget still lands on the right tab.
    static var pending = false

    static func open(_ segment: PFSegment) {
        UserDefaults.standard.set(segment.rawValue, forKey: "noop.paceforge.segment")
        pending = true
        NotificationCenter.default.post(name: .pfOpenToday, object: nil)
    }

    static func openToday() { open(.today) }

    /// `noop://paceforge` opens Today; `noop://paceforge/week` (or coach, insights, body) opens that screen;
    /// `noop://paceforge/standing` opens Insights with the "Where you stand" scorecard on top.
    static func open(url: URL) {
        let name = url.pathComponents.dropFirst().first ?? ""
        if name == "standing" {
            open(.insights)
            PFStandingLink.open()
            return
        }
        open(PFSegment(rawValue: name) ?? .today)
    }

    /// Picks up the request a Control Center control left in the App Group.
    static func openIfControlRequested() {
        if PFOpenRequest.consume() { openToday() }
    }
}

/// Refreshes PaceForge every few hours in the background (BGAppRefreshTask): updates the widget summary
/// and posts a local "PaceForge daily brief" notification when a new brief date appears.
/// No push notification or APNs entitlement is involved.
@MainActor
enum PaceForgeBackground {
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".paceforge"
    static let notificationCategory = "paceforge.brief"
    private static let lastBriefKey = "noop.paceforge.lastNotifiedBrief"
    private static let askedKey = "noop.paceforge.notificationsAsked"
    private static let lastBriefUpdateKey = "noop.paceforge.lastNotifiedBriefUpdate"
    private static let notifiedAlertsKey = "noop.paceforge.notifiedAlerts"

    /// Register before launch finishes; the identifier is listed in BGTaskSchedulerPermittedIdentifiers.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let worker = Task { @MainActor in
                schedule()
                let ok = await refresh()
                guard !Task.isCancelled else { return }
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { worker.cancel() }
        }
    }

    /// One pending request at a time; iOS picks the actual wake time, no earlier than three hours out.
    static func schedule() {
        guard PFAPI.isConfigured, !PFAPI.isFixture else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Fetches PaceForge, rewrites the widget summary and notifies about a new daily brief.
    static func refresh() async -> Bool {
        guard PFAPI.isConfigured, !PFAPI.isFixture else { return false }
        guard let raw = try? await PFAPI.fetchBundle(),
              let snapshot = PFBuilder.snapshot(from: raw, today: PFFormat.isoString(Date())) else { return false }
        PFSummaryWriter.publish(snapshot)
        if let brief = snapshot.today.brief {
            await notifyIfNew(brief, today: snapshot.todayISO)
            await notifyIfUpdated(brief, today: snapshot.todayISO)
        }
        await notifyNewAlerts(snapshot.alerts)
        return true
    }

    /// Asks once, the first time the PaceForge tab is open with sync set up.
    static func requestNotificationPermissionOnce() {
        let defaults = UserDefaults.standard
        guard PFAPI.isConfigured, !PFAPI.isFixture, !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func canNotify() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Once each time the server rewrites today's brief after new data arrived (its `updated_at` changes).
    /// The first value seen is only recorded, so a brief that was already updated does not announce itself.
    private static func notifyIfUpdated(_ brief: PFDailyBrief, today: String) async {
        guard let updated = brief.updatedAt, brief.date == today else { return }
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: lastBriefUpdateKey)
        guard last != updated else { return }
        defaults.set(updated, forKey: lastBriefUpdateKey)
        guard last != nil, await canNotify() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Briefing updated"
        content.body = brief.headline
        content.sound = .default
        content.categoryIdentifier = notificationCategory
        let request = UNNotificationRequest(identifier: "paceforge.brief.update.\(updated)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// One local notification for each open alert not seen before. Alerts older than two days are only
    /// recorded, so turning this on does not replay the backlog. The toggle is in More > PaceForge sync.
    private static func notifyNewAlerts(_ alerts: [PFAlert]) async {
        let defaults = UserDefaults.standard
        let seen = Set(defaults.stringArray(forKey: notifiedAlertsKey) ?? [])
        let fresh = alerts.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        defaults.set(Array((Array(seen) + fresh.map(\.id)).suffix(200)), forKey: notifiedAlertsKey)
        guard defaults.object(forKey: PFPrefs.alertsKey) as? Bool ?? true, await canNotify() else { return }
        for alert in fresh where isRecent(alert.createdAt) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            if let body = alert.body { content.body = String(body.prefix(180)) }
            content.sound = .default
            content.categoryIdentifier = notificationCategory
            let request = UNNotificationRequest(identifier: "paceforge.alert.\(alert.id)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private static func isRecent(_ createdAt: String?) -> Bool {
        guard let createdAt else { return true }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let when = withFraction.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
                ?? local.date(from: String(createdAt.prefix(19))) else { return true }
        return Date().timeIntervalSince(when) < 2 * 86_400
    }

    private static func notifyIfNew(_ brief: PFDailyBrief, today: String) async {
        guard let date = brief.date else { return }
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: lastBriefKey)
        guard last != date else { return }
        defaults.set(date, forKey: lastBriefKey)
        // The first ever refresh only records the brief; it notifies only if the brief is today's.
        if last == nil && date != today { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "PaceForge daily brief"
        content.body = brief.headline
        content.sound = .default
        content.categoryIdentifier = notificationCategory
        let request = UNNotificationRequest(identifier: "paceforge.brief.\(date)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
