import WidgetKit
import SwiftUI

/// The widget extension entry point. Bundles the glanceable widget, the live-HR Live Activity,
/// the K10 Coach brief widget (stored morning brief on Lock Screen / Home Screen), the
/// heart-rate trace widget (#1957), the stress curve widget (#2040), the Lift Log session
/// Live Activity, the strap-sync Live Activity, the PaceForge widgets and control, the My Day widget and the Effort target widget.
@main
struct NOOPWidgetBundle: WidgetBundle {
    var body: some Widget {
        NOOPWidget()
        NOOPLiveActivity()
        CoachBriefWidget()
        HeartRateWidget()
        StressWidget()
        LiftLiveActivity()
        SyncLiveActivity()
        PaceForgeTodayWidget()
        PaceForgeSessionWidget()
        PaceForgeRaceWidget()
        PaceForgeRecoveryGaugeWidget()
        PaceForgeStrainGaugeWidget()
        PaceForgeWeekWidget()
        PaceForgeSleepHrvWidget()
        PaceForgeLoadWidget()
        PaceForgeBodyWidget()
        PaceForgeHeartRecoveryWidget()
        MyDayWidget()
        EffortTargetWidget()
        if #available(iOS 18.0, *) {
            PaceForgeTodayControl()
        }
    }
}
