#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Look: Today pieces
//
// The iPhone Today pieces that sit on the look components: the Health and Stress monitor tiles. Each reads the same data the rest of Today reads; nothing here scores
// or stores anything.

// MARK: Health monitor

/// Health monitor tile. With PaceForge's daily-intel.json it reads each vital against its own 30-day range:
/// "WITHIN RANGE · 4/4 metrics", or the worst vital ("VERY ELEVATED · Respiratory rate") in red. Without it (PaceForge not
/// set up or not reachable) it keeps to what the illness early-warning already knows: red when it has raised an alert, calm
/// otherwise. Either way it opens the one Health screen, which carries the monitor at its top.
/// Its own leaf, because it observes AppModel (see HealthAlertBanner for why that is kept out of Today's body).
struct LookHealthTile: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var intelStore = PFDailyIntelStore.shared

    /// Today's tile text from the server, when the file is today's and the Health monitor has vitals.
    private var monitorTile: PFHealthTile? { intelStore.current?.health?.tile }

    var body: some View {
        NavigationLink(value: TabRoute.health) { tile }
            .buttonStyle(.plain)
            .accessibilityIdentifier("look-health-tile")
            .task { await intelStore.refreshIfStale() }
    }

    @ViewBuilder private var tile: some View {
        if let monitor = monitorTile {
            PFHealthMonitorTile(tile: monitor)
        } else if let alert = model.healthAlert {
            MonitorTile(title: String(localized: "Health monitor"), badge: .symbol("exclamationmark"),
                        badgeForeground: Color(hex: "#E8505A"), badgeBackground: NoopLook.alertWash,
                        status: String(localized: "ELEVATED"), statusColor: NoopLook.alert,
                        detail: alert.firedSignals.first ?? String(localized: "Body looks strained"))
        } else {
            MonitorTile(title: String(localized: "Health monitor"), badge: .symbol("checkmark"),
                        badgeForeground: NoopLook.trendUp, badgeBackground: NoopLook.trendUp.opacity(0.16),
                        status: String(localized: "NO ALERTS"), statusColor: NoopLook.trendUp,
                        detail: String(localized: "Signals look typical"))
        }
    }
}

// MARK: Stress monitor

struct LookStressTile: View {
    /// Stress score 0-3, or nil while the baseline is still building.
    let score: Double?

    var body: some View {
        // The one Stress screen, which leads with the monitor (reading, day line, honest empty state).
        NavigationLink(value: TabRoute.stress) { tile }
            .buttonStyle(.plain)
            .accessibilityIdentifier("look-stress-tile")
    }

    @ViewBuilder private var tile: some View {
        if let value = score {
            let level = LookStressLevel.forScore(value)
            let color = NoopLook.color(for: level)
            MonitorTile(title: String(localized: "Stress monitor"),
                        badge: .text(String(format: "%.1f", locale: AppLanguage.activeLocale, value)),
                        badgeForeground: color, badgeBackground: color.opacity(0.2),
                        status: level.label, statusColor: color, detail: String(localized: "Scale 0 to 3"))
        } else {
            MonitorTile(title: String(localized: "Stress monitor"), badge: .symbol("hourglass"),
                        badgeForeground: NoopLook.textTertiary, badgeBackground: NoopLook.track,
                        status: String(localized: "CALIBRATING"), statusColor: NoopLook.textTertiary,
                        detail: String(localized: "Needs more worn nights"))
        }
    }
}
#endif
