#if os(iOS)
import SwiftUI
import StrandDesign

// The opt-in "New navigation (beta)" (stages 3 and 4 of the app redesign). Off by default: with the switch off every tab and screen is
// the one build 480 has. On, the tab bar is Today, Calendar, Day, Insights and More, with the Coach as the button at the end of the
// bar (it opens CoachUnifiedView). There is no PaceForge, Trends or Sleep tab: their screens are chips of the new tabs.
// The switch is read once, at launch, so a change applies after the app is restarted. It implies the Day tab (UnifiedDay).
//
// Built small on purpose (builds 465 to 478): every chip is its own small view, only the selected chip of a tab is mounted, nothing
// here reads a live strap value, there is no GeometryReader, ViewThatFits or preference key, and PaceForge's core is never called
// from here: every PaceForge chip reads the snapshot PFModel already built.

enum UnifiedNav {
    static let defaultsKey = "unifiedNav"

    /// Read once per launch; the Settings switch only writes the preference.
    static let isOn: Bool = UserDefaults.standard.bool(forKey: defaultsKey)

    /// Called from the app's init. A launch always opens every tab on its first chip, never on one remembered from a previous run
    /// (a heavy chip left selected is what must not be the first thing a restart mounts).
    static func captureAtLaunch() {
        guard isOn else { return }
        let defaults = UserDefaults.standard
        defaults.set(CalendarChip.calendar.rawValue, forKey: CalendarChip.storageKey)
        defaults.set(InsightsChip.overview.rawValue, forKey: InsightsChip.storageKey)
        defaults.set(CoachChip.coach.rawValue, forKey: CoachChip.storageKey)
        defaults.set(BodyChip.body.rawValue, forKey: BodyChip.storageKey)
        NoopDiag.crumb("nav.unified enabled")
    }

    /// Tab tags are the ones the shell has always used (0 Today, 1 second, 2 Day, 3 fourth, 4 More), so the per-tab paths, the scroll
    /// signals and the swipe between tabs need no change.
    static let calendarTab = 1
    static let insightsTab = 3
    static let moreTab = 4

    /// The titles and icons of the two tabs the switch renames (Trends becomes Calendar, PaceForge becomes Insights).
    static var secondTabTitle: LocalizedStringKey { isOn ? "Calendar" : "Trends" }
    static var secondTabIcon: String { isOn ? "calendar.badge.clock" : "chart.line.uptrend.xyaxis" }
    static var fourthTabTitle: LocalizedStringKey { isOn ? "Insights" : "PaceForge" }
    static var fourthTabIcon: String { isOn ? "chart.line.uptrend.xyaxis" : "figure.run" }

    /// The tab bar with the switch on.
    static let tabs: [LookTabItem] = [
        LookTabItem(id: "today", title: "Today", symbol: "square.grid.2x2"),
        LookTabItem(id: "calendar", title: "Calendar", symbol: "calendar.badge.clock"),
        LookTabItem(id: "day", title: "Day", symbol: "calendar"),
        LookTabItem(id: "insights", title: "Insights", symbol: "chart.line.uptrend.xyaxis"),
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

/// Settings > Tools > New navigation (beta).
struct UnifiedNavToggle: View {
    @AppStorage(UnifiedNav.defaultsKey) private var isEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isEnabled) {
                Text("New navigation (beta)")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(StrandPalette.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings-tool-unifiednav")
            Text("Tabs become Today, Calendar, Day, Insights and More, with the Coach on the button at the end of the bar. PaceForge, Trends and Sleep move into them. Includes the Day tab. Off keeps the tabs you have today. Restart NOOP to apply a change.")
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
