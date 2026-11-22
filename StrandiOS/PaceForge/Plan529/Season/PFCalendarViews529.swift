import SwiftUI
import StrandDesign

// C1, the Calendar chip of the Plan tab: a month grid for every month of the plan (the week index says which), each day drawn as bars
// (height = minutes, colour = how hard; solid done, outlined planned, dashed optional), the hours at the end of each week row, and the
// chosen day's items under it with the two buttons that add to the calendar.

/// The week documents the grid and the day panel read, by ISO week, loaded as the months are paged.
@MainActor
final class PFWeekDocs529: ObservableObject {
    @Published private(set) var docs: [String: PFPlanWeekDoc] = [:]
    /// Weeks the server does not serve (asked once, so a missing week is not asked for again on every redraw).
    @Published private(set) var absent: Set<String> = []
    /// Weeks that could not be read at all (no answer and no saved copy): the panel says so and offers to try again.
    @Published private(set) var failed: Set<String> = []

    func load(_ keys: [String]) async {
        for key in keys where docs[key] == nil && !absent.contains(key) {
            let fetched = await PFAPI.fetchDoc(PFDocPath529.week(key))
            if let data = fetched.data, let doc = try? PFPlan529Decoder.make().decode(PFPlanWeekDoc.self, from: data) {
                docs[key] = doc
                failed.remove(key)
            } else if fetched.failed {
                failed.insert(key)
            } else {
                absent.insert(key)
                failed.remove(key)
            }
        }
    }

    /// Forgets these weeks and reads them again (after an edit, or a pull to refresh).
    func reload(_ keys: [String]) async {
        for key in keys {
            docs[key] = nil
            absent.remove(key)
            failed.remove(key)
        }
        await load(keys)
    }
}

private enum PFCalendarMath529 {
    private static let monthName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    static func firstOfMonth(_ iso: String) -> String { String(iso.prefix(8)) + "01" }

    static func shift(_ monthStart: String, by step: Int) -> String {
        firstOfMonth(PFFormat.addDays(monthStart, step > 0 ? 32 : -1))
    }

    static func title(_ monthStart: String) -> String { monthName.string(from: PFFormat.date(monthStart)) }

    static func dayNumber(_ iso: String) -> String { String(Int(iso.suffix(2)) ?? 0) }

    /// The Monday-first weeks that hold a day of the month: five or six rows of seven days.
    static func rows(_ monthStart: String) -> [[String]] {
        let start = PFFormat.monday(of: monthStart)
        var rows: [[String]] = []
        for row in 0..<6 {
            let days = (0..<7).map { PFFormat.addDays(start, row * 7 + $0) }
            if days.contains(where: { $0.prefix(7) == monthStart.prefix(7) }) { rows.append(days) }
        }
        return rows
    }
}

struct PFCalendarContent529: View {
    let index: PFPlanWeekIndexDoc

    @StateObject private var weeks = PFWeekDocs529()
    @State private var monthStart: String
    @State private var selected: String

    init(index: PFPlanWeekIndexDoc) {
        self.index = index
        let first = index.weeks?.first?.from ?? PFAPI.todayISO
        let last = index.weeks?.last?.to ?? PFAPI.todayISO
        let current = index.weeks?.first { $0.week == index.current }?.from
        let today = PFAPI.todayISO
        // Today when the plan covers it; the current week's first day otherwise (a phone whose clock is outside the plan).
        let start = (first...max(first, last)).contains(today) ? today : (current ?? first)
        _selected = State(initialValue: start)
        _monthStart = State(initialValue: PFCalendarMath529.firstOfMonth(start))
    }

    private var firstDay: String { index.weeks?.first?.from ?? monthStart }
    private var lastDay: String { index.weeks?.last?.to ?? monthStart }

    /// The day marked "now": today when the plan covers it, else the current week's first day.
    private var nowDay: String {
        let today = PFAPI.todayISO
        if (firstDay...max(firstDay, lastDay)).contains(today) { return today }
        return index.weeks?.first { $0.week == index.current }?.from ?? firstDay
    }

    private func week(containing day: String) -> PFPlanWeekIndexDoc.Week? {
        index.weeks?.first { ($0.from ?? "") <= day && day <= ($0.to ?? "") }
    }

    private func weekKey(startingOn monday: String) -> String? {
        index.weeks?.first { $0.from == monday }?.week
    }

    private var visibleKeys: [String] {
        let grid = PFCalendarMath529.rows(monthStart).compactMap { weekKey(startingOn: $0[0]) }
        return grid + [week(containing: selected)?.week].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            monthCard
            let key = week(containing: selected)?.week ?? ""
            PFCalendarDayPanel529(day: selected, week: week(containing: selected), doc: weeks.docs[key],
                                  isFailed: weeks.failed.contains(key), isAbsent: weeks.absent.contains(key), reload: { await weeks.reload(visibleKeys) })
        }
        .task(id: monthStart + selected) { await weeks.load(visibleKeys) }
        .reloadsAfterPull529 { await weeks.reload(visibleKeys) }
    }

    // MARK: Month

    private var canGoBack: Bool { monthStart > PFCalendarMath529.firstOfMonth(firstDay) }
    private var canGoForward: Bool { monthStart < PFCalendarMath529.firstOfMonth(lastDay) }

    private var monthCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { monthStart = PFCalendarMath529.shift(monthStart, by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(!canGoBack)
                .accessibilityLabel("Previous month")
                .accessibilityIdentifier("calendar-month-prev")
                Text(PFCalendarMath529.title(monthStart))
                    .pfCaps(15)
                    .foregroundStyle(NoopLook.textPrimary)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("calendar-month-title")
                Button { monthStart = PFCalendarMath529.shift(monthStart, by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(!canGoForward)
                .accessibilityLabel("Next month")
                .accessibilityIdentifier("calendar-month-next")
            }
            .buttonStyle(.plain)
            .foregroundStyle(StrandPalette.accent)
            weekdayRow
            VStack(spacing: 4) {
                ForEach(PFCalendarMath529.rows(monthStart), id: \.first) { days in
                    row(days)
                }
            }
            legend
        }
        .planCard529(padding: 12)
        .containerIdentifier("calendar-month")
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(PFPlanFont543.text(10, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            Text("hours")
                .font(PFPlanFont543.text(10, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 44)
        }
        .accessibilityHidden(true)
    }

    private func row(_ days: [String]) -> some View {
        let key = weekKey(startingOn: days[0])
        let doc = key.flatMap { weeks.docs[$0] }
        return HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                PFCalendarCell529(day: day, isNow: day == nowDay, isSelected: day == selected,
                                  isInMonth: day.prefix(7) == monthStart.prefix(7),
                                  strip: doc?.strip?.first { $0.date == day }) { selected = day }
            }
            Text(hoursText(doc))
                .font(PFPlanFont543.text(11))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityIdentifier("calendar-week-hours-\(days[0])")
        }
    }

    /// Done for a week that is over, planned for the rest.
    private func hoursText(_ doc: PFPlanWeekDoc?) -> String {
        guard let hours = doc?.hours else { return "" }
        let value = doc?.state == "finished" ? (hours.done ?? hours.planned) : (hours.planned ?? hours.firm)
        return value.map { PFHours529.text($0) } ?? ""
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            LookFlowLayout(spacing: 12, lineSpacing: 2) {
                ForEach(["solid = done", "outline = planned", "dashed = optional", "height = minutes"], id: \.self) { text in
                    Text(text)
                        .font(PFPlanFont543.text(11))
                        .foregroundStyle(NoopLook.textSecondary)
                }
            }
            LookFlowLayout(spacing: 12, lineSpacing: 2) {
                ForEach(["easy", "moderate", "hard", "race"], id: \.self) { effort in
                    HStack(spacing: 4) {
                        Circle().fill(PFEffort529.color(effort)).frame(width: 7, height: 7)
                        Text(effort)
                            .font(PFPlanFont543.text(11))
                            .foregroundStyle(NoopLook.textSecondary)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: One day of the grid

struct PFCalendarCell529: View {
    let day: String
    let isNow: Bool
    let isSelected: Bool
    let isInMonth: Bool
    let strip: PFPlanWeekDoc.StripDay?
    let onTap: () -> Void

    private var bars: [PFPlanWeekDoc.Bar] { Array((strip?.bars ?? []).prefix(3)) }

    private var label: String {
        let minutes = bars.compactMap { $0.minutes }.reduce(0, +)
        let what = bars.isEmpty ? "nothing planned" : "\(bars.count) \(bars.count == 1 ? "session" : "sessions"), \(minutes) min"
        return "\(PFFormat.dayTitle(day)), \(what)" + (isNow ? ", today" : "")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(PFCalendarMath529.dayNumber(day))
                    .font(PFPlanFont543.text(11, weight: isNow ? .bold : .medium))
                    .foregroundStyle(isInMonth ? NoopLook.textPrimary : NoopLook.textMuted)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        PFCalendarBar529(bar: bar, width: bars.count == 1 ? 14 : 8)
                    }
                }
                .frame(height: 20, alignment: .bottom)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? StrandPalette.accent.opacity(0.22) : NoopLook.row.opacity(isInMonth ? 1 : 0.4)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isNow ? StrandPalette.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar-day-\(day)")
    }
}

/// One bar: as tall as the session is long, coloured by how hard it is; filled when done, outlined when planned, dashed when optional.
struct PFCalendarBar529: View {
    let bar: PFPlanWeekDoc.Bar
    let width: CGFloat

    private var height: CGFloat { min(20, max(4, CGFloat(bar.minutes ?? 0) * 0.2)) }
    private var color: Color { PFEffort529.color(bar.effort) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Group {
            switch bar.state ?? "planned" {
            case "done":
                shape.fill(color)
            case "missed":
                shape.fill(PFColor.critical.opacity(0.35))
            case "optional":
                shape.strokeBorder(NoopLook.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            default:
                shape.strokeBorder(color, lineWidth: 1.5)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: The chosen day

struct PFCalendarDayPanel529: View {
    let day: String
    let week: PFPlanWeekIndexDoc.Week?
    let doc: PFPlanWeekDoc?
    /// The week's document could not be read (as against not being served: nothing is scheduled then).
    var isFailed = false
    /// The server does not serve the week's document.
    var isAbsent = false
    let reload: () async -> Void

    @State private var results: PFResultsTarget529?
    @State private var addsDayOff = false
    private let hiding = PFHiding()

    private var items: [PFPlanWeekDoc.Item] { doc?.days?.first { $0.date == day }?.items ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: PFFormat.dayTitle(day))
                .padding(.bottom, 4)
            if items.isEmpty {
                if isFailed && doc == nil {
                    HStack(spacing: 10) {
                        Text("This week could not be loaded.")
                            .font(PFPlanFont543.text(14))
                            .foregroundStyle(NoopLook.textSecondary)
                            .accessibilityIdentifier("calendar-day-failed")
                        Spacer(minLength: 6)
                        PFPillButton529(title: "Try again") { Task { await reload() } }
                            .accessibilityIdentifier("calendar-day-retry")
                    }
                    .padding(.vertical, 8)
                } else {
                    // Still loading only while the week is being asked for; a week the server does not serve holds nothing.
                    Text(doc == nil && week != nil && !isAbsent ? "Loading" : "Nothing scheduled")
                        .font(PFPlanFont543.text(14))
                        .foregroundStyle(NoopLook.textSecondary)
                        .padding(.vertical, 8)
                }
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { PFDivider529() }
                itemRow(item)
            }
            HStack(spacing: 6) {
                // "Add an activity" has no phone job yet (server pending): it opens the change-today sheet, which has the coach field.
                PFPillButton529(title: "+ Add an activity") { PFPlan529Router.shared.sheet = .changeToday }
                    .accessibilityIdentifier("calendar-add-activity")
                PFPillButton529(title: "+ Day off") { addsDayOff = true }
                    .accessibilityIdentifier("calendar-add-day-off")
            }
            .padding(.top, 8)
        }
        .planCard529()
        .containerIdentifier("calendar-day-panel")
        .pfResultsSheet529($results)
        .sheet(isPresented: $addsDayOff) { PFDayOffSheet529(day: day, saved: reload) }
    }

    @ViewBuilder private func itemRow(_ item: PFPlanWeekDoc.Item) -> some View {
        switch item.kind ?? "session" {
        case "race":
            Button { pfOpenRace529(item.raceDate ?? day) } label: {
                PFRow529(dot: PFEffort529.color("race"), title: item.title ?? "Race", sub: hiding.text(raceLine(item)), showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar-item-race-\(item.raceDate ?? day)")
        case "rest":
            PFRow529(title: item.title ?? "Rest", sub: item.why)
                .accessibilityIdentifier("calendar-item-rest-\(day)")
        default:
            Button { open(item) } label: {
                PFRow529(dot: PFEffort529.color(item.effort), title: item.title ?? "Session", sub: hiding.text(sessionLine(item)),
                         trailing: item.minutes.map { "\($0) min" }, showsChevron: true)
            }
            .buttonStyle(.plain)
            .disabled(item.sessionId == nil && item.activityId == nil)
            .accessibilityIdentifier("calendar-item-\(item.sessionId ?? item.activityId ?? day)")
        }
    }

    private func raceLine(_ item: PFPlanWeekDoc.Item) -> String {
        if let result = item.result {
            return [result.time, result.delta].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
        return item.effortLabel ?? "Race"
    }

    private func sessionLine(_ item: PFPlanWeekDoc.Item) -> String {
        if let line = item.done?.line, item.status == "done" || item.status == "partial" { return line }
        return [item.effortLabel, item.pills?.first].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// A done session opens the results sheet; one still to do opens the session sheet of its week.
    private func open(_ item: PFPlanWeekDoc.Item) {
        if item.status == "done" || item.status == "partial", let id = item.activityId {
            results = PFResultsTarget529(id: id, title: item.title, date: day)
        } else if let id = item.sessionId, let week = week?.week {
            PFPlan529Router.shared.sheet = .session(week: week, id: id)
        }
    }
}

// MARK: Day off

/// A day off, or a run of them (`dayoff-add`). The server takes today and later.
struct PFDayOffSheet529: View {
    let day: String
    let saved: () async -> Void
    /// Hands back the day off the server just made, for a list that shows it before the document is read again.
    var onAdded: ((PFPlanSettingsDoc.DayOff) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var label = ""
    @State private var start: Date
    @State private var end: Date
    @State private var severalDays = false
    @State private var kind = "holiday"

    init(day: String, saved: @escaping () async -> Void, onAdded: ((PFPlanSettingsDoc.DayOff) -> Void)? = nil) {
        self.day = day
        self.saved = saved
        self.onAdded = onAdded
        let first = max(PFFormat.date(day), Calendar.current.startOfDay(for: Date()))
        _start = State(initialValue: first)
        _end = State(initialValue: first)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Label (for example Holiday)", text: $label)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("day-off-label")
                        Picker("Kind", selection: $kind) {
                            Text("Holiday").tag("holiday")
                            Text("Rest").tag("rest")
                            Text("Travel").tag("travel")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("day-off-kind")
                        DatePicker(severalDays ? "From" : "Day", selection: $start, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                            .accessibilityIdentifier("day-off-start")
                        Toggle("Several days", isOn: $severalDays)
                            .accessibilityIdentifier("day-off-several")
                        if severalDays {
                            DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                                .accessibilityIdentifier("day-off-end")
                        }
                    }
                    .font(PFPlanFont543.text(15))
                    .planCard529()
                    PFEditMessage529(runner: runner)
                    PFPillButton529(title: "Add day off", isMain: true, isDisabled: runner.isBusy) { Task { await save() } }
                        .accessibilityIdentifier("day-off-save")
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle("Day off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
        .containerIdentifier("day-off-sheet")
    }

    private func save() async {
        let first = PFFormat.isoString(start)
        let last = severalDays ? PFFormat.isoString(max(start, end)) : nil
        let inputs = PFPlanInputs529.dayOffAdd(start: first, end: last, label: label.isEmpty ? "Day off" : label, kind: kind)
        if await runner.run(.dayoffAdd, inputs: inputs) {
            let added = PFPlanSettingsDoc.DayOff(id: runner.lastResultID ?? "local-\(first)", start: first, end: last ?? first,
                                                 label: label.isEmpty ? "Day off" : label, kind: kind)
            onAdded?(added)
            await saved()
            dismiss()
        }
    }
}
