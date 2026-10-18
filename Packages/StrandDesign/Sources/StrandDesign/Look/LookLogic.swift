import Foundation

// MARK: - Look logic (pure)
//
// The decisions behind the dark "look" components, kept free of SwiftUI so they run in the Linux logic
// tests (`scripts/look-logic-tests-linux.sh`) and so a component never has to guess which side of a band a
// number is on. Foundation only: no UIKit, no Color, no Date.now.

// MARK: Safe conversion

/// `Int(Double)` traps on NaN, infinity and out-of-range values, so every place the look turns a score, duration or percent
/// into whole numbers goes through this. (The app targets have the same helper as `Safe.int`; a package cannot see them.)
public enum LookSafe {
    public static let limit: Double = 9_007_199_254_740_992

    /// `value` rounded (to nearest by default) as an `Int`. NaN reads as 0 and out-of-range values clamp to `limit`.
    public static func int(_ value: Double, _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        guard !value.isNaN else { return 0 }
        return Int(min(max(value.rounded(rule), -limit), limit))
    }
}

// MARK: Score bands

/// The three hard bands the Charge dial and the weekly bars colour by. A score is banded on its ROUNDED
/// value so the colour always agrees with the number printed in the ring (66.6 prints "67" and is green).
public enum LookBand: String, Sendable, Equatable, CaseIterable {
    case low, medium, high

    public static let mediumFloor = 34
    public static let highFloor = 67

    /// Band for a 0-100 score. Out-of-range input clamps to the nearest band.
    public static func forScore(_ score: Double) -> LookBand {
        let s = LookSafe.int(score)
        if s >= highFloor { return .high }
        if s >= mediumFloor { return .medium }
        return .low
    }
}

// MARK: Today versus the last 30 days

/// The little triangle beside a "today vs. last 30 days" row: which way today moved, and whether that
/// direction is good for this metric (resting heart rate down is good; HRV down is not).
public struct LookTodayMark: Equatable, Sendable {
    public enum Tone: String, Sendable { case favourable, unfavourable, neutral }
    public let pointsUp: Bool
    public let tone: Tone

    public init(pointsUp: Bool, tone: Tone) {
        self.pointsUp = pointsUp
        self.tone = tone
    }
}

public enum LookCompare {
    /// nil when there is nothing to compare or the two values print the same at `decimals` places (a mark
    /// for a difference the reader cannot see would only invite a question). `higherIsBetter` nil means the
    /// metric has no good direction, so the triangle is neutral.
    public static func mark(today: Double?, baseline: Double?, decimals: Int = 0,
                            higherIsBetter: Bool?) -> LookTodayMark? {
        guard let today, let baseline else { return nil }
        let factor = pow(10.0, Double(max(decimals, 0)))
        let t = (today * factor).rounded() / factor
        let b = (baseline * factor).rounded() / factor
        if t == b { return nil }
        let up = t > b
        guard let higherIsBetter else { return LookTodayMark(pointsUp: up, tone: .neutral) }
        return LookTodayMark(pointsUp: up, tone: up == higherIsBetter ? .favourable : .unfavourable)
    }
}

// MARK: Delta chips

/// A percentage chip such as "+8 %" or "-3 %".
public struct LookChip: Equatable, Sendable {
    public enum Tone: String, Sendable { case positive, negative, neutral }
    public let text: String
    public let tone: Tone

    public init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }
}

public enum LookDelta {
    /// (to - from) / |from| * 100. nil when `from` is zero or either value is missing.
    public static func percentChange(from: Double?, to: Double?) -> Double? {
        guard let from, let to, from != 0 else { return nil }
        return (to - from) / abs(from) * 100
    }

    /// The chip for a change. The percentage is rounded to a whole number; a change that rounds to zero is a
    /// neutral "0 %". `higherIsBetter` nil keeps every non-zero change neutral.
    public static func chip(percent: Double?, higherIsBetter: Bool? = true) -> LookChip? {
        guard let percent else { return nil }
        let whole = LookSafe.int(percent)
        if whole == 0 { return LookChip(text: "0 %", tone: .neutral) }
        let text = (whole > 0 ? "+" : "-") + "\(abs(whole)) %"
        guard let higherIsBetter else { return LookChip(text: text, tone: .neutral) }
        return LookChip(text: text, tone: (whole > 0) == higherIsBetter ? .positive : .negative)
    }
}

// MARK: Three-step rows (Poor / Sufficient / Optimal)

public enum LookStep: Int, Sendable, Equatable, CaseIterable {
    case poor = 0, sufficient, optimal

    /// `value` below `sufficientFrom` is poor, from there up to (not including) `optimalFrom` is sufficient.
    public static func classify(_ value: Double, sufficientFrom: Double, optimalFrom: Double) -> LookStep {
        if value >= optimalFrom { return .optimal }
        if value >= sufficientFrom { return .sufficient }
        return .poor
    }
}

// MARK: Dial geometry

public enum LookDial {
    /// 0...1 share of the circle a value fills.
    public static func fraction(_ value: Double, max maxValue: Double) -> Double {
        guard maxValue > 0, value.isFinite else { return 0 }
        return min(max(value / maxValue, 0), 1)
    }

    /// The target range as an ordered, clamped (start, end) pair of circle fractions, or nil when it is
    /// missing or collapses to nothing. The tick sits at the START (the Effort the athlete should reach).
    public static func targetArc(low: Double?, high: Double?, max maxValue: Double) -> (start: Double, end: Double)? {
        guard let low, let high, maxValue > 0 else { return nil }
        let a = fraction(Swift.min(low, high), max: maxValue)
        let b = fraction(Swift.max(low, high), max: maxValue)
        return b > a ? (a, b) : nil
    }

    /// Clockwise degrees from 12 o'clock for a circle fraction.
    public static func degrees(forFraction f: Double) -> Double {
        min(max(f, 0), 1) * 360
    }
}

// MARK: Stress monitor level

public enum LookStressLevel: String, Sendable, Equatable {
    case low, medium, high

    /// Stress is scored 0-3: under 1 is low, under 2 medium, otherwise high.
    public static func forScore(_ score: Double) -> LookStressLevel {
        if score < 1 { return .low }
        if score < 2 { return .medium }
        return .high
    }

    public var label: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        }
    }
}

// MARK: Formatting

public enum LookFormat {
    /// 380 -> "6:20". Negative or absurd input clamps to 0.
    public static func hoursMinutes(minutes: Int) -> String {
        let m = max(minutes, 0)
        return "\(m / 60):" + (m % 60 < 10 ? "0" : "") + "\(m % 60)"
    }

    /// 1325 -> "22:05" (minutes after midnight, wrapped to a day).
    public static func clock(minutesAfterMidnight: Int) -> String {
        let m = ((minutesAfterMidnight % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// A number at a fixed number of decimal places ("16.1", "114").
    public static func number(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(max(decimals, 0))f", value)
    }
}

// MARK: Trend ranges (W / M / 6M / Y)

public enum LookRange: String, CaseIterable, Sendable, Equatable {
    case week = "W"
    case month = "M"
    case sixMonths = "6M"
    case year = "Y"

    /// Days a window spans, end day included. 6M is 180 days (Apr 14 to Oct 10 in the reference).
    public var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 180
        case .year: return 365
        }
    }

    /// Whether the trend draws monthly average segments (only the long views).
    public var usesMonthlySegments: Bool { self == .sixMonths || self == .year }

    /// First and last day of the window that ends on `end` (start of day, in `calendar`).
    public func window(endingOn end: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let last = calendar.startOfDay(for: end)
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: last) ?? last
        return (first, last)
    }

    /// The window one page earlier (-1) or later (+1), never past `today`. Returns `end` unchanged when the
    /// move is not allowed.
    public func stepped(end: Date, by pages: Int, today: Date, calendar: Calendar) -> Date {
        let last = calendar.startOfDay(for: end)
        let cap = calendar.startOfDay(for: today)
        guard let moved = calendar.date(byAdding: .day, value: pages * days, to: last) else { return last }
        return min(moved, cap)
    }

    /// False when the window already ends on or after `today`.
    public func canStepForward(end: Date, today: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: end) < calendar.startOfDay(for: today)
    }

    /// "APR 14 – OCT 10, 26" ("OCT 4 – 10, 26" inside one month). Year is two digits, as in the reference.
    public func label(endingOn end: Date, calendar: Calendar, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let w = window(endingOn: end, calendar: calendar)
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d"
        let day = DateFormatter()
        day.calendar = calendar
        day.locale = locale
        day.timeZone = calendar.timeZone
        day.dateFormat = "d"
        let yy = DateFormatter()
        yy.calendar = calendar
        yy.locale = locale
        yy.timeZone = calendar.timeZone
        yy.dateFormat = "yy"
        let sameMonth = calendar.isDate(w.start, equalTo: w.end, toGranularity: .month)
        let startText = f.string(from: w.start).uppercased()
        let endText = sameMonth ? day.string(from: w.end) : f.string(from: w.end).uppercased()
        return "\(startText) \u{2013} \(endText), \(yy.string(from: w.end))"
    }
}

// MARK: Trend statistics

public struct LookPoint: Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// One calendar month of a long trend: its average and the change against the month before it.
public struct LookMonthSegment: Equatable, Sendable {
    public let monthStart: Date
    public let average: Double
    public let count: Int
    /// Percent change against the previous segment in the list; nil for the first one.
    public let percentChange: Double?
}

public enum LookTrendStats {
    public static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean plus or minus one population standard deviation: OUR typical band for a metric, drawn behind
    /// the line. It is not WHOOP's band and is labelled as the athlete's own typical range. Needs 3 values.
    public static func typicalRange(of values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 3, let mean = average(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let sd = variance.squareRoot()
        return (mean - sd)...(mean + sd)
    }

    /// Per-calendar-month averages in date order, each with its change against the previous month listed.
    public static func monthlySegments(_ points: [LookPoint], calendar: Calendar) -> [LookMonthSegment] {
        var buckets: [Date: [Double]] = [:]
        for p in points where p.value.isFinite {
            let comps = calendar.dateComponents([.year, .month], from: p.date)
            guard let start = calendar.date(from: comps) else { continue }
            buckets[start, default: []].append(p.value)
        }
        var out: [LookMonthSegment] = []
        var previous: Double?
        for start in buckets.keys.sorted() {
            let values = buckets[start] ?? []
            guard let avg = average(values) else { continue }
            out.append(LookMonthSegment(monthStart: start, average: avg, count: values.count,
                                        percentChange: LookDelta.percentChange(from: previous, to: avg)))
            previous = avg
        }
        return out
    }

    /// Axis tick values covering min...max with `count` ticks on a 1/2/5 step, lowest first. Always strictly increasing,
    /// and at least two ticks for finite input: a flat series (one reading, or the same value every day) is padded
    /// either side first, because a zero-height range produced one tick or the same tick repeated, which left the chart
    /// with a collapsed value axis.
    public static func niceTicks(min inLow: Double, max inHigh: Double, count: Int = 6) -> [Double] {
        guard inLow.isFinite, inHigh.isFinite, count >= 2 else { return [] }
        var lo = Swift.min(inLow, inHigh)
        var hi = Swift.max(inLow, inHigh)
        if hi - lo < 1e-9 * Swift.max(1, Swift.abs(hi)) {
            let pad = Swift.max(Swift.abs(hi) * 0.05, 1)
            lo -= pad
            hi += pad
        }
        let span = hi - lo
        let rough = span / Double(count - 1)
        let magnitude = pow(10.0, floor(log10(rough)))
        let residual = rough / magnitude
        let nice: Double = residual <= 1 ? 1 : residual <= 2 ? 2 : residual <= 5 ? 5 : 10
        let step = nice * magnitude
        guard step.isFinite, step > 0 else { return [] }
        let first = floor(lo / step) * step
        var ticks: [Double] = []
        var index = 0.0
        while ticks.count < count + 2 {
            let v = ((first + index * step) * 1e9).rounded() / 1e9
            if v >= hi + step * 0.999 { break }
            if let last = ticks.last, v <= last { break }
            ticks.append(v)
            index += 1
        }
        return ticks
    }
}

// MARK: Trend window (everything a trend screen shows for one metric, one range, one end date)

/// A month segment clipped to the visible window: where its average line starts and ends.
public struct LookSegmentSpan: Equatable, Sendable {
    public let segment: LookMonthSegment
    public let from: Date
    public let to: Date

    /// Middle of the span: where its month label sits.
    public var middle: Date { Date(timeIntervalSince1970: (from.timeIntervalSince1970 + to.timeIntervalSince1970) / 2) }
}

public struct LookTrendWindow: Equatable, Sendable {
    public let range: LookRange
    public let start: Date
    public let end: Date
    /// Points inside the window, oldest first.
    public let points: [LookPoint]
    public let average: Double?
    /// Average of the window of the same length just before this one.
    public let previousAverage: Double?
    /// Percent change of `average` against `previousAverage`.
    public let deltaPercent: Double?
    /// Monthly segments for the 6M and Y views; empty for W and M.
    public let spans: [LookSegmentSpan]
    /// The typical band: `typicalOverride` if given, else mean plus or minus one standard deviation of the window.
    public let typical: ClosedRange<Double>?
    public let yTicks: [Double]
    /// True when the data holds a point before `start`, so stepping back shows something.
    public let hasEarlierData: Bool

    public var yDomain: ClosedRange<Double> {
        guard let lo = yTicks.first, let hi = yTicks.last, hi > lo else { return 0...1 }
        return lo...hi
    }

    public static func make(points all: [LookPoint], range: LookRange, endingOn end: Date, calendar: Calendar,
                            typicalOverride: ClosedRange<Double>? = nil) -> LookTrendWindow {
        let w = range.window(endingOn: end, calendar: calendar)
        let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: w.end) ?? w.end
        let valid = all.filter { $0.value.isFinite }
        let inside = valid.filter { $0.date >= w.start && $0.date < dayAfterEnd }.sorted { $0.date < $1.date }
        let prevEnd = calendar.date(byAdding: .day, value: -1, to: w.start) ?? w.start
        let prev = range.window(endingOn: prevEnd, calendar: calendar)
        let prevInside = valid.filter { $0.date >= prev.start && $0.date < w.start }
        let avg = LookTrendStats.average(inside.map(\.value))
        let prevAvg = LookTrendStats.average(prevInside.map(\.value))

        var spans: [LookSegmentSpan] = []
        if range.usesMonthlySegments {
            for seg in LookTrendStats.monthlySegments(inside, calendar: calendar) {
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: seg.monthStart) ?? seg.monthStart
                let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? nextMonth
                spans.append(LookSegmentSpan(segment: seg, from: max(seg.monthStart, w.start), to: min(lastDay, w.end)))
            }
        }

        let band = typicalOverride ?? LookTrendStats.typicalRange(of: inside.map(\.value))
        var lo = inside.map(\.value).min()
        var hi = inside.map(\.value).max()
        if let band {
            lo = Swift.min(lo ?? band.lowerBound, band.lowerBound)
            hi = Swift.max(hi ?? band.upperBound, band.upperBound)
        }
        let ticks: [Double]
        if let lo, let hi { ticks = LookTrendStats.niceTicks(min: lo, max: hi, count: 6) } else { ticks = [] }

        let earlier = valid.contains { $0.date < w.start }
        return LookTrendWindow(range: range, start: w.start, end: w.end, points: inside, average: avg,
                               previousAverage: prevAvg,
                               deltaPercent: LookDelta.percentChange(from: prevAvg, to: avg),
                               spans: spans, typical: band, yTicks: ticks, hasEarlierData: earlier)
    }

    /// Dates the x axis labels: every day for W, every 7th for M, the middle of each month segment for 6M and Y.
    public func xTickDates(calendar: Calendar) -> [Date] {
        switch range {
        case .week:
            return (0..<range.days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            return stride(from: 0, to: range.days, by: 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .sixMonths, .year:
            return spans.map(\.middle)
        }
    }
}

// MARK: Sticky mini-dials

public enum LookSticky {
    /// The strip of mini dials shows once the big dials have scrolled under the top edge.
    public static func isVisible(heroBottomY: Double, topInset: Double) -> Bool {
        heroBottomY < topInset
    }
}
