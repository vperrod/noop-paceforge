import Foundation

// MARK: - Stress monitor (the day line)
//
// The Stress monitor screen draws NOOP's own daytime stress read (`DaytimeStress`, heart rate and beat-to-beat intervals from the
// strap, a 0 to 3 scale) as a line across the day. This is the pure half of that drawing: which points are real, where the line
// must break, and where a point sits. An hour with no signal or taken out because the wearer was moving is a gap in the line, never
// a value, so nothing is drawn that the strap did not measure. Foundation only, so it is unit tested.

enum StressMonitorLogic {

    struct Hour: Equatable {
        var startTs: Int
        /// 0...3, or nil when the hour could not be scored (no signal, or masked as exercise).
        var level: Double?
        var masked: Bool

        init(startTs: Int, level: Double?, masked: Bool = false) {
            self.startTs = startTs
            self.level = level
            self.masked = masked
        }
    }

    struct Reading: Equatable {
        var startTs: Int
        var level: Double
    }

    /// The most that may separate two scored points before the line is not drawn across the gap.
    static let maxGapSeconds = 2 * 3600

    /// The most recent scored point, in time order.
    static func latest(_ hours: [Hour]) -> Reading? {
        hours.sorted { $0.startTs < $1.startTs }.last { $0.level != nil }.flatMap { hour in
            hour.level.map { Reading(startTs: hour.startTs, level: min(max($0, 0), 3)) }
        }
    }

    /// Whether anything was scored at all. False is the "No stress data from the strap yet" state.
    static func hasData(_ hours: [Hour]) -> Bool { hours.contains { $0.level != nil } }

    /// The scored points as runs the line is drawn through. An unscored hour, a masked hour or a long gap ends a run.
    static func runs(_ hours: [Hour], maxGap: Int = maxGapSeconds) -> [[Reading]] {
        var out: [[Reading]] = []
        var current: [Reading] = []
        for hour in hours.sorted(by: { $0.startTs < $1.startTs }) {
            guard let level = hour.level, !hour.masked else {
                if !current.isEmpty { out.append(current); current = [] }
                continue
            }
            if let last = current.last, hour.startTs - last.startTs > maxGap {
                out.append(current)
                current = []
            }
            current.append(Reading(startTs: hour.startTs, level: min(max(level, 0), 3)))
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// The hours taken out because the wearer was moving, for the marks along the base of the chart.
    static func maskedStarts(_ hours: [Hour]) -> [Int] {
        hours.filter { $0.masked }.map(\.startTs).sorted()
    }

    /// 0...1 across the day from `dayStart`.
    static func xFraction(ts: Int, dayStart: Int, span: Int = 86_400) -> Double {
        guard span > 0 else { return 0 }
        return min(max(Double(ts - dayStart) / Double(span), 0), 1)
    }

    /// 0 at the bottom, 1 at the top, for a level on the 0...3 scale.
    static func yFraction(level: Double) -> Double { min(max(level / 3, 0), 1) }

    /// A level as one decimal, "2.0".
    static func levelText(_ level: Double) -> String { String(format: "%.1f", level) }

    /// "Last updated" is the end of the latest scored hour, but never later than `now`.
    static func lastUpdated(_ hours: [Hour], hourLength: Int = 3600, now: Int) -> Int? {
        latest(hours).map { min($0.startTs + hourLength, now) }
    }
}
