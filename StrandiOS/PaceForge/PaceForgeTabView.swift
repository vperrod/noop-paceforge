import SwiftUI
import StrandDesign

/// The five PaceForge screens, in the order the segmented control shows them.
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

/// The PaceForge tab: a large title, a native segmented control and the selected screen,
/// fed by the live PaceForge server (cached on the device for offline).
struct PaceForgeTabView: View {
    @StateObject private var model = PFModel()
    @ObservedObject private var lock = PFLock.shared
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PFPrefs.lockKey) private var lockEnabled = false

    @AppStorage("noop.paceforge.segment") private var segmentRaw = PFSegment.today.rawValue
    @State private var showStanding = false
    @State private var insightRoute: PFInsightRoute?
    @State private var openedAt: UInt64?
    /// Settings > Hide numbers: body weight and body fat. The Body screen then shows a placeholder.
    private let hiding = PFHiding()

    private var segment: Binding<PFSegment> {
        Binding(
            get: { PFSegment(rawValue: segmentRaw) ?? .today },
            set: { segmentRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            let _ = NoopDiag.body("PaceForgeTabView")
            if lockEnabled && !lock.isUnlocked {
                PFLockedView(lock: lock)
            } else {
                content
            }
        }
        // Locks again as soon as the app leaves the foreground (not on `inactive`, which the Face ID
        // prompt itself causes).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lock.lock()
                PFPeek.shared.isShowing = false
            }
        }
        // The one-tap reveal lasts until the athlete leaves the tab.
        .onDisappear {
            PFPeek.shared.isShowing = false
            NoopDiagSampler.shared.isWatchingClosely = false
        }
        // Diagnostics: the segment on show names the screen, and memory is sampled into the breadcrumbs while the tab is open.
        .onAppear {
            NoopDiagSampler.shared.isWatchingClosely = true
            NoopDiag.screen("pf.\(segment.wrappedValue.rawValue)")
            openedAt = model.phase == .ready ? nil : DispatchTime.now().uptimeNanoseconds
        }
        // Time from opening the tab to its content (the first load), in the breadcrumbs and the perf numbers.
        .onChange(of: model.phase) { _, phase in
            guard phase == .ready, let start = openedAt else { return }
            openedAt = nil
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            NoopPerfStats.shared.section("pf.time_to_ready", ms: ms, onMain: false)
            NoopDiag.crumb("pf.ready", ["ms": ms.rounded()])
        }
        .onChange(of: segmentRaw) { _, raw in NoopDiag.screen("pf.\(raw)") }
    }

    private var content: some View {
        ScreenScaffold(title: "PaceForge", onRefresh: { await model.refresh() }) {
            phaseContent
        }
        .environmentObject(model)
        .environment(\.pfOpenStanding, { openStanding() })
        .environment(\.pfOpenInsight, { id in openInsight(id) })
        .sheet(isPresented: $showStanding) { standingSheet }
        .sheet(item: $insightRoute) { route in insightSheet(route.id) }
        .onReceive(NotificationCenter.default.publisher(for: .pfOpenStanding)) { _ in
            _ = PFStandingLink.consume()
            openStanding()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pfOpenInsight)) { _ in
            if let id = PFInsightLink.consume() { openInsight(id) }
        }
        .task {
            await model.refreshIfStale()
            if model.phase == .ready { PaceForgeBackground.requestNotificationPermissionOnce() }
            // A `noop://paceforge/standing` link that arrived before the tab existed.
            if await PFStandingLink.consume() { openStanding() }
            if let id = await PFInsightLink.consume() { openInsight(id) }
            await PFHeartRecovery.updateSummary(repo: repo, hrMax: profile.hrMax)
        }
    }

    /// Opens the scorecard when the server serves one; otherwise the request is dropped.
    private func openStanding() {
        if model.snapshot?.standing?.hasContent == true { showStanding = true }
    }

    /// Opens an insight's detail when the server serves that item; otherwise the request is dropped.
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

    // The screen below is built from small pieces, each erased to `AnyView` at its own boundary. One big
    // `@ViewBuilder` switch over the phase and the five segments makes SwiftUI instantiate a single enormous
    // nested `_ConditionalContent`/`TupleView` type at runtime, deep enough to overflow the stack on a device.

    /// What the scaffold shows for the load phase. Every branch is a small type; only the screen below it is erased.
    @ViewBuilder private var phaseContent: some View {
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
            readyContent
        }
    }

    @ViewBuilder private var readyContent: some View {
        if let snapshot = model.snapshot {
            if PFAPI.showsWidgetGallery {
                PFWidgetGallery(snapshot: snapshot)
            } else {
                readySections(snapshot)
            }
        }
    }

    @ViewBuilder private func readySections(_ snapshot: PFSnapshot) -> some View {
        Picker("PaceForge section", selection: segment) {
            ForEach(PFSegment.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("pf-segments")

        PFRevealBar()

        if let note = model.offlineNote {
            PFOfflineBanner(text: note, detail: model.failureDetail, isRetrying: model.isRefreshing) {
                Task { await model.refresh() }
            }
        }
        screen(for: segment.wrappedValue, snapshot: snapshot)
    }

    private func screen(for segment: PFSegment, snapshot: PFSnapshot) -> AnyView {
        AnyView(segmentScreen(for: segment, snapshot: snapshot).environment(\.pfExplainers, snapshot.explainerMap))
    }

    private func segmentScreen(for segment: PFSegment, snapshot: PFSnapshot) -> AnyView {
        switch segment {
        case .today: return AnyView(PFTodayView(snapshot: snapshot))
        case .coach: return AnyView(PFCoachView(snapshot: snapshot))
        case .week: return AnyView(PFWeekView(snapshot: snapshot))
        // The same sections as the Insights screen in More, with PaceForge's Training first.
        case .insights: return AnyView(PFInsightsHost(snapshot: snapshot))
        case .body: return bodyScreen(snapshot)
        }
    }

    private func bodyScreen(_ snapshot: PFSnapshot) -> AnyView {
        if hiding.hides(.body) {
            return AnyView(PFBodyHiddenView())
        }
        return AnyView(PFBodyView(snapshot: snapshot))
    }
}

/// The Body screen while Settings > Hide numbers hides body weight and body fat.
private struct PFBodyHiddenView: View {
    var body: some View {
        PFCard("Body", icon: "figure.stand") {
            PFParagraph("\(HideScoresPrefs.placeholder) \u{2014} body weight and body fat are hidden. Tap the eye above to show them, or turn this off in Settings > Hide numbers.")
        }
        .containerIdentifier("pf-body-hidden")
    }
}
