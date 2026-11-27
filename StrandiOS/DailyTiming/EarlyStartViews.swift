import SwiftUI
import StrandDesign

// Early start: you give the day, the wake time you need and when to start shifting; the plan moves your wake time one hour a day.
// Nothing is guessed: the wake time and the start day have no default.

/// What was entered, kept so the plan is still there next time.
struct EarlyStartInputs: Equatable {
    var eventDay: String?
    var wake: Int?
    var startDay: String?

    private static let eventKey = "noop.timing.early.event"
    private static let wakeKey = "noop.timing.early.wake"
    private static let startKey = "noop.timing.early.start"

    static var stored: EarlyStartInputs {
        #if DEBUG
        // A UI test starts clean, or with the made-up entries of the `early` fixture.
        if DailyTimingFixture.data != nil { return DailyTimingFixture.earlyInputs }
        #endif
        let defaults = UserDefaults.standard
        return EarlyStartInputs(eventDay: defaults.string(forKey: eventKey), wake: defaults.object(forKey: wakeKey) as? Int,
                                startDay: defaults.string(forKey: startKey))
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(eventDay, forKey: Self.eventKey)
        defaults.set(wake, forKey: Self.wakeKey)
        defaults.set(startDay, forKey: Self.startKey)
    }
}

struct EarlyStartScreen: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var behavior: BehaviorStore
    @State private var data: DailyTimingData?
    @State private var inputs = EarlyStartInputs.stored
    @State private var picking: Field?

    private enum Field: String, Identifiable {
        case event, wake, start
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data {
                if let race = data.race { raceCard(race, today: data.today) }
                entryCard(data)
                planButton(data)
            }
        }
        .planScreen529(title: "Early start", identifier: "early-start-screen")
        .task {
            let loaded = await DailyTimingLoader.load(repo: repo,
                                                      alarmMinutes: behavior.smartAlarmEnabled ? behavior.smartAlarmMinutes : nil)
            data = loaded
            // A day that has passed is not offered again; the next race fills the day.
            if let day = inputs.eventDay, day < loaded.today { inputs = EarlyStartInputs() }
            if inputs.eventDay == nil { inputs.eventDay = loaded.race?.date }
        }
        .sheet(item: $picking) { field in sheet(field) }
    }

    private func raceCard(_ race: PFNextRace, today: String) -> some View {
        let days = max(0, Int(((DailyTiming.date(race.date) ?? Date()).timeIntervalSince(DailyTiming.date(today) ?? Date())) / 86_400))
        return VStack(alignment: .leading, spacing: 6) {
            PFOver529(text: "Next race")
            Text(race.name)
                .font(PFPlanFont543.text(17, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(TimingDates.weekdayDayMonth(race.date)) \u{00B7} in \(days) day\(days == 1 ? "" : "s") \u{00B7} start time not stored")
                .font(PFPlanFont543.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planCard529(padding: 16)
        .containerIdentifier("early-start-race")
    }

    private func entryCard(_ data: DailyTimingData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "You enter")
                .padding(.bottom, 4)
            field(.event, "The day", inputs.eventDay.map(TimingDates.weekdayDayMonth), "choose a date")
            PFDivider529()
            field(.wake, "Wake time on the day", inputs.wake.map(DailyTiming.clock), "--:--")
            PFDivider529()
            field(.start, "Start shifting", inputs.startDay.map(TimingDates.weekdayDayMonth), "choose a date")
        }
        .planCard529(padding: 16)
    }

    private func field(_ field: Field, _ label: String, _ value: String?, _ empty: String) -> some View {
        Button { picking = field } label: {
            PFRow529(title: label, trailing: value ?? empty, showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("early-start-\(field.rawValue)")
    }

    @ViewBuilder private func planButton(_ data: DailyTimingData) -> some View {
        if let event = inputs.eventDay, let wake = inputs.wake, let start = inputs.startDay {
            NavigationLink {
                EarlyStartPlanScreen(currentWake: data.plannerWake, bed: data.bed, targetWake: wake, startDay: start, eventDay: event)
            } label: {
                planLabel
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("early-start-make")
        } else {
            planLabel
                .opacity(0.4)
                .accessibilityLabel("Make plan. Enter the day, the wake time and the start day first.")
        }
    }

    private var planLabel: some View {
        Text("Make plan")
            .lookCaps(13)
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(StrandPalette.accent))
            .contentShape(Capsule())
    }

    @ViewBuilder private func sheet(_ field: Field) -> some View {
        switch field {
        case .wake:
            // The wheel opens on the planner's wake time; it is kept only when Set is tapped.
            TimingTimeSheet(title: "Wake time on the day", initial: inputs.wake ?? data?.plannerWake ?? 0) { minutes in
                inputs.wake = minutes
                inputs.save()
                picking = nil
            }
        case .event, .start:
            let today = data?.today ?? DailyTiming.day(Date())
            TimingDaySheet(title: field == .event ? "The day" : "Start shifting",
                           initial: (field == .event ? inputs.eventDay : inputs.startDay) ?? today, earliest: today) { day in
                if field == .event { inputs.eventDay = day } else { inputs.startDay = day }
                inputs.save()
                picking = nil
            }
        }
    }
}

/// A calendar for one day, from `earliest` on. Nothing is kept until Set is tapped.
struct TimingDaySheet: View {
    let title: String
    let earliest: String
    let onSet: (String) -> Void
    @State private var date: Date

    init(title: String, initial: String, earliest: String, onSet: @escaping (String) -> Void) {
        self.title = title
        self.earliest = earliest
        self.onSet = onSet
        _date = State(initialValue: DailyTiming.date(initial) ?? Date())
    }

    private var range: PartialRangeFrom<Date> {
        // Noon minus half a day: the earliest day itself stays selectable.
        (DailyTiming.date(earliest) ?? Date()).addingTimeInterval(-43_200)...
    }

    var body: some View {
        TimingPickerSheet(title: title) {
            onSet(DailyTiming.day(date))
        } picker: {
            DatePicker(title, selection: $date, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
                .labelsHidden()
        }
        .presentationDetents([.large])
    }
}

struct EarlyStartPlanScreen: View {
    let currentWake: Int
    let bed: Int
    let targetWake: Int
    let startDay: String
    let eventDay: String

    private var plan: DailyTiming.EarlyPlan? {
        DailyTiming.earlyPlan(currentWake: currentWake, bed: bed, targetWake: targetWake, startDay: startDay, eventDay: eventDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan, let total = DailyTiming.earlierBy(current: currentWake, target: targetWake) {
                note("From your planned \(DailyTiming.clock(currentWake)) wake to \(DailyTiming.clock(targetWake)) on \(TimingDates.weekdayDayMonth(eventDay)): \(DailyTiming.duration(total)) earlier.")
                if !plan.days.isEmpty { daysCard(plan) }
                if !plan.reachesTargetInTime {
                    note("From this start day the plan does not reach \(DailyTiming.clock(targetWake)) by \(TimingDates.dayMonth(eventDay)).")
                        .accessibilityIdentifier("early-plan-short")
                }
                shiftCard
            } else {
                note("\(DailyTiming.clock(targetWake)) is not earlier than your planned \(DailyTiming.clock(currentWake)) wake, so there is nothing to shift.")
                    .accessibilityIdentifier("early-plan-nothing")
            }
        }
        .planScreen529(title: "Early start", identifier: "early-start-plan")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(PFPlanFont543.text(13.5))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func daysCard(_ plan: DailyTiming.EarlyPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PFOver529(text: "Each day")
                Spacer(minLength: 8)
                Text("Wake").lookCaps(10).foregroundStyle(NoopLook.textTertiary).frame(width: 64, alignment: .trailing)
                Text("In bed").lookCaps(10).foregroundStyle(NoopLook.textTertiary).frame(width: 64, alignment: .trailing)
            }
            .padding(.bottom, 4)
            ForEach(Array(plan.days.enumerated()), id: \.element.day) { index, day in
                if index > 0 { PFDivider529() }
                dayRow(day)
            }
            if plan.reachesTargetInTime, let last = plan.days.last, last.day < eventDay {
                PFDivider529()
                note("Then wake at \(DailyTiming.clock(targetWake)) up to and including \(TimingDates.weekdayDayMonth(eventDay)).")
                    .padding(.top, 8)
            }
        }
        .planCard529(padding: 16)
        .containerIdentifier("early-plan-days")
    }

    private func dayRow(_ day: DailyTiming.ShiftDay) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TimingDates.weekdayDayMonth(day.day))
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Label("Light on waking", systemImage: "sun.max.fill")
                    .font(PFPlanFont543.text(12.5))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            Spacer(minLength: 8)
            Text(DailyTiming.clock(day.wake)).lookNumeral(24).foregroundStyle(NoopLook.textPrimary)
                .frame(width: 64, alignment: .trailing)
            // The bed on the evening before that wake.
            Text(DailyTiming.clock(day.bed)).lookNumeral(24).foregroundStyle(NoopLook.rest)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(TimingDates.weekdayDayMonth(day.day)): in bed \(DailyTiming.clock(day.bed)) the evening before, wake \(DailyTiming.clock(day.wake)), light on waking")
    }

    private var shiftCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PFOver529(text: "Shift per day")
            Text("1 h").lookNumeral(40).foregroundStyle(NoopLook.textPrimary)
            Text("Get bright light when you wake. In a small trial, 1 h a day with bright light for 3 days moved the body clock about 1.5 h. Race performance was not tested. In bed is the time on the evening before each wake.")
                .font(PFPlanFont543.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planCard529(padding: 16)
    }
}
