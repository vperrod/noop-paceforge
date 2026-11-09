#if os(iOS)
import SwiftUI
import StrandDesign

// The unified navigation consolidates PaceForge sections while keeping daily essentials visible.
// With the switch on, the bar is a scrolling strip of Today, My Day, Plan, Athlete, Sleep, Insights, Workouts and More, with the single
// Coach button beside it. Plan opens on Plan; Calendar is its second chip and Workouts, Season, Events and HYROX are the others.
// The system tab view still holds five tabs (tags 0 Today, 1 My Day, 2 Plan, 3 Athlete, 4 More): Sleep, Insights and Workouts are bar items
// that open as the only screen pushed on More's stack, and the Rest ring on Today also opens Sleep over the tab on show. The switch is
// read once at launch, so a change applies after the app is restarted.
//
// Built small on purpose (builds 465 to 478): every chip is its own small view, only the selected chip of a tab is mounted, nothing
// here reads a live strap value, there is no GeometryReader, ViewThatFits or preference key, and PaceForge's core is never called
// from here: every PaceForge chip reads the snapshot PFModel already built.

enum UnifiedNav {
    static let defaultsKey = "unifiedNav"

    /// Read once per launch. A saved user choice wins; installs that have never seen this preference
    /// get the simplified navigation by default.
    static let isOn: Bool = UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true

    /// Called from the app's init. A launch always opens every tab on its first chip, never on one remembered from a previous run
    /// (a heavy chip left selected is what must not be the first thing a restart mounts).
    static func captureAtLaunch() {
        guard isOn else { return }
        let defaults = UserDefaults.standard
        defaults.set(CalendarChip.plan.rawValue, forKey: CalendarChip.storageKey)
        defaults.set(InsightsChip.overview.rawValue, forKey: InsightsChip.storageKey)
        defaults.set(BodyChip.body.rawValue, forKey: BodyChip.storageKey)
        NoopDiag.crumb("nav.unified enabled")
    }

    /// Tab tags are the ones the shell has always used (0 Today, 1 second, 2 third, 3 fourth, 4 More), so the per-tab paths, the scroll
    /// signals and the swipe between tabs need no change. With the switch on the second tab is My Day, the third is Plan and the fourth
    /// is Athlete. Sleep, Insights and Workouts have no tab: `moreBarIDs` open on More.
    static let myDayTab = 1
    static let calendarTab = 2
    static let athleteTab = 3
    static let moreTab = 4

    /// The second tab is My Day with the switch on; Workouts is the classic tab.
    static var secondTabTitle: LocalizedStringKey { isOn ? "My Day" : "Workouts" }
    static var secondTabIcon: String { isOn ? "calendar.day.timeline.left" : "figure.run" }
    /// The third tab is Plan with the switch on (it opens on the Plan chip).
    static var thirdTabTitle: LocalizedStringKey { isOn ? "Plan" : UnifiedDay.tabTitle }
    static var thirdTabIcon: String { isOn ? "calendar" : UnifiedDay.tabIcon }
    static var fourthTabTitle: LocalizedStringKey { isOn ? "Athlete" : "PaceForge" }
    static var fourthTabIcon: String { isOn ? "person.crop.circle" : "figure.run" }

    /// The bar items that are not tabs: each opens its screen as the only one pushed on the More tab.
    static let moreBarIDs: Set<String> = ["sleep", "insights", "workouts"]

    /// The bar with the switch on. The first four items are the tabs with tags 0 to 3, the More item is tag 4, and the three in between
    /// are `moreBarIDs`.
    static let tabs: [LookTabItem] = [
        LookTabItem(id: "today", title: "Today", symbol: "square.grid.2x2"),
        LookTabItem(id: "my day", title: "My Day", symbol: "calendar.day.timeline.left"),
        LookTabItem(id: "plan", title: "Plan", symbol: "calendar"),
        LookTabItem(id: "athlete", title: "Athlete", symbol: "person.crop.circle"),
        LookTabItem(id: "sleep", title: "Sleep", symbol: "bed.double"),
        LookTabItem(id: "insights", title: "Insights", symbol: "chart.line.uptrend.xyaxis"),
        LookTabItem(id: "workouts", title: "Workouts", symbol: "figure.run"),
        LookTabItem(id: "more", title: "More", symbol: "ellipsis"),
    ]

    /// Where an old PaceForge link (widget, notification, `noop://paceforge/...`, the Home Screen menu) lands with the switch on.
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
        case .week: return .calendar(.plan)
        case .insights: return .insights(.overview)
        case .body: return .body
        }
    }
}

/// Settings > Tools > Unified navigation.
struct UnifiedNavToggle: View {
    @AppStorage(UnifiedNav.defaultsKey) private var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isEnabled) {
                Text("Unified navigation")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(StrandPalette.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings-tool-unifiednav")
            Text("The bar scrolls: Today, My Day, Plan, Athlete, Sleep, Insights, Workouts and More, with one Coach button beside it. Plan opens first; Calendar is its second chip. Sleep also opens from the Rest ring on Today. Restart NOOP to apply a change.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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

/// The one PaceForge model the flag-on tabs share. A plain static, created on first use, so a launch with the switch off never
/// builds it; the PaceForge tab (switch off) still owns its own.
@MainActor
enum PFUnified {
    static let model = PFModel()
}
#endif
