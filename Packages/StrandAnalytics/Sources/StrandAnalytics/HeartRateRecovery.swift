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
/// A caller whose source stops recording at the stop (Garmin through PaceForge: its per-second recording ends
/// there, and what follows is the 120 s all-day series, bin means rather than readings) passes
/// `requiredPostStopSeconds`; the engine then refuses to compute a drop unless continuous readings run that
/// far past the end. The day-series readings that do follow (one every 2 minutes) are returned as
/// `.garminReadings`, listed exactly as Garmin Connect shows them: not 1- / 2-minute values, no band.
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

        public init(endHR: Int, peakHR: Int? = nil, after1Minute: Int?, after2Minutes: Int?, after5Minutes: Int?,
                    maxHR: Double? = nil, maxHRSource: MaxHRSource? = nil,
                    risingAfterStop: Bool = false, walking: Bool = false) {
            self.endHR = endHR
            self.peakHR = peakHR ?? endHR
            self.after1Minute = after1Minute
            self.after2Minutes = after2Minutes
            self.after5Minutes = after5Minutes
            self.maxHR = maxHR
            self.maxHRSource = maxHRSource
            self.risingAfterStop = risingAfterStop
            self.walking = walking
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
        /// The source stopped recording at the stop and its all-day series has nothing after it yet.
        case noPostStopData
    }

    /// One Garmin all-day-series reading after the stop, exactly as Garmin Connect shows it.
    public struct GarminReading: Equatable, Sendable {
        public let offsetSeconds: Int
        public let bpm: Int
        /// The stop reference minus this reading (negative: above the stop value).
        public let drop: Int
        public init(offsetSeconds: Int, bpm: Int, drop: Int) {
            self.offsetSeconds = offsetSeconds
            self.bpm = bpm
            self.drop = drop
        }
    }

    /// What exists after the stop when the source stopped recording at it: the first readings of Garmin's
    /// all-day series. Display only: never scored, banded or compared with a baseline.
    public struct GarminReadings: Equatable, Sendable {
        public let endHR: Int
        public let peakHR: Int
        public let readings: [GarminReading]
        public init(endHR: Int, peakHR: Int, readings: [GarminReading]) {
            self.endHR = endHR
            self.peakHR = peakHR
            self.readings = readings
        }
    }

    public static let garminReadingCount = 3
    public static let garminReadingsLabel = "Garmin records one reading every 2 minutes after the workout; shown as Garmin Connect shows it"

    public enum Outcome: Equatable, Sendable {
        case measured(Result)
        case garminReadings(GarminReadings)
        case unavailable(Unavailable)
    }

    public static func calculate(samples: [HRSample], workoutStart: Int, workoutEnd: Int,
                                 maxHR: Double, maxHRSource: MaxHRSource? = nil,
                                 minimumSamplesPerReading: Int = HeartRateRecovery.minimumSamplesPerReading,
                                 measurementToleranceSeconds: Int = HeartRateRecovery.measurementToleranceSeconds,
                                 minimumCessationSamples: Int = HeartRateRecovery.minimumSamplesPerReading,
                                 maximumContinuousGapSeconds: Int = HeartRateRecovery.maximumContinuousGapSeconds,
                                 requiredPostStopSeconds: Int = 0) -> Result? {
        if case .measured(let result) = evaluate(
            samples: samples, workoutStart: workoutStart, workoutEnd: workoutEnd,
            maxHR: maxHR, maxHRSource: maxHRSource,
            minimumSamplesPerReading: minimumSamplesPerReading,
            measurementToleranceSeconds: measurementToleranceSeconds,
            minimumCessationSamples: minimumCessationSamples,
            maximumContinuousGapSeconds: maximumContinuousGapSeconds,
            requiredPostStopSeconds: requiredPostStopSeconds) {
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
                                maximumContinuousGapSeconds: Int = HeartRateRecovery.maximumContinuousGapSeconds,
                                requiredPostStopSeconds: Int = 0) -> Outcome {
        guard maxHR > 0 else { return .unavailable(.missingMaxHR) }
        guard workoutStart > 0, workoutEnd > workoutStart else { return .unavailable(.invalidWorkout) }
        let lowerBound = max(workoutStart, workoutEnd - eligibilityLookbackSeconds)
        // A source that stops recording at the stop lists its next day-series readings, about +2, +4 and +6 min.
        let upperBound = workoutEnd + 5 * 60 + max(0, measurementToleranceSeconds)
            + (requiredPostStopSeconds > 0 ? 2 * 60 : 0)
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
        let coverage = continuousSecondsAfterEnd(in: sorted, workoutEnd: workoutEnd,
                                                 maximumGapSeconds: maximumContinuousGapSeconds)
        if coverage < requiredPostStopSeconds {
            let readings = sorted.filter { $0.ts > workoutEnd + coverage }.prefix(garminReadingCount)
                .map { GarminReading(offsetSeconds: $0.ts - workoutEnd, bpm: $0.bpm, drop: endHR - $0.bpm) }
            return readings.isEmpty
                ? .unavailable(.noPostStopData)
                : .garminReadings(GarminReadings(endHR: endHR, peakHR: peakHR, readings: Array(readings)))
        }

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

    /// Seconds past the end covered by unbroken readings (gaps of at most `maximumGapSeconds`), starting from
    /// the last reading at or before the end. 0 when the recording stops at the end.
    private static func continuousSecondsAfterEnd(in sorted: [HRSample], workoutEnd: Int,
                                                  maximumGapSeconds: Int) -> Int {
        guard var last = sorted.last(where: { $0.ts <= workoutEnd })?.ts else { return 0 }
        for sample in sorted where sample.ts > workoutEnd {
            guard sample.ts - last <= maximumGapSeconds else { break }
            last = sample.ts
        }
        return max(0, last - workoutEnd)
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
