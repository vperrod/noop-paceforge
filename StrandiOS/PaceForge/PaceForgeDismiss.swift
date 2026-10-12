import Foundation

// "Not today": hiding a PaceForge card from the screen. Two modes: "Hide until it changes" remembers a hash of the
// card's current text and keeps the card hidden while its text hashes to the same value; "Snooze until tomorrow"
// hides it until the next day. Both are kept on the phone only (UserDefaults); the server's dismissed.json is
// read as well and the two lists are united. The app is read-only toward PaceForge, so nothing is written back.
// Foundation only, so the hash, the rules and the persistence helpers are compiled into the macOS unit-test bundle.

// MARK: - Hash

/// FNV-1a, 32 bit, over the UTF-8 bytes: the same algorithm the PaceForge server hashes card text with, written
/// as eight lower-case hex digits. FNV-1a("") = 811c9dc5, FNV-1a("a") = e40c292c, FNV-1a("foobar") = bf9cf968.
enum PFFNV {
    static func hash(_ text: String) -> String {
        var value: UInt32 = 0x811c_9dc5
        for byte in text.utf8 {
            value ^= UInt32(byte)
            value = value &* 0x0100_0193
        }
        return String(format: "%08x", value)
    }
}

// MARK: - Model

/// One hidden card. `until` set means a snooze (hidden while today is before that day); otherwise it is a
/// "hide until it changes" and `textHash` is the hash of the text that was hidden.
struct PFDismissal: Codable, Equatable {
    var key: String
    /// yyyy-MM-dd, or nil.
    var until: String?
    /// ISO-8601 time the card was hidden.
    var dismissedAt: String?
    var textHash: String?

    enum CodingKeys: String, CodingKey {
        case key, until
        case dismissedAt = "dismissed_at"
        case textHash = "text_hash"
    }
}

enum PFDismissMode: Equatable {
    /// Hide until the card's text changes.
    case untilChanged
    /// Hide until tomorrow.
    case untilTomorrow
}

enum PFDismissSource: Equatable {
    case local, server
}

// MARK: - Rules

enum PFDismissLogic {

    /// Which list hides card `key` showing `text` on `today` (yyyy-MM-dd), or nil when neither does. The two
    /// lists are united: either one hides the card. The local list is asked first.
    ///
    /// A snooze (an entry with `until`) hides while `today` is before `until`. A "hide until it changes" entry
    /// hides while the hash of the current text equals its `textHash`. An entry with neither cannot be checked
    /// against anything, so it hides nothing.
    static func hiddenBy(key: String, text: String, today: String, local: [PFDismissal],
                         server: [PFDismissal]) -> PFDismissSource? {
        let hash = PFFNV.hash(text)
        func hides(_ items: [PFDismissal]) -> Bool {
            items.contains { item in
                guard item.key == key else { return false }
                if let until = item.until { return today < until }
                if let stored = item.textHash { return stored == hash }
                return false
            }
        }
        if hides(local) { return .local }
        if hides(server) { return .server }
        return nil
    }

    static func isHidden(key: String, text: String, today: String, local: [PFDismissal],
                         server: [PFDismissal]) -> Bool {
        hiddenBy(key: key, text: text, today: today, local: local, server: server) != nil
    }

    /// The local list after hiding `key`: any earlier local entry for it is replaced by the new one.
    static func dismissing(_ items: [PFDismissal], key: String, text: String, mode: PFDismissMode, today: String,
                           now: Date) -> [PFDismissal] {
        var out = items.filter { $0.key != key }
        let stamp = ISO8601DateFormatter().string(from: now)
        switch mode {
        case .untilChanged:
            out.append(PFDismissal(key: key, until: nil, dismissedAt: stamp, textHash: PFFNV.hash(text)))
        case .untilTomorrow:
            out.append(PFDismissal(key: key, until: tomorrow(after: today), dismissedAt: stamp,
                                   textHash: PFFNV.hash(text)))
        }
        return out
    }

    /// The local list after showing `key` again.
    static func restoring(_ items: [PFDismissal], key: String) -> [PFDismissal] {
        items.filter { $0.key != key }
    }

    /// Snoozes that have run out are dropped; "hide until it changes" entries are kept.
    static func pruned(_ items: [PFDismissal], today: String) -> [PFDismissal] {
        items.filter { item in
            guard let until = item.until else { return true }
            return today < until
        }
    }

    /// The day after `day` (yyyy-MM-dd). An unreadable day is returned unchanged.
    static func tomorrow(after day: String) -> String {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let next = calendar.date(byAdding: .day, value: 1, to: start) else { return day }
        let c = calendar.dateComponents([.year, .month, .day], from: next)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Storage

/// The local list as JSON in UserDefaults, and the server's dismissed.json.
enum PFDismissStorage {
    static let defaultsKey = "noop.paceforge.dismissed.v1"

    static func load(defaults: UserDefaults = .standard, today: String) -> [PFDismissal] {
        guard let data = defaults.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([PFDismissal].self, from: data) else { return [] }
        return PFDismissLogic.pruned(items, today: today)
    }

    static func save(_ items: [PFDismissal], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: defaultsKey) }
    }

    /// `{items:[{key, until, dismissed_at, text_hash}]}`; anything else reads as no dismissals.
    static func parseServer(_ j: PFJ) -> [PFDismissal] {
        j["items"].array.compactMap { item in
            guard let key = item["key"].text else { return nil }
            return PFDismissal(key: key, until: item["until"].text, dismissedAt: item["dismissed_at"].text,
                               textHash: item["text_hash"].text)
        }
    }
}
