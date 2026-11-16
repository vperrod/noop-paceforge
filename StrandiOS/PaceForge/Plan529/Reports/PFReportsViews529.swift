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

    @Published private(set) var seen: [String: String]
    /// False until a first list has been read and taken as the baseline.
    private var hasBaseline: Bool

    private init() {
        let defaults = UserDefaults.standard
        var stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String]
        #if DEBUG
        // UI tests start with every row unread (a baseline with nothing in it), whatever an earlier run opened.
        if ProcessInfo.processInfo.arguments.contains("-Plan529ResetSeen") {
            defaults.removeObject(forKey: Self.storageKey)
            stored = [:]
        }
        #endif
        hasBaseline = stored != nil
        seen = stored ?? [:]
    }

    /// Takes the first list as seen; does nothing once a baseline exists.
    func adoptBaseline(_ rows: [(id: String, ts: String?)]) {
        guard !hasBaseline else { return }
        hasBaseline = true
        for row in rows { seen[row.id] = row.ts ?? "opened" }
        UserDefaults.standard.set(seen, forKey: Self.storageKey)
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

    @ObservedObject private var seen = PFReportSeenStore529.shared
    @State private var results: PFResultsTarget529?
    private let hiding = PFHiding()

    private var isEmpty: Bool {
        doc.today == nil && (doc.weeks ?? []).isEmpty && (doc.months ?? []).isEmpty && (doc.races ?? []).isEmpty && (doc.workouts ?? []).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEmpty {
                PFDocPlaceholder529(kind: .empty, emptyTitle: "No reports yet",
                                    emptyText: "The daily report is written each morning after the Garmin sync, the week report on Sunday evening and the month report on the 1st.")
            }
            if let today = doc.today, let key = today.key {
                section("Today", rows: [reportRow(id: "today:\(key)", lead: today.day, verdict: today.verdict, sub: today.sub, ts: today.ts) {
                    PFPlan529Router.shared.sheet = .dailyReport(date: key)
                }])
            }
            if let weeks = doc.weeks, !weeks.isEmpty {
                section("Weeks", rows: weeks.compactMap { row in
                    guard let key = row.key else { return nil }
                    return reportRow(id: "week:\(key)", lead: row.day, verdict: row.verdict, sub: row.sub, ts: row.ts) {
                        PFDeepLink529.open(.week(key))
                    }
                })
            }
            if let months = doc.months, !months.isEmpty {
                section("Months", rows: months.compactMap { row in
                    guard let key = row.key else { return nil }
                    return reportRow(id: "month:\(key)", lead: row.day, verdict: row.verdict, sub: row.sub, ts: row.ts) {
                        PFPlan529Router.shared.sheet = .monthReport(key: key)
                    }
                })
            }
            if let races = doc.races, !races.isEmpty {
                section("Races", rows: races.compactMap { row in
                    guard let date = row.date else { return nil }
                    return reportRow(id: "race:\(date)", lead: row.day, verdict: row.name, sub: row.sub, ts: row.ts) {
                        PFPlan529Router.shared.sheet = .race(date: date)
                    }
                })
            }
            if let workouts = doc.workouts, !workouts.isEmpty {
                section("Workouts", rows: workouts.compactMap { row in
                    guard let id = row.activityId else { return nil }
                    let sub = [row.sub ?? (row.state == "pending" ? "Review pending" : nil), row.meaning].compactMap { $0 }.joined(separator: "\n")
                    return reportRow(id: "workout:\(id)", lead: row.day, verdict: row.name, sub: sub, ts: row.ts) {
                        results = PFResultsTarget529(id: id, title: row.name)
                    }
                })
            }
        }
        .pfResultsSheet529($results)
        .containerIdentifier("plan529-reports")
        .task { seen.adoptBaseline(Self.rows(of: doc)) }
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

    private func reportRow(id: String, lead: String?, verdict: String?, sub: String?, ts: String?, open: @escaping () -> Void) -> AnyView {
        let isNew = seen.isNew(id: id, ts: ts)
        return AnyView(
            Button {
                seen.markOpened(id: id, ts: ts)
                open()
            } label: {
                PFRow529(lead: lead, isNew: isNew, title: hiding.text(verdict ?? "Report"), sub: sub.map { hiding.text($0) }, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isNew ? "new" : "")
            .accessibilityIdentifier("reports-row-\(id)")
        )
    }

    private func section(_ title: String, rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: title)
                .padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { PFDivider529() }
                row
            }
        }
        .planCard529()
        .containerIdentifier("reports-section-\(title.lowercased())")
    }
}
