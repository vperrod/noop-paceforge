#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Coach: one surface for the shared PaceForge brain
//
// Three chips, one mounted at a time: Read (the plan changes waiting, today's read in full, the Expert reading, what waits on the athlete,
// the Monthly coach review, the workout reviews and reads, the Coach log, and one row that opens Plan > Reports), Ask (the whole chat and
// the composer: Question or Change my plan) and Insights (Overview, Trends, Journal, Deep dives). The reports live in Plan now. Daily
// interpretation, the weekly review and the conversation all use PaceForge's server-side coach job, which builds its context from the
// synced NOOP and PaceForge records. The Season plan and "Your numbers" cards are mounted elsewhere; the status of the morning briefing
// is under Settings > Briefing.

enum CoachChip: String, CaseIterable, Identifiable {
    case read, ask, insights

    /// The chip on show, remembered between launches.
    static let storageKey = "noop.coach.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return "Read"
        case .ask: return "Ask"
        case .insights: return "Insights"
        }
    }
}

struct CoachUnifiedView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @ObservedObject private var prefill = PFChatPrefill.shared
    @AppStorage(CoachChip.storageKey) private var chipRaw = CoachChip.read.rawValue
    @State private var showBriefSettings = false
    @State private var showNeedsYou = false
    @State private var showWeekPlan = false
    /// "Read why" in the Needs you sheet: the sheet closes first, then the week plan page opens (see its `onDismiss`).
    @State private var openWeekPlanAfterSheet = false

    private var chip: CoachChip { CoachChip(rawValue: chipRaw) ?? .read }

    private var selection: Binding<CoachChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip coach.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Coach", subtitle: "One coach for your training, recovery, sleep and progress.",
                       onRefresh: {
            await PFUnified.model.refresh()
            await PFCoachLogStore.shared.refresh()
            await PFReportsStore.shared.loadIndex()
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
            CoachColumn(selection: selection,
                        onOpenProposals: { showWeekPlan = true },
                        onOpenNeedsYou: { showNeedsYou = true },
                        onAsk: { chipRaw = CoachChip.ask.rawValue })
        }
        .containerIdentifier("coach-host")
        // The stores behind the Expert reading and the log draw nothing until they have a file, and an empty view never runs its own task.
        .task {
            await PFCoachLogStore.shared.refreshIfStale()
            await PFReportsStore.shared.loadCapabilities()
            await PFReportsStore.shared.refreshLatestIfStale()
        }
        // A question handed to the coach ("Ask the coach about this", "Ask Coach about this workout") lands in the chat, wherever it came from.
        // The callers set it before the sheet exists, and onChange does not fire for a value already there at appear.
        .onAppear {
            if prefill.text?.isEmpty == false || coach.pendingPrompt?.isEmpty == false { chipRaw = CoachChip.ask.rawValue }
        }
        .onChange(of: prefill.text) { _, text in
            if text?.isEmpty == false { chipRaw = CoachChip.ask.rawValue }
        }
        .onChange(of: coach.pendingPrompt) { _, prompt in
            if prompt?.isEmpty == false { chipRaw = CoachChip.ask.rawValue }
        }
        .sheet(isPresented: $showBriefSettings) {
            CoachSettingsView(sharedBrainMode: true)
                .environmentObject(coach)
        }
        .sheet(isPresented: $showNeedsYou, onDismiss: {
            if openWeekPlanAfterSheet {
                openWeekPlanAfterSheet = false
                showWeekPlan = true
            }
        }) {
            PFNeedsYouSheet(onReadWhy: {
                openWeekPlanAfterSheet = true
                showNeedsYou = false
            })
        }
        .navigationDestination(isPresented: $showWeekPlan) { PFWeekPlanScreen() }
    }
}

/// The chips and the chosen chip's content.
private struct CoachColumn: View {
    @Binding var selection: CoachChip
    let onOpenProposals: () -> Void
    let onOpenNeedsYou: () -> Void
    let onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionChips(options: CoachChip.allCases, selection: $selection, idPrefix: "coach-chip",
                         id: { $0.rawValue }, title: { $0.title })
            CoachChipBody(chip: selection, onOpenProposals: onOpenProposals, onOpenNeedsYou: onOpenNeedsYou, onAsk: onAsk)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
    }
}

private struct CoachChipBody: View {
    let chip: CoachChip
    let onOpenProposals: () -> Void
    let onOpenNeedsYou: () -> Void
    let onAsk: () -> Void

    var body: some View {
        UnifiedChipMount(host: "coach", name: chip.rawValue, content: content)
    }

    private var content: AnyView {
        switch chip {
        case .read:
            return AnyView(CoachReadChip(onOpenProposals: onOpenProposals, onOpenNeedsYou: onOpenNeedsYou, onAsk: onAsk))
        case .ask:
            return AnyView(CoachAskChip())
        case .insights:
            return AnyView(InsightsEmbedded())
        }
    }
}

/// The cards that need the PaceForge snapshot sit in its host (the lock, loading, failed and offline states); the log reads its own
/// store, so it stays reachable while the snapshot is loading or has failed.
private struct CoachReadChip: View {
    let onOpenProposals: () -> Void
    let onOpenNeedsYou: () -> Void
    let onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFSnapshotHost(content: { snapshot in
                AnyView(PFCoachView(snapshot: snapshot, onOpenProposals: onOpenProposals,
                                    onOpenNeedsYou: onOpenNeedsYou, onAsk: onAsk))
            })
            .containerIdentifier("coach-full-brain")
            CoachReportsRow()
            PFCoachLogCard()
        }
        .containerIdentifier("coach-chip-content-read")
    }
}

private struct CoachAskChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(PFCoachComposer(snapshot: snapshot)) })
            .containerIdentifier("coach-chip-content-ask")
    }
}

/// The reports moved to Plan (the Reports chip): one row here closes the Coach and opens it.
private struct CoachReportsRow: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
            // The Plan tab sits under the Coach sheet; it opens on Reports once the sheet has gone.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                PFDeepLink529.open(.chip(.reports))
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 26, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reports")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Today, weeks, months, races and workouts, in Plan")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach-reports-row")
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
