import Foundation
import StrandAnalytics
import WhoopStore

// What the daily timing screens show: the sleep planner's bedtime (with PaceForge's need when it has it), last night from the
// WHOOP strap only, the planned sessions and the usual class slot from the PaceForge settings. A missing value stays missing.

struct TimingSession: Equatable, Identifiable {
    var id: String
    var name: String
    var durationMin: Int?
    /// A booked class: the only kind the usual class slot speaks for.
    var isClass: Bool

    /// The server's own definition of a booked class (season_doc `_classes`).
    static let classKinds: Set<String> = ["class_session", "hyrox_mixed"]
}

struct TimingJournalLine: Equatable {
    var day: String
    var yes: Bool
}

struct DailyTimingData: Equatable {
    var today: String
    var now: Date
    /// Tonight's bedtime in minutes after midnight, and the moment it falls on.
    var bed: Int
    var bedDate: Date
    var bedSource: String
    /// The planner's wake time the bedtime counts back from.
    var plannerWake: Int
    /// This morning's wake and time asleep, from the WHOOP strap.
    var wokeAt: Int?
    var asleepMin: Double?
    var pattern: DailyTiming.Pattern
    /// The two newest answers to "Did you eat close to bedtime?".
    var ateClose: [TimingJournalLine] = []
    var todaySessions: [TimingSession] = []
    var tomorrowSessions: [TimingSession] = []
    /// The usual class slot of each weekday ("mon" ... "sun") from the PaceForge settings.
    var classSlots: [String: PFClassSlot] = [:]
    var race: PFNextRace?

    var hasLastNight: Bool { asleepMin != nil }
    var tomorrow: String { DailyTiming.addDays(today, 1) }
    var isShortNight: Bool { DailyTiming.needsNap(asleepMin: asleepMin) }

    static func weekdayKey(_ day: String) -> String? {
        DailyTiming.weekday(day).map { ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][$0 - 1] }
    }

    func usualSlot(_ day: String) -> PFClassSlot? { Self.weekdayKey(day).flatMap { classSlots[$0] } }

    /// Today's booked class, the one the usual slot gives a time to.
    var todayClass: TimingSession? { todaySessions.first(where: \.isClass) }

    /// The time shown for today's class: the one set on the session page, else the usual slot.
    func classStart(override: Int?) -> Int? {
        guard todayClass != nil else { return nil }
        return override ?? usualSlot(today)?.startMinutes
    }

    func classDuration(_ session: TimingSession) -> Int? { session.durationMin ?? usualSlot(today)?.minutes }

    func cues(classOverride: Int?) -> [DailyTiming.Cue] {
        DailyTiming.cues(bed: bed, coffeeCutoff: CaffeineDecay.cutoffMinutesSinceMidnight(bedtimeMinutes: bed),
                         asleepMin: asleepMin, sessionStart: classStart(override: classOverride))
    }
}

/// The class time changed on the session page, kept for that day only.
enum TimingClassTimeStore {
    static func key(_ day: String) -> String { "noop.timing.classStart.\(day)" }

    static func minutes(_ day: String) -> Int? { UserDefaults.standard.object(forKey: key(day)) as? Int }

    static func set(_ minutes: Int?, day: String) {
        if let minutes { UserDefaults.standard.set(minutes, forKey: key(day)) }
        else { UserDefaults.standard.removeObject(forKey: key(day)) }
    }
}

@MainActor
enum DailyTimingLoader {
    static let mealQuestion = "Did you eat close to bedtime?"

    static func load(repo: Repository, alarmMinutes: Int?, now: Date = Date()) async -> DailyTimingData {
        #if DEBUG
        if let fixture = DailyTimingFixture.data { return fixture }
        #endif
        let calendar = Calendar.current
        func minutes(_ date: Date) -> Int {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }

        // The same bedtime the sleep planner draws, PaceForge's need and bedtime included when it has them.
        await PFDailyIntelStore.shared.refreshIfStale()
        var planner = await SleepPlannerLoader.load(repo: repo, alarmMinutes: alarmMinutes, now: now)
        let preset = SleepPlannerStore.preset
        if let need = PFDailyIntelStore.shared.current?.sleepNeed {
            planner = planner.applying(need, preset: preset, userWake: SleepPlannerStore.wakeMinutes, now: now)
        }
        let plan = planner.plan(for: preset)
        let wake = minutes(plan.wake)
        let source: String
        if let need = planner.intelNeed {
            source = "PaceForge: you need about \(need.needText ?? DailyTiming.duration(need.needMin))"
        } else {
            source = "Sleep planner: \(preset.title) goal, wake \(DailyTiming.clock(wake))"
        }

        // Last night and the 14-night pattern: the WHOOP strap only.
        let strapRow = Repository.resolveToday(days: repo.strapDays, logicalKey: Repository.logicalDayKey(now),
                                               localKey: Repository.localDayKey(now))
        let today = strapRow?.day ?? Repository.logicalDayKey(now)
        let blocks = await repo.allSleepSessions(days: DailyTiming.patternNights + 2).map { session -> DailyTiming.Block in
            let end = Date(timeIntervalSince1970: TimeInterval(session.endTs))
            return DailyTiming.Block(wakeDay: Repository.localDayKey(end), wakeMinutes: minutes(end),
                                     lengthSec: session.endTs - session.effectiveStartTs)
        }
        let nights = DailyTiming.mainNights(blocks)
        let asleep = strapRow?.totalSleepMin.flatMap { $0 > 0 ? $0 : nil }

        let meals = await repo.journalEntries(days: DailyTiming.patternNights)
            .filter { $0.question == mealQuestion }
            .sorted { $0.day > $1.day }
            .prefix(2)
            .map { TimingJournalLine(day: $0.day, yes: $0.answeredYes) }

        await PFUnified.model.refreshIfStale()
        let snapshot = PFUnified.model.snapshot
        func sessions(_ day: String) -> [TimingSession] {
            (snapshot?.sessions ?? []).filter { $0.date == day && $0.status != "optional" }.map {
                TimingSession(id: $0.id, name: $0.name ?? "Session", durationMin: $0.durationMin.map { Int($0) },
                              isClass: TimingSession.classKinds.contains($0.kind ?? ""))
            }
        }

        return DailyTimingData(
            today: today, now: now, bed: minutes(plan.bedtime), bedDate: plan.bedtime, bedSource: source, plannerWake: wake,
            wokeAt: asleep == nil ? nil : nights[today]?.wakeMinutes, asleepMin: asleep,
            pattern: DailyTiming.pattern(nights, today: today), ateClose: Array(meals),
            todaySessions: sessions(today), tomorrowSessions: sessions(DailyTiming.addDays(today, 1)),
            classSlots: snapshot?.classSlots ?? [:],
            race: snapshot?.races.filter { $0.date >= today }.min { $0.date < $1.date })
    }
}

#if DEBUG
/// Made-up readings for simulator screenshots and UI tests: `-DailyTimingFixture normal | short | evening | weekend | nodata | early`.
/// 2030-03-13 is a Wednesday; nothing here is real data.
enum DailyTimingFixture {
    private static var variant: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-DailyTimingFixture"), args.index(after: i) < args.endIndex else { return nil }
        return args[args.index(after: i)]
    }

    static var earlyInputs: EarlyStartInputs {
        variant == "early" ? EarlyStartInputs(eventDay: "2030-04-02", wake: 3 * 60 + 45, startDay: "2030-03-30") : EarlyStartInputs()
    }

    static var data: DailyTimingData? {
        guard let variant else { return nil }
        let weekend = variant == "weekend"
        let today = weekend ? "2030-03-15" : "2030-03-13"
        let bed = 22 * 60 + 40
        let now = Date()
        // Bedtime is 14 h 40 after "now", so "now" reads as 08:00.
        let bedDate = now.addingTimeInterval(Double(bed - 8 * 60) * 60)
        let strength = TimingSession(id: "s1", name: "Synthetic strength", durationMin: 60, isClass: false)
        let hyrox = TimingSession(id: "s2", name: "Synthetic HYROX class", durationMin: 45, isClass: true)
        let saturday = TimingSession(id: "s3", name: "Synthetic Saturday class", durationMin: 50, isClass: true)
        var data = DailyTimingData(
            today: today, now: now, bed: bed, bedDate: bedDate, bedSource: "PaceForge: you need about 8 h 10",
            plannerWake: 6 * 60 + 15, wokeAt: 5 * 60 + 48, asleepMin: variant == "short" ? 372 : 436,
            pattern: DailyTiming.Pattern(weekdayWake: 5 * 60 + 52, weekendWake: 7 * 60 + 5, weekdayNights: 10, weekendNights: 4),
            ateClose: [TimingJournalLine(day: "2030-03-12", yes: true), TimingJournalLine(day: "2030-03-11", yes: false)],
            todaySessions: [variant == "evening" ? hyrox : strength],
            tomorrowSessions: weekend ? [saturday] : [],
            classSlots: ["wed": PFClassSlot(startMinutes: 19 * 60, minutes: 60),
                         "sat": PFClassSlot(startMinutes: 7 * 60, minutes: 60)],
            race: PFNextRace(name: "Synthetic HYROX race", date: "2030-04-02", daysOut: 20, goalTime: nil))
        if variant == "nodata" {
            data.wokeAt = nil
            data.asleepMin = nil
            data.todaySessions = []
        }
        return data
    }
}
#endif
