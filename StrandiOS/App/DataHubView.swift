#if os(iOS)
import SwiftUI
import StrandDesign

/// The one Data screen: where NOOP's numbers come from and where they go. Eight rows of the old More list are sections of it (Data
/// Sources, Apple Health, Mi Band, Your Data Fused, Backup & Sync, PaceForge sync, Shortcuts Export, NOOP Limitations), each the
/// content of the screen it replaces, drawn under the section chips (they hand their scaffold's scrolling to this screen).
struct DataHubView: View {
    enum Part: String, CaseIterable, Identifiable {
        case sources, appleHealth, miBand, fused, backup, paceForge, shortcuts, limitations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sources: return "Data Sources"
            case .appleHealth: return "Apple Health"
            case .miBand: return "Mi Band"
            case .fused: return "Fused"
            case .backup: return "Backup & Sync"
            // PaceForge's one-way push of NOOP's metrics (NOOP's own numbers, sent as NOOP's, never merged with Garmin's).
            case .paceForge: return "PaceForge sync"
            // #155: HealthKit-free Apple Health path for sideloaded installs (a Siri Shortcut reads the opt-in drop file).
            case .shortcuts: return "Shortcuts"
            // The plain 4.0 vs 5.0/MG capability grid: what NOOP reads live off each strap.
            case .limitations: return "Limitations"
            }
        }
    }

    @State private var section: Part

    init(initial: Part = .sources) {
        _section = State(initialValue: initial)
    }

    var body: some View {
        ScreenScaffold(title: "Data", subtitle: "Sources, devices, backup and sync",
                       topBackground: liquidScaffoldSky()) {
            VStack(alignment: .leading, spacing: 16) {
                SectionChips(options: Part.allCases, selection: $section, idPrefix: "data-section",
                             id: { $0.rawValue }, title: { $0.title })
                content
                    .environment(\.screenScaffoldEmbedded, true)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .sources: DataSourcesView()
        case .appleHealth: AppleHealthView()
        case .miBand: XiaomiBandView()
        case .fused: FusedRecordHost()
        case .backup: BackupSyncView()
        case .paceForge: SelfHostedPushSettingsView()
        case .shortcuts: ShortcutExportSettingsView()
        case .limitations: NoopLimitationsView()
        }
    }
}
#endif
