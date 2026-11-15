import SwiftUI
import StrandDesign

/// One finished workout or race to open in the existing results sheet, by its Garmin activity id.
struct PFResultsTarget529: Identifiable, Equatable {
    let id: String
    var title: String?
    var date: String?
    var isRace = false
}

/// Presents the existing `PFResultsSheet` for a `PFResultsTarget529`.
struct PFResultsLink529: ViewModifier {
    @Binding var target: PFResultsTarget529?
    @ObservedObject private var model = PFUnified.model
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter

    func body(content: Content) -> some View {
        content.sheet(item: $target) { item in
            if let snapshot = model.snapshot {
                PFResultsSheet(workout: PFWeekLookup529.workout(for: item, in: snapshot), snapshot: snapshot,
                               onAskCoach: PFResultsSheet.askCoach(coach, router))
            } else {
                PFWeekState529(kind: .loading, message: "Loading the results")
                    .padding(16)
                    .task { await model.refreshIfStale() }
            }
        }
    }
}

extension View {
    func pfResultsSheet529(_ target: Binding<PFResultsTarget529?>) -> some View {
        modifier(PFResultsLink529(target: target))
    }
}

/// What the phone's PaceForge snapshot knows about a session or an activity. The week documents carry everything the cards write out;
/// the snapshot adds the long briefing, the breakdown and the recordings.
enum PFWeekLookup529 {
    static func workout(for target: PFResultsTarget529, in snapshot: PFSnapshot) -> PFWorkout {
        if let activity = snapshot.activities[target.id] { return PFRecording.workout(activity, snapshot) }
        let planned = snapshot.weeks.flatMap { $0.days }.flatMap { $0.workouts }.first { $0.activityId == target.id }
        if let planned { return planned }
        return PFWorkout(id: target.id, date: target.date ?? snapshot.todayISO, status: "done", name: target.title,
                         kind: target.isRace ? "race" : nil, activityId: target.id)
    }

    /// The planned session the snapshot holds for a session id of the week document.
    static func plannedWorkout(sessionId: String, in snapshot: PFSnapshot) -> PFWorkout? {
        snapshot.weeks.flatMap { $0.days }.flatMap { $0.workouts }
            .first { $0.coachSessionID == sessionId || $0.id == sessionId }
    }

    /// The previous recording with the same name before `date`, newest first.
    static func lastTime(title: String, before date: String, in snapshot: PFSnapshot) -> PFActivity? {
        let wanted = title.lowercased()
        return snapshot.activities.values
            .filter { activity in
                guard let start = activity.startTime, start.count >= 10, String(start.prefix(10)) < date else { return false }
                return (activity.name ?? "").lowercased() == wanted
            }
            .max { ($0.startTime ?? "") < ($1.startTime ?? "") }
    }
}
