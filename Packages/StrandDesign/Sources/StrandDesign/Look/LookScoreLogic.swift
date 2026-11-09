import Foundation

// MARK: - Look score and sleep logic (pure)
//
// What the Charge / Effort / Rest detail screens, the sleep block and the sleep planner decide before any view
// draws: day keys, series conversion, the 30-day baseline behind a "today vs. last 30 days" row, the seven-day
// strip, the 7-day average line, the Poor / Sufficient / Optimal bands of the Rest rows, the planner's wording
// and the overnight heart-rate line. Foundation only (no SwiftUI, no Date.now), so it runs in the Linux logic
// tests (`scripts/look-logic-tests-linux.sh`). The bands are NOOP's own and are named as such on screen.

// MARK: Day keys

/// "yyyy-MM-dd" day keys, parsed without a DateFormatter so a calendar's time zone is the only thing that matters.
public enum LookDayKey {
    /// Start of the named day in `calendar`, or nil when the text is not a day key.
    public static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
    }

    public static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: Series

public enum LookSeries {
    /// Daily rows ("yyyy-MM-dd", value) as trend points; rows with a bad key or a non-finite value are dropped.
    public static func points(_ rows: [(day: String, value: Double)], calendar: Calendar) -> [LookPoint] {
        rows.compactMap { row -> LookPoint? in
            guard row.value.isFinite, let date = LookDayKey.date(row.day, calendar: calendar) else { return nil }
            return LookPoint(date: date, value: row.value)
        }
    }

    /// The most recent point, or nil for an empty series.
    public static func latest(_ points: [LookPoint]) -> LookPoint? {
        points.max { $0.date < $1.date }
    }

    /// Points with `start <= date <= end`, oldest first.
    public static func within(_ points: [LookPoint], from start: Date, to end: Date) -> [LookPoint] {
        points.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
    }
}

extension LookTrendStats {
    /// For every point, the mean of the points inside the `days` calendar days that end on it (itself included).
    /// Points come back oldest first. `days` of 1 or less returns the points unchanged.
    public static func trailingAverage(_ points: [LookPoint], days: Int, calendar: Calendar) -> [LookPoint] {
        let sorted = points.filter { $0.value.isFinite }.sorted { $0.date < $1.date }
        guard days > 1 else { return sorted }
        var out: [LookPoint] = []
        var first = 0
        var sum = 0.0
        for (index, point) in sorted.enumerated() {
            sum += point.value
            let from = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: point.date)) ?? point.date
            while first < index && sorted[first].date < from {
                sum -= sorted[first].value
                first += 1
            }
            out.append(LookPoint(date: point.date, value: sum / Double(index - first + 1)))
        }
        return out
    }
}

// MARK: Baseline for "today vs. last 30 days"

public enum LookBaseline {
    /// Mean of the points in the `days` days before `day` (`day` itself excluded). nil under `minimum` points, so
    /// a row never compares today with a single stray reading.
    public static func mean(of points: [LookPoint], before day: Date, days: Int = 30, minimum: Int = 3,
                            calendar: Calendar) -> Double? {
        let start = calendar.startOfDay(for: day)
        guard let from = calendar.date(byAdding: .day, value: -days, to: start) else { return nil }
        let values = points.filter { $0.date >= from && $0.date < start && $0.value.isFinite }.map(\.value)
        guard values.count >= minimum else { return nil }
        return LookTrendStats.average(values)
    }

    /// One comparison row: the latest value, the 30-day mean before it and which way it moved.
    public struct Comparison: Equatable, Sendable {
        public let value: Double
        public let baseline: Double?
        public let mark: LookTodayMark?
    }

    public static func comparison(_ points: [LookPoint], decimals: Int = 0, higherIsBetter: Bool?,
                                  calendar: Calendar) -> Comparison? {
        guard let latest = LookSeries.latest(points) else { return nil }
        let base = mean(of: points, before: latest.date, calendar: calendar)
        return Comparison(value: latest.value, baseline: base,
                          mark: LookCompare.mark(today: latest.value, baseline: base, decimals: decimals,
                                                 higherIsBetter: higherIsBetter))
    }
}

// MARK: The seven-day strip

public struct LookWeekDay: Equatable, Sendable {
    public let date: Date
    /// One letter, S M T W T F S.
    public let letter: String
    public let value: Double?
    public let isToday: Bool
}

public enum LookWeek {
    private static let letters = ["S", "M", "T", "W", "T", "F", "S"]

    /// The seven days ending on `end`, oldest first, each with that day's value when there is one.
    public static func days(points: [LookPoint], endingOn end: Date, calendar: Calendar) -> [LookWeekDay] {
        let last = calendar.startOfDay(for: end)
        var byDay: [Date: Double] = [:]
        for p in points where p.value.isFinite { byDay[calendar.startOfDay(for: p.date)] = p.value }
        return (0..<7).reversed().compactMap { back -> LookWeekDay? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: last) else { return nil }
            let weekday = calendar.component(.weekday, from: day)
            let letter = letters[min(max(weekday - 1, 0), 6)]
            return LookWeekDay(date: day, letter: letter, value: byDay[day], isToday: back == 0)
        }
    }
}

// MARK: Rest rows (Poor / Sufficient / Optimal)

/// NOOP's own bands for the Rest rows. Higher is better for the first three; sleep stress is the other way.
public enum LookRestBands {
    public static func hoursVsNeeded(_ percent: Double) -> LookStep {
        LookStep.classify(percent, sufficientFrom: 70, optimalFrom: 100)
    }

    public static func consistency(_ percent: Double) -> LookStep {
        LookStep.classify(percent, sufficientFrom: 60, optimalFrom: 80)
    }

    public static func efficiency(_ percent: Double) -> LookStep {
        LookStep.classify(percent, sufficientFrom: 75, optimalFrom: 85)
    }

    /// Average stress asleep on Garmin's 0-100 scale: under 25 is optimal, under 40 sufficient.
    public static func sleepStress(_ average: Double) -> LookStep {
        if average < 25 { return .optimal }
        if average < 40 { return .sufficient }
        return .poor
    }
}

// MARK: Sleep planner wording

/// The words and numbers on the Look sleep planner, assembled from the planner's own plan so the screen only lays
/// them out. `clock` formats a moment ("22:05") in the app's clock style.
public struct LookPlannerCopy: Equatable, Sendable {
    public let sentence: String
    public let bedtimeText: String
    public let wakeText: String
    public let timeInBedText: String
    public let timeInBedMinutes: Int
    public let optimalText: String
    public let optimalMinutes: Int
    public let goalPillText: String

    /// - Parameters:
    ///   - targetSleepMin: sleep wanted tonight (the chosen goal).
    ///   - latencyMin: minutes to fall asleep, added to the time in bed.
    ///   - peakSleepMin: the full need (the "optimal" bracket reaches back this far).
    public static func make(bedtime: Date, wake: Date, targetSleepMin: Int, latencyMin: Int, peakSleepMin: Int,
                            goalTitle: String, percentText: String, clock: (Date) -> String) -> LookPlannerCopy {
        let inBed = max(targetSleepMin, 0) + max(latencyMin, 0)
        let optimalSpan = max(peakSleepMin, 0) + max(latencyMin, 0)
        let optimalBed = wake.addingTimeInterval(-Double(optimalSpan) * 60)
        let sleepText = LookFormat.hoursMinutes(minutes: targetSleepMin)
        let sentence = "Go to bed at \(clock(bedtime)) tonight to get \(sleepText) of sleep: \(goalTitle), \(percentText) of tonight's need."
        return LookPlannerCopy(
            sentence: sentence,
            bedtimeText: clock(bedtime),
            wakeText: clock(wake),
            timeInBedText: LookFormat.hoursMinutes(minutes: inBed),
            timeInBedMinutes: inBed,
            optimalText: "\(clock(optimalBed)) \u{2013} \(clock(wake))",
            optimalMinutes: optimalSpan,
            goalPillText: "REACH MY \(goalTitle.uppercased()) GOAL")
    }

    /// Width of the time-in-bed bar as a share of the optimal bracket, clamped to 0...1.
    public var barFraction: Double {
        guard optimalMinutes > 0 else { return 1 }
        return min(max(Double(timeInBedMinutes) / Double(optimalMinutes), 0), 1)
    }
}

// MARK: Overnight heart-rate line

public struct LookHRPoint: Equatable, Sendable {
    /// Position in the night, 0 at bedtime and 1 at wake.
    public let x: Double
    public let bpm: Double
    /// True when more than the gap limit passed since the previous point, so the line breaks instead of bridging.
    public let breaksBefore: Bool
}

public enum LookNightHR {
    /// Folds per-minute readings (unix seconds, bpm) between `start` and `end` into at most `maxPoints` points,
    /// averaging each bin. Readings outside the night and non-finite values are ignored; fewer than two readings
    /// yield an empty line, because one dot is not a trace.
    public static func points(_ samples: [(ts: Int, bpm: Double)], start: Int, end: Int, maxPoints: Int = 120,
                              gapSeconds: Int = 600) -> [LookHRPoint] {
        guard end > start, maxPoints > 1 else { return [] }
        let inside = samples.filter { $0.ts >= start && $0.ts <= end && $0.bpm.isFinite && $0.bpm > 0 }
            .sorted { $0.ts < $1.ts }
        guard inside.count >= 2 else { return [] }
        let span = Double(end - start)
        let binWidth = span / Double(maxPoints)
        var bins: [Int: (sumBpm: Double, sumTs: Double, count: Int)] = [:]
        for s in inside {
            let index = min(Int(Double(s.ts - start) / binWidth), maxPoints - 1)
            let old = bins[index] ?? (0, 0, 0)
            bins[index] = (old.sumBpm + s.bpm, old.sumTs + Double(s.ts), old.count + 1)
        }
        var out: [LookHRPoint] = []
        var previousTs: Double?
        for index in bins.keys.sorted() {
            guard let bin = bins[index] else { continue }
            let ts = bin.sumTs / Double(bin.count)
            let breaks = previousTs.map { ts - $0 > Double(gapSeconds) } ?? false
            out.append(LookHRPoint(x: (ts - Double(start)) / span, bpm: bin.sumBpm / Double(bin.count), breaksBefore: breaks))
            previousTs = ts
        }
        return out
    }

    /// Axis ticks and the drawn range for a set of readings (a little padding either side).
    public static func axis(_ points: [LookHRPoint]) -> (ticks: [Double], range: ClosedRange<Double>)? {
        guard let lo = points.map(\.bpm).min(), let hi = points.map(\.bpm).max() else { return nil }
        let ticks = LookTrendStats.niceTicks(min: lo - 3, max: hi + 3, count: 5)
        guard let first = ticks.first, let last = ticks.last, last > first else { return nil }
        return (ticks, first...last)
    }
}

// MARK: Typical sleep-stage shares

/// One recorded night: minutes asleep, minutes per stage, and efficiency as a 0...1 fraction (asleep over time in bed).
public struct LookNight: Equatable, Sendable {
    public let asleepMin: Double
    public let deepMin: Double
    public let remMin: Double
    public let lightMin: Double
    public let efficiency: Double

    public init(asleepMin: Double, deepMin: Double, remMin: Double, lightMin: Double, efficiency: Double) {
        self.asleepMin = asleepMin
        self.deepMin = deepMin
        self.remMin = remMin
        self.lightMin = lightMin
        self.efficiency = efficiency
    }
}

/// The share of the night each stage usually takes, as the athlete's own range: mean plus or minus one standard
/// deviation over recent nights. Awake time is what efficiency leaves over.
public struct LookStageRanges: Equatable, Sendable {
    public let awake: ClosedRange<Double>
    public let light: ClosedRange<Double>
    public let deep: ClosedRange<Double>
    public let rem: ClosedRange<Double>
}

public enum LookStageTypical {
    /// nil under `minimum` usable nights. A night is usable with a positive sleep time and an efficiency in (0.3, 1].
    public static func ranges(_ nights: [LookNight], minimum: Int = 5) -> LookStageRanges? {
        var awake: [Double] = [], light: [Double] = [], deep: [Double] = [], rem: [Double] = []
        for n in nights where n.asleepMin > 0 && n.efficiency > 0.3 && n.efficiency <= 1 {
            let inBed = n.asleepMin / n.efficiency
            awake.append(1 - n.asleepMin / inBed)
            light.append(n.lightMin / inBed)
            deep.append(n.deepMin / inBed)
            rem.append(n.remMin / inBed)
        }
        guard awake.count >= minimum,
              let a = band(awake), let l = band(light), let d = band(deep), let r = band(rem) else { return nil }
        return LookStageRanges(awake: a, light: l, deep: d, rem: r)
    }

    private static func band(_ shares: [Double]) -> ClosedRange<Double>? {
        guard let mean = LookTrendStats.average(shares) else { return nil }
        let variance = shares.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(shares.count)
        let sd = variance.squareRoot()
        let lo = min(max(mean - sd, 0), 1)
        let hi = min(max(mean + sd, 0), 1)
        return lo...max(hi, lo)
    }
}
