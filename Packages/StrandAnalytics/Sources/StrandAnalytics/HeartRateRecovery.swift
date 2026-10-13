import Foundation
import WhoopProtocol

/// Heart-rate recovery after a sufficiently intense workout (#516).
///
/// The engine deliberately works from the recorded HR stream rather than the workout's editable summary
/// fields. It looks for sustained Zone-3-or-higher effort near the end of the session, takes the median
/// recorded HR in the final 10 seconds as the stop reference (the highest HR in the final 30 seconds is kept
/// as `peakHR`, but is not the reference: it sits above the HR at the moment of stopping and inflates the
/// drop), then compares it with robust median readings around 1, 2 and 5 minutes after the workout ended.
///
/// Two situations are tagged rather than scored: a walking cool-down (HR within 5 bpm of the stop reference
/// at 1 minute, so there was no real stop) and HR that rises after the stop (>= 8 bpm above the reference at
/// 1 or 2 minutes). Their drops are still reported, but `contextBand` is nil.
///
/// A watch's post-stop trace can be too thin to read (fewer than `fallbackMinimumSamples` readings in
/// `fallbackWindowSeconds` after the stop). `evaluateWithStrapFallback` then reads the strap's own trace for
/// the same window instead, stop reference included (two devices read a few bpm apart, so a drop is never
/// taken across devices) and marks the result `fromStrap`.
///
/// Missing post-workout coverage stays nil. The engine never interpolates across a gap or turns a missing
/// reading into zero, which is important when a strap disconnects as the workout ends.
public enum HeartRateRecovery {
    /// Where the HRmax behind the 70 % eligibility gate came from.
    public enum MaxHRSource: String, Equatable, Sendable {
        case override
        case tanaka
        case measured
    }

    /// Population context for the 1-minute drop (Cole 1999: <= 12 bpm is abnormal). Shown as a neutral
    /// caption only, never as a pass/fail grade.
    public enum ContextBand: String, Equatable, Sendable {
        case flag     // <= 12 bpm
        case low      // 13...18
        case typical  // 19...30
        case strong   // > 30

        public static func band(forOneMinuteDrop drop: Int) -> ContextBand {
            switch drop {
            case ...12: return .flag
            case 13...18: return .low
            case 19...30: return .typical
            default: return .strong
            }
        }
    }

    public struct Result: Equatable, Sendable {
        /// The stop reference: median HR in the last 10 s before the end. Drops are measured from it.
        public let endHR: Int
        /// Highest HR in the last 30 s before the end (the pre-change start value).
        public let peakHR: Int
        public let after1Minute: Int?
        public let after2Minutes: Int?
        public let after5Minutes: Int?
        /// HRmax the 70 % eligibility gate used, and where it came from (nil when the caller did not say).
        public let maxHR: Double?
        public let maxHRSource: MaxHRSource?
        /// HR at +1 or +2 min was >= 8 bpm above the stop reference.
        public let risingAfterStop: Bool
        /// HR at +1 min was within 5 bpm of the stop reference: a walking cool-down, not a real stop.
        public let walking: Bool
        /// The figure was read from the strap because the watch's post-stop trace was too sparse.
        public let fromStrap: Bool

        public init(endHR: Int, peakHR: Int? = nil, after1Minute: Int?, after2Minutes: Int?, after5Minutes: Int?,
                    maxHR: Double? = nil, maxHRSource: MaxHRSource? = nil,
                    risingAfterStop: Bool = false, walking: Bool = false, fromStrap: Bool = false) {
            self.endHR = endHR
            self.peakHR = peakHR ?? endHR
            self.after1Minute = after1Minute
            self.after2Minutes = after2Minutes
            self.after5Minutes = after5Minutes
            self.maxHR = maxHR
            self.maxHRSource = maxHRSource
            self.risingAfterStop = risingAfterStop
            self.walking = walking
            self.fromStrap = fromStrap
        }

        public var hasMeasurement: Bool {
            after1Minute != nil || after2Minutes != nil || after5Minutes != nil
        }

        /// True when the drop is a real post-stop recovery rather than a walking or rising pattern.
        public var isScorable: Bool { !walking && !risingAfterStop }

        /// Context band for the 1-minute drop; nil when there is no 1-minute reading or it is not scorable.
        public var contextBand: ContextBand? {
            guard isScorable, let drop = after1Minute else { return nil }
            return ContextBand.band(forOneMinuteDrop: drop)
        }
    }

    /// Zone 3 starts at 70% HRmax in NOOP's display-zone model.
    public static let eligibilityFractionOfMaxHR = 0.70
    /// The high-intensity effort must be sustained, not a single optical spike.
    public static let minimumHighIntensitySeconds = 120
    /// Eligibility is intentionally tied to the end of the workout: HRR is meaningful only when exercise
    /// cessation, rather than a long cool-down, anchors the recovery clock.
    public static let eligibilityLookbackSeconds = 300
    public static let cessationWindowSeconds = 30
    /// The stop reference is the median over this many seconds before the end.
    public static let stopReferenceWindowSeconds = 10
    public static let risingThresholdBpm = 8
    public static let walkingToleranceBpm = 5
    public static let measurementToleranceSeconds = 15
    public static let minimumSamplesPerReading = 3
    public static let maximumContinuousGapSeconds = 10
    /// Sparse watch trace: fewer than this many readings between +20 s and +130 s after the stop.
    public static let fallbackWindowSeconds = 20...130
    public static let fallbackMinimumSamples = 3

    /// Why a workout has no recovery figure, in the order the checks run.
    public enum Unavailable: Equatable, Sendable {
        /// No usable maximum heart rate to measure intensity against.
        case missingMaxHR
        /// The workout has no valid start/end window.
        case invalidWorkout
        /// Not enough readings at the very end of the workout to set the starting heart rate.
        case tooFewReadingsAtEnd
        /// Under `minimumHighIntensitySeconds` at or above 70% of max heart rate near the end.
        case notHardEnough
        /// The end heart rate is known but no recovery point (1, 2 or 5 min) has enough readings.
        case noReadingsAfterEnd
    }

    public enum Outcome: Equatable, Sendable {
        case measured(Result)
        case unavailable(Unavailable)
    }

    public static func calculate(samples: [HRSample], workoutStart: Int, workoutEnd: Int,
                                 maxHR: Double, maxHRSource: MaxHRSource? = nil,
                                 minimumSamplesPerReading: Int = HeartRateRecovery.minimumSamplesPerReading,
                                 measurementToleranceSeconds: Int = HeartRateRecovery.measurementToleranceSeconds,
                                 minimumCessationSamples: Int = HeartRateRecovery.minimumSamplesPerReading,
                                 maximumContinuousGapSeconds: Int = HeartRateRecovery.maximumContinuousGapSeconds) -> Result? {
        if case .measured(let result) = evaluate(
            samples: samples, workoutStart: workoutStart, workoutEnd: workoutEnd,
            maxHR: maxHR, maxHRSource: maxHRSource,
            minimumSamplesPerReading: minimumSamplesPerReading,
            measurementToleranceSeconds: measurementToleranceSeconds,
            minimumCessationSamples: minimumCessationSamples,
            maximumContinuousGapSeconds: maximumContinuousGapSeconds) {
            return result
        }
        return nil
    }

    /// `calculate` with the reason attached when there is no figure. Same checks, same order.
    ///
    /// `maximumContinuousGapSeconds` is the longest hole between readings that still counts as
    /// continuous effort. The 10 s default suits a 1 Hz strap; a watch that records every 5 to 30 s needs
    /// a wider one or no run can ever reach `minimumHighIntensitySeconds`.
    public static func evaluate(samples: [HRSample], workoutStart: Int, workoutEnd: Int,
                                maxHR: Double, maxHRSource: MaxHRSource? = nil,
                                minimumSamplesPerReading: Int = HeartRateRecovery.minimumSamplesPerReading,
                                measurementToleranceSeconds: Int = HeartRateRecovery.measurementToleranceSeconds,
                                minimumCessationSamples: Int = HeartRateRecovery.minimumSamplesPerReading,
                                maximumContinuousGapSeconds: Int = HeartRateRecovery.maximumContinuousGapSeconds) -> Outcome {
        guard maxHR > 0 else { return .unavailable(.missingMaxHR) }
        guard workoutStart > 0, workoutEnd > workoutStart else { return .unavailable(.invalidWorkout) }
        let lowerBound = max(workoutStart, workoutEnd - eligibilityLookbackSeconds)
        let upperBound = workoutEnd + 5 * 60 + max(0, measurementToleranceSeconds)
        let sorted = samples
            .filter { $0.ts >= lowerBound && $0.ts <= upperBound && (30...250).contains($0.bpm) }
            .sorted { lhs, rhs in lhs.ts == rhs.ts ? lhs.bpm < rhs.bpm : lhs.ts < rhs.ts }

        let beforeEnd = sorted.filter { $0.ts <= workoutEnd }
        guard !beforeEnd.isEmpty else { return .unavailable(.tooFewReadingsAtEnd) }
        let threshold = maxHR * eligibilityFractionOfMaxHR
        guard sustainedSeconds(atOrAbove: threshold, in: beforeEnd,
                               maximumGapSeconds: maximumContinuousGapSeconds) >= minimumHighIntensitySeconds else {
            return .unavailable(.notHardEnough)
        }

        let cessation = beforeEnd
            .filter { $0.ts >= workoutEnd - cessationWindowSeconds }
            .map(\.bpm)
        guard cessation.count >= max(1, minimumCessationSamples), let peakHR = cessation.max() else {
            return .unavailable(.tooFewReadingsAtEnd)
        }
        // The stop reference is the median of the last 10 s. A sparse (watch) stream may have too few
        // readings that close to the end, so fall back to the median of the 30 s cessation window rather
        // than refusing; the median, unlike the old max, does not read above the HR at the moment of stopping.
        let lastTen = beforeEnd
            .filter { $0.ts >= workoutEnd - stopReferenceWindowSeconds }
            .map(\.bpm)
        let referencePool = lastTen.count >= max(1, minimumCessationSamples) ? lastTen : cessation
        guard let endHR = median(referencePool) else { return .unavailable(.tooFewReadingsAtEnd) }

        /// HR median around `minutes` after the end, or nil without enough readings.
        func reading(at minutes: Int) -> Int? {
            let target = workoutEnd + minutes * 60
            let values = sorted
                .filter { abs($0.ts - target) <= measurementToleranceSeconds }
                .map(\.bpm)
            guard values.count >= max(1, minimumSamplesPerReading) else { return nil }
            return median(values)
        }
        let hr1 = reading(at: 1)
        let hr2 = reading(at: 2)
        let hr5 = reading(at: 5)

        let isRising = [hr1, hr2].contains { value in value.map { $0 - endHR >= risingThresholdBpm } ?? false }
        let isWalking = hr1.map { abs($0 - endHR) <= walkingToleranceBpm } ?? false

        let result = Result(
            endHR: endHR,
            peakHR: peakHR,
            after1Minute: hr1.map { endHR - $0 },
            after2Minutes: hr2.map { endHR - $0 },
            after5Minutes: hr5.map { endHR - $0 },
            maxHR: maxHR,
            maxHRSource: maxHRSource,
            risingAfterStop: isRising,
            walking: isWalking
        )
        return result.hasMeasurement ? .measured(result) : .unavailable(.noReadingsAfterEnd)
    }

    /// True when `samples` has fewer than `fallbackMinimumSamples` readings in +20...+130 s after `workoutEnd`.
    public static func postStopWindowIsSparse(samples: [HRSample], workoutEnd: Int) -> Bool {
        let count = samples.filter {
            fallbackWindowSeconds.contains($0.ts - workoutEnd) && (30...250).contains($0.bpm)
        }.count
        return count < fallbackMinimumSamples
    }

    /// `evaluate` over the watch's `samples`, with the strap as the fallback for a sparse post-stop window.
    ///
    /// The strap replaces the watch only when the watch window is sparse, the strap's is not, and the strap
    /// yields a measured result; otherwise the watch's outcome stands. The strap is read with the strict
    /// 1 Hz defaults (3 readings within 15 s of each recovery point), whatever lenient settings the watch used.
    public static func evaluateWithStrapFallback(
        samples: [HRSample], strapSamples: [HRSample], workoutStart: Int, workoutEnd: Int,
        maxHR: Double, maxHRSource: MaxHRSource? = nil,
        minimumSamplesPerReading: Int = HeartRateRecovery.minimumSamplesPerReading,
        measurementToleranceSeconds: Int = HeartRateRecovery.measurementToleranceSeconds,
        minimumCessationSamples: Int = HeartRateRecovery.minimumSamplesPerReading,
        maximumContinuousGapSeconds: Int = HeartRateRecovery.maximumContinuousGapSeconds) -> Outcome {
        let primary = evaluate(samples: samples, workoutStart: workoutStart, workoutEnd: workoutEnd,
                               maxHR: maxHR, maxHRSource: maxHRSource,
                               minimumSamplesPerReading: minimumSamplesPerReading,
                               measurementToleranceSeconds: measurementToleranceSeconds,
                               minimumCessationSamples: minimumCessationSamples,
                               maximumContinuousGapSeconds: maximumContinuousGapSeconds)
        guard postStopWindowIsSparse(samples: samples, workoutEnd: workoutEnd),
              !postStopWindowIsSparse(samples: strapSamples, workoutEnd: workoutEnd),
              case .measured(let strap) = evaluate(samples: strapSamples, workoutStart: workoutStart,
                                                   workoutEnd: workoutEnd, maxHR: maxHR,
                                                   maxHRSource: maxHRSource),
              strap.after1Minute != nil || strap.after2Minutes != nil else { return primary }
        return .measured(Result(
            endHR: strap.endHR, peakHR: strap.peakHR, after1Minute: strap.after1Minute,
            after2Minutes: strap.after2Minutes, after5Minutes: strap.after5Minutes,
            maxHR: strap.maxHR, maxHRSource: strap.maxHRSource,
            risingAfterStop: strap.risingAfterStop, walking: strap.walking, fromStrap: true))
    }

    private static func sustainedSeconds(atOrAbove threshold: Double, in samples: [HRSample],
                                         maximumGapSeconds: Int) -> Int {
        guard samples.count >= 2 else { return 0 }
        var currentSeconds = 0
        var longestSeconds = 0
        for i in 0..<(samples.count - 1) {
            let gap = samples[i + 1].ts - samples[i].ts
            guard gap > 0 else { continue }
            guard gap <= maximumGapSeconds else {
                currentSeconds = 0
                continue
            }
            guard Double(samples[i].bpm) >= threshold else {
                currentSeconds = 0
                continue
            }
            currentSeconds += gap
            longestSeconds = max(longestSeconds, currentSeconds)
        }
        return longestSeconds
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Int((Double(sorted[middle - 1] + sorted[middle]) / 2.0).rounded())
        }
        return sorted[middle]
    }
}
