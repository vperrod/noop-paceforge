import Foundation

// DetectedSegmentClassifier.swift: walk-or-workout for the segments My Day lists as "Looks like a workout".
//
// The opt-in detector (`AutoWorkoutDetector`) only knows "heart rate stayed raised": a 20 minute stroll at
// 93 bpm and a 20 minute tempo run both qualify. This file decides, from signals the app already stores,
// whether a segment is better offered as a Walk. Pure and Foundation only (Linux-testable), no clock.
//
// A segment is a Walk when ALL of these hold:
//  1. It lasts 8 to 120 minutes.
//  2. Its mean heart rate is below 60 % of the heart-rate reserve ((HRmax - resting) the Karvonen way) AND
//     below the start of zone 3, whichever is lower. Zone 3 (70 % of HRmax by default) is where steady
//     training starts, so a stretch whose average already sits there is not an amble.
//  3. It is steady: the per-minute standard deviation is at most 12 bpm, and no 3 minutes in a row reach
//     zone 3. A short hill or a sprint for a bus is fine; a sustained effort is not. With no per-minute
//     series (a caller that only has avg/peak) the peak may sit at most 40 bpm above the average instead.
//  4. When the strap's own gait classifier (stepSample.activityClass: 0 still, 1 walk, 2 run) has at least
//     20 classed ticks inside the window: run ticks are under 15 % and walk ticks are at least 40 %. An easy
//     jog, a slow bike ride or a yoga class can all keep the heart rate low; the gait ticks tell them apart.
//     Without that data (a 4.0 strap, a window not offloaded yet) the heart rate alone decides.
//
// Anything else stays a plain "Looks like a workout".

public enum DetectedSegmentClassifier {

    // MARK: Types

    public enum Guess: String, Equatable, Sendable {
        case walk, workout
    }

    /// What the rules need to know about the person. Every field is optional; the defaults match
    /// `AutoWorkoutDetector` (resting 60) and a mid-range adult (HRmax 190).
    public struct Profile: Equatable, Sendable {
        /// The profile's max heart rate (the manual override, else Tanaka from age).
        public var maxHr: Double?
        public var restingHr: Double?
        /// First bpm of zone 3, from the person's own zone model; nil means 70 % of max.
        public var zone3LowerBpm: Double?

        public init(maxHr: Double? = nil, restingHr: Double? = nil, zone3LowerBpm: Double? = nil) {
            self.maxHr = maxHr; self.restingHr = restingHr; self.zone3LowerBpm = zone3LowerBpm
        }

        var resolvedMax: Double {
            guard let maxHr, maxHr >= 120, maxHr <= 230 else { return DetectedSegmentClassifier.defaultMaxHr }
            return maxHr
        }

        var resolvedResting: Double {
            guard let restingHr, restingHr >= 30, restingHr <= 100 else { return DetectedSegmentClassifier.defaultRestingHr }
            return restingHr
        }

        var resolvedZone3Lower: Double {
            if let zone3LowerBpm, zone3LowerBpm > resolvedResting, zone3LowerBpm < resolvedMax { return zone3LowerBpm }
            return 0.70 * resolvedMax
        }
    }

    /// Share of the strap's classed gait ticks inside a window, each 0...1 of the classed ticks.
    public struct GaitMix: Equatable, Sendable {
        public let walkShare: Double
        public let runShare: Double
        public let classedTicks: Int
        public init(walkShare: Double, runShare: Double, classedTicks: Int) {
            self.walkShare = walkShare; self.runShare = runShare; self.classedTicks = classedTicks
        }

        /// From the raw `activityClass` values of the ticks in a window (nil = not classed). Nil when nothing
        /// was classed at all.
        public static func from(classes: [Int?]) -> GaitMix? {
            let classed = classes.compactMap { $0 }.filter { (0...2).contains($0) }
            guard !classed.isEmpty else { return nil }
            let n = Double(classed.count)
            return GaitMix(walkShare: Double(classed.filter { $0 == 1 }.count) / n,
                           runShare: Double(classed.filter { $0 == 2 }.count) / n,
                           classedTicks: classed.count)
        }
    }

    // MARK: Constants

    public static let defaultMaxHr = 190.0
    /// Same default as `AutoWorkoutDetector.defaultRestingHR`.
    public static let defaultRestingHr = 60.0
    public static let minWalkSec = 8 * 60
    public static let maxWalkSec = 120 * 60
    /// Mean heart rate must stay under this share of the heart-rate reserve.
    public static let maxWalkReserveShare = 0.60
    public static let maxWalkSdBpm = 12.0
    /// This many minutes in a row at or above zone 3 is a sustained effort, not a walk.
    public static let sustainedZone3Minutes = 3
    /// Without a per-minute series: the peak may be at most this far above the average.
    public static let maxWalkPeakAboveAvg = 40
    /// The gait ticks only speak when there are at least this many classed ones in the window.
    public static let minGaitTicks = 20
    public static let maxWalkRunShare = 0.15
    public static let minWalkWalkShare = 0.40
    /// Fewer per-minute points than this and the series is too short to judge steadiness.
    public static let minSeriesMinutes = 5

    /// A walk is saved by itself once it is at least this long...
    public static let autoSaveMinSec = 15 * 60
    /// ...and has been over for this long, so a walk still going is not saved in two pieces.
    public static let autoSaveSettleSec = 10 * 60

    /// The auto-save setting: on unless the person switched it off. `stored` is the value the Settings toggle
    /// wrote, nil when it never did (the setting used to default to off, so nobody is stuck on an old default).
    public static func autoSaveEnabled(stored: Bool?) -> Bool { stored ?? true }

    // MARK: Classify

    /// - Parameters:
    ///   - minuteBpm: mean heart rate per minute of the window, in order; empty when only avg/peak are known.
    public static func classify(durationSec: Int, avgBpm: Int, peakBpm: Int, minuteBpm: [Double],
                                gait: GaitMix?, profile: Profile) -> Guess {
        guard durationSec >= minWalkSec, durationSec <= maxWalkSec else { return .workout }

        let rest = profile.resolvedResting
        let zone3 = profile.resolvedZone3Lower
        let reserve = max(30, profile.resolvedMax - rest)
        let ceiling = min(rest + maxWalkReserveShare * reserve, zone3)
        guard Double(avgBpm) < ceiling else { return .workout }

        if minuteBpm.count >= minSeriesMinutes {
            guard standardDeviation(minuteBpm) <= maxWalkSdBpm else { return .workout }
            guard !hasSustained(minuteBpm, atOrAbove: zone3, minutes: sustainedZone3Minutes) else { return .workout }
        } else {
            guard peakBpm - avgBpm <= maxWalkPeakAboveAvg else { return .workout }
        }

        if let gait, gait.classedTicks >= minGaitTicks {
            guard gait.runShare < maxWalkRunShare, gait.walkShare >= minWalkWalkShare else { return .workout }
        }
        return .walk
    }

    /// Whether a suggestion should be saved by itself: the setting is on, it is a walk nobody has recorded,
    /// it is long enough, and it is over.
    public static func shouldAutoSave(guess: Guess, isRecorded: Bool, durationSec: Int, endTs: Int, nowTs: Int,
                                      enabled: Bool) -> Bool {
        enabled && guess == .walk && !isRecorded
            && durationSec >= autoSaveMinSec && endTs <= nowTs - autoSaveSettleSec
    }

    // MARK: Matching

    /// A recorded workout the segment can be matched to.
    public struct Recorded: Equatable, Sendable {
        public let startTs: Int
        public let endTs: Int
        public let sport: String
        public init(startTs: Int, endTs: Int, sport: String) {
            self.startTs = startTs; self.endTs = endTs; self.sport = sport
        }
    }

    /// The recorded workout that covers MORE than half of the segment (the largest such), or nil.
    public static func recordedMatch(startTs: Int, endTs: Int, in recorded: [Recorded]) -> Recorded? {
        let length = endTs - startTs
        guard length > 0 else { return nil }
        var best: (Recorded, Int)?
        for r in recorded {
            let overlap = min(endTs, r.endTs) - max(startTs, r.startTs)
            guard overlap > 0, Double(overlap) > 0.5 * Double(length) else { continue }
            if best == nil || overlap > best!.1 { best = (r, overlap) }
        }
        return best?.0
    }

    // MARK: Helpers

    /// Per-minute means of `(ts, bpm)` samples inside `[start, end)`, in time order. Minutes with no sample are
    /// skipped, never interpolated.
    public static func minuteMeans(samples: [(ts: Int, bpm: Double)], start: Int, end: Int) -> [Double] {
        var sums: [Int: (sum: Double, n: Int)] = [:]
        for s in samples where s.ts >= start && s.ts < end {
            let minute = (s.ts - start) / 60
            let cur = sums[minute] ?? (0, 0)
            sums[minute] = (cur.sum + s.bpm, cur.n + 1)
        }
        return sums.keys.sorted().map { sums[$0]!.sum / Double(sums[$0]!.n) }
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }

    static func hasSustained(_ values: [Double], atOrAbove limit: Double, minutes: Int) -> Bool {
        var run = 0
        for v in values {
            run = v >= limit ? run + 1 : 0
            if run >= minutes { return true }
        }
        return false
    }
}
