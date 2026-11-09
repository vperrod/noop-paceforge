import Foundation

// SleepPlanner.swift — tonight's sleep need, a goal, and the bedtime that reaches it.
//
// Pure, deterministic, DB-free. The caller supplies the personal baseline need (the existing
// `AnalyticsEngine.Rest.personalizedNeedHours`), the 14-night debt (`SleepDebt`), yesterday's Effort and
// the user's typical Effort, today's naps, the wake time and the nights' stage timelines. Nothing here
// reads a clock except through a `Date` or `Calendar` passed in.
//
// Tonight's need, in minutes, is a plain sum so every part can be shown:
//
//   tonight = baseline + effort extra + debt repayment − nap credit
//
//   effort extra     0…45 min.  45 × clamp((yesterday / typical − 1) / 0.5, 0, 1): nothing at or below your
//                    typical Effort, the full 45 min once yesterday ran 50 % above it.
//   debt repayment   25 % of the 14-night debt, at most 60 min a night, so a debt is paid down over several
//                    nights instead of in one.
//   nap credit       minutes asleep in today's naps, at most 60.
//
// With the baseline floored at 8 h and capped at 9.5 h upstream, tonight's need stays between 7 h and
// 11 h 15 min, so no further clamp is needed and the parts always add up to the total.

public enum SleepPlanner {

    // MARK: - Constants

    /// Nights of sleep data before the plan is personal. Matches `AnalyticsEngine.Rest.minNeedNights`.
    public static let minimumNights = 7
    public static let effortExtraMaxMin = 45.0
    /// Yesterday's Effort over typical at which the full extra applies (1.5 = 50 % above typical).
    public static let effortFullAtRatio = 1.5
    public static let debtRepaymentShare = 0.25
    public static let debtRepaymentMaxMin = 60.0
    public static let napCreditMaxMin = 60.0
    /// Typical Effort below this is too small for a ratio to mean anything.
    public static let minimumTypicalEffort = 5.0
    /// Time to fall asleep when the data cannot say.
    public static let defaultLatencyMin = 15
    /// The strap cannot see the minutes between lying down and the first still epoch, and a night is
    /// never planned with an absurd latency either way.
    public static let latencyFloorMin = 5
    public static let latencyCeilingMin = 60
    public static let fallbackWakeMinutes = 7 * 60

    // MARK: - Need breakdown

    public struct Breakdown: Equatable, Sendable {
        public let baselineMin: Int
        public let effortExtraMin: Int
        public let debtRepaymentMin: Int
        public let napCreditMin: Int

        public var tonightMin: Int { baselineMin + effortExtraMin + debtRepaymentMin - napCreditMin }

        /// For a need worked out elsewhere (PaceForge's sleep model) that the planner shows in the same table.
        public init(baselineMin: Int, effortExtraMin: Int, debtRepaymentMin: Int, napCreditMin: Int) {
            self.baselineMin = baselineMin
            self.effortExtraMin = effortExtraMin
            self.debtRepaymentMin = debtRepaymentMin
            self.napCreditMin = napCreditMin
        }
    }

    /// Mean of the supplied daily Effort values, nil under `minimumNights` of them.
    public static func typicalEffort(_ values: [Double]) -> Double? {
        let xs = values.filter { $0.isFinite && $0 >= 0 }
        guard xs.count >= minimumNights else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    public static func effortExtraMin(yesterdayEffort: Double?, typicalEffort: Double?) -> Int {
        guard let y = yesterdayEffort, let t = typicalEffort, y.isFinite, t >= minimumTypicalEffort else { return 0 }
        let scaled = max(0, min(1, (y / t - 1) / (effortFullAtRatio - 1)))
        return Int((effortExtraMaxMin * scaled).rounded())
    }

    public static func debtRepaymentMin(debtMin: Double) -> Int {
        guard debtMin.isFinite, debtMin > 0 else { return 0 }
        return Int(min(debtMin * debtRepaymentShare, debtRepaymentMaxMin).rounded())
    }

    public static func napCreditMin(napMin: Double) -> Int {
        guard napMin.isFinite, napMin > 0 else { return 0 }
        return Int(min(napMin, napCreditMaxMin).rounded())
    }

    public static func breakdown(baselineMin: Double, yesterdayEffort: Double?, typicalEffort: Double?,
                                 debtMin: Double, napMin: Double) -> Breakdown {
        Breakdown(baselineMin: Int(baselineMin.rounded()),
                  effortExtraMin: effortExtraMin(yesterdayEffort: yesterdayEffort, typicalEffort: typicalEffort),
                  debtRepaymentMin: debtRepaymentMin(debtMin: debtMin),
                  napCreditMin: napCreditMin(napMin: napMin))
    }

    // MARK: - Goal presets

    public enum Preset: String, CaseIterable, Equatable, Sendable {
        case getBy, perform, peak

        public static let `default` = Preset.perform

        /// Share of tonight's need the goal aims for.
        public var fraction: Double {
            switch self {
            case .getBy: return 0.70
            case .perform: return 0.85
            case .peak: return 1.0
            }
        }

        public var title: String {
            switch self {
            case .getBy: return "Get by"
            case .perform: return "Perform"
            case .peak: return "Peak"
            }
        }

        public var percentText: String { "\(Int((fraction * 100).rounded())) %" }
    }

    public static func targetSleepMin(needMin: Int, preset: Preset) -> Int {
        Int((Double(needMin) * preset.fraction).rounded())
    }

    // MARK: - Wake time

    public enum WakeSource: Equatable, Sendable {
        /// The wake time set on the planner screen itself.
        case user
        /// The wake time of the wind-down reminder.
        case windDown
        /// The strap alarm's time.
        case alarm
        /// The median of recent wake-ups.
        case typical
        case fallback

        /// Finishes "Taken from ..." / "from ..." on the planner screen.
        public var sourceText: String {
            switch self {
            case .user: return "the wake time you set here"
            case .windDown: return "the wake time of your wind-down reminder"
            case .alarm: return "your strap alarm's time"
            case .typical: return "your typical wake-up"
            case .fallback: return "a default of 07:00, since no wake time is set yet"
            }
        }
    }

    /// A stored planner wake time as minutes after midnight, or nil when it is not a time of day.
    public static func validWakeMinutes(_ minutes: Int?) -> Int? {
        guard let m = minutes, (0..<(24 * 60)).contains(m) else { return nil }
        return m
    }

    /// The wake time (minutes after midnight) to plan for: the one set on the planner screen when there is
    /// one, else the wind-down reminder's when it is on, else the strap alarm's when it is on, else the typical
    /// wake, else 07:00. Planning only: nothing here arms an alarm or a notification.
    public static func resolveWake(userMinutes: Int? = nil, windDownMinutes: Int?, alarmMinutes: Int?,
                                   typicalMinutes: Int?) -> (minutes: Int, source: WakeSource) {
        if let m = validWakeMinutes(userMinutes) { return (m, .user) }
        if let m = windDownMinutes { return (m, .windDown) }
        if let m = alarmMinutes { return (m, .alarm) }
        if let m = typicalMinutes { return (m, .typical) }
        return (fallbackWakeMinutes, .fallback)
    }

    /// The per-weekday wake times (reminder / alarm) that retime the plan: only when one of those supplied the
    /// wake. A time set on the planner screen is explicit and applies to every day, so they are left out.
    public static func weekdayOverrides(for source: WakeSource, _ overrides: [Int: Int]) -> [Int: Int] {
        source == .windDown || source == .alarm ? overrides : [:]
    }

    /// Median wake-up (minutes after midnight), nil under `minimumNights` of them. Wake-ups sit in the
    /// morning, away from midnight, so a plain median is safe.
    public static func typicalWakeMinutes(_ wakeMinutes: [Int]) -> Int? {
        guard wakeMinutes.count >= minimumNights else { return nil }
        let s = wakeMinutes.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : Int((Double(s[mid - 1] + s[mid]) / 2).rounded())
    }

    /// The first wake strictly after `now`. `overrides` are per-weekday wake minutes (1 = Sunday … 7), which
    /// win over `baseMinutes` for their day. Built with `Calendar` so a day that skips or repeats an hour
    /// still lands on the wall-clock time.
    public static func nextWake(baseMinutes: Int, overrides: [Int: Int] = [:], after now: Date,
                                calendar: Calendar) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let minutes = min(max(overrides[weekday] ?? baseMinutes, 0), 24 * 60 - 1)
            guard let wake = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
                                           of: day, matchingPolicy: .nextTime) else { continue }
            if wake > now { return wake }
        }
        return nil
    }

    // MARK: - Falling asleep

    /// Minutes between the session start and the first non-wake epoch, nil without a stage timeline or
    /// with no sleep in it.
    public static func latencyMinutes(stages: [StageSegment], sessionStart: Int) -> Double? {
        let ordered = stages.sorted { $0.start < $1.start }
        guard let first = ordered.first(where: { $0.stage != "wake" && $0.end > $0.start }) else { return nil }
        return Double(max(first.start - sessionStart, 0)) / 60.0
    }

    /// Typical time to fall asleep: the median of the nights' latencies, floored and capped. Under
    /// `minimumNights` of them it is the default and says so.
    public static func typicalLatency(_ latencies: [Double]) -> (minutes: Int, isPersonal: Bool) {
        let xs = latencies.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard xs.count >= minimumNights else { return (defaultLatencyMin, false) }
        let mid = xs.count / 2
        let median = xs.count % 2 == 1 ? xs[mid] : (xs[mid - 1] + xs[mid]) / 2
        return (min(max(Int(median.rounded()), latencyFloorMin), latencyCeilingMin), true)
    }

    // MARK: - Bedtime

    public struct Plan: Equatable, Sendable {
        public let wake: Date
        public let targetSleepMin: Int
        public let latencyMin: Int
        /// When to be in bed with the lights out.
        public let bedtime: Date
        /// When the goal's sleep starts: bedtime plus the time to fall asleep.
        public let asleepBy: Date
    }

    /// Bedtime = wake − target sleep − time to fall asleep. Elapsed-time arithmetic on instants, so a night
    /// that crosses midnight or a clock change still holds exactly the planned hours of sleep.
    public static func plan(wake: Date, targetSleepMin: Int, latencyMin: Int) -> Plan {
        let asleepBy = wake.addingTimeInterval(-Double(targetSleepMin) * 60)
        return Plan(wake: wake, targetSleepMin: targetSleepMin, latencyMin: latencyMin,
                    bedtime: asleepBy.addingTimeInterval(-Double(latencyMin) * 60), asleepBy: asleepBy)
    }

    public struct PresetRow: Equatable, Sendable {
        public let preset: Preset
        public let plan: Plan
        /// Bedtime relative to the selected preset's, in minutes: positive = later, negative = earlier.
        public let bedtimeShiftMin: Int
        /// Sleep relative to the selected preset's, in minutes.
        public let sleepShiftMin: Int
    }

    public static func presetRows(needMin: Int, wake: Date, latencyMin: Int, selected: Preset) -> [PresetRow] {
        let base = plan(wake: wake, targetSleepMin: targetSleepMin(needMin: needMin, preset: selected),
                        latencyMin: latencyMin)
        return Preset.allCases.map { preset in
            let p = plan(wake: wake, targetSleepMin: targetSleepMin(needMin: needMin, preset: preset),
                         latencyMin: latencyMin)
            return PresetRow(preset: preset, plan: p,
                             bedtimeShiftMin: Int((p.bedtime.timeIntervalSince(base.bedtime) / 60).rounded()),
                             sleepShiftMin: p.targetSleepMin - base.targetSleepMin)
        }
    }

    // MARK: - Calibration

    public enum Calibration: Equatable, Sendable {
        /// Fewer than `minimumNights` of sleep data: the plan runs on defaults.
        case needsNights(Int)
        case ready

        public var note: String? {
            switch self {
            case .needsNights(let n): return "Needs \(n) more night\(n == 1 ? "" : "s") to personalise"
            case .ready: return nil
            }
        }
    }

    public static func calibration(nights: Int) -> Calibration {
        nights >= minimumNights ? .ready : .needsNights(minimumNights - max(nights, 0))
    }

    // MARK: - "Wake me when I have slept enough"

    /// The platform cannot watch sleep live while the app is closed, so this is an estimate: the alarm goes
    /// at the moment lights-out plus the time to fall asleep plus the goal would be reached, never later
    /// than the latest wake the user set.
    public static func goalAlarm(lightsOut: Date, latencyMin: Int, goalSleepMin: Int,
                                 latestWake: Date) -> (alarm: Date, isCappedByLatestWake: Bool) {
        let reached = lightsOut.addingTimeInterval(Double(latencyMin + goalSleepMin) * 60)
        return reached > latestWake ? (latestWake, true) : (reached, false)
    }

    // MARK: - Text

    /// "45 min", "8 h", "7 h 45 min".
    public static func durationText(_ minutes: Int) -> String {
        let m = abs(minutes)
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    /// "+30 min", "\u{2212}20 min", "0 min".
    public static func signedDurationText(_ minutes: Int) -> String {
        if minutes == 0 { return "0 min" }
        return (minutes > 0 ? "+" : "\u{2212}") + durationText(minutes)
    }
}
