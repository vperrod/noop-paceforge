import Foundation
import UIKit
import UserNotifications

/// Build 529 notifications: on a background contact with the server, read `data/inbox.json` and raise one local notification for each item
/// the phone has not announced, with its kind switched on. The phone contacts the server all day because the strap keeps it awake, so
/// the notifications arrive within minutes. No push service is involved.
///
/// Called from the end of the sync (`SelfHostedPushClient.pushIfEnabled`) and, as the fallback, from the background refresh
/// (`PaceForgeBackground.deliver`). At most one check every ten minutes, whichever calls. The decisions are in `PFInboxLogic529`; when an
/// item is raised (window, quiet hours, a workout recording, the daily cap) is `PFAlertDelivery530` (build 530), and what the phone tells
/// the server about it is `PFInboxAck530`.
@MainActor
enum PFInboxNotifier529 {
    static let interval: TimeInterval = 600
    private static let notifiedKey = "noop.paceforge.inbox.notified"
    private static let attemptKey = "noop.paceforge.inbox.lastAttempt"
    private static var isRunning = false

    /// Starts a check without making the caller wait (the end of a sync): the GET is held by its own short background-task assertion, so
    /// iOS does not suspend the app in the middle of it. The assertion starts here, synchronously, not when the task gets its turn.
    static func startCheck() {
        guard PFAPI.isConfigured, !PFAPI.isFixture, !isRunning else { return }
        let assertion = BackgroundAssertion529(name: "paceforge.inbox-check")
        Task {
            await checkIfDue()
            assertion.end()
        }
    }

    static func checkIfDue(now: Date = Date()) async {
        guard PFAPI.isConfigured, !PFAPI.isFixture, !isRunning else { return }
        let defaults = UserDefaults.standard
        guard PFInboxLogic529.isDue(last: defaults.object(forKey: attemptKey) as? Date, now: now, interval: interval) else { return }
        isRunning = true
        defer { isRunning = false }
        // The attempt counts even when the server does not answer, so a server that is down is not asked every few seconds.
        defaults.set(now, forKey: attemptKey)
        guard let data = try? await PFAPI.fetch(PFDocPath529.inbox),
              let doc = try? PFPlan529Decoder.make().decode(PFInboxDoc.self, from: data) else { return }
        let store = PFInboxStore529.shared
        store.apply(doc)
        let seenAt = Date()
        let decision = PFInboxLogic529.decide(items: doc.items ?? [], notified: defaults.stringArray(forKey: notifiedKey),
                                              enabledKinds: store.enabledKinds, legacyNotified: legacyNotified(defaults), now: seenAt)
        // Build 530: the delivery rules (`PFAlertDelivery530`). A held item is not remembered as announced, so the next contact asks again.
        let ledger = PFInboxAck530.raisedLedger()
        let plan = PFAlertDelivery530.plan(items: decision.toNotify, now: seenAt, quiet: doc.quiet,
                                           isRecordingWorkout: PFAlertMoment530.isRecordingWorkout(now: seenAt), isAsleep: nil,
                                           enabledKinds: store.enabledKinds, raisedIDs: ledger.ids,
                                           raisedToday: ledger.countToday(now: seenAt, calendar: .current))
        defaults.set(decision.notified.filter { !plan.held.contains($0) }, forKey: notifiedKey)
        let delay = plan.deliver.compactMap { PFInboxLogic529.delay(of: $0, now: seenAt) }.min()
        store.recordCheck(at: seenAt, newDelay: delay)
        if !plan.deliver.isEmpty, await canNotify() {
            await PFAlertCategoryRegistration530.register()
            for item in plan.deliver {
                await post(item, defaults: defaults)
                PFInboxAck530.raised(item, at: seenAt)
            }
        }
        // Acknowledgements the last contact could not send go with this one.
        await PFInboxAck530.flush()
    }

    private static func canNotify() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    private static func post(_ item: PFInboxDoc.Item, defaults: UserDefaults) async {
        guard let id = item.id else { return }
        let content = UNMutableNotificationContent()
        // Hide numbers (Settings) applies to what a lock screen shows as well.
        let scores = defaults.bool(forKey: HideScoresPrefs.scoresKey)
        let body = defaults.bool(forKey: HideScoresPrefs.bodyKey)
        content.title = PFRedact.text(item.title ?? "", scores: scores, body: body)
        content.body = String(PFRedact.text(item.body ?? "", scores: scores, body: body).prefix(180))
        content.sound = .default
        content.categoryIdentifier = PFAlertCategory530.identifier(for: item)
        content.userInfo = PFInboxPayload529.userInfo(for: item)
        // An alert the earlier path would announce under this identifier replaces it rather than doubling it.
        let identifier = id.hasPrefix("alert:") ? "paceforge.alert.\(id.dropFirst("alert:".count))" : "paceforge.inbox.\(id)"
        rememberForEarlierPath(id: id, defaults: defaults)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    // MARK: Not twice

    /// The ids the earlier alert path remembers as announced.
    private static func legacyNotified(_ defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: PaceForgeBackground.notifiedAlertsKey) ?? [])
    }

    /// An alert announced here is entered in the earlier path's list, so that path does not announce it again.
    private static func rememberForEarlierPath(id: String, defaults: UserDefaults) {
        guard id.hasPrefix("alert:") else { return }
        let earlierID = String(id.dropFirst("alert:".count))
        let list = defaults.stringArray(forKey: PaceForgeBackground.notifiedAlertsKey) ?? []
        if !list.contains(earlierID) { defaults.set(Array((list + [earlierID]).suffix(200)), forKey: PaceForgeBackground.notifiedAlertsKey) }
    }
}


/// One `beginBackgroundTask` / `endBackgroundTask` pair: the app is kept running for the short GET, and the task ends when the check does
/// or when iOS says the time is up.
@MainActor
final class BackgroundAssertion529 {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
