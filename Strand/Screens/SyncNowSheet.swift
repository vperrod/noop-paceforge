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
    @State private var finishedJustNow = false

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text("Strap sync")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)

            HStack(spacing: 10) {
                if live.backfilling {
                    ProgressView()
                }
                Text(statusLine)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = live.lastSyncError, !live.backfilling {
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

            NoopButton(live.backfilling ? "Syncing…" : "Sync now",
                       systemImage: "arrow.triangle.2.circlepath",
                       kind: .primary, fullWidth: true) {
                finishedJustNow = false
                outcome = model.ble.syncNowReporting()
            }
            .disabled(live.backfilling)
            .accessibilityIdentifier("sync-now-button")

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
        .onChangeCompat(of: live.backfilling) { isSyncing in
            if isSyncing {
                outcome = nil
                finishedJustNow = false
            } else {
                finishedJustNow = true
            }
        }
    }

    private var statusLine: String {
        if live.backfilling {
            let n = live.syncChunksThisSession
            return n > 0 ? String(localized: "Syncing strap history… \(n) chunks") : String(localized: "Syncing strap history…")
        }
        if let ts = live.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let ago = formatter.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
            let prefix = finishedJustNow && live.lastSyncError == nil ? String(localized: "Sync finished. ") : ""
            return prefix + String(localized: "Last synced \(ago)")
        }
        return String(localized: "No completed sync yet")
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
