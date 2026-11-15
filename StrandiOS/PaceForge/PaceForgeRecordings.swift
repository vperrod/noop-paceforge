import SwiftUI
import StrandDesign

// Recordings on the Train tab: the latest runs (Running chip) and the coach-review status of the recent recordings (Workouts chip). A row
// opens the same results sheet as everywhere else; that sheet carries the coach review and "Ask Coach about this workout". Nothing here is
// fetched: the rows are the snapshot's activities, the status is its analyses and their statuses.

enum PFRecording {
    /// A recording as the results sheet wants it (the same shape the Coach screen builds for its workout reads).
    static func workout(_ activity: PFActivity, _ snapshot: PFSnapshot) -> PFWorkout {
        let date = activity.startTime.map { String($0.prefix(10)) } ?? snapshot.todayISO
        var result = PFWorkout(id: "rec-\(activity.id)", date: date, status: "done",
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

    /// The newest recordings first; a recording without a start time sorts last.
    static func latest(_ snapshot: PFSnapshot, runsOnly: Bool, limit: Int) -> [PFActivity] {
        snapshot.activities.values
            .filter { !runsOnly || $0.isRun }
            .sorted { ($0.startTime ?? "") > ($1.startTime ?? "") }
            .prefix(limit)
            .map { $0 }
    }

    /// "Reviewed: <headline>" once the coach has read it, else the server's reason it has not, else nil (PaceForge has said nothing).
    static func reviewLine(_ id: String, _ snapshot: PFSnapshot) -> String? {
        if let headline = snapshot.analyses[id]?.headline { return headline }
        if let status = snapshot.analysisStatuses[id] { return status.reason ?? "Coach review pending." }
        return nil
    }

    static func isReviewed(_ id: String, _ snapshot: PFSnapshot) -> Bool { snapshot.analyses[id]?.headline != nil }

    /// Garmin unless the recording came in through NOOP: the builder tags those in the name ("... \u{00B7} NOOP strap" is the WHOOP
    /// strap, "... \u{00B7} Apple Health via NOOP" is Apple Health).
    static func source(_ activity: PFActivity) -> String {
        let name = activity.name ?? ""
        if name.contains("Apple Health") { return "Apple Health" }
        if name.contains("NOOP strap") { return "WHOOP strap" }
        return name.contains("via NOOP") ? "NOOP" : "Garmin"
    }

    /// Distance, time, pace and heart rate, whichever the recording has.
    static func metricsLine(_ activity: PFActivity) -> String {
        var bits: [String] = []
        if let m = activity.distanceM, m > 0 { bits.append("\(PFFormat.oneDecimal(m / 1000)) km") }
        if let s = activity.durationS, s > 0 { bits.append(PFFormat.clock(s)) }
        if activity.isRun, let pace = activity.avgPaceSecPerKm, pace > 0 { bits.append("\(PFFormat.pace(pace)) /km") }
        if let hr = activity.avgHr, hr > 0 { bits.append("\(Safe.int(hr)) bpm") }
        return bits.joined(separator: " \u{00B7} ")
    }
}

/// One recording: name and day, its key metrics, its source and (when asked) the coach-review line. Opens the results sheet.
struct PFRecordingRow: View {
    let activity: PFActivity
    let snapshot: PFSnapshot
    var showsReview = false
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @State private var showResults = false

    var body: some View {
        Button { showResults = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(activity.name ?? activity.type ?? "Workout")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    PFSourceTag(source: PFRecording.source(activity))
                    Spacer(minLength: 6)
                    Text(activity.startTime.map { PFFormat.shortDate(String($0.prefix(10))) } ?? "")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                let metrics = PFRecording.metricsLine(activity)
                if !metrics.isEmpty {
                    Text(metrics).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if showsReview, let line = PFRecording.reviewLine(activity.id, snapshot) {
                    Text(PFRecording.isReviewed(activity.id, snapshot) ? "Coach review: \(line)" : line)
                        .font(StrandFont.caption)
                        .foregroundStyle(PFRecording.isReviewed(activity.id, snapshot) ? StrandPalette.textSecondary : PFColor.warning)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-recording-\(activity.id)")
        .sheet(isPresented: $showResults) {
            PFResultsSheet(workout: PFRecording.workout(activity, snapshot), snapshot: snapshot,
                           onAskCoach: PFResultsSheet.askCoach(coach, router))
        }
    }
}

/// The latest five runs, each opening its results sheet.
struct PFRecentRunsCard: View {
    let snapshot: PFSnapshot

    var body: some View {
        let runs = PFRecording.latest(snapshot, runsOnly: true, limit: 5)
        PFCard("Recent runs", icon: "figure.run") {
            if runs.isEmpty {
                PFParagraph("Runs PaceForge has recorded show here, newest first.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                        PFRecordingRow(activity: run, snapshot: snapshot)
                        if index < runs.count - 1 { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
        }
        .containerIdentifier("train-running-recent-runs")
    }
}

/// The open treadmill-pace question, if one waits, else one line saying none does. The row opens the Needs you sheet, where it is answered.
struct PFTreadmillPacesRow: View {
    let snapshot: PFSnapshot
    @State private var showNeedsYou = false

    var body: some View {
        let waiting = snapshot.needsYou.filter { $0.kind == .treadmillPace }
        PFCard("Treadmill paces", icon: "figure.run.treadmill") {
            if let first = waiting.first {
                Button { showNeedsYou = true } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(first.title).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                            Text(waiting.count > 1 ? "\(waiting.count) treadmill runs wait for a pace." : "Waiting for the belt pace.")
                                .font(StrandFont.caption).foregroundStyle(PFColor.warning)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("train-running-treadmill-open")
            } else {
                Text("No treadmill run is waiting for a pace.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .containerIdentifier("train-running-treadmill")
        .sheet(isPresented: $showNeedsYou) { PFNeedsYouSheet(onReadWhy: { showNeedsYou = false }) }
    }
}
