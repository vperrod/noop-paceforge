import Foundation

// Weekly goals: a plan for the week made of two or three measurable targets taken from NOOP's own data, with a
// progress figure for each. The week runs Monday to Sunday. Foundation only and pure (no store, no clock), so
// the counting rules below are unit-tested; the loader that gathers a week's figures and the card that shows
// them are in WeeklyGoalsCard.swift. Everything is kept on this device.

// MARK: - Metrics

/// What a weekly target counts. Each is a number of nights, days or minutes in the Monday-to-Sunday week.
enum WeeklyGoalMetric: String, CaseIterable, Codable, Identifiable {
    /// Nights with at least `sleepHoursMinutes` of sleep.
    case sleepHours
    /// Nights whose bedtime is within `consistencyWindowMinutes` of your usual bedtime.
    case sleepConsistency
    /// Minutes in heart-rate zones 4 and 5, over the week.
    case zone45Minutes
    /// Days with at least `stepsThreshold` steps.
    case steps
    /// Nights you were asleep by your planned bedtime (plus `windDownGraceMinutes`).
    case windDown

    var id: String { rawValue }

    static let sleepHoursMinutes = 7 * 60
    static let consistencyWindowMinutes = 45
    static let stepsThreshold = 8_000
    static let windDownGraceMinutes = 30

    var title: String {
        switch self {
        case .sleepHours: return "Sleep \(Self.sleepHoursMinutes / 60) hours or more"
        case .sleepConsistency: return "Regular bedtime"
        case .zone45Minutes: return "Hard effort"
        case .steps: return "Active days"
        case .windDown: return "Wind down on time"
        }
    }

    /// One line on what is counted.
    var detail: String {
        switch self {
        case .sleepHours:
            return "Nights with at least \(Self.sleepHoursMinutes / 60) hours of sleep."
        case .sleepConsistency:
            return "Nights you went to bed within \(Self.consistencyWindowMinutes) minutes of your usual bedtime."
        case .zone45Minutes:
            return "Minutes this week with your heart rate in zones 4 and 5."
        case .steps:
            return "Days with at least 8,000 steps."
        case .windDown:
            return "Nights you were asleep by your planned bedtime. Needs the wind-down reminder to be on."
        }
    }

    /// The word after the number: "4 of 5 nights".
    var unit: String {
        switch self {
        case .sleepHours, .sleepConsistency, .windDown: return "nights"
        case .zone45Minutes: return "min"
        case .steps: return "days"
        }
    }

    var defaultTarget: Int {
        switch self {
        case .sleepHours: return 5
        case .sleepConsistency: return 5
        case .zone45Minutes: return 60
        case .steps: return 5
        case .windDown: return 4
        }
    }

    var targetRange: ClosedRange<Int> {
        switch self {
        case .sleepHours, .sleepConsistency, .windDown, .steps: return 1...7
        case .zone45Minutes: return 10...300
        }
    }

    var targetStep: Int { self == .zone45Minutes ? 10 : 1 }

    func clamped(_ target: Int) -> Int { min(max(target, targetRange.lowerBound), targetRange.upperBound) }
}

// MARK: - Plans

struct WeeklyGoalTarget: Codable, Equatable, Identifiable {
    var metric: WeeklyGoalMetric
    var target: Int
    var id: String { metric.rawValue }
}

/// The three presets, and a custom plan the person puts together.
enum WeeklyGoalPreset: String, CaseIterable, Codable, Identifiable {
    case sleepDeeper
    case boostFitness
    case feelBetter
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepDeeper: return "Sleep deeper"
        case .boostFitness: return "Boost fitness"
        case .feelBetter: return "Feel better"
        case .custom: return "Custom"
        }
    }

    var summary: String {
        switch self {
        case .sleepDeeper: return "Enough sleep, at a steady time, with a wind-down."
        case .boostFitness: return "Hard minutes, active days and enough sleep to absorb them."
        case .feelBetter: return "Move most days, sleep enough, keep a steady bedtime."
        case .custom: return "Pick two or three targets and set your own numbers."
        }
    }

    /// The preset's targets. Custom has none until the person sets them.
    var targets: [WeeklyGoalTarget] {
        switch self {
        case .sleepDeeper:
            return [WeeklyGoalTarget(metric: .sleepHours, target: 5),
                    WeeklyGoalTarget(metric: .sleepConsistency, target: 5),
                    WeeklyGoalTarget(metric: .windDown, target: 4)]
        case .boostFitness:
            return [WeeklyGoalTarget(metric: .zone45Minutes, target: 60),
                    WeeklyGoalTarget(metric: .steps, target: 5),
                    WeeklyGoalTarget(metric: .sleepHours, target: 5)]
        case .feelBetter:
            return [WeeklyGoalTarget(metric: .steps, target: 5),
                    WeeklyGoalTarget(metric: .sleepHours, target: 5),
                    WeeklyGoalTarget(metric: .sleepConsistency, target: 4)]
        case .custom:
            return []
        }
    }
}

struct WeeklyGoalPlan: Codable, Equatable {
    var preset: WeeklyGoalPreset
    var targets: [WeeklyGoalTarget]

    static func preset(_ preset: WeeklyGoalPreset) -> WeeklyGoalPlan {
        WeeklyGoalPlan(preset: preset, targets: preset.targets)
    }

    /// A custom plan from the person's picks: at most three targets, each clamped to its range, one per metric.
    static func custom(_ picks: [WeeklyGoalTarget]) -> WeeklyGoalPlan {
        var seen = Set<WeeklyGoalMetric>()
        let kept = picks.filter { seen.insert($0.metric).inserted }.prefix(3)
            .map { WeeklyGoalTarget(metric: $0.metric, target: $0.metric.clamped($0.target)) }
        return WeeklyGoalPlan(preset: .custom, targets: Array(kept))
    }

    var needsWindDown: Bool { targets.contains { $0.metric == .windDown } }
}

// MARK: - A week's figures

/// One day of the week, as the loader gathers it. Bedtimes are minutes after midnight on the clock (23:30 is
/// 1410), the bedtime of the night that ended with this day's morning.
struct WeeklyGoalDay: Equatable {
    var day: String
    var sleepMinutes: Double?
    var bedtimeMinute: Int?
    var plannedBedtimeMinute: Int?
    var steps: Int?
    var zone45Minutes: Double?

    init(day: String, sleepMinutes: Double? = nil, bedtimeMinute: Int? = nil, plannedBedtimeMinute: Int? = nil,
         steps: Int? = nil, zone45Minutes: Double? = nil) {
        self.day = day
        self.sleepMinutes = sleepMinutes
        self.bedtimeMinute = bedtimeMinute
        self.plannedBedtimeMinute = plannedBedtimeMinute
        self.steps = steps
        self.zone45Minutes = zone45Minutes
    }
}

struct WeeklyGoalProgress: Equatable, Identifiable {
    var metric: WeeklyGoalMetric
    var value: Double
    var target: Int
    var id: String { metric.rawValue }

    /// 0...1, capped at 1 once the target is reached.
    var fraction: Double { target > 0 ? min(max(value / Double(target), 0), 1) : 0 }
    var isMet: Bool { target > 0 && value >= Double(target) }

    /// "4 of 5 nights", "35 of 60 min".
    var valueText: String { "\(Int(value.rounded())) of \(target) \(metric.unit)" }

    var accessibilityText: String {
        "\(metric.title): \(valueText)" + (isMet ? ", done" : "")
    }
}

// MARK: - Engine

enum WeeklyGoalEngine {

    // MARK: Week

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private static func date(_ day: String) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The Monday (yyyy-MM-dd) of the week holding `day`. A Sunday belongs to the week that began the Monday
    /// before it. An unreadable day is returned unchanged.
    static func weekStart(containing day: String) -> String {
        guard let date = date(day) else { return day }
        let weekday = calendar.component(.weekday, from: date)   // 1 = Sunday
        let back = (weekday + 5) % 7
        return key(calendar.date(byAdding: .day, value: -back, to: date) ?? date)
    }

    /// The seven days (Monday first) of the week that starts on `start`.
    static func weekDays(startingAt start: String) -> [String] {
        guard let first = date(start) else { return [start] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first).map(key) }
    }

    /// Calendar weekday (1 = Sunday ... 7 = Saturday) of a yyyy-MM-dd day, or nil when unreadable.
    static func weekday(of day: String) -> Int? {
        date(day).map { calendar.component(.weekday, from: $0) }
    }

    // MARK: Clock arithmetic

    /// The shorter way round the 24-hour clock between two minutes-after-midnight, 0...720.
    static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let diff = abs(a - b) % 1_440
        return min(diff, 1_440 - diff)
    }

    /// How far `a` is after `b` on the clock, in minutes, -720...720 (negative = earlier).
    static func signedDifference(_ a: Int, from b: Int) -> Int {
        var diff = (a - b) % 1_440
        if diff > 720 { diff -= 1_440 }
        if diff <= -720 { diff += 1_440 }
        return diff
    }

    /// The usual bedtime: the circular mean of the bedtimes, so 23:30 and 00:30 average to midnight and not
    /// to noon. nil with no bedtimes.
    static func usualBedtime(_ minutes: [Int]) -> Int? {
        guard !minutes.isEmpty else { return nil }
        var x = 0.0, y = 0.0
        for minute in minutes {
            let angle = Double(minute) / 1_440 * 2 * Double.pi
            x += cos(angle)
            y += sin(angle)
        }
        guard abs(x) > 1e-9 || abs(y) > 1e-9 else { return nil }
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * Double.pi }
        return Int((angle / (2 * Double.pi) * 1_440).rounded()) % 1_440
    }

    // MARK: Counting

    /// The week's value for one metric. `usualBedtime` is what regularity is measured against.
    static func value(for metric: WeeklyGoalMetric, days: [WeeklyGoalDay], usualBedtime: Int?) -> Double {
        switch metric {
        case .sleepHours:
            return Double(days.filter { ($0.sleepMinutes ?? 0) >= Double(WeeklyGoalMetric.sleepHoursMinutes) }.count)
        case .sleepConsistency:
            guard let usualBedtime else { return 0 }
            return Double(days.filter { day in
                guard let bedtime = day.bedtimeMinute else { return false }
                return circularDistance(bedtime, usualBedtime) <= WeeklyGoalMetric.consistencyWindowMinutes
            }.count)
        case .zone45Minutes:
            return days.compactMap(\.zone45Minutes).reduce(0, +)
        case .steps:
            return Double(days.filter { ($0.steps ?? 0) >= WeeklyGoalMetric.stepsThreshold }.count)
        case .windDown:
            return Double(days.filter { day in
                guard let bedtime = day.bedtimeMinute, let planned = day.plannedBedtimeMinute else { return false }
                return signedDifference(bedtime, from: planned) <= WeeklyGoalMetric.windDownGraceMinutes
            }.count)
        }
    }

    static func progress(plan: WeeklyGoalPlan, days: [WeeklyGoalDay], usualBedtime: Int?) -> [WeeklyGoalProgress] {
        plan.targets.map { target in
            WeeklyGoalProgress(metric: target.metric,
                               value: value(for: target.metric, days: days, usualBedtime: usualBedtime),
                               target: target.target)
        }
    }
}

// MARK: - Storage

enum WeeklyGoalStore {
    static let key = "noop.weeklyGoals.plan"

    static func load(_ defaults: UserDefaults = .standard) -> WeeklyGoalPlan? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeeklyGoalPlan.self, from: data)
    }

    static func save(_ plan: WeeklyGoalPlan?, to defaults: UserDefaults = .standard) {
        guard let plan, let data = try? JSONEncoder().encode(plan) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
