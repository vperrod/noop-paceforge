import SwiftUI
import StrandDesign
import StrandAnalytics

// The daily timing plan: the Today card, the day in time order, and the reason behind every cue. The look's cards, D-DIN times
// and data colours; every figure comes from DailyTimingData.

// MARK: - Loading

/// Loads the plan and hands it to the screen; reloads when the strap data, PaceForge's files or the day's class time change.
private struct DailyTimingHost<Content: View>: View {
    @ViewBuilder let content: (DailyTimingData, Int?) -> Content
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var behavior: BehaviorStore
    @ObservedObject private var intel = PFDailyIntelStore.shared
    @ObservedObject private var model = PFUnified.model
    @State private var data: DailyTimingData?
    @State private var classOverride: Int?

    private var alarmMinutes: Int? { behavior.smartAlarmEnabled ? behavior.smartAlarmMinutes : nil }
    private var loadKey: String {
        "\(repo.refreshSeq)|\(alarmMinutes ?? -1)|\(intel.intel?.generatedAt ?? "")|\(model.snapshot?.generatedAt ?? "")"
    }

    var body: some View {
        Group {
            if let data {
                content(data, classOverride)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task(id: loadKey) {
            let loaded = await DailyTimingLoader.load(repo: repo, alarmMinutes: alarmMinutes)
            guard !Task.isCancelled else { return }
            data = loaded
            classOverride = TimingClassTimeStore.minutes(loaded.today)
        }
        .onAppear { if let day = data?.today { classOverride = TimingClassTimeStore.minutes(day) } }
        // Beside the load, never ahead of it.
        .task {
            await intel.refreshIfStale()
            await model.refreshIfStale()
        }
    }
}

// MARK: - A cue as words and a mark

struct TimingCueText: Equatable {
    var title: String
    var sub: String
    var strength: String?
    var symbol: String
    var color: Color

    static func make(_ cue: DailyTiming.Cue, data: DailyTimingData, classOverride: Int?) -> TimingCueText {
        switch cue.kind {
        case .daylight:
            return TimingCueText(title: "Daylight", sub: "No set time or minutes", strength: nil,
                                 symbol: "sun.max.fill", color: NoopLook.chargeMedium)
        case .nap:
            return TimingCueText(title: "Nap, optional",
                                 sub: "\(DailyTiming.clock(DailyTiming.napStartMin))\u{2013}\(DailyTiming.clock(DailyTiming.napEndMin)), under 1 h",
                                 strength: "Moderate to weak", symbol: "powersleep", color: NoopLook.stageRem)
        case .coffee:
            return TimingCueText(title: "Coffee cut-off",
                                 sub: data.isShortNight ? "No coffee nap after this" : "\(coffeeLead) before bed",
                                 strength: "Weak as a fixed time", symbol: "cup.and.saucer.fill", color: NoopLook.zones[3])
        case .session:
            let name = data.todayClass?.name ?? "Class"
            return TimingCueText(title: name,
                                 sub: classOverride == nil ? "Usual class time, not booked" : "Your time for today",
                                 strength: nil, symbol: "figure.run", color: NoopLook.effort)
        case .hardTraining:
            let untimed = data.todaySessions.first { !$0.isClass || data.classStart(override: classOverride) == nil }
            return TimingCueText(title: "Hard training done by",
                                 sub: untimed.map { "\($0.name) today has no time set" } ?? "4 h before bed",
                                 strength: "Moderate", symbol: "flame.fill", color: NoopLook.effort)
        case .dimLights:
            return TimingCueText(title: "Dim the lights", sub: "3 h before bed", strength: "Moderate",
                                 symbol: "light.min", color: NoopLook.stageLight)
        case .bed:
            return TimingCueText(title: "In bed", sub: data.bedSource, strength: nil,
                                 symbol: "bed.double.fill", color: NoopLook.rest)
        }
    }

    /// "11 h": the app's caffeine rule.
    static var coffeeLead: String { DailyTiming.duration(Int(CaffeineDecay.cutoffLeadHours() * 60)) }
}

/// One cue: a coloured mark, what it is and the time in the look's numerals.
struct TimingCueRow: View {
    let text: TimingCueText
    let time: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: text.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(text.color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(text.color.opacity(0.18)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Text(text.sub)
                    .font(PFPlanFont543.text(12.5))
                    .foregroundStyle(NoopLook.textSecondary)
                if let strength = text.strength {
                    Text(strength).lookCaps(9.5).foregroundStyle(NoopLook.textTertiary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let time {
                Text(time).lookNumeral(26).foregroundStyle(NoopLook.textPrimary)
            } else {
                Text("Day").lookCaps(12).foregroundStyle(NoopLook.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - 1. Today card

struct DailyTimingTodayCard: View {
    var body: some View {
        DailyTimingHost { data, classOverride in
            card(data, classOverride)
        }
    }

    private func card(_ data: DailyTimingData, _ classOverride: Int?) -> some View {
        let next = data.hasLastNight
            ? DailyTiming.nextCue(data.cues(classOverride: classOverride), bed: data.bed, bedDate: data.bedDate, now: data.now)
            : nil
        return NavigationLink(value: TabRoute.dailyTiming) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Today's timing").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
                    Spacer(minLength: 8)
                    Text("See the day").lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                .padding(.bottom, 6)
                if let next {
                    let text = TimingCueText.make(next, data: data, classOverride: classOverride)
                    // A session keeps its own name; the other cues read on from "Next:".
                    let title = next.kind == .session ? text.title : text.title.lowercasedFirst
                    TimingCueRow(text: TimingCueText(title: "Next: \(title)", sub: text.sub, strength: nil,
                                                     symbol: text.symbol, color: text.color),
                                 time: next.minutes.map(DailyTiming.clock), showsChevron: false)
                    PFDivider529()
                }
                TimingCueRow(text: TimingCueText(title: "Tonight: in bed", sub: data.bedSource, strength: nil,
                                                 symbol: "bed.double.fill", color: NoopLook.rest),
                             time: DailyTiming.clock(data.bed), showsChevron: false)
            }
            .planCard529()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daily-timing-today-card")
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

// MARK: - 2, 5, 10. The day

struct DailyTimingScreen: View {
    var body: some View {
        DailyTimingHost { data, classOverride in
            VStack(alignment: .leading, spacing: 12) {
                if data.hasLastNight {
                    Text(header(data))
                        .font(PFPlanFont543.text(13.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("daily-timing-header")
                } else {
                    waiting
                }
                cueCard(data, classOverride)
                if data.hasLastNight { links(data) }
                earlyStartLink
            }
        }
        .planScreen529(title: "Today's timing", identifier: "daily-timing-screen")
    }

    private func header(_ data: DailyTimingData) -> String {
        var parts = [TimingDates.weekdayDayMonth(data.today)]
        if let woke = data.wokeAt { parts.append("woke \(DailyTiming.clock(woke))") }
        if let asleep = data.asleepMin { parts.append("slept \(DailyTiming.duration(Int(asleep.rounded()))) (WHOOP)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            PFOver529(text: "Waiting for last night")
            Text("No wake time or time asleep from the WHOOP strap yet.")
                .font(PFPlanFont543.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planCard529()
        .containerIdentifier("daily-timing-waiting")
    }

    /// Every cue in time order; with no last night, only bedtime.
    private func cueCard(_ data: DailyTimingData, _ classOverride: Int?) -> some View {
        let cues = data.cues(classOverride: classOverride).filter { data.hasLastNight || $0.kind == .bed }
        return VStack(spacing: 0) {
            ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                if index > 0 { PFDivider529() }
                NavigationLink {
                    destination(cue, data)
                } label: {
                    TimingCueRow(text: TimingCueText.make(cue, data: data, classOverride: classOverride),
                                 time: cue.minutes.map(DailyTiming.clock))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("timing-cue-\(cue.kind.rawValue)")
            }
        }
        .planCard529()
        .containerIdentifier("daily-timing-cues")
    }

    @ViewBuilder private func destination(_ cue: DailyTiming.Cue, _ data: DailyTimingData) -> some View {
        if cue.kind == .session {
            TimingSessionScreen(data: data)
        } else {
            TimingWhyScreen(why: TimingWhy.make(cue.kind, data: data))
        }
    }

    private func links(_ data: DailyTimingData) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                TimingWhyScreen(why: TimingWhy.meals(data))
            } label: {
                PFRow529(title: "Meals: no cut-off time", sub: "Why there is none", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timing-meals")
            if DailyTiming.isWeekend(data.tomorrow) {
                PFDivider529()
                NavigationLink {
                    TimingWeekendScreen(data: data)
                } label: {
                    PFRow529(title: "Tomorrow's timing", sub: "Your weekend pattern", showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timing-weekend")
            }
        }
        .planCard529()
    }

    private var earlyStartLink: some View {
        NavigationLink {
            EarlyStartScreen()
        } label: {
            PFRow529(title: "Early start", sub: "Move your wake time before a race or a meeting", showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timing-early-start")
        .planCard529()
    }
}

enum TimingDates {
    private static func text(_ day: String, _ format: String) -> String {
        guard let date = DailyTiming.date(day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        // No-break spaces: a date never splits over two lines.
        return formatter.string(from: date).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    static func weekdayDayMonth(_ day: String) -> String { text(day, "EEE d MMM") }
    static func dayMonth(_ day: String) -> String { text(day, "d MMM") }
    static func weekdayName(_ day: String) -> String { text(day, "EEEE") }
}

// MARK: - 3, 4. Why

struct TimingWhy: Equatable {
    struct Card: Equatable {
        var title: String
        var paragraphs: [String]
    }

    var id: String
    var title: String
    var big: String
    var cards: [Card]

    private static func make(_ id: String, _ title: String, _ big: String, why: [String], sure: String) -> TimingWhy {
        TimingWhy(id: id, title: title, big: big, cards: [Card(title: "Why", paragraphs: why),
                                                          Card(title: "How sure", paragraphs: [sure])])
    }

    static func make(_ kind: DailyTiming.Kind, data: DailyTimingData) -> TimingWhy {
        let cutoff = CaffeineDecay.cutoffMinutesSinceMidnight(bedtimeMinutes: data.bed)
        switch kind {
        case .daylight:
            return make("daylight", "Daylight", "No time",
                        why: ["Bright light by day, daylight first, is the expert advice.",
                              "Light after your body clock's low point moves the clock earlier; light before it moves it later. The research read gives no morning window and no number of minutes."],
                        sure: "The direction: moderate. A set time or number of minutes: no good evidence.")
        case .nap:
            return make("nap", "Nap, optional", "13\u{2013}16",
                        why: ["Shown because last night's WHOOP time asleep was under 6 h 30.",
                              "Between 13:00 and 16:00, under 1 h. Under 30 min if time is short. Skip it if you struggle to sleep at night.",
                              "In trials, naps of 30 to under 60 min helped thinking and physical performance, also after a short night."],
                        sure: "Moderate to weak. The performance studies are in men aged 18 to 35.")
        case .coffee:
            return make("coffee", "Coffee cut-off", DailyTiming.clock(cutoff),
                        why: ["This is NOOP's caffeine rule. A dose halves about every \(DailyTiming.halfLife) h, a population average, so yours may be faster or slower.",
                              "The cut-off is two halvings, \(TimingCueText.coffeeLead), before your \(DailyTiming.clock(data.bed)) bedtime, when about a quarter of a dose is left. The time is the same for any dose.",
                              "Research says the dose matters: a model of 24 studies put about 107 mg at least 8.8 h before bed and 217 mg about 13 h. In one trial of 23 men, 100 mg had no significant effect even 4 h before."],
                        sure: "That dose and timing matter: moderate. Any one fixed cut-off, this one included: weak.")
        case .hardTraining:
            return make("hardTraining", "Hard training done by", DailyTiming.clock(data.bed - DailyTiming.hardTrainingLeadMin),
                        why: ["Finishing 4 h or more before sleep showed no link with worse sleep in a large study of WHOOP users. It watched people and did not test them, so no link is not proof.",
                              "Trials suggest 2 to 4 h before bed is mostly fine. Hard exercise ending within 1 h of bed may hurt sleep."],
                        sure: "Moderate.")
        case .dimLights:
            return make("dimLights", "Dim the lights", DailyTiming.clock(data.bed - DailyTiming.dimLightsLeadMin),
                        why: ["Experts advise very dim light for at least 3 h before bed, and a darker bedroom still.",
                              "How strongly evening light affects the body clock differs a lot between people."],
                        sure: "Moderate for the body clock, weaker for sleep itself.")
        case .bed, .session:
            return make("bed", "In bed", DailyTiming.clock(data.bed),
                        why: ["This is the sleep planner's bedtime for tonight. This plan does not change it.", data.bedSource + "."],
                        sure: "Regular sleep times help. No research limit is known for how far they may drift.")
        }
    }

    static func meals(_ data: DailyTimingData) -> TimingWhy {
        var why = make("meals", "Last meal", "No time",
                       why: ["There is no good evidence for a cut-off.",
                             "A 20-person trial found similar sleep stages with dinner 1 h or 5 h before bed. A companion report found worse overnight glucose handling after the late dinner."],
                       sure: "Weak: no good evidence for any number of hours.")
        let journal = data.ateClose.map { "\(TimingDates.dayMonth($0.day)): ate close to bed, \($0.yes ? "yes" : "no")." }
        why.cards.insert(Card(title: "Your journal",
                              paragraphs: journal.isEmpty ? ["Not answered in the last 14 days."] : journal), at: 1)
        return why
    }
}

extension DailyTiming {
    /// "5.5": the app's caffeine half-life.
    static var halfLife: String { String(format: "%.1f", CaffeineDecay.defaultHalfLifeHours) }
}

struct TimingWhyScreen: View {
    let why: TimingWhy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(why.big)
                .lookNumeral(64)
                .foregroundStyle(NoopLook.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityIdentifier("timing-why-big")
            ForEach(why.cards, id: \.title) { card in
                VStack(alignment: .leading, spacing: 8) {
                    PFOver529(text: card.title)
                    ForEach(card.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(PFPlanFont543.text(15))
                            .foregroundStyle(NoopLook.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .planCard529(padding: 16)
            }
        }
        .planScreen529(title: why.title, identifier: "timing-why-\(why.id)")
    }
}

// MARK: - 6. Weekend

struct TimingWeekendScreen: View {
    let data: DailyTimingData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            patternCard
            tomorrowCard
            Text("Regular sleep times help. No research limit is known for weekend drift, so nothing here is scored.")
                .font(PFPlanFont543.text(12.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planScreen529(title: "Tomorrow's timing", identifier: "timing-weekend-screen")
    }

    private var patternCard: some View {
        let pattern = data.pattern
        return VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: "Your pattern, 14 nights")
            wakeRow("Weekday wake", pattern.weekdayWake)
            PFDivider529()
            wakeRow("Weekend wake", pattern.weekendWake)
            Text(footnote(pattern))
                .font(PFPlanFont543.text(12.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planCard529(padding: 16)
        .containerIdentifier("timing-weekend-pattern")
    }

    private func wakeRow(_ label: String, _ minutes: Int?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 8)
            Text(minutes.map(DailyTiming.clock) ?? "\u{2013}")
                .lookNumeral(34)
                .foregroundStyle(NoopLook.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func footnote(_ pattern: DailyTiming.Pattern) -> String {
        let nights = "WHOOP, \(pattern.weekdayNights) weekday and \(pattern.weekendNights) weekend nights"
        guard let weekdays = pattern.weekdayWake, let weekend = pattern.weekendWake else { return nights }
        let difference = weekend - weekdays
        if difference == 0 { return "The same time on both (\(nights))" }
        return "Weekends \(DailyTiming.duration(difference)) \(difference > 0 ? "later" : "earlier") (\(nights))"
    }

    private var tomorrowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PFOver529(text: TimingDates.weekdayName(data.tomorrow))
            if data.tomorrowSessions.isEmpty {
                line("Nothing on the plan.")
            }
            ForEach(data.tomorrowSessions) { session in
                Text([session.name, session.durationMin.map { "\($0) min" }].compactMap { $0 }.joined(separator: ", "))
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if session.isClass, let slot = data.usualSlot(data.tomorrow) {
                    line("No time on the plan. Your usual \(TimingDates.weekdayName(data.tomorrow)) class is \(DailyTiming.clock(slot.startMinutes)), not a booking.")
                } else {
                    line("No time on the plan.")
                }
            }
        }
        .planCard529(padding: 16)
        .containerIdentifier("timing-weekend-tomorrow")
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(PFPlanFont543.text(13.5))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 7. Evening session

struct TimingSessionScreen: View {
    let data: DailyTimingData
    @State private var override: Int?
    @State private var isChanging = false

    init(data: DailyTimingData) {
        self.data = data
        _override = State(initialValue: TimingClassTimeStore.minutes(data.today))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = data.todayClass, let start = data.classStart(override: override) {
                let duration = data.classDuration(session)
                Text([session.name, duration.map { "\($0) min" }].compactMap { $0 }.joined(separator: ", "))
                    .font(PFPlanFont543.text(13.5))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                timeCard(start)
                if let duration { endCard(start: start, duration: duration) }
            }
        }
        .planScreen529(title: TimingDates.weekdayDayMonth(data.today), identifier: "timing-session-screen")
        .sheet(isPresented: $isChanging) {
            TimingTimeSheet(title: "Session time", initial: data.classStart(override: override) ?? 0) { minutes in
                override = minutes
                TimingClassTimeStore.set(minutes, day: data.today)
            }
        }
    }

    private func timeCard(_ start: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: "Session time")
            HStack(alignment: .firstTextBaseline) {
                Text(override == nil ? "Usual \(TimingDates.weekdayName(data.today)) class" : "Your time for today")
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(DailyTiming.clock(start))
                    .lookNumeral(34)
                    .foregroundStyle(NoopLook.textPrimary)
                    .accessibilityIdentifier("timing-session-start")
            }
            if override == nil {
                Text("From your PaceForge routine. Not a booking.")
                    .font(PFPlanFont543.text(12.5))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            HStack(spacing: 10) {
                PFPillButton529(title: "Change time") { isChanging = true }
                    .accessibilityIdentifier("timing-session-change")
                if override != nil, data.usualSlot(data.today) != nil {
                    PFPillButton529(title: "Use usual time") {
                        override = nil
                        TimingClassTimeStore.set(nil, day: data.today)
                    }
                    .accessibilityIdentifier("timing-session-usual")
                }
            }
        }
        .planCard529(padding: 16)
    }

    private func endCard(start: Int, duration: Int) -> some View {
        let gap = DailyTiming.gapToBed(start: start, durationMin: duration, bed: data.bed)
        let bed = DailyTiming.clock(data.bed)
        let sub = gap >= 0 ? "\(DailyTiming.duration(gap)) before tonight's \(bed) bed" : "After tonight's \(bed) bedtime"
        return VStack(alignment: .leading, spacing: 8) {
            TimingCueRow(text: TimingCueText(title: "Class would end", sub: sub, strength: nil,
                                             symbol: "flag.checkered", color: NoopLook.effort),
                         time: DailyTiming.clock(start + duration), showsChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("timing-session-end")
            if DailyTiming.endsInsideHardWindow(start: start, durationMin: duration, bed: data.bed) {
                Text("Under 4 h before bed. Studies suggest 2 to 4 h is mostly fine. Ending within 1 h may hurt sleep.")
                    .font(PFPlanFont543.text(13.5))
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("timing-session-window")
            }
        }
        .planCard529(padding: 16)
    }
}

/// The full-width filled button of these screens; greyed, not faded, while it cannot be used.
struct TimingPrimaryLabel: View {
    let title: String
    var isDisabled = false

    var body: some View {
        Text(title)
            .lookCaps(13)
            .foregroundStyle(isDisabled ? NoopLook.textTertiary : Color.black.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(isDisabled ? NoopLook.row : StrandPalette.accent))
            .contentShape(Capsule())
    }
}

/// A wheel for a time of day. Nothing is kept until Set is tapped.
struct TimingTimeSheet: View {
    let title: String
    let onSet: (Int) -> Void
    @State private var time: Date
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: Int, onSet: @escaping (Int) -> Void) {
        self.title = title
        self.onSet = onSet
        _time = State(initialValue: Calendar.current.date(bySettingHour: DailyTiming.wrap(initial) / 60,
                                                          minute: DailyTiming.wrap(initial) % 60, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        TimingPickerSheet(title: title) {
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            onSet((c.hour ?? 0) * 60 + (c.minute ?? 0))
            dismiss()
        } picker: {
            DatePicker(title, selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
        }
    }
}

/// The frame of a picker sheet: the title, the picker and Set.
struct TimingPickerSheet<Content: View>: View {
    let title: String
    let onSet: () -> Void
    @ViewBuilder let picker: () -> Content

    var body: some View {
        VStack(spacing: 16) {
            Text(title).lookCaps(13).foregroundStyle(NoopLook.textSecondary)
            picker()
            PFPillButton529(title: "Set", isMain: true, action: onSet)
                .accessibilityIdentifier("timing-picker-set")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .lookScreenBackground()
        .presentationDetents([.medium, .large])
    }
}
