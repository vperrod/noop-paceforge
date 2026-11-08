#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Coach: one surface for the shared PaceForge brain
//
// The tab-bar Coach button opens this one screen. Daily interpretation, weekly review and the conversation all
// use PaceForge's server-side coach job, which builds its context from the synced NOOP and PaceForge records.

struct CoachUnifiedView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @ObservedObject private var reports = PFReportsStore.shared
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
            // The Coach is where PaceForge's text lives, in this order: the assessment, the briefing, Today's call and the readings that
            // sit behind the rows on Today, the Expert reading with the reports row, Day in review, the reviews and the conversation,
            // then the status of the morning briefing. The cards in the middle read their own stores, so they are siblings of the two
            // snapshot hosts around them and stay reachable while the PaceForge snapshot is loading or has failed.
            PFPageNote(key: "today", alwaysOpen: true)
            PFPageNote(key: "coach", alwaysOpen: true)
            CoachPaceForgeChip(part: .brief)
            CoachTextCards()
            PFCoachLogCard()
            CoachPaceForgeChip(part: .reviews)
            briefStatusCard
        }
        .containerIdentifier("coach-host")
        // The stores behind the cards below draw nothing until they have a file, and an empty view never runs its own task.
        .task {
            await reports.loadCapabilities()
            await reports.refreshLatestIfStale()
            await PFDailyIntelStore.shared.refreshIfStale()
            await PFScoresStore.shared.refreshIfStale()
            await PFCoachLogStore.shared.refreshIfStale()
        }
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
/// `part` is `.brief` for the first host (it also shows the lock and the loading, failed and offline states) and `.reviews` for the
/// second, which draws only its cards once the snapshot is ready.
private struct CoachPaceForgeChip: View {
    let part: PFCoachPart

    var body: some View {
        PFSnapshotHost(drawsChrome: part != .reviews, content: { snapshot in
            AnyView(CoachPaceForgeContent(snapshot: snapshot, part: part))
        })
        .containerIdentifier(part == .reviews ? "coach-reviews" : "coach-full-brain")
    }
}

private struct CoachPaceForgeContent: View {
    let snapshot: PFSnapshot
    let part: PFCoachPart

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFCoachView(snapshot: snapshot, part: part)
        }
    }
}

/// What moved here from Today, in the Coach's order: Today's call with its narrative, the body-signal and verdict lines, the Expert
/// reading, the reports row and Day in review (evening). Each draws nothing when it has nothing.
private struct CoachTextCards: View {
    @ObservedObject private var reports = PFReportsStore.shared

    var body: some View {
        // A Group, not a stack: the column it joins spaces its children, and an empty stack would still add a gap.
        Group {
            PFTodaysCallStoreHost()
            CoachPFReadout()
            PFExpertReadingHost()
            if reports.showsReports {
                IndexSection("Reports") {
                    IndexRow("Coach reports", "doc.text.fill", TabRoute.reports(PFReportKind.daily.rawValue), id: "coach-reports-row")
                }
            }
            PFDayReviewStoreHost()
        }
    }
}

#endif
