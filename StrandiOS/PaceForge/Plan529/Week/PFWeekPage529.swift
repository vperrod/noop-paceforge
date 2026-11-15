import SwiftUI
import StrandDesign

/// The week's name with an arrow each side: arrows move across every week of `plan-week/index.json`.
struct PFWeekHeader529: View {
    let label: String
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            arrow("chevron.left", enabled: canGoBack, id: "plan529-week-prev", name: "Previous week", action: goBack)
            Spacer(minLength: 4)
            Text(label)
                .lookCaps(15, weight: .bold)
                .foregroundStyle(NoopLook.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("plan529-week-label")
            Spacer(minLength: 4)
            arrow("chevron.right", enabled: canGoForward, id: "plan529-week-next", name: "Next week", action: goForward)
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, id: String, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? NoopLook.textPrimary : NoopLook.textMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(name)
        .accessibilityIdentifier(id)
    }
}

enum PFWeekPhase529 {
    /// The pill colour of a season-plan phase (build, sharpen, taper, race, recover).
    static func color(_ key: String?) -> Color {
        switch key ?? "" {
        case "recover", "taper": return PFWeekColor529.amber
        case "race": return PFWeekColor529.red
        case "build": return PFWeekColor529.blue
        case "sharpen": return PFColor.violet
        default: return NoopLook.textTertiary
        }
    }
}

/// One week of the Week chip: reads its document and draws the plan (W1) for a coming or current week, the report (R1) for a finished one.
struct PFWeekPage529: View {
    let week: String
    let header: PFWeekHeader529
    let goToWeek: (String) -> Void

    @StateObject private var store: PFDocStore529<PFPlanWeekDoc>
    @StateObject private var decisions = PFWeekDecisions529()
    @ObservedObject private var model = PFUnified.model
    @EnvironmentObject private var router: NavRouter
    @State private var results: PFResultsTarget529?
    @State private var swap: PFSwapTarget529?

    init(week: String, header: PFWeekHeader529, goToWeek: @escaping (String) -> Void) {
        self.week = week
        self.header = header
        self.goToWeek = goToWeek
        _store = StateObject(wrappedValue: PFDocStore529<PFPlanWeekDoc>(path: PFDocPath529.week(week)))
    }

    private var hooks: PFWeekHooks529 {
        PFWeekHooks529(
            openResults: { results = $0 },
            openSession: { id in PFDeepLink529.open(.sheet(.session(week: week, id: id))) },
            openSwap: { swap = $0 },
            askCoach: { prompt in
                PFChatPrefill.shared.text = prompt
                router.openCoach()
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .loading:
                header.pfWeekCard()
                PFWeekState529(kind: .loading, message: "Loading the week")
            case .empty:
                header.pfWeekCard()
                PFWeekState529(kind: .empty, message: "Nothing is planned for this week yet.")
            case .failed:
                header.pfWeekCard()
                PFWeekState529(kind: .failed, message: "The week could not be loaded.", retry: { Task { await store.refresh() } })
            case .loaded(let doc):
                if store.isStale { PFWeekSub529(text: "Showing the copy saved on this phone. PaceForge could not be reached.") }
                if doc.state == "finished", doc.report != nil {
                    PFWeekReport529(week: week, doc: doc, header: header, hooks: hooks, goToWeek: goToWeek, decisions: decisions)
                } else {
                    PFWeekComing529(week: week, doc: doc, header: header, hooks: hooks, decisions: decisions,
                                    reload: { await reload() })
                }
            }
        }
        .pfResultsSheet529($results)
        .sheet(item: $swap) { target in PFChangeWorkoutSheet529(target: target) }
        .task {
            await store.refreshIfStale()
            await model.refreshIfStale()
            remember()
        }
        .onChange(of: store.state) { _, _ in remember() }
        .onReceive(NotificationCenter.default.publisher(for: .pfPlan529Changed)) { _ in
            Task { await store.refresh() }
        }
    }

    private func remember() {
        if let doc = store.doc { PFChangeLookup529.remember(doc) }
    }

    /// Reads the week again and hands back what is on screen.
    @MainActor private func reload() async -> PFPlanWeekDoc? {
        await store.refresh()
        return store.doc
    }
}
