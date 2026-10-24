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
            CoachPaceForgeChip()
        }
        .containerIdentifier("coach-host")
        .sheet(isPresented: $showBriefSettings) {
            CoachSettingsView(sharedBrainMode: true)
                .environmentObject(coach)
        }
    }
}

/// PaceForge's Coach screen, with what PaceForge is waiting on him for at the top.
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
            if !snapshot.needsYou.isEmpty { PFNeedsYouCard(items: snapshot.needsYou) }
            PFCoachView(snapshot: snapshot)
        }
    }
}

#endif
