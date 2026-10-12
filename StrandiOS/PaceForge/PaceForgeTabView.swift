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
    /// Settings > Hide numbers: body weight and body fat. The Body screen then shows a placeholder.
    @AppStorage(HideScoresPrefs.bodyKey) private var hideBody = false

    private var segment: Binding<PFSegment> {
        Binding(
            get: { PFSegment(rawValue: segmentRaw) ?? .today },
            set: { segmentRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            if lockEnabled && !lock.isUnlocked {
                PFLockedView(lock: lock)
            } else {
                content
            }
        }
        // Locks again as soon as the app leaves the foreground (not on `inactive`, which the Face ID
        // prompt itself causes).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.lock() }
        }
    }

    private var content: some View {
        ScreenScaffold(title: "PaceForge", onRefresh: { await model.refresh() }) {
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
                if let snapshot = model.snapshot, PFAPI.showsWidgetGallery {
                    PFWidgetGallery(snapshot: snapshot)
                } else if let snapshot = model.snapshot {
                    Picker("PaceForge section", selection: segment) {
                        ForEach(PFSegment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pf-segments")

                    if let note = model.offlineNote {
                        PFOfflineBanner(text: note, detail: model.failureDetail, isRetrying: model.isRefreshing) {
                            Task { await model.refresh() }
                        }
                    }
                    screen(for: segment.wrappedValue, snapshot: snapshot)
                }
            }
        }
        .environmentObject(model)
        .environment(\.pfOpenStanding, { openStanding() })
        .sheet(isPresented: $showStanding) { standingSheet }
        .onReceive(NotificationCenter.default.publisher(for: .pfOpenStanding)) { _ in
            _ = PFStandingLink.consume()
            openStanding()
        }
        .task {
            await model.refreshIfStale()
            if model.phase == .ready { PaceForgeBackground.requestNotificationPermissionOnce() }
            // A `noop://paceforge/standing` link that arrived before the tab existed.
            if PFStandingLink.consume() { openStanding() }
            await PFHeartRecovery.updateSummary(repo: repo, hrMax: profile.hrMax)
        }
    }

    /// Opens the scorecard when the server serves one; otherwise the request is dropped.
    private func openStanding() {
        if model.snapshot?.standing?.hasContent == true { showStanding = true }
    }

    @ViewBuilder private var standingSheet: some View {
        if let snapshot = model.snapshot, let standing = snapshot.standing {
            PFStandingView(standing: standing)
                .environmentObject(model)
                .environment(\.pfExplainers, snapshot.explainerMap)
        }
    }

    @ViewBuilder private func screen(for segment: PFSegment, snapshot: PFSnapshot) -> some View {
        Group {
            switch segment {
            case .today: PFTodayView(snapshot: snapshot)
            case .coach: PFCoachView(snapshot: snapshot)
            case .week: PFWeekView(snapshot: snapshot)
            case .insights: PFInsightsView(snapshot: snapshot)
            case .body:
                if hideBody {
                    PFCard("Body", icon: "figure.stand") {
                        PFParagraph("\(HideScoresPrefs.placeholder) \u{2014} body weight and body fat are hidden. Turn this off in Settings > Hide numbers.")
                    }
                    .containerIdentifier("pf-body-hidden")
                } else {
                    PFBodyView(snapshot: snapshot)
                }
            }
        }
        .environment(\.pfExplainers, snapshot.explainerMap)
    }
}
