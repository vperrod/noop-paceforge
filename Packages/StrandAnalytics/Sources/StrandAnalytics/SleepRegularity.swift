import Foundation

// SleepRegularity.swift - the Sleep Regularity Index (SRI) over the last 14 nights.
//
// The standard definition (Phillips et al. 2017): the probability that the wearer is in the SAME state
// (asleep or awake) at two moments exactly 24 hours apart, taken over every such pair in the window.
// Reported two ways from the same count: `matchPercent` is that probability as 0-100, and `sri` is the
// published scale, -100 + 200 x probability (100 = the same pattern every day, 0 = no more regular
// than chance).
//
// Built only from NOOP's own sleep sessions (start/end times). Awake is simply "not inside a session",
// so a day with no session at all is treated as NOT WORN and left out of the comparison instead of
// counting as a day awake. Pure and clock-free: the caller passes the end of the window.
//
// The own-baseline comparison reads the same measure over the previous 14-night windows and says
// steadier / usual / less steady. The margin is NOOP's own, not a published cut-off.

public enum SleepRegularity {

    // MARK: - Tunables

    /// One comparison point every five minutes; 288 per day.
    public static let epochSeconds: Int = 300
    /// Nights in one reading.
    public static let windowNights: Int = 14
    /// Fewest nights (sessions of at least `minNightSeconds`, one per day) a reading needs.
    public static let minNights: Int = 5
    /// A session shorter than this is a nap and does not count as a night.
    public static let minNightSeconds: Int = 2 * 3_600
    /// How many earlier 14-night windows feed the personal baseline, and how many must exist.
    public static let baselineWindows: Int = 4
    public static let minBaselineWindows: Int = 2
    /// Percentage points a reading must sit above or below the personal baseline to be called steadier or less steady.
    public static let steadyMarginPoints: Double = 3.0

    private static let daySeconds = 86_400

    // MARK: - Types

    /// One sleep session, unix seconds.
    public struct Span: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    public struct Reading: Equatable, Sendable {
        /// The published scale, -100...100.
        public let sri: Double
        /// The same agreement as a probability, 0...100.
        public let matchPercent: Double
        /// Nights (one long session per day) the reading is built from.
        public let nights: Int

        public init(sri: Double, matchPercent: Double, nights: Int) {
            self.sri = sri
            self.matchPercent = matchPercent
            self.nights = nights
        }
    }

    public enum Trend: String, Equatable, Sendable {
        case steadier
        case usual
        case lessSteady
    }

    public struct Assessment: Equatable, Sendable {
        public let reading: Reading
        /// Median `matchPercent` of the earlier windows, or nil when fewer than `minBaselineWindows` had a reading.
        public let baselinePercent: Double?
        public let trend: Trend?

        public init(reading: Reading, baselinePercent: Double?, trend: Trend?) {
            self.reading = reading
            self.baselinePercent = baselinePercent
            self.trend = trend
        }
    }

    // MARK: - Public API

    /// The reading for the `nights` local days ending with the day `endTs` falls in (that last day only up to `endTs`).
    /// Nil when fewer than `minNights` nights are on file, or when too few comparable days remain.
    public static func reading(spans: [Span], endingAt endTs: Int, nights: Int = windowNights,
                               tzOffsetSeconds: Int = 0) -> Reading? {
        guard nights > 0 else { return nil }
        let windowStart = dayStart(endTs, tz: tzOffsetSeconds) - (nights - 1) * daySeconds
        guard endTs > windowStart else { return nil }
        let perDay = daySeconds / epochSeconds
        let epochCount = (endTs - windowStart + epochSeconds - 1) / epochSeconds
        guard epochCount > perDay else { return nil }

        var asleep = [Bool](repeating: false, count: epochCount)
        var observedDays = Set<Int>()
        var nightDays = Set<Int>()
        for span in spans where span.end > span.start && span.end > windowStart && span.start < endTs {
            let lo = max(span.start, windowStart)
            let hi = min(span.end, endTs)
            let first = (lo - windowStart) / epochSeconds
            let last = (hi - windowStart - 1) / epochSeconds
            if first <= last { for i in first...last { asleep[i] = true } }
            for day in ((lo - windowStart) / daySeconds)...((hi - 1 - windowStart) / daySeconds) { observedDays.insert(day) }
            if span.end - span.start >= minNightSeconds && span.end <= endTs {
                nightDays.insert((span.end - 1 - windowStart) / daySeconds)
            }
        }
        guard nightDays.count >= minNights else { return nil }

        var pairs = 0
        var matches = 0
        for i in 0..<(epochCount - perDay) {
            let j = i + perDay
            guard observedDays.contains(i / perDay), observedDays.contains(j / perDay) else { continue }
            pairs += 1
            if asleep[i] == asleep[j] { matches += 1 }
        }
        guard pairs >= 2 * perDay else { return nil }
        let p = Double(matches) / Double(pairs)
        return Reading(sri: -100 + 200 * p, matchPercent: 100 * p, nights: nightDays.count)
    }

    /// The latest reading and where it sits against the same measure over the earlier 14-night windows.
    public static func assess(spans: [Span], endingAt endTs: Int, nights: Int = windowNights,
                              tzOffsetSeconds: Int = 0) -> Assessment? {
        guard let now = reading(spans: spans, endingAt: endTs, nights: nights, tzOffsetSeconds: tzOffsetSeconds) else {
            return nil
        }
        var earlier: [Double] = []
        for k in 1...baselineWindows {
            let end = endTs - k * nights * daySeconds
            if let past = reading(spans: spans, endingAt: end, nights: nights, tzOffsetSeconds: tzOffsetSeconds) {
                earlier.append(past.matchPercent)
            }
        }
        guard earlier.count >= minBaselineWindows else {
            return Assessment(reading: now, baselinePercent: nil, trend: nil)
        }
        let baseline = median(earlier)
        let gap = now.matchPercent - baseline
        let trend: Trend = gap > steadyMarginPoints ? .steadier : (gap < -steadyMarginPoints ? .lessSteady : .usual)
        return Assessment(reading: now, baselinePercent: baseline, trend: trend)
    }

    // MARK: - Helpers

    /// Local midnight (as unix seconds, still on the UTC axis the spans use) of the day `ts` falls in.
    static func dayStart(_ ts: Int, tz: Int) -> Int {
        let local = ts + tz
        let q = local / daySeconds
        let r = local % daySeconds
        let floored = r < 0 ? q - 1 : q
        return floored * daySeconds - tz
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
