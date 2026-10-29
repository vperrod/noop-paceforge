import SwiftUI

/// NOOP Today's Needs you: it leads the page while PaceForge is waiting on an answer (treadmill pace, a proposal, effort, feel) and
/// leaves as soon as the answer is taken. Draws nothing when nothing is open. Shares the PaceForge tab's model, so an answer given
/// here or there clears both.
struct PFTodayNeedsYouHost: View {
    @ObservedObject private var model = PFUnified.model

    var body: some View {
        Group {
            if let items = model.snapshot?.needsYou, !items.isEmpty {
                PFNeedsYouCard(items: items)
                    .environmentObject(model)
            }
        }
        .task { await model.refreshIfStale() }
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
