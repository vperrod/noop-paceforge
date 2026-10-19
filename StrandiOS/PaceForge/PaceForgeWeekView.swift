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
        LazyVStack(alignment: .leading, spacing: 16) {
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
            if workouts.isEmpty && rides.isEmpty {
                Text("Nothing scheduled")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(workouts) { PFWorkoutRow(workout: $0, snapshot: snapshot) }
                ForEach(rides) { PFRideRow(ride: $0, snapshot: snapshot) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
