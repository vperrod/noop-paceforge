import SwiftUI
import StrandDesign
import WhoopStore

/// D10: Today's workouts, one list. It replaces the recordings under Today so far and the Last workouts card: one row per workout, the
/// strap's version and Garmin's matched by start time (`PFWorkoutMatch`) so a workout both devices recorded is one row, each device's
/// numbers named. A tap opens the workout with the coach's review.
struct PFTodaysWorkoutsHost: View {
    /// The strap's workouts as Today read them (newest first, every day); this list keeps the day on screen's.
    let strap: [WorkoutRow]
    /// The day key Today is showing (today's, or the earlier day browsed to), and whether that is today.
    var dayKey: String = ""
    var isToday = true

    @ObservedObject private var model = PFUnified.model

    var body: some View {
        if model.snapshot == nil {
            // PaceForge is not set up, still loading or failed: the strap's own workouts are still Today's workouts.
            PFTodaysWorkoutsCard(snapshot: nil, strap: strap, dayKey: dayKey, isToday: isToday)
        } else {
            PFSnapshotHost(drawsChrome: false, content: { snapshot in
                AnyView(PFTodaysWorkoutsCard(snapshot: snapshot, strap: strap, dayKey: dayKey, isToday: isToday))
            })
        }
    }
}

/// One line of the list: Garmin's recording, the strap's workouts that started within a quarter of an hour of it, or a strap workout
/// nothing on Garmin's side matches.
struct PFTodaysWorkoutRow529: Identifiable {
    let id: String
    var activity: PFActivity?
    var strap: [WorkoutRow]
    var startTs: Int
}

enum PFTodaysWorkouts529 {
    /// The rows of `todayISO`, in the order the workouts started. A strap workout the PaceForge mirror wrote into NOOP's own list
    /// (source "paceforge") is Garmin's recording again, so it is left out; Garmin's side comes from the snapshot's recordings.
    /// `day` is the day listed (yyyy-MM-dd). Without a snapshot only the strap's own workouts of that day are listed.
    static func rows(snapshot: PFSnapshot?, strap: [WorkoutRow], day: String) -> [PFTodaysWorkoutRow529] {
        let todayStrap = strap.filter { row in
            // Without PaceForge nothing mirrors Garmin into the strap list, so every strap row counts.
            (snapshot == nil || WorkoutSource.classify(row.source) != .paceforge)
                && PFFormat.isoString(Date(timeIntervalSince1970: TimeInterval(row.startTs))) == day
        }
        guard let snapshot else {
            return todayStrap.map { PFTodaysWorkoutRow529(id: "strap-\($0.startTs)", activity: nil, strap: [$0], startTs: $0.startTs) }
                .sorted { $0.startTs < $1.startTs }
        }
        var byActivity: [String: [WorkoutRow]] = [:]
        var strapOnly: [WorkoutRow] = []
        for row in todayStrap {
            if let match = PFWorkoutMatch.activity(startTs: row.startTs, in: snapshot) {
                byActivity[match.id, default: []].append(row)
            } else {
                strapOnly.append(row)
            }
        }
        var out: [PFTodaysWorkoutRow529] = []
        var shown: Set<String> = []
        let recordedToday = snapshot.activities.values.filter { $0.startTime?.hasPrefix(day) == true }
        for activity in recordedToday.sorted(by: { ($0.startTime ?? "") < ($1.startTime ?? "") }) {
            shown.insert(activity.id)
            let start = activity.startTime.flatMap { PFMyDay.parse($0) }.map { Int($0.timeIntervalSince1970) } ?? 0
            out.append(PFTodaysWorkoutRow529(id: "garmin-\(activity.id)", activity: activity, strap: byActivity[activity.id] ?? [], startTs: start))
        }
        // A strap workout whose match started on another day (around midnight) keeps its match, and is listed once.
        for (activityID, rows) in byActivity.sorted(by: { $0.key < $1.key }) where !shown.contains(activityID) {
            guard let activity = snapshot.activities[activityID] else { continue }
            out.append(PFTodaysWorkoutRow529(id: "garmin-\(activityID)", activity: activity, strap: rows, startTs: rows.map(\.startTs).min() ?? 0))
        }
        for row in strapOnly {
            out.append(PFTodaysWorkoutRow529(id: "strap-\(row.startTs)", activity: nil, strap: [row], startTs: row.startTs))
        }
        return out.sorted { $0.startTs != $1.startTs ? $0.startTs < $1.startTs : $0.id < $1.id }
    }
}

private struct PFTodaysWorkoutsCard: View {
    let snapshot: PFSnapshot?
    let strap: [WorkoutRow]
    let dayKey: String
    let isToday: Bool
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var opened: PFWorkout?
    private let hiding = PFHiding()

    var body: some View {
        // Today lists the snapshot's own day (the fixture's, or the phone's); an earlier day browsed to lists that day.
        let day = isToday ? (snapshot?.todayISO ?? dayKey) : dayKey
        let rows = PFTodaysWorkouts529.rows(snapshot: snapshot, strap: strap, day: day)
        PFCard(isToday ? "Today's workouts" : "Workouts", icon: "figure.run") {
            VStack(alignment: .leading, spacing: 4) {
                if rows.isEmpty {
                    Text(isToday ? "No workout recorded today." : "No workout recorded on this day.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("today-workouts-empty")
                    if isToday { latest }
                } else {
                    ForEach(rows) { row in rowView(row) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .containerIdentifier("today-workouts")
        .sheet(item: $opened) { workout in
            if let snapshot { PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router)) }
        }
    }

    // MARK: Latest from an earlier day

    /// Nothing today: the strap's latest workout of any day, named with its date, and the way to the whole list (what the retired Last
    /// workouts card showed).
    @ViewBuilder private var latest: some View {
        if let last = strap.first(where: { snapshot == nil || WorkoutSource.classify($0.source) != .paceforge }) {
            let day = PFFormat.isoString(Date(timeIntervalSince1970: TimeInterval(last.startTs)))
            Text("Latest: \(PFFormat.dayTitle(day))")
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(.top, 4)
                .accessibilityIdentifier("today-workouts-latest")
            rowView(PFTodaysWorkoutRow529(id: "strap-\(last.startTs)", activity: nil, strap: [last], startTs: last.startTs))
        }
        NavigationLink(value: TabRoute.workouts) {
            HStack {
                Text("All workouts (\(strap.count))")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-workouts-all")
    }

    // MARK: Rows

    @ViewBuilder private func rowView(_ row: PFTodaysWorkoutRow529) -> some View {
        if let activity = row.activity, let snapshot {
            Button { opened = PFAlertActivityRouter.workout(for: activity, in: snapshot) } label: { content(row) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-workout-row-\(row.id)")
        } else if let first = row.strap.first {
            // A strap workout nothing on Garmin's side matches: the strap's own detail, as the Workouts list opens.
            PFWorkoutResultsLink(startTs: first.startTs) { content(row) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-workout-row-\(row.id)")
        }
    }

    private func content(_ row: PFTodaysWorkoutRow529) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hiding.text(title(row)))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let activity = row.activity {
                    line(device: PFRecording.source(activity), numbers: garminNumbers(activity))
                }
                ForEach(row.strap.indices, id: \.self) { index in
                    line(device: "NOOP strap", numbers: strapNumbers(row.strap[index]))
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func line(device: String, numbers: String) -> some View {
        Text(hiding.text("\(device) \u{00B7} \(numbers)"))
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func title(_ row: PFTodaysWorkoutRow529) -> String {
        if let activity = row.activity { return activity.name ?? PFFormat.words(activity.type ?? "Activity") }
        return row.strap.first.map { WorkoutSource.displaySport($0.sport) } ?? "Workout"
    }

    /// "08:12 · 10.2 km · 52:10 · 5:07 /km · 148 bpm": the start time and whichever numbers the recording has.
    private func garminNumbers(_ activity: PFActivity) -> String {
        var parts: [String] = []
        if let time = PFFormat.timeOfDay(activity.startTime) { parts.append(time) }
        let metrics = PFRecording.metricsLine(activity)
        if !metrics.isEmpty { parts.append(metrics) }
        return parts.isEmpty ? "recorded" : parts.joined(separator: " \u{00B7} ")
    }

    /// "Effort 23 · 52 min · 151 bpm average", whichever the strap workout has.
    private func strapNumbers(_ row: WorkoutRow) -> String {
        var parts: [String] = []
        if let strain = row.strain {
            parts.append("Effort " + UnitFormatter.effortDisplay(strain, scale: UnitPrefs.resolveEffortScale(effortScaleRaw)))
        }
        let seconds = row.durationS ?? Double(max(row.endTs - row.startTs, 0))
        if seconds > 0 { parts.append("\(Int(seconds / 60)) min") }
        if let hr = row.avgHr, hr > 0 { parts.append("\(hr) bpm average") }
        return parts.isEmpty ? "recorded" : parts.joined(separator: " \u{00B7} ")
    }
}
