import Foundation

// Build 530, APP-4: what the phone tells the server about its alerts (`POST /app/inbox-ack`) and the dismiss-twice rule. Foundation only,
// tested in PFAlertAck530Tests. The sending and the storage are in `PFInboxAck530`.

/// One request body: `{raised: [ids], dismissed: [ids], opened: [ids], unmute: kind}`, every key optional, at least one present.
struct PFAckBatch530: Codable, Equatable {
    var raised: [String] = []
    var dismissed: [String] = []
    var opened: [String] = []
    var unmute: String?

    var isEmpty: Bool { raised.isEmpty && dismissed.isEmpty && opened.isEmpty && unmute == nil }

    var body: [String: Any] {
        var out: [String: Any] = [:]
        if !raised.isEmpty { out["raised"] = raised }
        if !dismissed.isEmpty { out["dismissed"] = dismissed }
        if !opened.isEmpty { out["opened"] = opened }
        if let unmute { out["unmute"] = unmute }
        return out
    }
}

/// Acknowledgements waiting for the server. A failed send keeps them, and the next contact sends them again.
struct PFAckQueue530: Codable, Equatable {
    /// The server takes at most this many ids per key.
    static let maxIDs = 100
    /// The oldest batch is forgotten past this many.
    static let maxBatches = 50
    /// The server's own check on an id (`inbox_rules._ID`).
    static func isValid(id: String) -> Bool {
        guard (1...120).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || "_:.-".unicodeScalars.contains($0)) }
    }

    var batches: [PFAckBatch530] = []

    var next: PFAckBatch530? { batches.first }

    /// Takes out of the first batch what a send of `sent` carried. Anything added while the send was out stays for the next one.
    mutating func settle(_ sent: PFAckBatch530) {
        guard var first = batches.first else { return }
        first.raised.removeAll { sent.raised.contains($0) }
        first.dismissed.removeAll { sent.dismissed.contains($0) }
        first.opened.removeAll { sent.opened.contains($0) }
        if first.unmute == sent.unmute { first.unmute = nil }
        if first.isEmpty { batches.removeFirst() } else { batches[0] = first }
    }

    mutating func addRaised(_ id: String) { add(id, to: \.raised) }
    mutating func addOpened(_ id: String) { add(id, to: \.opened) }

    /// A dismissal that comes after an unmute starts a new batch: the server handles a batch's dismissals before its unmute, so one batch
    /// would undo a mute the later dismissals had earned.
    mutating func addDismissed(_ id: String) {
        guard Self.isValid(id: id) else { return }
        if batches.last?.unmute != nil { batches.append(PFAckBatch530()) }
        add(id, to: \.dismissed)
    }

    /// A batch carries one unmute: a second kind goes in a batch of its own.
    mutating func addUnmute(_ kind: String) {
        if let last = batches.last, last.unmute == nil || last.unmute == kind {
            batches[batches.count - 1].unmute = kind
        } else {
            batches.append(PFAckBatch530(unmute: kind))
        }
    }

    private mutating func add(_ id: String, to key: WritableKeyPath<PFAckBatch530, [String]>) {
        guard Self.isValid(id: id) else { return }
        if var last = batches.last, last[keyPath: key].count < Self.maxIDs {
            if !last[keyPath: key].contains(id) {
                last[keyPath: key].append(id)
                batches[batches.count - 1] = last
            }
            return
        }
        var fresh = PFAckBatch530()
        fresh[keyPath: key] = [id]
        batches.append(fresh)
        if batches.count > Self.maxBatches { batches.removeFirst(batches.count - Self.maxBatches) }
    }

    /// What to do with the server's answer: a 2xx is done; a 400 or 413 would be refused again, so the batch is dropped; anything else
    /// (429 over the hourly cap, 5xx, no answer) keeps it for a later contact.
    static func isSettled(status: Int) -> Bool {
        (200..<300).contains(status) || status == 400 || status == 413
    }
}

/// Which kinds the dismiss-twice rule has silenced: a kind dismissed twice in a row (two different items, no open of that kind between) stops
/// alerting until the athlete switches it back on. The problems and the journal questions are never silenced.
struct PFMuteState530: Codable, Equatable {
    static let never: Set<String> = ["problem", "journal"]
    static let after = 2

    var muted: Set<String> = []
    /// Per kind, the item ids dismissed since the last open of that kind.
    var streaks: [String: [String]] = [:]

    mutating func dismissed(id: String, kind: String) {
        guard !Self.never.contains(kind) else { return }
        var list = streaks[kind] ?? []
        if !list.contains(id) { list = Array((list + [id]).suffix(Self.after)) }
        streaks[kind] = list
        if list.count >= Self.after { muted.insert(kind) }
    }

    mutating func opened(kind: String) {
        streaks[kind] = []
    }

    mutating func unmute(kind: String) {
        muted.remove(kind)
        streaks[kind] = []
    }

    /// The server's list after it took an acknowledgement: what it muted stays muted here too.
    mutating func merge(server kinds: [String]) {
        muted.formUnion(Set(kinds).subtracting(Self.never))
    }
}

/// The alerts raised on this phone, kept for three days: the cap of six a day and "already raised" read it.
struct PFRaisedLedger530: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var id: String
        var kind: String
        var at: Date
    }

    static let keepDays = 3
    var entries: [Entry] = []

    var ids: Set<String> { Set(entries.map(\.id)) }

    /// Today's raised alerts outside the cap-exempt kinds, on `calendar`'s day.
    func countToday(now: Date, calendar: Calendar) -> Int {
        entries.filter { !PFAlertDelivery530.capExemptKinds.contains($0.kind) && calendar.isDate($0.at, inSameDayAs: now) }.count
    }

    mutating func add(id: String, kind: String, at: Date) {
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(Entry(id: id, kind: kind, at: at))
        entries = entries.filter { at.timeIntervalSince($0.at) < Double(Self.keepDays) * 86_400 }
    }
}
