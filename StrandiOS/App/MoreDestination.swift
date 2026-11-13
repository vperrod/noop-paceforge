#if os(iOS)
import SwiftUI
import StrandDesign

// The screens that rows inside the Health chips open: Alarms and Rhythm (under Sleep) and the Lab Book (under Body). A row pushes a
// VALUE, so a re-tap of the tab can pop it off the tab's bound path (#135/#198). Settings and the Data hub are opened from the avatar on
// Today (Settings > Tools > Data). These destinations have no `TabRoute` value, so they have their own, registered once per tab stack
// (`moreDestinations()`).

enum MoreDestination: String, Hashable {
    case rhythm, alarms, labBook, data, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .rhythm: RhythmHost()
        case .alarms: SmartAlarmView()
        case .labBook: LabBookView()
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
#endif
