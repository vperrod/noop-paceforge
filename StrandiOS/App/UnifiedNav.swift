#if os(iOS)
import SwiftUI
import StrandDesign

// The navigation: five tabs in the floating bar, Today, Plan, Coach, Reports and Body (tags 0 to 4). It is the only navigation; the
// earlier classic five-tab map and the Settings switch that chose between them are gone.
//
// - Plan opens on This week; Calendar and Season are its other chips (Workouts live inside Calendar; Events and HYROX are sections at
//   the top of Season).
// - Reports has two chips: Reports (the index: Day, Week, Month, Race) and Insights. My Day, Sleep and Workouts are "More" rows at its
//   end.
// - Body has the Body and Lab Book chips; Athlete, Lift Log, Health, Stress, Rhythm, Alarms, Data and Settings are "More" rows at its end.
// - Sleep also opens from the Rest ring on Today (a push over the tab on show), and My Day from `noop://myday`.
//
// Built small on purpose (builds 465 to 478): every chip is its own small view, only the selected chip of a tab is mounted, nothing
// here reads a live strap value, there is no GeometryReader, ViewThatFits or preference key, and PaceForge's core is never called
// from here: every PaceForge chip reads the snapshot PFModel already built.

enum UnifiedNav {
    static let todayTab = 0
    static let planTab = 1
    static let coachTab = 2
    static let reportsTab = 3
    static let bodyTab = 4

    /// A launch always opens every tab on its first chip, never on one remembered from a previous run (a heavy chip left selected is
    /// what must not be the first thing a restart mounts).
    static func captureAtLaunch() {
        let defaults = UserDefaults.standard
        defaults.set(CalendarChip.thisWeek.rawValue, forKey: CalendarChip.storageKey)
        defaults.set(InsightsChip.overview.rawValue, forKey: InsightsChip.storageKey)
        defaults.set(BodyChip.body.rawValue, forKey: BodyChip.storageKey)
        defaults.set(ReportsChip.reports.rawValue, forKey: ReportsChip.storageKey)
        // The retired switch and the retired Day-tab preference: a stored value must not outlive the code that read it.
        defaults.removeObject(forKey: "unifiedNav")
        defaults.removeObject(forKey: "unifiedDay")
        NoopDiag.crumb("nav.unified enabled")
    }

    /// The bar, in tag order. The ids are the lower-cased titles, which is what the UI tests look for (`look-tab-<id>`).
    static let tabs: [LookTabItem] = [
        LookTabItem(id: "today", title: "Today", symbol: "square.grid.2x2"),
        LookTabItem(id: "plan", title: "Plan", symbol: "calendar"),
        LookTabItem(id: "coach", title: "Coach", symbol: "sparkles"),
        LookTabItem(id: "reports", title: "Reports", symbol: "doc.text"),
        LookTabItem(id: "body", title: "Body", symbol: "figure.stand"),
    ]

    /// Where an old PaceForge link (widget, notification, `noop://paceforge/...`, the Home Screen menu) lands.
    enum Landing: Equatable {
        case today
        case calendar(CalendarChip)
        case insights(InsightsChip)
        case coach
        case body
    }

    static func landing(for segment: PFSegment) -> Landing {
        switch segment {
        case .today: return .today
        case .coach: return .coach
        case .week: return .calendar(.thisWeek)
        case .insights: return .insights(.overview)
        case .body: return .body
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
