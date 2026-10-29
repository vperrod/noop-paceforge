import BackgroundTasks
import Foundation
import UserNotifications

extension Notification.Name {
    static let pfOpenToday = Notification.Name("noop.paceforge.openToday")
    /// A tapped PaceForge notification: scroll NOOP Today to the Needs you card, or open one activity's results.
    static let pfShowNeedsYou = Notification.Name("noop.paceforge.showNeedsYou")
    static let pfShowAlertActivity = Notification.Name("noop.paceforge.showAlertActivity")
}

/// Opens the app on its requested PaceForge section from a widget, notification or Control Center tap.
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

    /// `noop://paceforge` opens Today; `noop://paceforge/coach` opens the shared Coach; week, insights and body open their sections;
    /// `noop://paceforge/standing` opens Insights with the "Where you stand" scorecard on top.
    /// `noop://paceforge/insights/power-curve` (or race-countdown, weight-goal, efficiency, sleep) opens Insights with that
    /// item's detail on top; `next-best-action` opens Today with its detail. The short form `noop://paceforge/sleep` works too.
    static func open(url: URL) {
        let name = url.pathComponents.dropFirst().first ?? ""
        if name == "standing" {
            open(.insights)
            PFStandingLink.open()
            return
        }
        if let id = PFInsightID.linkedID(pathComponents: url.pathComponents) {
            open(id == PFInsightID.nextBestAction ? .today : .insights)
            PFInsightLink.open(id)
            return
        }
        open(PFSegment(rawValue: name) ?? .today)
    }

    /// Picks up the request a Control Center control left in the App Group.
    static func openIfControlRequested() {
        if PFOpenRequest.consume() { openToday() }
    }
}

/// Opens NOOP Today on what a tapped PaceForge alert or Needs you notification is about.
@MainActor
enum PFAlertLink {
    /// The activity of a tap whose results have not opened yet, with the time of the tap: a tap nothing picked up must not
    /// open a sheet minutes later.
    private static var pendingActivity: (id: String, at: Date)?

    static func open(userInfo: [AnyHashable: Any]) {
        guard let route = PFAlertRoute(userInfo: userInfo) else { return }
        PFDeepLink.openToday()
        switch route {
        case .needsYou:
            NotificationCenter.default.post(name: .pfShowNeedsYou, object: nil)
        case .activity(let id):
            pendingActivity = (id: id, at: Date())
            NotificationCenter.default.post(name: .pfShowAlertActivity, object: nil)
        }
    }

    /// The activity of a tap made in the last minute, once.
    static func consumeActivity() -> String? {
        defer { pendingActivity = nil }
        guard let pending = pendingActivity, Date().timeIntervalSince(pending.at) < 60 else { return nil }
        return pending.id
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
    private static let notifiedNeedsKey = "noop.paceforge.notifiedNeedsYou"

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
        // Beta only (see PaceForgeBeta.swift): the coordinator also republishes the widget summary when its inputs changed.
        if PFBeta.isOn {
            do {
                if let snapshot = try await PFRefreshCoordinator.shared.refresh(.everything).snapshot {
                    return await deliver(snapshot)
                }
                PFBeta.fallback("no-snapshot")
            } catch {
                PFBeta.fallback(PFBeta.reason(error))
            }
        }
        guard let raw = try? await PFAPI.fetchBundle(),
              let snapshot = PFBuilder.snapshot(from: raw, today: PFFormat.isoString(Date())) else { return false }
        PFSummaryWriter.publish(snapshot)
        return await deliver(snapshot)
    }

    private static func deliver(_ snapshot: PFSnapshot) async -> Bool {
        // One notification owner for the shared Coach. When the scheduled brief is enabled it
        // handles delivery and status; this background refresh must not send a second, differently
        // routed notification for the same brief. Keep the existing new/updated notices when the
        // scheduled briefing is off.
        if CoachBriefScheduler.coachMasterEnabled,
           !CoachBriefScheduler.isEnabled,
           let brief = snapshot.today.brief {
            await notifyIfNew(brief, today: snapshot.todayISO)
            await notifyIfUpdated(brief, today: snapshot.todayISO)
        }
        await notifyNewAlerts(snapshot.alerts)
        await notifyNewNeedsYou(snapshot.needsYou)
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
            content.userInfo = PFAlertRoute.userInfo(kind: PFAlertRoute.alertKind, id: alert.id, activityID: alert.activityID)
            let request = UNNotificationRequest(identifier: "paceforge.alert.\(alert.id)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// One local notification for each open Needs you item not announced before (see `PFNeedsNotify`). The server's list holds
    /// open items only, so an answered one is never announced. The first run only records what is open, so installing this build
    /// does not announce what Telegram has already said. The toggle is the alerts one in More > PaceForge sync.
    private static func notifyNewNeedsYou(_ items: [PFNeedsItem]) async {
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: notifiedNeedsKey)
        let fresh = PFNeedsNotify.fresh(items, seen: Set(stored ?? []))
        guard !fresh.isEmpty else {
            if stored == nil { defaults.set([String](), forKey: notifiedNeedsKey) }
            return
        }
        defaults.set(PFNeedsNotify.remembering(stored ?? [], adding: fresh), forKey: notifiedNeedsKey)
        guard stored != nil, defaults.object(forKey: PFPrefs.alertsKey) as? Bool ?? true, await canNotify() else { return }
        for item in fresh {
            let content = UNMutableNotificationContent()
            content.title = item.title
            if let meaning = item.meaning { content.body = String(meaning.prefix(180)) }
            content.sound = .default
            content.categoryIdentifier = notificationCategory
            content.userInfo = PFAlertRoute.userInfo(kind: PFAlertRoute.needsYouKind, id: item.id, activityID: item.activityID)
            let request = UNNotificationRequest(identifier: "paceforge.needsyou.\(item.id)", content: content, trigger: nil)
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
