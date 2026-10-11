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

/// The PaceForge tab: a large title, a native segmented control and the selected screen.
/// Data is a bundled preview snapshot until the server step lands.
struct PaceForgeTabView: View {
    private static let snapshot = PFSnapshot.load()

    @AppStorage("noop.paceforge.segment") private var segmentRaw = PFSegment.today.rawValue

    private var segment: Binding<PFSegment> {
        Binding(
            get: { PFSegment(rawValue: segmentRaw) ?? .today },
            set: { segmentRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScreenScaffold(title: "PaceForge") {
            Picker("PaceForge section", selection: segment) {
                ForEach(PFSegment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pf-segments")

            switch Self.snapshot {
            case .success(let snapshot):
                PFPreviewLabel(text: snapshot.label)
                screen(for: segment.wrappedValue, snapshot: snapshot)
            case .failure(let error):
                PFCard("PaceForge preview unavailable", icon: "exclamationmark.triangle") {
                    PFParagraph("The bundled preview data could not be read: \(error.localizedDescription)")
                }
            }
        }
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
