import SwiftUI
import StrandDesign

/// NOOP Today's Needs you: one 44 pt row (the count and the first item's title) while PaceForge is waiting on an answer (treadmill
/// pace, effort, feel, a question); it leaves as soon as the answer is taken and draws nothing when nothing is open. A tap runs
/// `onOpen`, which opens `PFNeedsYouSheet` with the whole card. Plan proposals are not listed here: one row, "Your coach wants to
/// change N things in your plan", runs `onReadWhy` (the Coach screen, where each one has its reasons and Accept / Reject).
/// Shares the PaceForge tab's model, so an answer given here or there clears both.
struct PFTodayNeedsYouHost: View {
    let onOpen: () -> Void
    let onReadWhy: () -> Void
    @ObservedObject private var model = PFUnified.model

    var body: some View {
        let parts = PFWeekPlan.split(model.snapshot?.needsYou ?? [])
        Group {
            if !parts.others.isEmpty {
                PFNeedsYouRow(items: parts.others, onOpen: onOpen)
            }
            if !parts.proposals.isEmpty {
                PFProposalsRow(count: parts.proposals.count, onOpen: onReadWhy)
            }
        }
        .task { await model.refreshIfStale() }
    }
}

private struct PFNeedsYouRow: View {
    let items: [PFNeedsItem]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .font(StrandFont.scaled(14, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
                Text("Needs you")
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                PFChip(text: "\(items.count)", color: PFNeutral.other)
                    .fixedSize()
                    .accessibilityIdentifier("pf-needs-row-count")
                if let first = items.first {
                    Text(first.title)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(StrandFont.scaled(12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityLabel(Text("Needs you, \(items.count) waiting"))
        .accessibilityHint(Text("Opens what PaceForge is waiting on"))
        .accessibilityIdentifier("pf-needs-row")
    }
}

/// The sheet behind the Needs you row: the whole card, answers and the plain error line included. It closes itself once the last item
/// is answered. Opened from the row, and from a tapped Needs you notification.
struct PFNeedsYouSheet: View {
    /// Closes the sheet and opens the Coach screen, where the proposals are.
    let onReadWhy: () -> Void
    @ObservedObject private var model = PFUnified.model
    @Environment(\.dismiss) private var dismiss

    private var isCleared: Bool { model.snapshot?.needsYou.isEmpty == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let parts = PFWeekPlan.split(model.snapshot?.needsYou ?? [])
                    if !parts.others.isEmpty {
                        PFNeedsYouCard(items: parts.others)
                            .environmentObject(model)
                    }
                    if !parts.proposals.isEmpty {
                        PFProposalsRow(count: parts.proposals.count, onOpen: onReadWhy)
                    }
                    if parts.others.isEmpty && parts.proposals.isEmpty {
                        Text("Nothing is waiting on you.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("pf-needs-sheet-done")
                }
            }
        }
        .onChange(of: isCleared) { _, cleared in
            if cleared { dismiss() }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Draws nothing. Tells Today when the number of open Needs you items changes (the snapshot arrives after a cold launch from a tapped
/// notification), so a tap that found nothing to open yet can open the sheet now. Today does not observe the model itself: every
/// model change would re-run its whole body.
struct PFNeedsYouArrival: View {
    let onChange: () -> Void
    @ObservedObject private var model = PFUnified.model

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: model.snapshot?.needsYou.count) { _, _ in onChange() }
    }
}

/// Opens the results of the activity a tapped PaceForge alert is about. It draws nothing: NOOP Today carries it as a background, so the
/// sheet always has a view to come from, whether or not the Needs you card is on screen. The tap leaves the activity in
/// `PFAlertLink`; it waits here for the snapshot to hold that activity, for a minute after the tap at most (`PFWantedActivity`).
struct PFAlertActivityRouter: View {
    @ObservedObject private var model = PFUnified.model
    @State private var wanted: PFWantedActivity?
    @State private var routedWorkout: PFWorkout?

    var body: some View {
        Color.clear
            .onAppear { take() }
            .onReceive(NotificationCenter.default.publisher(for: .pfShowAlertActivity)) { _ in take() }
            .onChange(of: model.savedAt) { _, _ in openWanted() }
            .sheet(item: $routedWorkout) { workout in
                if let snapshot = model.snapshot {
                    PFResultsSheet(workout: workout, snapshot: snapshot)
                        .environmentObject(model)
                }
            }
    }

    private func take() {
        guard let tapped = PFAlertLink.consumeActivity() else { return }
        wanted = tapped
        openWanted()
    }

    private func openWanted() {
        guard let tapped = wanted else { return }
        guard !tapped.isExpired() else {
            wanted = nil
            return
        }
        guard let snapshot = model.snapshot, let activity = snapshot.activities[tapped.id] else { return }
        wanted = nil
        routedWorkout = Self.workout(for: activity, in: snapshot)
    }

    /// The same session shape the Coach screen builds for a finished activity.
    private static func workout(for activity: PFActivity, in snapshot: PFSnapshot) -> PFWorkout {
        let date = activity.startTime.map { String($0.prefix(10)) } ?? snapshot.todayISO
        var result = PFWorkout(id: "alert-\(activity.id)", date: date, status: "done",
                               name: activity.name ?? activity.type, kind: activity.type, sport: activity.type,
                               durationMin: activity.durationS.map { $0 / 60 },
                               distanceKm: activity.distanceM.map { $0 / 1000 }, targetRpe: nil,
                               userRpe: snapshot.rpe[activity.id], cadenceTarget: nil, description: nil, briefing: nil,
                               steps: [], exercises: [], compliance: nil, completionAnalysis: nil, notes: nil,
                               activityId: activity.id)
        result.coachSessionID = snapshot.weeks.flatMap { $0.days }.flatMap { $0.workouts }
            .first(where: { $0.activityId == activity.id })?.coachSessionID
        return result
    }
}
