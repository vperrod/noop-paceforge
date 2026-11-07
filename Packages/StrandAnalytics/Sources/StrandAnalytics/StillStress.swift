import Foundation
import WhoopProtocol

// StillStress.swift - the daytime stress proxy read ONLY from moments the wearer was sitting still, plus
// "restorative minutes".
//
// WHY: heart rate that is up and HRV that is down cannot tell a tense meeting from a brisk walk, so the hourly
// timeline (DaytimeStress) masks whole ambulatory hours. This reads finer: it looks at five-minute windows and keeps
// a window only when the wrist accelerometer says the wearer was still for the whole of it, it is waking time,
// and no workout was running or had ended within the last 30 minutes (heart rate is still coming down then).
//
// ADDITIVE: it feeds no score and changes no existing number. The Stress score, the hourly timeline and the high-stress
// minutes are untouched.
//
// Level: the same 0-3 proxy as the rest of the Stress screen (heart rate only; daytime wrist HRV is too noisy, see
// `DaytimeStress.daytimeRMSSDScoringEnabled`). A window is scored against a calm anchor: the typical calm level of
// recent days when there is one, else the day's own calm quarter.
//
// Restorative minutes: still minutes whose mean heart rate is at or below the personal calm level, the median over
// recent days of each day's calmest quarter of still windows. They exist only once `minReferenceDays` earlier days are
// on file; before that the number is nil rather than a quarter of the day by construction.
//
// The thresholds are NOOP's own, not a published standard.

public enum StillStress {

    // MARK: - Tunables

    public static let windowSeconds: Int = 300
    /// Heart-rate samples a window needs (a fifth of a window at 1 Hz).
    public static let minWindowHRSamples: Int = 60
    /// Motion records a window needs; with fewer, stillness cannot be told, so the window is left out.
    public static let minWindowGravityRecords: Int = 3
    /// Largest share of a window's motion records that may clear `WorkoutDetector.motionThreshold`.
    public static let stillMaxActiveFraction: Double = 0.05
    /// A window starting within this long after a workout ends (or during one) is left out.
    public static let quietAfterWorkoutSeconds: Int = 1_800
    /// Still windows needed for any read at all (30 minutes).
    public static let minStillWindows: Int = 6
    /// Still windows an hour needs to get a point on the hourly curve.
    public static let minWindowsPerHour: Int = 2
    /// Floor for the spread the levels are scaled by, so a flat day does not read as wildly swinging.
    public static let minSpreadBPM: Double = 3.0
    /// Earlier days needed before restorative minutes are shown, and the most that are used.
    public static let minReferenceDays: Int = 5
    public static let maxReferenceDays: Int = 28
    /// A day's calm level is kept for later days only after this many still minutes, so a morning peek does not set it.
    public static let minMinutesToRecord: Int = 60

    // MARK: - Types

    /// A stretch of unix seconds, e.g. a workout.
    public struct Interval: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    public struct Window: Equatable, Sendable {
        /// Unix seconds at the start of the window.
        public let startTs: Int
        public let meanHR: Double
        /// The shared 0-3 proxy.
        public let level: Double

        public init(startTs: Int, meanHR: Double, level: Double) {
            self.startTs = startTs
            self.meanHR = meanHR
            self.level = level
        }
    }

    public struct Result: Equatable, Sendable {
        public let windows: [Window]
        public let stillMinutes: Int
        /// Today's calmest quarter of still windows (lower quartile of their mean HR), bpm. Kept as a reference for later days.
        public let calmHR: Double
        /// The personal calm level, or nil while fewer than `minReferenceDays` earlier days are known.
        public let referenceHR: Double?
        public let referenceDays: Int
        /// Still minutes at or below `referenceHR`; nil with no reference.
        public let restorativeMinutes: Int?
        /// One point per waking hour (06-22, local), `level` nil when the hour had fewer than `minWindowsPerHour` still windows.
        public let hourly: [DaytimeStress.HourPoint]

        public init(windows: [Window], stillMinutes: Int, calmHR: Double, referenceHR: Double?, referenceDays: Int,
                    restorativeMinutes: Int?, hourly: [DaytimeStress.HourPoint]) {
            self.windows = windows
            self.stillMinutes = stillMinutes
            self.calmHR = calmHR
            self.referenceHR = referenceHR
            self.referenceDays = referenceDays
            self.restorativeMinutes = restorativeMinutes
            self.hourly = hourly
        }
    }

    // MARK: - Analysis

    /// Nil when there is no gravity, or fewer than `minStillWindows` windows qualify.
    ///
    /// - Parameters:
    ///   - hr: the day's heart-rate samples.
    ///   - gravity: the day's wrist accelerometer samples.
    ///   - workouts: today's workouts, wall-clock seconds; their windows and the 30 minutes after are left out.
    ///   - tzOffsetSeconds: seconds east of UTC, to find waking hours on the local clock.
    ///   - recentCalmHR: `calmHR` of earlier days (up to `maxReferenceDays` of them, today excluded).
    public static func analyze(hr: [HRSample], gravity: [GravitySample], workouts: [Interval] = [],
                               tzOffsetSeconds: Int = 0, recentCalmHR: [Double] = []) -> Result? {
        guard !hr.isEmpty, !gravity.isEmpty else { return nil }
        let size = windowSeconds

        var hrSums: [Int: (sum: Double, count: Int)] = [:]
        for sample in hr {
            let index = DaytimeStress.floorDiv(sample.ts + tzOffsetSeconds, size)
            var entry = hrSums[index] ?? (0.0, 0)
            entry.sum += Double(sample.bpm)
            entry.count += 1
            hrSums[index] = entry
        }
        var motion: [Int: (active: Int, total: Int)] = [:]
        for point in WorkoutDetector.activitySeries(gravity) {
            let index = DaytimeStress.floorDiv(point.ts + tzOffsetSeconds, size)
            var entry = motion[index] ?? (0, 0)
            entry.total += 1
            if point.intensity > WorkoutDetector.motionThreshold { entry.active += 1 }
            motion[index] = entry
        }

        var kept: [(start: Int, mean: Double)] = []
        for index in hrSums.keys.sorted() {
            guard let sums = hrSums[index], sums.count >= minWindowHRSamples,
                  let moves = motion[index], moves.total >= minWindowGravityRecords,
                  Double(moves.active) / Double(moves.total) <= stillMaxActiveFraction else { continue }
            let localStart = index * size
            guard DaytimeStress.isWakingHour(localStart) else { continue }
            let wallStart = localStart - tzOffsetSeconds
            let nearWorkout = workouts.contains { wallStart < $0.end + quietAfterWorkoutSeconds && wallStart + size > $0.start }
            if nearWorkout { continue }
            kept.append((start: wallStart, mean: sums.sum / Double(sums.count)))
        }
        guard kept.count >= minStillWindows else { return nil }

        let means = kept.map { $0.mean }
        guard let calm = DaytimeStress.calmReference(means, calmIsLow: true) else { return nil }
        let recent = Array(recentCalmHR.prefix(maxReferenceDays))
        let reference: Double? = recent.count >= minReferenceDays ? SleepRegularity.median(recent) : nil
        let anchor = reference ?? calm
        let spread = max(DaytimeStress.std(means, mean: DaytimeStress.mean(means)), minSpreadBPM)

        let windows = kept.map { item in
            Window(startTs: item.start, meanHR: item.mean,
                   level: DaytimeStress.squash(DaytimeStress.rawScore(hr: item.mean, meanHR: anchor, sdHR: spread,
                                                                      rmssd: nil, meanRMSSD: nil, sdRMSSD: 0)))
        }
        let minutesPerWindow = size / 60
        let restorative: Int? = reference.map { ref in
            windows.filter { $0.meanHR <= ref }.count * minutesPerWindow
        }
        return Result(windows: windows, stillMinutes: windows.count * minutesPerWindow, calmHR: calm,
                      referenceHR: reference, referenceDays: recent.count, restorativeMinutes: restorative,
                      hourly: hourlyPoints(windows, tzOffsetSeconds: tzOffsetSeconds))
    }

    /// The waking hours of the day the first window falls on, each with the mean level of its still windows.
    private static func hourlyPoints(_ windows: [Window], tzOffsetSeconds: Int) -> [DaytimeStress.HourPoint] {
        guard let first = windows.first else { return [] }
        let dayLocal = DaytimeStress.floorDiv(first.startTs + tzOffsetSeconds, 86_400) * 86_400
        var byHour: [Int: [Window]] = [:]
        for window in windows {
            let hour = DaytimeStress.floorDiv(window.startTs + tzOffsetSeconds - dayLocal, 3_600)
            byHour[hour, default: []].append(window)
        }
        return (DaytimeStress.wakingStartHour..<DaytimeStress.wakingEndHour).map { hour -> DaytimeStress.HourPoint in
            let inHour = byHour[hour] ?? []
            let enough = inHour.count >= minWindowsPerHour
            return DaytimeStress.HourPoint(hour: hour, startTs: dayLocal + hour * 3_600 - tzOffsetSeconds,
                                           level: enough ? DaytimeStress.mean(inHour.map { $0.level }) : nil,
                                           meanHR: enough ? DaytimeStress.mean(inHour.map { $0.meanHR }) : nil,
                                           rmssd: nil)
        }
    }

    // MARK: - Calm history (the reference for later days)

    /// `history` (day key `yyyy-MM-dd` to that day's `calmHR`) with `day` set, keeping the newest `maxReferenceDays + 1` days.
    public static func recordingCalm(_ history: [String: Double], day: String, calmHR: Double) -> [String: Double] {
        var out = history
        out[day] = calmHR
        let keep = maxReferenceDays + 1
        let extra = out.count - keep
        if extra > 0 {
            for key in out.keys.sorted().prefix(extra) { out.removeValue(forKey: key) }
        }
        return out
    }

    /// The calm levels of the days before `day`, oldest first, at most `maxReferenceDays` of them.
    public static func recentCalm(_ history: [String: Double], before day: String) -> [Double] {
        let earlier = history.keys.filter { $0 < day }.sorted().suffix(maxReferenceDays)
        return earlier.compactMap { history[$0] }
    }
}
