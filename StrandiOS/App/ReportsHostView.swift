#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Reports: the fourth tab
//
// Two chips, one mounted at a time: Reports (the index: Day, Week, Month and Race) and Insights (What moves you, trends, the journal and
// PaceForge's deep dives, with its own chips). My Day, Sleep and Workouts are "More" rows at the end.

enum ReportsChip: String, CaseIterable, Identifiable {
    case reports, insights

    /// The chip on show. Reset to Reports at every launch.
    static let storageKey = "noop.reports.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reports: return "Reports"
        case .insights: return "Insights"
        }
    }
}

struct ReportsHostView: View {
    @AppStorage(ReportsChip.storageKey) private var chipRaw = ReportsChip.reports.rawValue

    private var chip: ReportsChip { ReportsChip(rawValue: chipRaw) ?? .reports }

    private var selection: Binding<ReportsChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip reports.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Reports", subtitle: "Your reports, what moves you, and the screens behind them.",
                       onRefresh: {
            await PFUnified.model.refresh()
            await PFReportsStore.shared.loadIndex()
        }, lazy: true, topBackground: liquidScaffoldSky()) {
            ReportsColumn(selection: selection)
            ReportsMoreRows()
        }
    }
}

private struct ReportsColumn: View {
    @Binding var selection: ReportsChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionChips(options: ReportsChip.allCases, selection: $selection, idPrefix: "reports-chip",
                         id: { $0.rawValue }, title: { $0.title })
            ReportsChipBody(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("reports-host")
    }
}

private struct ReportsChipBody: View {
    let chip: ReportsChip

    var body: some View {
        UnifiedChipMount(host: "reports", name: chip.rawValue, content: content)
    }

    private var content: AnyView {
        switch chip {
        case .reports: return AnyView(PFReportsIndexContent().containerIdentifier("reports-chip-content-reports"))
        case .insights: return AnyView(InsightsEmbedded())
        }
    }
}
#endif
