import Foundation
import UserNotifications

/// Build 529 notifications: on a background contact with the server, read `data/inbox.json` and raise one local notification for each item
/// the phone has not announced, with its kind switched on. The phone contacts the server all day because the strap keeps it awake, so
/// the notifications arrive within minutes. No push service is involved.
///
/// Called from the end of the sync (`SelfHostedPushClient.pushIfEnabled`) and, as the fallback, from the background refresh
/// (`PaceForgeBackground.deliver`). At most one check every ten minutes, whichever calls. The decisions are in `PFInboxLogic529`.
@MainActor
enum PFInboxNotifier529 {
    static let interval: TimeInterval = 600
    private static let notifiedKey = "noop.paceforge.inbox.notified"
    private static let attemptKey = "noop.paceforge.inbox.lastAttempt"
    private static var isRunning = false

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
        defaults.set(decision.notified, forKey: notifiedKey)
        let delay = decision.toNotify.compactMap { PFInboxLogic529.delay(of: $0, now: seenAt) }.min()
        store.recordCheck(at: seenAt, newDelay: delay)
        guard !decision.toNotify.isEmpty, await canNotify() else { return }
        for item in decision.toNotify { await post(item, defaults: defaults) }
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
        content.categoryIdentifier = PaceForgeBackground.notificationCategory
        content.userInfo = PFInboxPayload529.userInfo(for: item)
        // An alert the earlier path would announce under this identifier replaces it rather than doubling it.
        let identifier = id.hasPrefix("alert:") ? "paceforge.alert.\(id.dropFirst("alert:".count))" : "paceforge.inbox.\(id)"
        rememberForEarlierPath(id: id, defaults: defaults)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    // MARK: Not twice

    /// The ids the earlier alert and Needs you paths remember as announced.
    private static func legacyNotified(_ defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: PaceForgeBackground.notifiedAlertsKey) ?? [])
            .union(defaults.stringArray(forKey: PaceForgeBackground.notifiedNeedsKey) ?? [])
    }

    /// An alert or Needs you item announced here is entered in the earlier path's list, so that path does not announce it again.
    private static func rememberForEarlierPath(id: String, defaults: UserDefaults) {
        for (prefix, key) in [("alert:", PaceForgeBackground.notifiedAlertsKey), ("needs_you:", PaceForgeBackground.notifiedNeedsKey)]
        where id.hasPrefix(prefix) {
            let earlierID = String(id.dropFirst(prefix.count))
            let stored = defaults.stringArray(forKey: key)
            // The Needs you path takes the first list it finds as its baseline and announces nothing from it, so it is never started here.
            if stored == nil, key == PaceForgeBackground.notifiedNeedsKey { continue }
            let list = stored ?? []
            if !list.contains(earlierID) { defaults.set(Array((list + [earlierID]).suffix(200)), forKey: key) }
        }
    }
}
