#if os(iOS)
import SwiftUI
import StrandDesign

/// Gives one chip of the unified navigation the PaceForge snapshot: the lock, the load states (loading, not set up, failed, saved
/// data with a banner), the "Where you stand" and insight sheets, and the environment the PaceForge cards read. It is what
/// PaceForgeTabView does around its five segments, for chips that sit in other tabs. It draws a column only: the tab's host owns the
/// scroll view, the chips and the pull-to-refresh.
///
/// `isPrimary` is true for exactly one host (Insights). Only that one answers the link notifications (`noop://paceforge/standing`,
/// an insight item) and refreshes the heart-recovery summary, so a link opens one sheet, not one per tab. Taps inside any host open
/// their sheets locally.
struct PFSnapshotHost: View {
    var isPrimary = false
    let content: (PFSnapshot) -> AnyView

    @ObservedObject private var model = PFUnified.model
    @ObservedObject private var lock = PFLock.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PFPrefs.lockKey) private var lockEnabled = false
    @State private var showStanding = false
    @State private var insightRoute: PFInsightRoute?

    var body: some View {
        Group {
            if lockEnabled && !lock.isUnlocked {
                PFLockedView(lock: lock)
            } else {
                loaded
            }
        }
        // Locks again as soon as the app leaves the foreground (not on `inactive`, which the Face ID prompt itself causes).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lock.lock()
                PFPeek.shared.isShowing = false
            }
        }
        .onDisappear { PFPeek.shared.isShowing = false }
    }

    private var loaded: some View {
        PFHostPhase(model: model, content: content)
            .environmentObject(model)
            .environment(\.pfOpenStanding, { openStanding() })
            .environment(\.pfOpenInsight, { id in openInsight(id) })
            .sheet(isPresented: $showStanding) { standingSheet }
            .sheet(item: $insightRoute) { route in insightSheet(route.id) }
            .onReceive(NotificationCenter.default.publisher(for: .pfOpenStanding)) { _ in
                guard isPrimary else { return }
                _ = PFStandingLink.consume()
                openStanding()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pfOpenInsight)) { _ in
                guard isPrimary else { return }
                if let id = PFInsightLink.consume() { openInsight(id) }
            }
            .task {
                await model.refreshIfStale()
                if model.phase == .ready { PaceForgeBackground.requestNotificationPermissionOnce() }
                guard isPrimary else { return }
                // A `noop://paceforge/standing` link that arrived before this tab was mounted.
                if await PFStandingLink.consume() { openStanding() }
                if let id = await PFInsightLink.consume() { openInsight(id) }
            }
            .background(HeartRecoveryTaskSlot(isPrimary: isPrimary))
    }

    private func openStanding() {
        if model.snapshot?.standing?.hasContent == true { showStanding = true }
    }

    private func openInsight(_ id: String) {
        if model.snapshot?.insightsV2?.item(id) != nil { insightRoute = PFInsightRoute(id: id) }
    }

    @ViewBuilder private func insightSheet(_ id: String) -> some View {
        if let snapshot = model.snapshot, let item = snapshot.insightsV2?.item(id) {
            PFInsightDetailView(item: item)
                .environmentObject(model)
                .environment(\.pfExplainers, snapshot.explainerMap)
        }
    }

    @ViewBuilder private var standingSheet: some View {
        if let snapshot = model.snapshot, let standing = snapshot.standing {
            PFStandingView(standing: standing)
                .environmentObject(model)
                .environment(\.pfExplainers, snapshot.explainerMap)
        }
    }
}

/// The heart-recovery summary refresh the PaceForge tab does when it opens, once, from the primary host.
private struct HeartRecoveryTaskSlot: View {
    let isPrimary: Bool

    var body: some View {
        if isPrimary { PFHeartRecoveryTask() }
    }
}

/// The load states and, once there is a snapshot, the chip's content. Each branch is a small type; only the chip itself is erased.
private struct PFHostPhase: View {
    @ObservedObject var model: PFModel
    let content: (PFSnapshot) -> AnyView

    var body: some View {
        switch model.phase {
        case .loading:
            PFLoadingView()
        case .notSetUp:
            PFNotSetUpView()
        case .failed(let message):
            PFFailedView(message: message, detail: model.failureDetail, isRetrying: model.isRefreshing) {
                Task { await model.refresh() }
            }
        case .ready:
            PFHostReady(model: model, content: content)
        }
    }
}

private struct PFHostReady: View {
    @ObservedObject var model: PFModel
    let content: (PFSnapshot) -> AnyView

    var body: some View {
        if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: 16) {
                PFRevealBar()
                if let note = model.offlineNote {
                    PFOfflineBanner(text: note, detail: model.failureDetail, isRetrying: model.isRefreshing) {
                        Task { await model.refresh() }
                    }
                }
                content(snapshot)
                    .environment(\.pfExplainers, snapshot.explainerMap)
            }
        }
    }
}
#endif
