import Foundation
import UIKit
import UserNotifications

/// Build 530, APP-4: what the phone keeps and tells the server about the alerts it raised. The decisions are pure (`PFAlertDelivery530`,
/// `PFAlertAck530`); this file holds them in UserDefaults and sends them.
///
/// `POST /app/inbox-ack` goes through the same client and bearer as `/app/answer`. A failed or refused send (no signal, a 5xx, a 429 over the
/// hourly cap) keeps the batch, and the next contact sends it again; nothing is shown to the athlete.
@MainActor
enum PFInboxAck530 {
    private static let queueKey = "noop.paceforge.inbox.ackQueue"
    private static let ledgerKey = "noop.paceforge.inbox.raisedLedger"
    private static var isFlushing = false

    // MARK: Raised, dismissed, opened

    /// An alert raised now: it counts toward today's cap, and the server is told.
    static func raised(_ item: PFInboxDoc.Item, at date: Date = Date()) {
        guard let id = item.id, let kind = item.kind else { return }
        var ledger = loadLedger()
        ledger.add(id: id, kind: kind, at: date)
        save(ledger, key: ledgerKey)
        var queue = loadQueue()
        queue.addRaised(id)
        save(queue, key: queueKey)
    }

    /// The athlete swiped an alert away (the notification category has the dismiss action). The dismiss-twice rule counts it.
    static func dismissed(userInfo: [AnyHashable: Any]) {
        guard let who = identity(of: userInfo) else { return }
        PFInboxStore529.shared.noteDismissed(id: who.id, kind: who.kind)
        var queue = loadQueue()
        queue.addDismissed(who.id)
        save(queue, key: queueKey)
        startFlush()
    }

    /// The athlete tapped an alert: it opens what the line is about, and the kind's dismiss count starts again.
    static func opened(userInfo: [AnyHashable: Any]) {
        guard let who = identity(of: userInfo) else { return }
        PFInboxStore529.shared.noteOpened(kind: who.kind)
        var queue = loadQueue()
        queue.addOpened(who.id)
        save(queue, key: queueKey)
        startFlush()
    }

    /// The athlete switched a kind back on: the server stops muting it.
    static func unmute(_ kind: PFInboxKind529) {
        var queue = loadQueue()
        queue.addUnmute(kind.rawValue)
        save(queue, key: queueKey)
        startFlush()
    }

    private static func identity(of userInfo: [AnyHashable: Any]) -> (id: String, kind: String)? {
        guard userInfo[PFInboxPayload529.kindKey] as? String == PFInboxPayload529.inboxKind,
              let id = userInfo["pf.id"] as? String, !id.isEmpty,
              let kind = userInfo[PFInboxPayload529.itemKindKey] as? String, !kind.isEmpty else { return nil }
        return (id: id, kind: kind)
    }

    // MARK: Sending

    /// A send the caller does not wait for (a tap or a dismissal, where the app may be woken for a moment only).
    static func startFlush() {
        guard PFAPI.isConfigured, !PFAPI.isFixture, !isFlushing else { return }
        let assertion = BackgroundAssertion529(name: "paceforge.inbox-ack")
        Task {
            await flush()
            assertion.end()
        }
    }

    /// Sends the waiting batches in order, until one is not accepted.
    static func flush() async {
        guard PFAPI.isConfigured, !PFAPI.isFixture, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        while let batch = loadQueue().next {
            guard let reply = try? await SelfHostedPushClient.paceForgePostReturningStatus("api/app/inbox-ack", body: batch.body),
                  PFAckQueue530.isSettled(status: reply.status) else { return }
            if (200..<300).contains(reply.status), let muted = mutedKinds(in: reply.data) {
                PFInboxStore529.shared.mergeServerMuted(muted)
            }
            var queue = loadQueue()
            queue.settle(batch)
            save(queue, key: queueKey)
        }
    }

    /// `{"ok": true, "muted": [kinds]}`.
    private static func mutedKinds(in data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["muted"] as? [String]
    }

    // MARK: Raised today

    static func raisedLedger() -> PFRaisedLedger530 { loadLedger() }

    // MARK: Storage

    private static func loadQueue() -> PFAckQueue530 {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let queue = try? JSONDecoder().decode(PFAckQueue530.self, from: data) else { return PFAckQueue530() }
        return queue
    }

    private static func loadLedger() -> PFRaisedLedger530 {
        guard let data = UserDefaults.standard.data(forKey: ledgerKey),
              let ledger = try? JSONDecoder().decode(PFRaisedLedger530.self, from: data) else { return PFRaisedLedger530() }
        return ledger
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// What the phone knows about the moment, for the delivery rules.
enum PFAlertMoment530 {
    /// A workout recorded in the app: a manual or GPS session, or a lift session that is not finished. Both are saved on the phone while
    /// they run (so this works from a background contact, with no live model) and cleared when they end. A snapshot older than half a day
    /// is a session iOS killed and nobody ended: it does not hold alerts for ever.
    static func isRecordingWorkout(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        var starts: [Date] = []
        if let session = ActiveWorkoutPersistence.load(from: defaults) {
            starts.append(Date(timeIntervalSince1970: TimeInterval(session.startSec)))
        }
        if let lift = LiftSessionPersistence.load(from: defaults), lift.stage.kind != "finished" {
            starts.append(Date(timeIntervalSince1970: TimeInterval(lift.startSec)))
        }
        return PFAlertDelivery530.isRecording(startedAt: starts, now: now)
    }
}

/// Registers the categories of build 530 (inbox alerts, and the afternoon journal question's Yes / No) in one read-merge-write, so neither
/// overwrites the other: `setNotificationCategories` replaces the whole set.
enum PFAlertCategoryRegistration530 {
    static func register() async {
        let center = UNUserNotificationCenter.current()
        let ours: Set<String> = [PFAlertCategory530.inbox, PFAlertCategory530.journalDay]
        var categories = await center.notificationCategories()
        categories = categories.filter { !ours.contains($0.identifier) }
        categories.insert(UNNotificationCategory(identifier: PFAlertCategory530.inbox, actions: [], intentIdentifiers: [],
                                                 options: [.customDismissAction]))
        categories.insert(PFJournalAction530.category)
        center.setNotificationCategories(categories)
    }
}
