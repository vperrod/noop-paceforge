#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Coach: the third tab, one surface for the shared PaceForge brain
//
// Four blocks, in this order: today's read (a headline and up to three sentences, the full read folded), the one composer (Question or
// Change my plan), how many things wait on the athlete, and the Coach log (three days). Daily interpretation, the weekly review and the
// conversation all use PaceForge's server-side coach job, which builds its context from the synced NOOP and PaceForge records. The
// week review is with the reports (Insights), the season plan and the race plans with Plan, the numbers and both devices' readiness with
// Today (the call), and the status of the morning briefing under Settings > Briefing.

struct CoachUnifiedView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @State private var showBriefSettings = false

    var body: some View {
        ScreenScaffold(title: "Coach", subtitle: "One coach for your training, recovery, sleep and progress.",
                       onRefresh: {
            await PFUnified.model.refresh()
            await PFCoachLogStore.shared.refresh()
        }, lazy: true, topBackground: liquidScaffoldSky(), trailing: {
            Button {
                showBriefSettings = true
            } label: {
                Label("Brief settings", systemImage: "bell.badge")
            }
            .buttonStyle(.plain)
            .foregroundStyle(StrandPalette.accent)
            .accessibilityIdentifier("coach-brief-settings")
        }) {
            // The first three blocks need the PaceForge snapshot (the host shows the lock, loading, failed and offline states); the
            // log reads its own store, so it stays reachable while the snapshot is loading or has failed.
            PFSnapshotHost(content: { snapshot in AnyView(PFCoachView(snapshot: snapshot)) })
                .containerIdentifier("coach-full-brain")
            PFCoachLogCard()
        }
        .containerIdentifier("coach-host")
        .task { await PFCoachLogStore.shared.refreshIfStale() }
        .sheet(isPresented: $showBriefSettings) {
            CoachSettingsView(sharedBrainMode: true)
                .environmentObject(coach)
        }
    }
}

/// The status of the morning briefing (when it last ran, the latest issue, whether iOS background refresh is available), under
/// Settings > Briefing; it sat on the Coach screen before.
struct CoachBriefStatusCard: View {
    @EnvironmentObject private var coach: AICoachEngine
    @State private var showBriefSettings = false
    @AppStorage("coachBrief.state") private var briefState = ""
    @AppStorage("coachBrief.lastFailureReason") private var briefFailureReason = ""
    @AppStorage("coachBrief.backgroundIssue") private var briefBackgroundIssue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(briefState.isEmpty ? (CoachBriefScheduler.isEnabled
                ? "No briefing attempt is recorded yet. Check Brief settings and diagnostics."
                : "The morning briefing is off. Enable it in Brief settings.") : briefState)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !briefFailureReason.isEmpty {
                Text("Latest issue: \(briefFailureReason)")
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if CoachBriefScheduler.shouldExplainBackgroundRefreshUnavailable {
                Text("Background App Refresh is unavailable in iOS. Automatic brief delivery may be delayed. Open Brief settings and tap Check now to try immediately.")
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !briefBackgroundIssue.isEmpty, !CoachBriefScheduler.hasBriefToday {
                Text("iOS background refresh issue: \(briefBackgroundIssue). Brief delivery may be delayed; open Coach to check now.")
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Brief settings and diagnostics") { showBriefSettings = true }
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
                .buttonStyle(.plain)
                .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("coach-morning-brief-status")
        .sheet(isPresented: $showBriefSettings) {
            CoachSettingsView(sharedBrainMode: true)
                .environmentObject(coach)
        }
    }
}
#endif
