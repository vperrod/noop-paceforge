#if os(iOS)
import SwiftUI
import StrandDesign

// The unified navigation consolidates PaceForge sections while keeping daily essentials visible.
// With the switch on, tabs are Today, Training, Sleep, Insights and More, with the single Coach button at
// the end of the bar. Training opens on Workouts; Calendar and Plan remain one tap away. The switch is
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
        defaults.set(CalendarChip.workouts.rawValue, forKey: CalendarChip.storageKey)
        defaults.set(InsightsChip.overview.rawValue, forKey: InsightsChip.storageKey)
        defaults.set(BodyChip.body.rawValue, forKey: BodyChip.storageKey)
        NoopDiag.crumb("nav.unified enabled")
    }

    /// Tab tags are the ones the shell has always used (0 Today, 1 second, 2 Day, 3 fourth, 4 More), so the per-tab paths, the scroll
    /// signals and the swipe between tabs need no change.
    static let calendarTab = 1
    static let insightsTab = 3
    static let moreTab = 4

    /// The second tab remains Training in both navigation modes; Workouts is its first screen.
    static var secondTabTitle: LocalizedStringKey { isOn ? "Training" : "Workouts" }
    static var secondTabIcon: String { "figure.run" }
    static var fourthTabTitle: LocalizedStringKey { isOn ? "Insights" : "PaceForge" }
    static var fourthTabIcon: String { isOn ? "chart.line.uptrend.xyaxis" : "figure.run" }

    /// The tab bar with the switch on.
    static let tabs: [LookTabItem] = [
        LookTabItem(id: "today", title: "Today", symbol: "square.grid.2x2"),
        LookTabItem(id: "training", title: "Training", symbol: "figure.run"),
        LookTabItem(id: "sleep", title: "Sleep", symbol: "bed.double"),
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
            Text("Tabs are Today, Training, Sleep, Insights and More, with one Coach button at the end of the bar. Workouts opens first in Training; Calendar and Plan are one tap away. Restart NOOP to apply a change.")
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
