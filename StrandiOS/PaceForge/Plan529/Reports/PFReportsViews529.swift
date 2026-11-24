import SwiftUI
import StrandDesign

// P1, the Reports chip of the Plan tab: today's report, the weeks, the months, the races and the workouts that have one, each row with its
// verdict and a line under it, and a dot on the rows newer than the last time that row was opened.

/// Which report rows were opened and what they said then, kept on the phone. A row is new while its timestamp is newer than the one it
/// had when it was last opened. The first list a phone reads is its baseline: everything in it counts as seen, so a first run does not
/// open on a dot at every row, and only what arrives later carries one.
@MainActor
final class PFReportSeenStore529: ObservableObject {
    static let shared = PFReportSeenStore529()
    static let storageKey = "noop.plan529.reportsSeen"
    /// Whether the first list has been taken as the baseline: its own flag, because a row can be marked opened (a deep link) before the
    /// list has ever loaded, and the seen map alone would then look like a baseline.
    static let baselineKey = "noop.plan529.reportsBaselined"

    @Published private(set) var seen: [String: String]
    /// False until a first list has been read and taken as the baseline.
    private var hasBaseline: Bool

    private init() {
        let defaults = UserDefaults.standard
        var stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String]
        var baselined = defaults.bool(forKey: Self.baselineKey)
        #if DEBUG
        // UI tests start with every row unread (a baseline with nothing in it), whatever an earlier run opened.
        if ProcessInfo.processInfo.arguments.contains("-Plan529ResetSeen") {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.set(true, forKey: Self.baselineKey)
            stored = nil
            baselined = true
        }
        #endif
        hasBaseline = baselined
        seen = stored ?? [:]
    }

    /// Takes the first list as seen; does nothing once a baseline exists.
    func adoptBaseline(_ rows: [(id: String, ts: String?)]) {
        guard !hasBaseline else { return }
        hasBaseline = true
        // A row opened before the list loaded keeps its own mark.
        for row in rows where seen[row.id] == nil { seen[row.id] = row.ts ?? "opened" }
        UserDefaults.standard.set(seen, forKey: Self.storageKey)
        UserDefaults.standard.set(true, forKey: Self.baselineKey)
    }

    func isNew(id: String, ts: String?) -> Bool {
        guard hasBaseline else { return false }
        guard let opened = seen[id] else { return true }
        guard let ts else { return false }
        return Self.isNewer(ts, than: opened)
    }

    func markOpened(id: String, ts: String?) {
        // A row without a timestamp is marked with a word that no timestamp is newer than.
        seen[id] = ts ?? "opened"
        UserDefaults.standard.set(seen, forKey: Self.storageKey)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        if let first = parse(a), let second = parse(b) { return first > second }
        return a > b
    }

    private static func parse(_ text: String) -> Date? {
        PFFormat.isoWithFraction.date(from: text) ?? PFFormat.isoPlain.date(from: text)
    }
}

struct PFPlanReportsContent529: View {
    let doc: PFReportsListDoc

    /// What the chips above the list narrow it to. Today's report is listed under All only.
    private enum Filter: String, CaseIterable {
        case all, weeks, months, races, workouts

        var title: String {
            switch self {
            case .all: return "All"
            case .weeks: return "Weeks"
            case .months: return "Months"
            case .races: return "Races"
            case .workouts: return "Workouts"
            }
        }

        func includes(_ kind: Kind) -> Bool {
            switch self {
            case .all: return true
            case .weeks: return kind == .week
            case .months: return kind == .month
            case .races: return kind == .race
            case .workouts: return kind == .workout
            }
        }
    }

    private enum Kind { case today, week, month, race, workout }

    /// One row of the list: the same three parts for every kind, a date, a title with its kind, and the one-line verdict.
    private struct Item {
        let id: String
        let kind: Kind
        let lead: String?
        let title: String?
        let sub: String?
        let ts: String?
        let isFinished: Bool
        let open: () -> Void
    }

    @ObservedObject private var seen = PFReportSeenStore529.shared
    @State private var results: PFResultsTarget529?
    @State private var filter = Filter.all
    private let hiding = PFHiding()

    private var isEmpty: Bool {
        doc.today == nil && (doc.weeks ?? []).isEmpty && (doc.months ?? []).isEmpty && (doc.races ?? []).isEmpty && (doc.workouts ?? []).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEmpty {
                PFDocPlaceholder529(kind: .empty, emptyTitle: "No reports yet",
                                    emptyText: "The daily report is written each morning after the Garmin sync, the week report on Sunday evening and the month report on the 1st.")
            } else {
                SectionChips(options: Filter.allCases, selection: $filter, idPrefix: "reports-filter",
                             id: { $0.rawValue }, title: { $0.title })
                list
            }
        }
        .pfResultsSheet529($results)
        .containerIdentifier("plan529-reports")
        .task { seen.adoptBaseline(Self.rows(of: doc)) }
    }

    /// Every report of every kind, as the rows of the list.
    private var items: [Item] {
        var out: [Item] = []
        if let today = doc.today, let key = today.key {
            // Listed either way; shown as finished only when the server says it is ready (`today.ready`), else pending with its reason.
            let isReady = PFReportReadiness529.isReady(today)
            out.append(Item(id: "today:\(key)", kind: .today, lead: today.day,
                            title: isReady ? today.verdict : PFReportReadiness529.pendingTitle,
                            sub: isReady ? today.sub : PFReportReadiness529.pendingSub(today), ts: today.ts, isFinished: isReady,
                            open: { PFPlan529Router.shared.sheet = .dailyReport(date: key) }))
        }
        for row in doc.weeks ?? [] {
            guard let key = row.key else { continue }
            out.append(Item(id: "week:\(key)", kind: .week, lead: row.day, title: row.verdict, sub: row.sub, ts: row.ts, isFinished: true,
                            open: { PFDeepLink529.open(.week(key)) }))
        }
        for row in doc.months ?? [] {
            guard let key = row.key else { continue }
            out.append(Item(id: "month:\(key)", kind: .month, lead: row.day, title: row.verdict, sub: row.sub, ts: row.ts, isFinished: true,
                            open: { PFPlan529Router.shared.sheet = .monthReport(key: key) }))
        }
        for row in doc.races ?? [] {
            guard let date = row.date else { continue }
            out.append(Item(id: "race:\(date)", kind: .race, lead: row.day, title: row.name, sub: row.sub, ts: row.ts, isFinished: true,
                            open: { PFPlan529Router.shared.sheet = .race(date: date) }))
        }
        for row in doc.workouts ?? [] {
            guard let id = row.activityId else { continue }
            let sub = [row.sub ?? (row.state == "pending" ? "Review pending" : nil), row.meaning].compactMap { $0 }.joined(separator: "\n")
            let name = row.name
            out.append(Item(id: "workout:\(id)", kind: .workout, lead: row.day, title: name, sub: sub, ts: row.ts, isFinished: true,
                            open: { results = PFResultsTarget529(id: id, title: name) }))
        }
        return out
    }

    /// The rows the chip lets through, newest first (a row without a timestamp goes after the ones with one, in the order it came).
    private var shown: [Item] {
        let kept = items.filter { filter.includes($0.kind) }
        let ordered = kept.enumerated().sorted { a, b in
            switch (a.element.ts, b.element.ts) {
            case let (x?, y?):
                if PFReportSeenStore529.isNewer(x, than: y) { return true }
                if PFReportSeenStore529.isNewer(y, than: x) { return false }
                return a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }
        return ordered.map { $0.element }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                if index > 0 { PFDivider529() }
                reportRow(item)
            }
        }
        .planCard529()
        .containerIdentifier("reports-list")
    }

    /// Every row of the list as (id, timestamp), the ids the rows are marked with.
    private static func rows(of doc: PFReportsListDoc) -> [(id: String, ts: String?)] {
        var out: [(id: String, ts: String?)] = []
        if let today = doc.today, let key = today.key { out.append(("today:\(key)", today.ts)) }
        for row in doc.weeks ?? [] { if let key = row.key { out.append(("week:\(key)", row.ts)) } }
        for row in doc.months ?? [] { if let key = row.key { out.append(("month:\(key)", row.ts)) } }
        for row in doc.races ?? [] { if let date = row.date { out.append(("race:\(date)", row.ts)) } }
        for row in doc.workouts ?? [] { if let id = row.activityId { out.append(("workout:\(id)", row.ts)) } }
        return out
    }

    private func pill(_ kind: Kind) -> PFPill529 {
        switch kind {
        case .today: return PFPill529(text: "DAY", tone: .grey)
        case .week: return PFPill529(text: "WEEK", tone: .teal)
        case .month: return PFPill529(text: "MONTH", tone: .teal)
        case .race: return PFPill529(text: "RACE", tone: .amber)
        case .workout: return PFPill529(text: "WORKOUT", tone: .blue)
        }
    }

    private func reportRow(_ item: Item) -> some View {
        // A report that is not ready carries no "new" dot: nothing has been announced about it.
        let isNew = item.isFinished && seen.isNew(id: item.id, ts: item.ts)
        return Button {
            seen.markOpened(id: item.id, ts: item.ts)
            item.open()
        } label: {
            PFRow529(lead: item.lead, isNew: isNew, title: hiding.text(item.title ?? "Report"), sub: item.sub.map { hiding.text($0) },
                     trailingPill: pill(item.kind), showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isNew ? "new" : "")
        .accessibilityIdentifier("reports-row-\(item.id)")
    }
}
