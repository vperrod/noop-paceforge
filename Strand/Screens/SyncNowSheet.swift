import SwiftUI
import StrandDesign

/// The strap sync sheet behind the sync indicator on Today and the sync button on the PaceForge tab: when the strap
/// last synced, live progress while it runs, a "Sync now" button, and a plain sentence for whatever the tap did or why it
/// could not start (strap not found, Bluetooth off, permission). One tap from either screen.
struct SyncNowSheet: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss

    /// What the last tap said; cleared when a sync finishes so the status line below tells the result.
    @State private var outcome: BLEManager.SyncNowOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text("Strap sync")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)

            HStack(spacing: 10) {
                if isSyncing {
                    ProgressView()
                }
                statusText
                    .font(StrandFont.body)
                    .foregroundStyle(failureLine == nil ? StrandPalette.textPrimary : StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isSyncing {
                // Re-read every 30 s: with a steady heart rate nothing else re-renders the sheet, and "2 min ago" must not stand still.
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(freshness.details, id: \.self) { line in
                            Text(line)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let error = live.lastSyncError, !isSyncing, failureLine == nil {
                Text(error)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = outcomeMessage {
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NoopButton(isSyncing ? "Syncing…" : "Sync now",
                       systemImage: "arrow.triangle.2.circlepath",
                       kind: .primary, fullWidth: true) {
                #if os(iOS)
                NoopDiag.crumb("syncsheet.tap", ["backfilling": live.backfilling ? 1 : 0, "connected": live.connected ? 1 : 0])
                #endif
                outcome = model.ble.syncNowReporting()
            }
            .disabled(isSyncing)
            .accessibilityIdentifier("sync-now-button")

            if isSyncing {
                NoopButton("Stop sync", systemImage: "stop.circle", kind: .secondary, fullWidth: true) {
                    #if os(iOS)
                    NoopDiag.crumb("syncsheet.stop", ["chunks": Double(live.syncTotalChunks)])
                    #endif
                    model.ble.cancelSync()
                }
                .accessibilityIdentifier("sync-stop-button")
            }

            NoopButton("Manage devices", kind: .tertiary, fullWidth: true) {
                dismiss()
                router.openDevices()
            }
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
        #if os(iOS)
        .onAppear {
            NoopDiag.crumb("syncsheet.open @\(NoopDiag.currentLabels.screen)",
                           ["backfilling": live.backfilling ? 1 : 0, "connected": live.connected ? 1 : 0,
                            "has_error": live.lastSyncError != nil ? 1 : 0])
        }
        #endif
        .onChangeCompat(of: isSyncing) { isSyncing in
            #if os(iOS)
            NoopDiag.crumb(isSyncing ? "syncsheet.sync_running" : "syncsheet.sync_stopped",
                           ["has_error": live.lastSyncError != nil ? 1 : 0, "chunks": Double(live.syncChunksThisSession)])
            #endif
            if isSyncing { outcome = nil }
        }
    }

    /// A logical sync is open (it spans the gaps between chained offload sessions, where `backfilling` flickers).
    private var isSyncing: Bool { live.backfilling || live.syncStartedAt != nil }

    /// Set when the last sync ended on a hard cap or the strap going quiet; the status line then says so.
    private var failureLine: String? {
        guard !isSyncing else { return nil }
        switch live.lastSyncEndReason {
        case "stalled": return String(localized: "Sync failed: no new data from the strap for 12 minutes")
        case "max_duration": return String(localized: "Sync failed: stopped after 45 minutes")
        case "no_response": return String(localized: "Sync failed: the strap went quiet before sending anything")
        default: return nil
        }
    }

    /// "Syncing n chunks · mm:ss" ticks once a second while a sync runs; otherwise the static outcome line.
    @ViewBuilder private var statusText: some View {
        if isSyncing, let started = live.syncStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince1970 - started))
                let n = max(live.syncTotalChunks, live.syncChunksThisSession)
                let clock = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
                Text(n > 0 ? String(localized: "Syncing \(n) chunks · \(clock)") : String(localized: "Syncing strap history… · \(clock)"))
            }
        } else {
            Text(statusLine)
        }
    }

    private var statusLine: String {
        if isSyncing {
            let n = max(live.syncTotalChunks, live.syncChunksThisSession)
            return n > 0 ? String(localized: "Syncing strap history… \(n) chunks") : String(localized: "Syncing strap history…")
        }
        if let failureLine { return failureLine }
        return freshness.headline
    }

    private var freshness: StrapDataFreshness.Lines {
        StrapDataFreshness.lines(connected: live.connected, lastSyncedAt: live.lastSyncedAt,
                                 lastSampleAt: live.lastSampleAt, now: Date().timeIntervalSince1970)
    }

    private var outcomeMessage: String? {
        switch outcome {
        case .none, .started, .alreadyRunning:
            return nil
        case .waitingForStrap:
            return String(localized: "Strap not connected. Looking for it now; the sync starts as soon as it answers. Keep it close and charged.")
        case .linkStillSettingUp:
            return String(localized: "The strap is connected but still setting up. The sync starts automatically when it is ready.")
        case .bluetoothOff:
            return String(localized: "Bluetooth is off. Turn it on in Settings or Control Center, then tap Sync now.")
        case .bluetoothDenied:
            return String(localized: "NOOP is not allowed to use Bluetooth. Open iPhone Settings > NOOP and switch Bluetooth on.")
        case .bluetoothUnsupported:
            return String(localized: "This device cannot use Bluetooth Low Energy.")
        case .otherDeviceActive:
            return String(localized: "Your ring is the active device, so there is no strap to sync. Switch devices in Manage devices.")
        }
    }
}

/// A compact header button that opens the sync sheet: a sync glyph, a spinner while an offload runs. Used on the PaceForge
/// tab; Today opens the same sheet from its battery/sync indicator.
struct SyncNowButton: View {
    @State private var isPresented = false
    @EnvironmentObject private var live: LiveState

    var body: some View {
        Button { isPresented = true } label: {
            ZStack {
                if live.backfilling {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync strap")
        .accessibilityHint("Shows when the strap last synced and lets you sync now.")
        .accessibilityIdentifier("sync-strap-button")
        .sheet(isPresented: $isPresented) { SyncNowSheet() }
    }
}

/// How fresh the strap's data is. A completed history sync is rare; live samples arrive continuously while the strap is
/// connected, so "last synced" alone read as stale beside data that was plainly arriving. The newest of the two is the
/// freshness, and a history sync is only mentioned separately once it is old. Pure, so the edges are unit-testable.
enum StrapDataFreshness {
    /// No strap sample at all for this long while connected is stale.
    static let staleAfter: TimeInterval = 15 * 60
    /// A live sample this recent means the strap is streaming right now.
    static let liveWithin: TimeInterval = 30

    struct Lines: Equatable {
        var headline: String
        var details: [String]
    }

    static func newest(lastSyncedAt: TimeInterval?, lastSampleAt: TimeInterval?) -> TimeInterval? {
        [lastSyncedAt, lastSampleAt].compactMap { $0 }.max()
    }

    static func lines(connected: Bool, lastSyncedAt: TimeInterval?, lastSampleAt: TimeInterval?, now: TimeInterval) -> Lines {
        let latest = newest(lastSyncedAt: lastSyncedAt, lastSampleAt: lastSampleAt)
        let isLive = connected && lastSampleAt.map { now - $0 <= liveWithin } == true
        var details: [String] = []

        let headline: String
        if isLive {
            headline = String(localized: "Connected, live")
        } else if let latest {
            headline = String(localized: "Latest strap data \(relativeAgo(latest, now: now))")
        } else {
            headline = String(localized: "No strap data yet")
        }

        if !connected {
            details.append(String(localized: "Strap not connected"))
        } else if let latest, now - latest > staleAfter {
            details.append(String(localized: "Stale: no strap data in the last 15 minutes"))
        }
        // Only when it adds something: older than the stale window, and not the very time the headline already states.
        if let sync = lastSyncedAt, now - sync > staleAfter, sync != latest {
            details.append(String(localized: "Last full history sync \(relativeAgo(sync, now: now))"))
        }
        return Lines(headline: headline, details: details)
    }
}
