import SwiftUI
import StrandDesign

/// PaceForge "This week": Monday to Sunday, every session expandable to its full detail.
struct PFWeekView: View {
    let snapshot: PFSnapshot
    @State private var chosenWeek: Int?

    private var weekIndex: Binding<Int> {
        Binding(
            get: { min(chosenWeek ?? snapshot.currentWeekIndex, snapshot.weeks.count - 1) },
            set: { chosenWeek = $0 }
        )
    }

    private var week: PFWeek { snapshot.weeks[weekIndex.wrappedValue] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if snapshot.weeks.count > 1 {
                Picker("Week", selection: weekIndex) {
                    ForEach(Array(snapshot.weeks.enumerated()), id: \.offset) { index, w in
                        Text(PFFormat.span(w.start, w.end)).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("pf-week-picker")
            }
            summaryCard
            ForEach(week.days) { day in
                PFDaySection(day: day, snapshot: snapshot)
            }
        }
    }

    private var summaryCard: some View {
        PFCard(title: weekTitle, icon: "calendar", trailing: {
            if let tally = week.tally {
                Text(tally).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                if let focus = week.focus {
                    Text(focus)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = hoursLine {
                    Text(line).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if let intro = week.intro { PFParagraph(intro) }
                if let headline = week.headline {
                    Text(headline).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private var weekTitle: String {
        let label = PFFormat.span(week.start, week.end)
        return week.phase.map { "\($0) \u{00B7} \(label)" } ?? label
    }

    private var hoursLine: String? {
        if let planned = week.plannedHours, let target = week.targetHours {
            return "\(PFFormat.oneDecimal(planned)) h planned against a \(PFFormat.trimmed(target)) h target"
        }
        if let target = week.targetHours { return "\(PFFormat.trimmed(target)) h target" }
        return nil
    }
}

private struct PFDaySection: View {
    let day: PFDay
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PFFormat.dayTitle(day.date))
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            let workouts = day.workouts
            let rides = snapshot.rides(on: day.date)
            let races = snapshot.races(on: day.date)
            if workouts.isEmpty && rides.isEmpty && races.isEmpty {
                Text("Nothing scheduled")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(races, id: \.name) { PFRaceDayRow(race: $0, outcome: snapshot.raceOutcome(on: day.date, name: $0.name), snapshot: snapshot) }
                ForEach(workouts) { PFWorkoutRow(workout: $0, snapshot: snapshot) }
                ForEach(rides) { PFRideRow(ride: $0, snapshot: snapshot) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A race on its day: the same booked-day card as a session, so a race week never reads "Nothing scheduled". A HYROX race opens the
/// HYROX screen with its race plan.
struct PFRaceDayRow: View {
    let race: PFNextRace
    /// The week strip's entry for this race when it has been run (result, gap to goal, recording).
    var outcome: PFTodayCall.WeekItem? = nil
    /// Needed to open the recording's results; without it a run race still opens the race plan.
    var snapshot: PFSnapshot? = nil
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @State private var showPlan = false
    @State private var showResults = false

    /// A race that was run opens its metrics and the coach's review; one still ahead opens the race plan.
    private var resultsWorkout: PFWorkout? {
        guard let id = outcome?.activityID, snapshot != nil else { return nil }
        return PFWorkout(id: id, date: race.date, status: "done", name: race.name, kind: "race", activityId: id)
    }

    private var isHyrox: Bool { race.name.localizedCaseInsensitiveContains("hyrox") }

    var body: some View {
        Group {
            if isHyrox || resultsWorkout != nil {
                Button { if resultsWorkout != nil { showResults = true } else { showPlan = true } } label: { card }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
        .sheet(isPresented: $showPlan) { PFHyroxSheet() }
        .sheet(isPresented: $showResults) {
            if let workout = resultsWorkout, let snapshot {
                PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router))
            }
        }
        .accessibilityIdentifier("pf-week-race-\(race.date)")
    }

    private var card: some View {
        StrandCard(padding: 14) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(PFColor.sky)
                    .frame(width: 4)
                    .frame(minHeight: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(race.name)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let result = outcome?.result {
                        Text([result, outcome?.goalGapLine, outcome?.resultSource == "garmin" ? "Garmin recording" : nil]
                            .compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .accessibilityIdentifier("pf-week-race-result-\(race.date)")
                    }
                    Text(race.goalTime.map { "Race \u{00B7} goal \($0)" } ?? "Race")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Spacer(minLength: 0)
                if outcome != nil {
                    Text("DONE")
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(PFColor.positive)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(PFColor.positive.opacity(0.15)))
                        .accessibilityIdentifier("pf-week-race-done-\(race.date)")
                }
            }
        }
    }
}
