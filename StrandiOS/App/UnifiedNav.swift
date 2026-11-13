#if os(iOS)
import SwiftUI
import StrandDesign

// The navigation: four tabs in the floating bar, Today, Plan, Train and Health (tags 0 to 3), and a round Coach button beside the bar that
// opens the Coach as a sheet over whatever screen is showing. It is the only navigation.
//
// - Plan has four chips: This week, Next week, Calendar and Season (Events, the race-week card, the season plan and the week rows).
// - Train has six chips: HYROX, Running, Strength, Bike, Workouts and Athlete.
// - Health has seven chips: Day, Sleep, Recovery, Body, Vitals, Journal and Trends.
// - The Coach sheet holds the reports and the insights; Settings opens from the avatar on Today, and Data from Settings > Tools.
// - Sleep also opens from the Rest ring on Today (a push over the tab on show), and My Day from `noop://myday`.
// - Every tab reopens on the chip it was left on (each host keeps its chip in @AppStorage; nothing resets it at launch).
//
// Built small on purpose (builds 465 to 478): every chip is its own small view, only the selected chip of a tab is mounted, nothing
// here reads a live strap value, there is no GeometryReader, ViewThatFits or preference key, and PaceForge's core is never called
// from here: every PaceForge chip reads the snapshot PFModel already built.

enum UnifiedNav {
    static let todayTab = 0
    static let planTab = 1
    static let trainTab = 2
    static let healthTab = 3

    /// Called from the app's init. The tabs keep their chips between launches, so there is nothing to reset: only the keys of the two
    /// switches that are gone are removed, so a stored value does not outlive the code that read it.
    static func captureAtLaunch() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "unifiedNav")
        defaults.removeObject(forKey: "unifiedDay")
        NoopDiag.crumb("nav.unified enabled")
    }

    /// The bar, in tag order. The ids are the lower-cased titles, which is what the UI tests look for (`look-tab-<id>`).
    static let tabs: [LookTabItem] = [
        LookTabItem(id: "today", title: "Today", symbol: "square.grid.2x2"),
        LookTabItem(id: "plan", title: "Plan", symbol: "calendar"),
        LookTabItem(id: "train", title: "Train", symbol: "figure.run"),
        LookTabItem(id: "health", title: "Health", symbol: "heart.text.square"),
    ]

    /// Where an old PaceForge link (widget, notification, `noop://paceforge/...`, the Home Screen menu) lands.
    enum Landing: Equatable {
        case today
        case calendar(CalendarChip)
        case health(HealthChip)
        /// The Coach sheet, which also holds the insights and the reports.
        case coach
    }

    static func landing(for segment: PFSegment) -> Landing {
        switch segment {
        case .today: return .today
        case .coach: return .coach
        case .week: return .calendar(.thisWeek)
        case .insights: return .coach
        case .body: return .health(.body)
        }
    }
}

/// One chip's content with its mount time in the breadcrumbs: the time from the moment the chip was chosen (this view is built then)
/// to its first appearance, and to the first pass after it, so a report shows which chip is heavy.
struct UnifiedChipMount: View {
    let host: String
    let name: String
    let content: AnyView
    @State private var born = DispatchTime.now().uptimeNanoseconds

    var body: some View {
        content
            .onAppear {
                let label = "\(host).\(name)"
                let started = born
                NoopDiag.screen("nav.\(label)")
                let first = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
                NoopDiag.crumb("nav.chip.mount \(label)", ["ms": first.rounded()])
                NoopPerfStats.shared.section("nav.chip.mount.\(label)", ms: first, onMain: true)
                DispatchQueue.main.async {
                    let settled = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
                    NoopDiag.crumb("nav.chip.settled \(label)", ["ms": settled.rounded()])
                }
            }
    }
}

/// The one PaceForge model the tabs share. A plain static, created on first use.
@MainActor
enum PFUnified {
    static let model = PFModel()
}
#endif
