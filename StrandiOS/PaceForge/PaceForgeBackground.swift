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

    /// `noop://paceforge` opens Today; `noop://paceforge/week` (or coach, insights, body) opens that screen.
    static func open(url: URL) {
        let name = url.pathComponents.dropFirst().first ?? ""
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
        if let brief = snapshot.today.brief { await notifyIfNew(brief, today: snapshot.todayISO) }
        return true
    }

    /// Asks once, the first time the PaceForge tab is open with sync set up.
    static func requestNotificationPermissionOnce() {
        let defaults = UserDefaults.standard
        guard PFAPI.isConfigured, !PFAPI.isFixture, !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
