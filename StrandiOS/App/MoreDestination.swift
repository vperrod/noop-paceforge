#if os(iOS)
import SwiftUI
import StrandDesign

// The "More" rows at the end of Reports and Body: the screens that are not tabs. A row pushes a VALUE, so a re-tap of the tab can pop it
// off the tab's bound path (#135/#198). My Day, Sleep, Workouts, Lift Log, Health and Stress already have `TabRoute` values; the
// screens below do not, so they have their own, registered once per tab stack (`moreDestinations()`).

enum MoreDestination: String, Hashable {
    case athlete, rhythm, alarms, data, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .athlete: AthleteHostView()
        case .rhythm: RhythmHost()
        case .alarms: SmartAlarmView()
        case .data: DataHubView()
        case .settings: SettingsView()
        }
    }
}

extension View {
    /// Resolves every `MoreDestination` push. Each destination keeps the per-screen wrapper the More list used to apply (surfaceBase
    /// background, inline title bar, hidden bar background: #1027, a pushed sky-scaffold screen draws a full-bleed liquid sky, and an
    /// opaque nav-bar band sat over it and clipped the top on scroll). The screen's own container identifier is `screen-<destination>`.
    func moreDestinations() -> some View {
        navigationDestination(for: MoreDestination.self) { route in
            route.destination
                .containerIdentifier("screen-\(route.rawValue)")
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

/// The end of Reports: the daily-record screens.
struct ReportsMoreRows: View {
    var body: some View {
        IndexSection("More") {
            IndexRow("My Day", "calendar.day.timeline.left", TabRoute.myDay, id: "more-row-myday")
            IndexRow("Sleep", "bed.double", TabRoute.sleep, id: "more-row-sleep")
            IndexRow("Workouts", "figure.run", TabRoute.workouts, id: "more-row-workouts")
        }
        .containerIdentifier("reports-more-rows")
    }
}

/// The end of Body: Athlete, the body screens, Data and Settings.
struct BodyMoreRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("More") {
                IndexRow("Athlete", "person.crop.circle", MoreDestination.athlete, id: "more-row-athlete")
                IndexRow("Lift Log", "dumbbell.fill", TabRoute.liftLog, id: "more-row-liftlog")
                IndexRow("Health", "heart.text.square.fill", TabRoute.health, id: "more-row-health")
                IndexRow("Stress", "bolt.heart.fill", TabRoute.stress, id: "more-row-stress")
                // Experimental beat-to-beat regularity visualization: self-gates on its own consent.
                IndexRow("Rhythm", "waveform.path", MoreDestination.rhythm, id: "more-row-rhythm")
                // #805/#811: the single "Alarms" entry, routed to SmartAlarmView, the cross-platform surface.
                IndexRow("Alarms", "alarm.fill", MoreDestination.alarms, id: "more-row-alarms")
            }
            IndexSection("App") {
                IndexRow("Data", "externaldrive.fill", MoreDestination.data, id: "more-row-data")
                IndexRow("Settings", "gearshape.fill", MoreDestination.settings, id: "more-row-settings")
            }
        }
        .containerIdentifier("body-more-rows")
    }
}
#endif
