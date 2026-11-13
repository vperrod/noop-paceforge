import Foundation

// The order of the cards on PaceForge Today. The PaceForge web page saves how its Today cards are arranged in
// data/today-layout.json ({"order": [ids], "pinned": [ids]}); the app reads that file but cannot write it (its token
// may log a measurement and nothing else), so an arrangement made in the app is kept on the phone (UserDefaults) and
// wins over the server's while it exists. The ordering rule is the web page's: pinned cards first, then the saved
// order, then any card the layout does not name in its default place. Foundation only, so it is compiled into the
// macOS unit-test bundle.

/// The six cards of the unified Today's PaceForge section, in the order they are drawn: the call, what needs him, today or the next
/// race, how he is, how he feels and the week. The order is fixed (the server's saved `today-layout.json` is still read and kept for
/// the web page, but no longer arranges these). The raw value is the card's id in `accessibilityIdentifier`
/// (`pf-today-card-<id>`) and in "Not today".
enum PFTodayCard: String, CaseIterable, Equatable {
    case theCall = "the-call"
    case needsYou = "needs-you"
    case today
    case howYouAre = "how-you-are"
    case feel
    case thisWeek = "this-week"

    var title: String {
        switch self {
        case .theCall: return "The call"
        case .needsYou: return "Needs you"
        case .today: return "Today"
        case .howYouAre: return "How you are"
        case .feel: return "How do you feel?"
        case .thisWeek: return "This week"
        }
    }

    var identifier: String { "pf-today-card-" + rawValue }

    /// The cards that have something to show, in the fixed order. `needsYou` is the live count of open items, `hasFeel` whether the
    /// server serves the feel summary. Today and the week strip always draw (a rest day says so); the rest are left out when empty.
    static func present(call: PFTodayCall, needsYou: Int, hasFeel: Bool) -> [PFTodayCard] {
        allCases.filter { card in
            switch card {
            case .theCall: return call.call != nil
            case .needsYou: return needsYou > 0
            case .today: return true
            case .howYouAre: return call.hasReadiness
            case .feel: return hasFeel
            case .thisWeek: return !call.week.isEmpty
            }
        }
    }
}

struct PFTodayLayout: Codable, Equatable {
    var order: [String] = []
    var pinned: [String] = []

    var isEmpty: Bool { order.isEmpty && pinned.isEmpty }
}

enum PFTodayOrder {

    /// `ids` (the cards present, in default order) arranged by `layout`: pinned first, then by position in
    /// `layout.order`, then the cards the order does not name in their default places after those.
    static func sorted(_ ids: [String], layout: PFTodayLayout) -> [String] {
        let pinned = Set(layout.pinned)
        func rank(_ id: String, _ defaultIndex: Int) -> Int {
            layout.order.firstIndex(of: id) ?? layout.order.count + defaultIndex
        }
        let keyed = ids.enumerated().map { (index: $0.offset, id: $0.element) }
        return keyed.sorted { a, b in
            let pa = pinned.contains(a.id), pb = pinned.contains(b.id)
            if pa != pb { return pa }
            let ra = rank(a.id, a.index), rb = rank(b.id, b.index)
            return ra != rb ? ra < rb : a.index < b.index
        }.map { $0.id }
    }

    /// Where card `id` would swap to when moved one step (`-1` up, `+1` down) among the cards in `visible`, inside
    /// its own group (pinned cards move among pinned, the rest among the rest). nil when it cannot move that way.
    private static func destination(of id: String, step: Int, ids: [String], visible: Set<String>,
                                    layout: PFTodayLayout) -> (sequence: [String], from: Int, to: Int)? {
        let sequence = sorted(ids, layout: layout)
        guard let from = sequence.firstIndex(of: id) else { return nil }
        let pinned = Set(layout.pinned)
        var to = from + step
        while to >= 0 && to < sequence.count
                && !(visible.contains(sequence[to]) && pinned.contains(sequence[to]) == pinned.contains(id)) {
            to += step
        }
        guard to >= 0 && to < sequence.count else { return nil }
        return (sequence, from, to)
    }

    static func canMove(_ id: String, step: Int, ids: [String], visible: Set<String>, layout: PFTodayLayout) -> Bool {
        destination(of: id, step: step, ids: ids, visible: visible, layout: layout) != nil
    }

    /// `layout` after moving `id` one step; unchanged when it cannot move. Names the cards in `ids` explicitly in
    /// the new order and keeps any ids the layout named that are not on screen now, after them.
    static func moving(_ id: String, step: Int, ids: [String], visible: Set<String>,
                       layout: PFTodayLayout) -> PFTodayLayout {
        guard var moved = destination(of: id, step: step, ids: ids, visible: visible, layout: layout) else {
            return layout
        }
        moved.sequence.swapAt(moved.from, moved.to)
        let kept = layout.order.filter { !moved.sequence.contains($0) }
        return PFTodayLayout(order: moved.sequence + kept, pinned: layout.pinned)
    }

    /// `layout` with `id` pinned, or unpinned when it was pinned.
    static func togglingPin(_ id: String, layout: PFTodayLayout) -> PFTodayLayout {
        var out = layout
        if let at = out.pinned.firstIndex(of: id) {
            out.pinned.remove(at: at)
        } else {
            out.pinned.append(id)
        }
        return out
    }

    /// The layout in force: the phone's own arrangement when there is one, else the server's.
    static func effective(local: PFTodayLayout?, server: PFTodayLayout) -> PFTodayLayout {
        local ?? server
    }

    /// `{order: [...], pinned: [...]}` as the server writes it; anything else reads as an empty layout. Ids are
    /// kept as sent (strings only, repeats dropped).
    static func parseServer(_ j: PFJ) -> PFTodayLayout {
        func ids(_ key: String) -> [String] {
            var seen = Set<String>()
            return j[key].strings.filter { seen.insert($0).inserted }
        }
        return PFTodayLayout(order: ids("order"), pinned: ids("pinned"))
    }
}

/// The phone's own arrangement as JSON in UserDefaults; nil means "none, follow PaceForge's".
enum PFTodayLayoutStorage {
    static let defaultsKey = "noop.paceforge.todayLayout.v1"

    static func load(defaults: UserDefaults = .standard) -> PFTodayLayout? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PFTodayLayout.self, from: data)
    }

    static func save(_ layout: PFTodayLayout?, defaults: UserDefaults = .standard) {
        guard let layout, let data = try? JSONEncoder().encode(layout) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(data, forKey: defaultsKey)
    }
}
