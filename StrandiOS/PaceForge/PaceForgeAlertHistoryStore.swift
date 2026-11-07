import SwiftUI

// Where the Alerts history keeps its two small records on the phone: which lines have been seen, and the Needs you items the phone
// announced. The merging, grouping and counting are Foundation-only and tested (PaceForgeAlertHistory.swift).

@MainActor
final class PFAlertHistoryStore: ObservableObject {
    static let shared = PFAlertHistoryStore()

    private static let seenKey = "noop.paceforge.alertsSeen"
    private static let announcedKey = "noop.paceforge.announcedNeeds"

    /// The ids of the lines that count as read. nil until this build has had a snapshot to start from (`adopt`).
    @Published private(set) var seen: [String]?
    /// The Needs you items this phone announced, oldest first.
    @Published private(set) var announced: [PFAnnouncedNeed]

    private init() {
        let defaults = UserDefaults.standard
        seen = defaults.stringArray(forKey: Self.seenKey)
        announced = PFAnnouncedNeed.decode(defaults.data(forKey: Self.announcedKey))
    }

    /// Every line, newest first. With no snapshot yet only the announced items show, without a status.
    func entries(for snapshot: PFSnapshot?) -> [PFAlertEntry] {
        PFAlertHistory.entries(alerts: snapshot?.alertHistory ?? [], announced: announced,
                               openNeedsIDs: snapshot.map { Set($0.needsYou.map { $0.id }) })
    }

    /// 0 until the first snapshot has been adopted.
    func unreadCount(for snapshot: PFSnapshot?) -> Int {
        guard let seen else { return 0 }
        return PFAlertHistory.unreadCount(entries(for: snapshot), seen: Set(seen))
    }

    /// The first time this build has a snapshot that was built with the alerts document, everything in it counts as read; later calls do
    /// nothing. A snapshot built without that document (the saved copy on the phone may lack it) is not a baseline: the alerts that
    /// arrive afterwards would count as already seen.
    func adopt(_ snapshot: PFSnapshot?) {
        guard seen == nil, let snapshot, snapshot.alertsLoaded else { return }
        setSeen(PFAlertHistory.adopting(stored: nil, entries: entries(for: snapshot)))
    }

    func markRead(_ ids: [String]) {
        guard let seen else { return }
        setSeen(PFAlertHistory.marking(seen, read: ids))
    }

    func markAllRead(_ entries: [PFAlertEntry]) {
        guard let seen else { return }
        setSeen(PFAlertHistory.markingAll(seen, entries: entries))
    }

    /// Called as the phone announces Needs you items, so the history keeps them after they leave the card.
    func recordAnnounced(_ items: [PFNeedsItem]) {
        announced = PFAlertHistory.recording(announced, adding: items, at: Date())
        if let data = PFAnnouncedNeed.encode(announced) { UserDefaults.standard.set(data, forKey: Self.announcedKey) }
    }

    private func setSeen(_ list: [String]) {
        seen = list
        UserDefaults.standard.set(list, forKey: Self.seenKey)
    }
}
