import Combine
import SwiftUI
import UserNotifications

/// What the phone keeps for the inbox: the last `data/inbox.json` it read, which lines are read, which kinds the athlete switched off, and
/// when the server was last asked (with how late the newest item was). The decisions are in `PFInboxLogic529`. The unread marks join the
/// earlier alert history's (`PFAlertHistoryStore`): a line either list has seen is read.
@MainActor
final class PFInboxStore529: ObservableObject {
    static let shared = PFInboxStore529()

    enum Load: Equatable {
        case loading
        case loaded
        case failed
    }

    private static let seenKey = "noop.paceforge.inbox.seen"
    private static let kindsOffKey = "noop.paceforge.inbox.kindsOff"
    private static let lastCheckKey = "noop.paceforge.inbox.lastCheck"
    private static let lastDelayKey = "noop.paceforge.inbox.lastNewDelay"
    private static let muteKey = "noop.paceforge.inbox.mute"
    private static let muteRevisionKey = "noop.paceforge.inbox.muteRevision"

    @Published private(set) var items: [PFInboxDoc.Item] = []
    @Published private(set) var load: Load = .loading
    /// The server's copy could not be read; what shows is the copy saved on the phone.
    @Published private(set) var isStale = false
    /// The ids that count as read. nil until a first document has been read and taken as the baseline.
    @Published private(set) var seen: [String]?
    @Published private(set) var kindsOff: Set<String>
    /// The kinds the dismiss-twice rule has silenced (build 530), and the dismissals it counts. The athlete's switch turns a kind back on.
    @Published private(set) var mute: PFMuteState530
    @Published private(set) var lastCheck: Date?
    /// How late the newest item the phone raised a notification for was when the phone first saw it (seconds).
    @Published private(set) var lastNewDelay: TimeInterval?
    /// What the bell and the tab bar read: worked out when something that feeds them changes, not on every redraw of a screen that
    /// watches a store that ticks often.
    @Published private(set) var unreadCount = 0
    @Published private(set) var hasUnreadPlan = false
    @Published private(set) var hasUnreadCoach = false

    private let defaults = UserDefaults.standard
    private var inFlight: Task<Void, Never>?
    private var lastFetch: Date?
    private var feeds: Set<AnyCancellable> = []

    private init() {
        seen = defaults.stringArray(forKey: Self.seenKey)
        kindsOff = Set(defaults.stringArray(forKey: Self.kindsOffKey) ?? [])
        mute = defaults.data(forKey: Self.muteKey).flatMap { try? JSONDecoder().decode(PFMuteState530.self, from: $0) } ?? PFMuteState530()
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        lastNewDelay = defaults.object(forKey: Self.lastDelayKey) as? Double
        #if DEBUG
        // UI tests: `-Plan529InboxUnread` starts with nothing read, where a phone would take the first document as its baseline.
        if ProcessInfo.processInfo.arguments.contains("-Plan529InboxUnread") { seen = [] }
        #endif
        // The saved copy, so the list is there before the first answer and with no signal.
        if PFAPI.usesPhoneState, let data = PFStore.read(path: PFDocPath529.inbox),
           let doc = try? PFPlan529Decoder.make().decode(PFInboxDoc.self, from: data) {
            items = doc.items ?? []
            load = .loaded
        }
        recount()
        // The earlier alert history and the PaceForge snapshot (where its entries come from) feed the unread count too; their changes are
        // gathered for a quarter of a second so a burst of them is one recount.
        Publishers.Merge(PFAlertHistoryStore.shared.objectWillChange.map { _ in () }, PFUnified.model.objectWillChange.map { _ in () })
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in self?.recount() }
            .store(in: &feeds)
    }

    /// Works the unread figures out again; publishes only what changed.
    func recount() {
        let unread = unreadRows()
        let count = unread.count
        let plan = PFInboxLogic529.hasUnread(unread, kinds: PFInboxLogic529.planDotKinds)
        let coach = PFInboxLogic529.hasUnread(unread, kinds: PFInboxLogic529.coachDotKinds)
        if unreadCount != count { unreadCount = count }
        if hasUnreadPlan != plan { hasUnreadPlan = plan }
        if hasUnreadCoach != coach { hasUnreadCoach = coach }
    }

    // MARK: Reading the document

    /// Reads again unless the last good read is under `maxAge` seconds old.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        if let lastFetch, load == .loaded, !isStale, Date().timeIntervalSince(lastFetch) < maxAge { return }
        await refresh()
    }

    /// One fetch at a time; a caller that arrives while one runs waits for it.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await fetch()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func fetch() async {
        guard PFAPI.isConfigured else {
            load = .loaded
            return
        }
        do {
            let data = try await PFAPI.fetch(PFDocPath529.inbox)
            apply(try PFPlan529Decoder.make().decode(PFInboxDoc.self, from: data))
        } catch {
            // Not served is an empty inbox, not a failure. Not asked: keep what is shown, else say so.
            if Self.isAbsent(error) {
                items = []
                load = .loaded
                isStale = false
            } else if load != .loaded {
                load = .failed
            } else {
                isStale = true
            }
        }
    }

    /// The server answered "not found" (a fixture without the file counts the same).
    private static func isAbsent(_ error: Error) -> Bool {
        if let failure = error as? SelfHostedPushClient.Failure, case .httpStatus(404, _) = failure { return true }
        return (error as? CocoaError)?.code == .fileNoSuchFile
    }

    /// Takes a document the notifier or the screen read.
    func apply(_ doc: PFInboxDoc) {
        items = doc.items ?? []
        if let serverMuted = doc.muted, let revisionText = doc.mutedAt,
           let revision = PFAlertDates.parse(revisionText), isNewerMuteRevision(revision) {
            let merged = PFInboxAck530.reconcile(serverMuted: serverMuted, localMuted: mute.muted, items: items)
            mute.merge(server: Array(merged))
            defaults.set(revision, forKey: Self.muteRevisionKey)
            saveMute()
        }
        load = .loaded
        isStale = false
        lastFetch = Date()
        adoptIfNeeded()
        recount()
        updateBadge()
    }

    // MARK: Rows and unread

    /// The document's items and the earlier alert history, newest first.
    func rows() -> [PFInboxRow529] {
        PFInboxLogic529.rows(items: items, legacy: PFAlertHistoryStore.shared.entries(for: PFUnified.model.snapshot))
    }

    /// The ids both lists count as read; nil while this one has no baseline.
    private func readIDs() -> Set<String>? {
        guard let seen else { return nil }
        return Set(seen).union(PFAlertHistoryStore.shared.seen ?? [])
    }

    func unreadRows() -> [PFInboxRow529] {
        PFInboxLogic529.unread(rows(), seen: readIDs())
    }

    func isUnread(_ row: PFInboxRow529) -> Bool {
        guard let read = readIDs() else { return false }
        return !read.contains(row.id)
    }


    /// The first document read becomes the baseline: everything in it (and in the earlier history) is read, so the day this build
    /// arrives there is no pile of unread. Only what comes after is.
    private func adoptIfNeeded() {
        guard seen == nil, load == .loaded else { return }
        setSeen(rows().map(\.id))
    }

    func markRead(_ row: PFInboxRow529) {
        guard let seen else { return }
        setSeen(PFInboxLogic529.marking(seen, read: [row.id]))
        if row.legacy != nil { PFAlertHistoryStore.shared.markRead([row.id]) }
        updateBadge()
    }

    func markAllRead() {
        guard let seen else { return }
        let all = rows()
        setSeen(PFInboxLogic529.marking(seen, read: all.reversed().map(\.id)))
        PFAlertHistoryStore.shared.markAllRead(all.compactMap(\.legacy))
        updateBadge()
    }

    private func setSeen(_ list: [String]) {
        seen = list
        defaults.set(list, forKey: Self.seenKey)
        recount()
    }

    // MARK: Kinds

    /// A kind the dismiss-twice rule silenced shows as off.
    func isOn(_ kind: PFInboxKind529) -> Bool { !kindsOff.contains(kind.rawValue) && !mute.muted.contains(kind.rawValue) }

    func set(_ kind: PFInboxKind529, on: Bool) {
        if on {
            // The server is told to stop muting it, whether the phone or the server silenced it.
            if kindsOff.contains(kind.rawValue) || mute.muted.contains(kind.rawValue) { PFInboxAck530.unmute(kind) }
            kindsOff.remove(kind.rawValue)
            mute.unmute(kind: kind.rawValue)
            saveMute()
        } else {
            kindsOff.insert(kind.rawValue)
        }
        defaults.set(kindsOff.sorted(), forKey: Self.kindsOffKey)
    }

    func noteDismissed(id: String, kind: String) {
        mute.dismissed(id: id, kind: kind)
        saveMute()
    }

    func noteOpened(kind: String) {
        mute.opened(kind: kind)
        saveMute()
    }

    func mergeServerMuted(_ kinds: [String], at revision: Date?) {
        guard let revision, isNewerMuteRevision(revision) else { return }
        let merged = PFInboxAck530.reconcile(serverMuted: kinds, localMuted: mute.muted, items: items)
        mute.merge(server: Array(merged))
        defaults.set(revision, forKey: Self.muteRevisionKey)
        saveMute()
    }

    private func isNewerMuteRevision(_ revision: Date) -> Bool {
        PFMuteState530.acceptsServerRevision(revision, after: defaults.object(forKey: Self.muteRevisionKey) as? Date)
    }

    private func saveMute() {
        if let data = try? JSONEncoder().encode(mute) { defaults.set(data, forKey: Self.muteKey) }
    }

    /// The kinds a notification may be raised for: switched on here, and for the health alerts also on in the earlier alerts switch
    /// (More > PaceForge sync), which keeps working.
    var enabledKinds: Set<String> {
        var kinds = Set(PFInboxKind529.allCases.map(\.rawValue)).subtracting(kindsOff).subtracting(mute.muted)
        if !(defaults.object(forKey: PFPrefs.alertsKey) as? Bool ?? true) { kinds.remove(PFInboxKind529.health.rawValue) }
        return kinds
    }

    // MARK: Diagnostics

    func recordCheck(at date: Date, newDelay: TimeInterval?) {
        lastCheck = date
        defaults.set(date, forKey: Self.lastCheckKey)
        if let newDelay {
            lastNewDelay = newDelay
            defaults.set(newDelay, forKey: Self.lastDelayKey)
        }
    }

    // MARK: App icon badge

    /// The app icon shows the unread count, where the phone allows badges (the notification permission has to include them).
    func updateBadge() {
        let count = unreadCount
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().badgeSetting == .enabled else { return }
            try? await center.setBadgeCount(count)
        }
    }
}
