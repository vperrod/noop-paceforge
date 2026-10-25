#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Training: the second tab with the unified navigation
//
// Chips at the top and ONE chip mounted below them: Workouts, Calendar (a month grid with the chosen day's sessions under it, built from the PaceForge snapshot), Plan
// (This week, My Plan), Season (the weeks ahead and behind), Events (races) and HYROX (the prognosis and race simulations). Each chip
// reuses views that exist in the PaceForge tab today; a day tap shows that day's sessions, which open the same results and session
// sheets as before. NOOP's and PaceForge's numbers are never merged: this tab is PaceForge's plan and results.

enum CalendarChip: String, CaseIterable, Identifiable {
    case workouts, calendar, plan, season, events, hyrox

    /// The chip on show, shared with the shell so a PaceForge link can land on a chip. Reset to Workouts at every launch.
    static let storageKey = "noop.calendar.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .calendar: return "Calendar"
        case .plan: return "Plan"
        case .season: return "Season"
        case .events: return "Events"
        case .hyrox: return "HYROX"
        }
    }
}

/// The Calendar tab's root.
struct CalendarHostView: View {
    @AppStorage(CalendarChip.storageKey) private var chipRaw = CalendarChip.workouts.rawValue

    private var chip: CalendarChip { CalendarChip(rawValue: chipRaw) ?? .workouts }

    private var selection: Binding<CalendarChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip calendar.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Training", subtitle: "Your workouts, calendar, plan and races.",
                       onRefresh: { await PFUnified.model.refresh() }, lazy: true, topBackground: liquidScaffoldSky()) {
            CalendarColumn(selection: selection)
        }
    }
}

/// The chips and the chosen chip's content.
private struct CalendarColumn: View {
    @Binding var selection: CalendarChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFPageNote(key: "training")
            SectionChips(options: CalendarChip.allCases, selection: $selection, idPrefix: "calendar-chip",
                         id: { $0.rawValue }, title: { $0.title })
            CalendarChipHost(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("calendar-host")
    }
}

/// The PaceForge snapshot around one chip.
private struct CalendarChipHost: View {
    let chip: CalendarChip

    var body: some View {
        PFSnapshotHost(content: { snapshot in
            AnyView(UnifiedChipMount(host: "calendar", name: chip.rawValue, content: CalendarChipBody.content(chip, snapshot)))
        })
    }
}

private enum CalendarChipBody {
    static func content(_ chip: CalendarChip, _ snapshot: PFSnapshot) -> AnyView {
        switch chip {
        case .workouts: return AnyView(WorkoutsView())
        case .calendar: return AnyView(CalendarMonthChip(snapshot: snapshot))
        case .plan: return AnyView(CalendarPlanChip(snapshot: snapshot))
        case .season: return AnyView(CalendarSeasonChip(snapshot: snapshot))
        case .events: return AnyView(CalendarEventsChip(snapshot: snapshot))
        case .hyrox: return AnyView(CalendarHyroxChip(snapshot: snapshot))
        }
    }
}

// MARK: - Calendar chip

/// The planned sessions of every day the snapshot holds, by day.
private struct CalendarIndex {
    let byDay: [String: [PFWorkout]]
    let first: String
    let last: String

    init(_ snapshot: PFSnapshot) {
        var map: [String: [PFWorkout]] = [:]
        for week in snapshot.weeks {
            for day in week.days { map[day.date] = day.workouts }
        }
        byDay = map
        first = snapshot.weeks.first?.start ?? snapshot.todayISO
        last = snapshot.weeks.last?.end ?? snapshot.todayISO
    }

    func workouts(on day: String) -> [PFWorkout] { byDay[day] ?? [] }
}

private enum CalendarMath {
    private static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static func firstOfMonth(_ iso: String) -> String { String(iso.prefix(8)) + "01" }

    static func shiftMonth(_ monthStart: String, by step: Int) -> String {
        firstOfMonth(PFFormat.addDays(monthStart, step > 0 ? 32 : -1))
    }

    static func title(_ monthStart: String) -> String { monthName.string(from: PFFormat.date(monthStart)) }

    /// Six Monday-first weeks that cover the month.
    static func monthCells(_ monthStart: String) -> [String] {
        let start = PFFormat.monday(of: monthStart)
        return (0..<42).map { PFFormat.addDays(start, $0) }
    }

    static func dayNumber(_ iso: String) -> String { String(Int(iso.suffix(2)) ?? 0) }
}

private struct CalendarMonthChip: View {
    let snapshot: PFSnapshot
    @State private var selected: String
    @State private var monthStart: String

    init(snapshot: PFSnapshot) {
        self.snapshot = snapshot
        let today = snapshot.todayISO.isEmpty ? PFFormat.isoString(Date()) : snapshot.todayISO
        _selected = State(initialValue: today)
        _monthStart = State(initialValue: CalendarMath.firstOfMonth(today))
    }

    private var today: String { snapshot.todayISO.isEmpty ? PFFormat.isoString(Date()) : snapshot.todayISO }

    var body: some View {
        let index = CalendarIndex(snapshot)
        VStack(alignment: .leading, spacing: 16) {
            CalendarMonthCard(monthStart: $monthStart, selected: $selected, today: today, index: index)
            CalendarLegend()
            CalendarDayPanel(day: selected, snapshot: snapshot, workouts: index.workouts(on: selected))
        }
        .containerIdentifier("calendar-chip-content-calendar")
    }
}

private struct CalendarMonthCard: View {
    @Binding var monthStart: String
    @Binding var selected: String
    let today: String
    let index: CalendarIndex

    var body: some View {
        StrandCard(padding: 12) {
            VStack(spacing: 10) {
                CalendarMonthHeader(monthStart: $monthStart, index: index)
                CalendarWeekdayRow()
                CalendarMonthRows(monthStart: monthStart, selected: $selected, today: today, index: index)
            }
        }
        .containerIdentifier("calendar-month")
    }
}

private struct CalendarMonthHeader: View {
    @Binding var monthStart: String
    let index: CalendarIndex

    private var canGoBack: Bool { monthStart > CalendarMath.firstOfMonth(index.first) }
    private var canGoForward: Bool { monthStart < CalendarMath.firstOfMonth(index.last) }

    var body: some View {
        HStack(spacing: 8) {
            Button { monthStart = CalendarMath.shiftMonth(monthStart, by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(!canGoBack)
            .accessibilityIdentifier("calendar-month-prev")
            Text(CalendarMath.title(monthStart))
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("calendar-month-title")
            Button { monthStart = CalendarMath.shiftMonth(monthStart, by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)
            .accessibilityIdentifier("calendar-month-next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(StrandPalette.accent)
    }
}

private struct CalendarWeekdayRow: View {
    private static let names = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { column in
                Text(Self.names[column])
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Six rows of seven days. Fixed counts, small cells: nothing here grows with the history.
private struct CalendarMonthRows: View {
    let monthStart: String
    @Binding var selected: String
    let today: String
    let index: CalendarIndex

    var body: some View {
        let cells = CalendarMath.monthCells(monthStart)
        VStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { row in
                CalendarMonthRow(days: Array(cells[(row * 7)..<(row * 7 + 7)]), monthStart: monthStart,
                                 selected: $selected, today: today, index: index)
            }
        }
    }
}

private struct CalendarMonthRow: View {
    let days: [String]
    let monthStart: String
    @Binding var selected: String
    let today: String
    let index: CalendarIndex

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                CalendarDayCell(day: day, today: today, isSelected: day == selected,
                                isInMonth: day.prefix(7) == monthStart.prefix(7),
                                workouts: index.workouts(on: day), height: 44) { selected = day }
            }
        }
    }
}

/// One day: its number and a dot per session coloured by its status (done, partial, missed; planned and optional are grey, optional
/// fainter). A fixed-size slot, so a day with nothing and a day with five sessions are the same size.
private struct CalendarDayCell: View {
    let day: String
    let today: String
    let isSelected: Bool
    let isInMonth: Bool
    let workouts: [PFWorkout]
    let height: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(CalendarMath.dayNumber(day))
                    .font(StrandFont.subhead.weight(day == today ? .bold : .regular))
                    .foregroundStyle(isInMonth ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                CalendarDots(workouts: workouts)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? StrandPalette.accent.opacity(0.22) : StrandPalette.surfaceInset.opacity(isInMonth ? 1 : 0.4)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(day == today ? StrandPalette.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PFFormat.dayTitle(day)), \(workouts.count) sessions")
        .accessibilityIdentifier("calendar-day-\(day)")
    }
}

private struct CalendarDots: View {
    let workouts: [PFWorkout]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(workouts.prefix(4).enumerated()), id: \.offset) { _, workout in
                Circle()
                    .fill(PFColor.status(workout.status))
                    .opacity(workout.status == "optional" ? 0.45 : 1)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 6)
    }
}

private struct CalendarLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            legend(PFColor.positive, "Done")
            legend(PFColor.warning, "Partial")
            legend(PFColor.critical, "Missed")
            legend(StrandPalette.textTertiary, "Planned")
        }
        .font(StrandFont.caption)
        .foregroundStyle(StrandPalette.textSecondary)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

/// The chosen day's sessions and rides, each the same row (and the same results or session sheet) as the PaceForge week.
private struct CalendarDayPanel: View {
    let day: String
    let snapshot: PFSnapshot
    let workouts: [PFWorkout]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PFFormat.dayTitle(day))
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            let rides = snapshot.rides(on: day)
            if workouts.isEmpty && rides.isEmpty {
                Text("Nothing scheduled")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
            } else {
                ForEach(workouts) { CalendarSessionRow(workout: $0, snapshot: snapshot) }
                ForEach(rides) { PFRideRow(ride: $0, snapshot: snapshot) }
            }
        }
        .containerIdentifier("calendar-day-panel")
    }
}

/// A session row with the state of its analysis under it.
private struct CalendarSessionRow: View {
    let workout: PFWorkout
    let snapshot: PFSnapshot

    private var analysisLine: String? {
        guard workout.hasResults, let id = workout.activityId else { return nil }
        return snapshot.analyses[id] == nil ? "Analysis pending" : "Analysis ready"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PFWorkoutRow(workout: workout, snapshot: snapshot)
            if let line = analysisLine {
                Text(line)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .padding(.leading, 6)
                    .accessibilityIdentifier("calendar-analysis-\(workout.id)")
            }
        }
    }
}

// MARK: - Plan, Season, Events, HYROX

/// This week (Monday to Sunday, every session expandable) under My Plan.
private struct CalendarPlanChip: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFMyPlanStoreHost()
            if !snapshot.weeks.isEmpty { PFWeekView(snapshot: snapshot) }
        }
        .containerIdentifier("calendar-chip-content-plan")
    }
}

/// One row per week the snapshot holds: its dates, phase, focus and tally.
private struct CalendarSeasonChip: View {
    let snapshot: PFSnapshot

    var body: some View {
        let currentKey = snapshot.weeks.indices.contains(snapshot.currentWeekIndex) ? snapshot.weeks[snapshot.currentWeekIndex].key : ""
        return LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(snapshot.weeks) { week in
                CalendarSeasonRow(week: week, isCurrent: week.key == currentKey)
            }
        }
        .containerIdentifier("calendar-chip-content-season")
    }
}

private struct CalendarSeasonRow: View {
    let week: PFWeek
    let isCurrent: Bool

    var body: some View {
        StrandCard(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(PFFormat.span(week.start, week.end))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    if isCurrent { PFChip(text: "this week", color: StrandPalette.accent) }
                    Spacer(minLength: 6)
                    if let tally = week.tally {
                        Text(tally).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if let phase = week.phase {
                    Text(phase).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if let focus = week.focus {
                    Text(focus)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The races PaceForge knows about, and race week when it is race week.
private struct CalendarEventsChip: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let week = snapshot.raceWeek {
                PFDismissable(.raceWeek, text: PFCardText.raceWeek(week), snapshot: snapshot) {
                    PFRaceWeekCard(week: week, todayISO: snapshot.todayISO)
                }
            }
            if snapshot.insights.races.isEmpty {
                PFCard("No races yet", icon: "flag.checkered") {
                    PFParagraph("Races PaceForge knows about show here with the days to go and how ready you are.")
                }
            } else {
                ForEach(snapshot.insights.races) { PFRaceCard(race: $0) }
            }
        }
        .containerIdentifier("calendar-chip-content-events")
    }
}

/// The HYROX prognosis and the race simulations.
private struct CalendarHyroxChip: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if snapshot.insights.hyrox != nil || snapshot.insights.hyroxFinish != nil {
                PFInsightsView(snapshot: snapshot).prognosisCard
            } else {
                PFCard("No HYROX prognosis yet", icon: "target") {
                    PFParagraph("The predicted finish and the stations that cost you most show here once PaceForge has enough HYROX work.")
                }
            }
            if let sims = snapshot.simulations { PFSimulationsCard(sims: sims) }
        }
        .containerIdentifier("calendar-chip-content-hyrox")
    }
}
#endif
