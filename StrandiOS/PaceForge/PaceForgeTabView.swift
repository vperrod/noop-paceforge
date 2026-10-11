import SwiftUI
import StrandDesign

/// The five PaceForge screens, in the order the segmented control shows them.
enum PFSegment: String, CaseIterable, Identifiable {
    case today, coach, week, insights, body

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .coach: return "Coach"
        case .week: return "This week"
        case .insights: return "Insights"
        case .body: return "Body"
        }
    }
}

/// The PaceForge tab: a large title, a native segmented control and the selected screen,
/// fed by the live PaceForge server (cached on the device for offline).
struct PaceForgeTabView: View {
    @StateObject private var model = PFModel()

    @AppStorage("noop.paceforge.segment") private var segmentRaw = PFSegment.today.rawValue

    private var segment: Binding<PFSegment> {
        Binding(
            get: { PFSegment(rawValue: segmentRaw) ?? .today },
            set: { segmentRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScreenScaffold(title: "PaceForge", onRefresh: { await model.refresh() }) {
            switch model.phase {
            case .loading:
                PFLoadingView()
            case .notSetUp:
                PFNotSetUpView()
            case .failed(let message):
                PFFailedView(message: message, isRetrying: model.isRefreshing) {
                    Task { await model.refresh() }
                }
            case .ready:
                if let snapshot = model.snapshot, PFAPI.showsWidgetGallery {
                    PFWidgetGallery(snapshot: snapshot)
                } else if let snapshot = model.snapshot {
                    Picker("PaceForge section", selection: segment) {
                        ForEach(PFSegment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pf-segments")

                    if let note = model.offlineNote {
                        PFOfflineBanner(text: note, isRetrying: model.isRefreshing) {
                            Task { await model.refresh() }
                        }
                    }
                    screen(for: segment.wrappedValue, snapshot: snapshot)
                }
            }
        }
        .environmentObject(model)
        .task { await model.refreshIfStale() }
    }

    @ViewBuilder private func screen(for segment: PFSegment, snapshot: PFSnapshot) -> some View {
        switch segment {
        case .today: PFTodayView(snapshot: snapshot)
        case .coach: PFCoachView(snapshot: snapshot)
        case .week: PFWeekView(snapshot: snapshot)
        case .insights: PFInsightsView(snapshot: snapshot)
        case .body: PFBodyView(snapshot: snapshot)
        }
    }
}
