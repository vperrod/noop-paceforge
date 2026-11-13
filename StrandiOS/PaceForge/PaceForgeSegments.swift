import SwiftUI
import StrandDesign

/// The PaceForge sections an old link (widget, notification, `noop://paceforge/...`, the Home Screen menu) names. The unified shell has no
/// PaceForge tab: `UnifiedNav.landing(for:)` maps each to the screen that holds it.
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

/// The Body screen while Settings > Hide numbers hides body weight and body fat.
struct PFBodyHiddenView: View {
    var body: some View {
        PFCard("Body", icon: "figure.stand") {
            PFParagraph("\(HideScoresPrefs.placeholder) \u{2014} body weight and body fat are hidden. Tap the eye above to show them, or turn this off in Settings > Hide numbers.")
        }
        .containerIdentifier("pf-body-hidden")
    }
}

/// Refreshes the heart-rate-recovery summary when the tab opens. It lives in its own view because it needs `Repository` and
/// `ProfileStore` only to read them once: as `@EnvironmentObject`s on `PaceForgeTabView` they re-evaluated the whole tab
/// (every card in it) on each of their publishes, none of which changes what the tab shows.
struct PFHeartRecoveryTask: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task { await PFHeartRecovery.updateSummary(repo: repo, hrMax: profile.hrMax) }
    }
}
