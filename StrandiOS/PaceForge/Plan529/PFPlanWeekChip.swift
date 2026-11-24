import SwiftUI
import StrandDesign

/// The Week chip of the Plan tab: the approved Week page for any week of the season (W1 for a coming or current week, R1 for a finished
/// one). Arrows move across every week of `data/plan-week/index.json`. `week` is the ISO week a deep link asked for ("2026-W47"); with
/// none the chip opens on the current week. The old My Plan card, Easy mode row, week picker, Adjust today card, Niggles row and Next
/// week card are gone from here: their functions live in W1 to W5 and R1 (`PFWeekComing529`, `PFWeekReport529`, `PFChangeTodaySheet529`).
struct PFPlanWeekChip: View {
    var week: String? = nil

    @StateObject private var index = PFDocStore529<PFPlanWeekIndexDoc>(path: PFDocPath529.weekIndex, showsSavedFirst: true)
    @ObservedObject private var router = PFPlan529Router.shared
    @State private var selected: String?

    init(week: String? = nil) {
        self.week = week
        _selected = State(initialValue: week)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch index.state {
            case .loading:
                PFWeekState529(kind: .loading, message: "Loading your plan")
            case .empty:
                PFWeekState529(kind: .empty, message: "Your plan is not on this phone yet. It shows here once PaceForge has written it.")
            case .failed:
                PFWeekState529(kind: .failed, message: "Your plan could not be loaded.", retry: { Task { await index.refresh() } })
            case .loaded(let doc):
                pager(doc)
            }
        }
        .containerIdentifier("calendar-chip-content-week")
        .task { await index.refreshIfStale() }
        // A deep link asks for a week; it is taken once and cleared, so the chip pages freely afterwards.
        .onChange(of: router.week, initial: true) { _, request in
            guard let request else { return }
            selected = request
            router.week = nil
        }
    }

    // MARK: Paging

    private func weeks(_ doc: PFPlanWeekIndexDoc) -> [PFPlanWeekIndexDoc.Week] { doc.weeks ?? [] }

    /// The week on show: the one asked for, else the current week of the index, else the first coming week.
    private func shown(_ doc: PFPlanWeekIndexDoc) -> String? {
        selected ?? doc.current ?? weeks(doc).first(where: { $0.state != "finished" })?.week ?? weeks(doc).first?.week
    }

    @ViewBuilder private func pager(_ doc: PFPlanWeekIndexDoc) -> some View {
        if let current = shown(doc) {
            let all = weeks(doc)
            let position = all.firstIndex(where: { $0.week == current })
            let entry = position.map { all[$0] }
            PFWeekPage529(week: current,
                          header: PFWeekHeader529(label: entry?.label ?? current,
                                                  canGoBack: (position ?? 0) > 0,
                                                  canGoForward: position.map { $0 < all.count - 1 } ?? false,
                                                  goBack: { move(all, position, by: -1) },
                                                  goForward: { move(all, position, by: 1) }),
                          goToWeek: { selected = $0 })
                .id(current)
        } else {
            PFWeekState529(kind: .empty, message: "No week of your plan is on this phone yet.")
        }
    }

    private func move(_ all: [PFPlanWeekIndexDoc.Week], _ position: Int?, by step: Int) {
        guard let position, all.indices.contains(position + step), let target = all[position + step].week else { return }
        selected = target
    }
}
