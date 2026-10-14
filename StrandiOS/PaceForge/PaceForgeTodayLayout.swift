import Foundation

// The order of the cards on PaceForge Today. The PaceForge web page saves how its Today cards are arranged in
// data/today-layout.json ({"order": [ids], "pinned": [ids]}); the app reads that file but cannot write it (its token
// may log a measurement and nothing else), so an arrangement made in the app is kept on the phone (UserDefaults) and
// wins over the server's while it exists. The ordering rule is the web page's: pinned cards first, then the saved
// order, then any card the layout does not name in its default place. Foundation only, so it is compiled into the
// macOS unit-test bundle.

/// The Today cards and their layout ids. Where the web page has the same card the id is the web's (`daily`, `feel`,
/// `easy`, `race-week`, `brief`, `session`), so one saved order means the same thing in both. The rest are the
/// app's own cards and use their own ids; the web layout does not name them, so they sit in their default place.
enum PFTodayCard: String, CaseIterable, Equatable {
    /// The daily loop's two cards (daily-intel.json): the day's verdict at the top, the evening wrap just under it.
    case todaysCall = "todays-call"
    case dayInReview = "day-in-review"
    case todaySoFar = "today-so-far"
    /// The week's plan progress (my-plan.json): the same card NOOP Today carries.
    case myPlan = "my-plan"
    case raceWeek = "race-week"
    case brief
    case nextBestAction = "next-best-action"
    case easy
    case feel
    case alerts
    case daily
    case whatChanged = "what-changed"
    case readiness
    case standing
    case session
    case nextRace = "next-race"

    var title: String {
        switch self {
        case .todaysCall: return "Today's call"
        case .dayInReview: return "Day in review"
        case .todaySoFar: return "Today so far"
        case .myPlan: return "My Plan"
        case .raceWeek: return "Race week"
        case .brief: return "Daily briefing"
        case .nextBestAction: return "Next best action"
        case .easy: return "Easy mode"
        case .feel: return "How do you feel?"
        case .alerts: return "Alerts"
        case .daily: return "Today's scores"
        case .whatChanged: return "What changed"
        case .readiness: return "Readiness"
        case .standing: return "Where you stand"
        case .session: return "Today's sessions"
        case .nextRace: return "Next race"
        }
    }

    /// The order the app has always drawn them in, before any layout is applied.
    static let defaultOrder: [PFTodayCard] = allCases
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
