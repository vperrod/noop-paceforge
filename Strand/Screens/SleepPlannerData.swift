import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - Sleep Planner: stored choices and the data behind the screen
//
// The maths lives in `SleepPlanner` (StrandAnalytics). This file reads the repository and the existing
// wind-down / alarm settings into its inputs, and keeps the planner's few choices in UserDefaults.

/// The planner's own choices. Plain UserDefaults, like the wind-down nudge's.
enum SleepPlannerStore {
    static let presetKey = "sleepPlanner.preset"
    static let useForReminderKey = "sleepPlanner.useForReminder"
    static let plannedSpanKey = "sleepPlanner.plannedSpanMin"
    static let alarmAtKey = "sleepPlanner.alarmAt"
    static let wakeMinutesKey = "sleepPlanner.wakeMinutes"

    /// The wake time set on the planner screen (minutes after midnight), or nil to use the other sources. It
    /// only feeds the plan; it arms no alarm and schedules no notification.
    static var wakeMinutes: Int? {
        get { SleepPlanner.validWakeMinutes(UserDefaults.standard.object(forKey: wakeMinutesKey) as? Int) }
        set {
            if let m = SleepPlanner.validWakeMinutes(newValue) { UserDefaults.standard.set(m, forKey: wakeMinutesKey) }
            else { UserDefaults.standard.removeObject(forKey: wakeMinutesKey) }
        }
    }

    /// Default Perform (85 % of tonight's need).
    static var preset: SleepPlanner.Preset {
        get {
            UserDefaults.standard.string(forKey: presetKey).flatMap(SleepPlanner.Preset.init(rawValue:)) ?? .default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: presetKey) }
    }

    /// Whether the wind-down reminder counts back from the planned bedtime. Default off.
    static var useForReminder: Bool {
        get { UserDefaults.standard.bool(forKey: useForReminderKey) }
        set { UserDefaults.standard.set(newValue, forKey: useForReminderKey) }
    }

    /// Sleep goal plus time to fall asleep, as of the last time the planner worked it out.
    static var plannedSpanMin: Int? {
        get { UserDefaults.standard.object(forKey: plannedSpanKey) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: plannedSpanKey) }
    }

    /// The span the wind-down reminder should count back over, or nil to keep its own sleep-need setting.
    /// Clamped to the range the reminder can schedule over.
    static var reminderSpanMinutes: Int? {
        guard useForReminder, let span = plannedSpanMin else { return nil }
        return min(max(span, 5 * 60), 12 * 60 + 30)
    }

    /// The moment the planner last armed the strap, while it is still ahead.
    static var armedAlarm: Date? {
        get {
            guard let t = UserDefaults.standard.object(forKey: alarmAtKey) as? Double else { return nil }
            let date = Date(timeIntervalSince1970: t)
            return date > Date() ? date : nil
        }
        set {
            if let newValue { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: alarmAtKey) }
            else { UserDefaults.standard.removeObject(forKey: alarmAtKey) }
        }
    }
}

/// Everything the planner screen and its entry card show for tonight.
struct SleepPlannerData: Equatable {
    var breakdown: SleepPlanner.Breakdown
    var calibration: SleepPlanner.Calibration
    var latencyMin: Int
    var latencyIsPersonal: Bool
    var latencyNights: Int
    var wake: Date
    var wakeSource: SleepPlanner.WakeSource
    var yesterdayEffort: Double?
    var typicalEffort: Double?
    var debtMin: Double
    var napMin: Double
    #if os(iOS)
    /// Set when the figures above are PaceForge's `sleep_need_tonight` (see SleepPlannerIntel.swift); the screens then
    /// draw its tiers and its own words for each row.
    var intelNeed: PFSleepNeed?
    #endif

    var needMin: Int { breakdown.tonightMin }

    func plan(for preset: SleepPlanner.Preset) -> SleepPlanner.Plan {
        SleepPlanner.plan(wake: wake, targetSleepMin: SleepPlanner.targetSleepMin(needMin: needMin, preset: preset),
                          latencyMin: latencyMin)
    }

    func presetRows(selected: SleepPlanner.Preset) -> [SleepPlanner.PresetRow] {
        SleepPlanner.presetRows(needMin: needMin, wake: wake, latencyMin: latencyMin, selected: selected)
    }
}

@MainActor
enum SleepPlannerLoader {

    /// Memo so the entry cards on Today and Sleep do not read a month of sleep blocks on every appearance.
    private static var memo: (key: String, data: SleepPlannerData)?

    /// - Parameter alarmMinutes: the strap alarm's time when it is on, else nil.
    static func load(repo: Repository, alarmMinutes: Int?, now: Date = Date(),
                     calendar: Calendar = .current) async -> SleepPlannerData {
        #if DEBUG
        if let fixture = PlannerFixture.sleepData { return fixture }
        #endif
        let userWake = SleepPlannerStore.wakeMinutes
        let key = "\(repo.refreshSeq)|\(alarmMinutes ?? -1)|\(userWake ?? -1)|\(WindDownNudge.isEnabled)|\(WindDownNudge.wakeMinutes)|"
            + "\(WindDownNudge.perDayWakeOverrides.sorted { $0.key < $1.key })|\(Int(now.timeIntervalSince1970 / 1800))"
        if let memo, memo.key == key { return memo.data }

        let days = repo.days
        let logicalKey = BodyVitalSigns.logicalDayKey(now)
        let todayRow = Repository.resolveToday(days: days, logicalKey: logicalKey, localKey: Repository.localDayKey(now))
        let todayKey = todayRow?.day ?? logicalKey

        let sessions = await repo.allSleepSessions(days: 32)
        let habitual = await DayTimelineLoader.habitualMidsleep(repo)

        // Today's naps are credited below as their own line, so they are taken out of the debt to avoid
        // counting them twice.
        var napByDay = SleepModel.napSleepMinutesByDay(navDays: SleepModel.navDays(navSessions: sessions),
                                                       habitualMidsleepSec: habitual)
        let napToday = napByDay[todayKey] ?? 0
        napByDay[todayKey] = 0
        let ledger = SleepModel.debtLedger(days: days, napSleepMinByDay: napByDay)

        // Yesterday's Effort against the 28 days before it.
        let yesterdayKey = previousDayKey(todayKey, calendar: calendar)
        let yesterdayEffort = days.first(where: { $0.day == yesterdayKey })?.strain
        let typical = SleepPlanner.typicalEffort(
            days.filter { $0.day < yesterdayKey }.suffix(28).compactMap(\.strain))

        let breakdown = SleepPlanner.breakdown(
            baselineMin: SleepModel.debtNeedMin(days: days), yesterdayEffort: yesterdayEffort,
            typicalEffort: typical, debtMin: ledger.magnitudeMin, napMin: napToday)

        let nights = days.suffix(28).filter { ($0.totalSleepMin ?? 0) > 0 }.count

        // Main sleeps of the last four weeks: long enough not to be a nap.
        let cutoff = Int(now.timeIntervalSince1970) - 28 * 86_400
        let mains = sessions.filter { $0.endTs > cutoff && $0.endTs - $0.effectiveStartTs >= 3 * 3_600 }
        let latencies = mains.compactMap {
            SleepPlanner.latencyMinutes(stages: AnalyticsEngine.decodeStages($0.stagesJSON),
                                        sessionStart: $0.effectiveStartTs)
        }
        let latency = SleepPlanner.typicalLatency(latencies)
        let typicalWake = SleepPlanner.typicalWakeMinutes(mains.map { s in
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(s.endTs)))
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })

        let resolved = SleepPlanner.resolveWake(
            userMinutes: userWake, windDownMinutes: WindDownNudge.isEnabled ? WindDownNudge.wakeMinutes : nil,
            alarmMinutes: alarmMinutes, typicalMinutes: typicalWake)
        // Per-weekday wake times retime the reminder and the alarm, so they apply when either supplied the wake.
        let overrides = SleepPlanner.weekdayOverrides(for: resolved.source, WindDownNudge.perDayWakeOverrides)
        let wake = SleepPlanner.nextWake(baseMinutes: resolved.minutes, overrides: overrides, after: now, calendar: calendar)
            ?? now.addingTimeInterval(8 * 3_600)

        let data = SleepPlannerData(
            breakdown: breakdown, calibration: SleepPlanner.calibration(nights: nights),
            latencyMin: latency.minutes, latencyIsPersonal: latency.isPersonal, latencyNights: latencies.count,
            wake: wake, wakeSource: resolved.source, yesterdayEffort: yesterdayEffort, typicalEffort: typical,
            debtMin: ledger.magnitudeMin, napMin: napToday)
        memo = (key, data)
        return data
    }

    /// Tell the wind-down reminder what the planner now thinks, and reschedule it when it follows the plan.
    static func publish(_ data: SleepPlannerData, preset: SleepPlanner.Preset) {
        let plan = data.plan(for: preset)
        let span = plan.targetSleepMin + plan.latencyMin
        let changed = SleepPlannerStore.plannedSpanMin != span
        SleepPlannerStore.plannedSpanMin = span
        if changed && SleepPlannerStore.useForReminder { WindDownNudge.refreshSchedule() }
    }

    /// yyyy-MM-dd of the day before `key`, by calendar days so a clock change cannot skip or repeat a day.
    static func previousDayKey(_ key: String, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key), let previous = calendar.date(byAdding: .day, value: -1, to: date) else {
            return key
        }
        return f.string(from: previous)
    }
}
