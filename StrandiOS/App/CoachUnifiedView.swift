#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Coach: one surface for the shared PaceForge brain
//
// The tab-bar Coach button opens this one screen. Daily interpretation, weekly review and the conversation all
// use PaceForge's server-side coach job, which builds its context from the synced NOOP and PaceForge records.

struct CoachUnifiedView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @State private var showBriefSettings = false
    @AppStorage("coachBrief.state") private var briefState = ""
    @AppStorage("coachBrief.lastFailureReason") private var briefFailureReason = ""
    @AppStorage("coachBrief.backgroundIssue") private var briefBackgroundIssue = ""

    var body: some View {
        ScreenScaffold(title: "Coach", subtitle: "One coach for your training, recovery, sleep and progress.",
                       onRefresh: { await PFUnified.model.refresh() }, lazy: true, topBackground: liquidScaffoldSky(), trailing: {
            Button {
                showBriefSettings = true
            } label: {
                Label("Brief settings", systemImage: "bell.badge")
            }
            .buttonStyle(.plain)
            .foregroundStyle(StrandPalette.accent)
            .accessibilityIdentifier("coach-brief-settings")
        }) {
            PFPageNote(key: "coach")
            IndexSection("Reports") {
                IndexRow("Coach reports", "doc.text.fill", TabRoute.reports(PFReportKind.daily.rawValue), id: "coach-reports-row")
            }
            briefStatusCard
            CoachPaceForgeChip()
        }
        .containerIdentifier("coach-host")
        .sheet(isPresented: $showBriefSettings) {
            CoachSettingsView(sharedBrainMode: true)
                .environmentObject(coach)
        }
    }

    private var briefStatusCard: some View {
        PFCard("Morning briefing", icon: "bell.badge") {
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
            }
        }
        .accessibilityIdentifier("coach-morning-brief-status")
    }
}

/// PaceForge's Coach screen. What PaceForge is waiting on him for lives only on Today.
private struct CoachPaceForgeChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(CoachPaceForgeContent(snapshot: snapshot)) })
            .containerIdentifier("coach-full-brain")
    }
}

private struct CoachPaceForgeContent: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFCoachView(snapshot: snapshot)
        }
    }
}

#endif
