import SwiftUI
import StrandDesign

// A finished race or workout on Today opens its results sheet, not the plan or the Workouts list. These helpers find the PaceForge
// recording behind a Today row: the race of a day from the call's week strip (its `activity_id`) or, failing that, the recording that
// day with the race in its name; and the recording of a strap workout by its start time.

enum PFWorkoutMatch {
    /// The recording of the race run on `date` as the results sheet wants it, or nil while no recording is known (a future race, or one
    /// still to sync). Order of trust: the week strip's outcome for that race name, any done race of that day in the strip, then a recording
    /// that started that day and carries "race" or "hyrox" (or the race's own name) in its name.
    static func raceWorkout(info: PFTodayCall, snapshot: PFSnapshot, date: String, name: String?) -> PFWorkout? {
        let strip = info.week.first { $0.date == date }?.items ?? []
        let named = name.flatMap { snapshot.raceOutcome(on: date, name: $0)?.activityID }
        let anyRace = strip.first { $0.kind == "race" && $0.activityID != nil }?.activityID
        guard let id = named ?? anyRace ?? raceRecordingID(snapshot: snapshot, date: date, name: name) else { return nil }
        return PFWorkout(id: id, date: date, status: "done", name: name ?? "Race", kind: "race", activityId: id)
    }

    /// Today's race, when today is a race day.
    static func todayRaceWorkout(info: PFTodayCall, snapshot: PFSnapshot) -> PFWorkout? {
        guard info.today.kind == "race" else { return nil }
        return raceWorkout(info: info, snapshot: snapshot, date: info.today.raceDate ?? snapshot.todayISO, name: info.today.title)
    }

    private static func raceRecordingID(snapshot: PFSnapshot, date: String, name: String?) -> String? {
        let wanted = name?.lowercased()
        return snapshot.activities.values
            .filter { activity in
                guard (activity.startTime ?? "").hasPrefix(date) else { return false }
                let title = (activity.name ?? "").lowercased()
                return title.contains("race") || title.contains("hyrox") || (wanted.map { !$0.isEmpty && title.contains($0) } ?? false)
            }
            .sorted { ($0.startTime ?? "") < ($1.startTime ?? "") }
            .first?.id
    }

    /// The PaceForge recording of a strap workout that started at `startTs` (unix seconds): the one that started closest to it, within a
    /// quarter of an hour; nil when none did.
    static func activity(startTs: Int, in snapshot: PFSnapshot) -> PFActivity? {
        let start = TimeInterval(startTs)
        var best: (activity: PFActivity, gap: TimeInterval)?
        for activity in snapshot.activities.values {
            guard let text = activity.startTime, let when = PFMyDay.parse(text) else { continue }
            let gap = abs(when.timeIntervalSince1970 - start)
            guard gap <= 15 * 60 else { continue }
            if let current = best, current.gap <= gap { continue }
            best = (activity, gap)
        }
        return best?.activity
    }
}

/// Wraps a Today workout tile: a tap opens that workout's results sheet when a PaceForge recording matches its start time, else it goes to
/// the Workouts list as before.
struct PFWorkoutResultsLink<Content: View>: View {
    let startTs: Int
    private let label: () -> Content
    @ObservedObject private var model = PFUnified.model
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @State private var opened: PFWorkout?

    init(startTs: Int, @ViewBuilder label: @escaping () -> Content) {
        self.startTs = startTs
        self.label = label
    }

    var body: some View {
        Group {
            if let snapshot = model.snapshot, let activity = PFWorkoutMatch.activity(startTs: startTs, in: snapshot) {
                Button { opened = PFRecording.workout(activity, snapshot) } label: { label() }
                    .accessibilityIdentifier("today-workout-results-\(activity.id)")
            } else {
                NavigationLink(value: TabRoute.workouts) { label() }
            }
        }
        .sheet(item: $opened) { workout in
            if let snapshot = model.snapshot {
                PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router))
                    .environmentObject(model)
            }
        }
    }
}

/// The coach's review of a strap or Garmin workout, drawn at the top of the workout detail (My Day, Workouts and Today all open that
/// screen). It finds the PaceForge recording by start time, the same way Today does, then shows the shared review card; a recording the
/// coach is still reading says "Coach review pending", and a workout PaceForge has no recording of says so in one line.
struct PFWorkoutCoachCard: View {
    let startTs: Int
    @ObservedObject private var model = PFUnified.model
    @State private var analysisID: String?
    @State private var markdown: String?
    @State private var analysisLoaded = false

    var body: some View {
        content
            .containerIdentifier("workout-coach-review")
            .task {
                if model.snapshot == nil { await model.refreshIfStale() }
            }
            .task(id: matchedID) {
                guard let id = matchedID else { return }
                analysisLoaded = false
                markdown = await model.analysisText(for: id)
                analysisID = id
                analysisLoaded = true
            }
    }

    private var matchedID: String? {
        model.snapshot.flatMap { PFWorkoutMatch.activity(startTs: startTs, in: $0) }?.id
    }

    @ViewBuilder private var content: some View {
        if !PFAPI.isConfigured {
            line("No coach review: PaceForge is not set up on this phone.")
        } else if let snapshot = model.snapshot {
            if let id = matchedID {
                let headline = snapshot.analyses[id]?.headline
                if headline == nil, !(analysisLoaded && analysisID == id) {
                    line("Loading the coach review.")
                } else {
                    PFCoachReviewCard(markdown: analysisID == id ? markdown : nil, headline: headline, completionAnalysis: nil,
                                      status: snapshot.analysisStatuses[id])
                }
            } else {
                line("No coach review: PaceForge has no recording of this workout within 15 minutes of its start.")
            }
        } else if case .failed = model.phase {
            line("No coach review: PaceForge could not be reached.")
        } else {
            line("Loading the coach review.")
        }
    }

    private func line(_ text: String) -> some View {
        PFCard(String(localized: "Coach review"), icon: "sparkles") {
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
