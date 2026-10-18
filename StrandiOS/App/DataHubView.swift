#if os(iOS)
import SwiftUI
import StrandDesign

/// The one Data screen: where NOOP's numbers come from and where they go. It replaces eight rows of the More list (Your Data Fused,
/// Apple Health, Mi Band, Data Sources, Backup & Sync, Shortcuts Export, PaceForge sync, NOOP Limitations); each opens the same
/// screen it always did, one tap from here.
struct DataHubView: View {
    private enum Route: Hashable {
        case dataSources, appleHealth, miBand, fused
        case backupSync, selfHostedPush, shortcutsExport
        case limitations

        @ViewBuilder var destination: some View {
            switch self {
            case .dataSources: DataSourcesView()
            case .appleHealth: AppleHealthView()
            case .miBand: XiaomiBandView()
            case .fused: FusedRecordHost()
            case .backupSync: BackupSyncView()
            case .selfHostedPush: SelfHostedPushSettingsView()
            case .shortcutsExport: ShortcutExportSettingsView()
            case .limitations: NoopLimitationsView()
            }
        }
    }

    var body: some View {
        ScreenScaffold(title: "Data", subtitle: "Sources, devices, backup and sync",
                       topBackground: liquidScaffoldSky()) {
            IndexSection("Sources and devices") {
                IndexRow("Data Sources", "externaldrive.fill", Route.dataSources, id: "data-row-sources")
                IndexRow("Apple Health", "heart.fill", Route.appleHealth, id: "data-row-applehealth")
                IndexRow("Mi Band", "figure.walk.motion", Route.miBand, id: "data-row-miband")
                IndexRow("Your Data, Fused", "square.stack.3d.up.fill", Route.fused, id: "data-row-fused")
            }
            IndexSection("Backup and sync") {
                IndexRow("Backup & Sync", "externaldrive.fill.badge.icloud", Route.backupSync, id: "data-row-backup")
                // PaceForge's one-way push of NOOP's metrics (NOOP's own numbers, sent as NOOP's, never merged with Garmin's).
                IndexRow("PaceForge sync", "arrow.left.arrow.right.circle.fill", Route.selfHostedPush, id: "data-row-paceforge-sync")
                // #155: HealthKit-free Apple Health path for sideloaded installs (Siri Shortcut reads the opt-in drop file).
                IndexRow("Shortcuts Export", "square.and.arrow.up.fill", Route.shortcutsExport, id: "data-row-shortcuts")
            }
            IndexSection("About the data") {
                // The plain 4.0 vs 5.0/MG capability grid: what NOOP reads live off each strap.
                IndexRow("NOOP Limitations", "list.bullet.rectangle", Route.limitations, id: "data-row-limitations")
            }
        }
        .navigationDestination(for: Route.self) { route in
            route.destination
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
#endif
