import Foundation

// EffortTarget.swift — today's Effort target ("to go") and the Training State word.
//
// Pure, deterministic, DB-free, NOOP's own scale. It invents no physiology and feeds nothing back into a
// score: it only re-presents values the app already has.
//
//   • The target BAND is not computed here. The app passes in the band it already shows as OPTIMAL
//     (CoupledView.optimalStrainRange, on WHOOP's 0–21 axis); `Band(whoopLow:whoopHigh:)` moves it onto
//     NOOP's stored 0–100 Effort axis through the one shared conversion (`StrainScorer.effortValue`).
//   • `progress` compares today's Effort with that band, in whatever scale the user reads Effort on.
//   • `trainingState` turns today's Charge band plus the training-load engine's acute/chronic pair into one
//     of four words. Every threshold is a named constant below.

public enum EffortTarget {

    // MARK: - Band

    /// The target band on NOOP's stored 0–100 Effort axis.
    public struct Band: Equatable, Sendable {
        public let low: Double
        public let high: Double

        public init(low: Double, high: Double) {
            self.low = min(low, high)
            self.high = max(low, high)
        }

        /// A band given on WHOOP's 0–21 Day Strain axis (what the OPTIMAL stat is defined on).
        public init(whoopLow: Int, whoopHigh: Int) {
            self.init(low: StrainScorer.effortValue(fromWhoopStrain: Double(whoopLow)),
                      high: StrainScorer.effortValue(fromWhoopStrain: Double(whoopHigh)))
        }
    }

    // MARK: - Progress against the band

    /// Today's Effort against the band, in the units the user reads Effort in.
    public struct Progress: Equatable, Sendable {
        public enum Status: Equatable, Sendable {
            /// No band: today's Charge is not known yet, so no target is guessed.
            case noTarget
            /// There is a band but Effort has not been scored today.
            case notScored
            /// Below the band: `toGoLow...toGoHigh` more Effort lands inside it.
            case toGo
            case inRange
            /// Above the band by `aboveBy`.
            case above
        }

        public let status: Status
        /// Display-unit values, rounded to the scale's precision. nil when unknown.
        public let effort: Double?
        public let low: Double?
        public let high: Double?
        public let toGoLow: Double
        public let toGoHigh: Double
        public let aboveBy: Double
        /// 0 for the 0–100 scale, 1 for the 0–21 scale.
        public let decimals: Int
        /// Fill fractions on the stored 0–100 axis (0...1), for gauges. nil when unknown.
        public let effortFraction: Double?
        public let lowFraction: Double?
        public let highFraction: Double?

        public var effortText: String? {
            effort.map { EffortTarget.format($0, decimals: decimals) }
        }

        public var rangeText: String? {
            guard let low, let high else { return nil }
            return "\(EffortTarget.format(low, decimals: decimals))\u{2013}\(EffortTarget.format(high, decimals: decimals))"
        }

        /// "13–28 to go", "In your range", "Above range by 5", or a plain reason there is no figure.
        public var detail: String {
            switch status {
            case .noTarget: return "Target appears once today's Charge is scored"
            case .notScored: return "Not scored yet"
            case .toGo:
                let a = EffortTarget.format(toGoLow, decimals: decimals)
                let b = EffortTarget.format(toGoHigh, decimals: decimals)
                return "\(a)\u{2013}\(b) to go"
            case .inRange: return "In your range"
            case .above: return "Above range by \(EffortTarget.format(aboveBy, decimals: decimals))"
            }
        }

        /// The one-line read: "Effort 42 of 55–70: 13–28 to go".
        public var text: String {
            guard let range = rangeText else { return detail }
            guard let effort else { return "Effort target \(range): \(detail)" }
            return "Effort \(EffortTarget.format(effort, decimals: decimals)) of \(range): \(detail)"
        }
    }

    /// - Parameters:
    ///   - effort: today's stored 0–100 Effort, or nil when not scored.
    ///   - band: the target band (stored axis), or nil when there is no target.
    ///   - displayFactor: 1 for the 0–100 scale, `21/100` for the 0–21 scale
    ///     (`UnitFormatter.effortScaleFactor`). Everything is compared AFTER rounding to display
    ///     precision, so the numbers on screen always add up ("42 of 55–70" is 13 to the bottom).
    public static func progress(effort: Double?, band: Band?, displayFactor: Double = 1) -> Progress {
        let decimals = displayFactor == 1 ? 0 : 1
        guard let band else {
            return Progress(status: .noTarget, effort: effort.map { display($0, displayFactor, decimals) },
                            low: nil, high: nil, toGoLow: 0, toGoHigh: 0, aboveBy: 0, decimals: decimals,
                            effortFraction: effort.map(fraction), lowFraction: nil, highFraction: nil)
        }
        let low = display(band.low, displayFactor, decimals)
        let high = display(band.high, displayFactor, decimals)
        let lowF = fraction(band.low), highF = fraction(band.high)
        guard let effort else {
            return Progress(status: .notScored, effort: nil, low: low, high: high, toGoLow: 0, toGoHigh: 0,
                            aboveBy: 0, decimals: decimals, effortFraction: nil,
                            lowFraction: lowF, highFraction: highF)
        }
        let shown = display(effort, displayFactor, decimals)
        let status: Progress.Status
        if shown < low { status = .toGo } else if shown > high { status = .above } else { status = .inRange }
        return Progress(status: status, effort: shown, low: low, high: high,
                        toGoLow: status == .toGo ? round(low - shown, decimals) : 0,
                        toGoHigh: status == .toGo ? round(high - shown, decimals) : 0,
                        aboveBy: status == .above ? round(shown - high, decimals) : 0,
                        decimals: decimals, effortFraction: fraction(effort),
                        lowFraction: lowF, highFraction: highF)
    }

    // MARK: - Training State

    /// Today's Charge band. The cut points are the same ones the OPTIMAL band is defined on
    /// (≥ 67 green, 34–66 yellow, < 34 red).
    public enum RecoveryBand: Equatable, Sendable {
        case low, mid, high

        public static let highFrom = 67.0
        public static let midFrom = 34.0

        public init?(recovery: Double?) {
            guard let recovery, recovery.isFinite else { return nil }
            if recovery >= Self.highFrom { self = .high }
            else if recovery >= Self.midFrom { self = .mid }
            else { self = .low }
        }
    }

    public enum TrainingState: String, Equatable, Sendable, CaseIterable {
        case restoring = "Restoring"
        case balanced = "Balanced"
        case building = "Building"
        case overreaching = "Overreaching"

        public var label: String { rawValue }

        /// One plain sentence per word, for the "How it works" sheet.
        public var meaning: String {
            switch self {
            case .restoring: return "Your recent load is light or your Charge is low. Easy days let you catch up."
            case .balanced: return "Recent load matches what you are used to and Charge supports it."
            case .building: return "Recent load is rising above your usual and Charge is keeping up."
            case .overreaching: return "Recent load is well above your usual and Charge is not keeping up."
            }
        }
    }

    /// How much history stands behind a Training State.
    public enum LoadCalibration: Equatable, Sendable {
        /// Not enough contiguous Effort days yet: this many more are needed before a word is shown.
        case needsDays(Int)
        /// A word is shown but the 42-day baseline is still filling.
        case calibrating(days: Int, of: Int)
        case established

        public var note: String? {
            switch self {
            case .needsDays(let n): return "Needs \(n) more day\(n == 1 ? "" : "s") of Effort to read your load"
            case .calibrating(let days, let total): return "Still calibrating: \(days) of \(total) days"
            case .established: return nil
            }
        }
    }

    public struct TrainingStateReading: Equatable, Sendable {
        /// nil while calibrating, or while today's Charge is not scored.
        public let state: TrainingState?
        public let calibration: LoadCalibration
        /// acute / chronic load, nil when the engine has no result or the chronic load is too small.
        public let loadRatio: Double?
    }

    // Thresholds. Acute and chronic load are the training-load engine's ATL (7-day time constant) and CTL
    // (42-day time constant) over daily Effort; the ratio ATL / CTL is the same "this week against what you
    // are used to" comparison the Readiness training-load signal makes, whose sweet spot ends at 1.3.
    /// Ratio at or above which recent load counts as well above usual.
    public static let loadHighRatio = 1.30
    /// Ratio at or above which recent load counts as rising (only reached from a green Charge).
    public static let loadRisingRatio = 1.10
    /// Ratio below which recent load counts as light.
    public static let loadLightRatio = 0.80
    /// Chronic load (Effort points per day) below which the ratio is not meaningful.
    public static let minimumChronicLoad = 5.0

    /// Word for a Charge band and a load ratio. The table:
    ///
    ///   ratio ≥ 1.30            green → Building      yellow / red → Overreaching
    ///   1.10 ≤ ratio < 1.30     green → Building      yellow → Balanced      red → Restoring
    ///   0.80 ≤ ratio < 1.10     green / yellow → Balanced                    red → Restoring
    ///   ratio < 0.80            green → Balanced      yellow / red → Restoring
    ///   no ratio                red → Restoring       otherwise Balanced
    public static func classify(recovery: RecoveryBand, loadRatio: Double?) -> TrainingState {
        guard let ratio = loadRatio else { return recovery == .low ? .restoring : .balanced }
        if ratio >= loadHighRatio {
            return recovery == .high ? .building : .overreaching
        }
        if ratio >= loadRisingRatio {
            switch recovery {
            case .high: return .building
            case .mid: return .balanced
            case .low: return .restoring
            }
        }
        if ratio >= loadLightRatio {
            return recovery == .low ? .restoring : .balanced
        }
        return recovery == .high ? .balanced : .restoring
    }

    /// The Training State for today from today's Charge and the training-load engine's result.
    public static func trainingState(recovery: Double?, load: TrainingLoadEngine.Result,
                                     configuration: TrainingLoadEngine.Configuration = .standard) -> TrainingStateReading {
        let calibration: LoadCalibration
        switch load.state {
        case .unavailable:
            calibration = .needsDays(max(configuration.minimumDays - load.contiguousDays, 1))
        case .building:
            calibration = .calibrating(days: load.contiguousDays, of: configuration.establishedDays)
        case .established:
            calibration = .established
        }
        var ratio: Double?
        if let acute = load.acuteLoad, let chronic = load.chronicLoad, chronic >= minimumChronicLoad {
            ratio = acute / chronic
        }
        guard load.isAvailable, let band = RecoveryBand(recovery: recovery) else {
            return TrainingStateReading(state: nil, calibration: calibration, loadRatio: ratio)
        }
        return TrainingStateReading(state: classify(recovery: band, loadRatio: ratio),
                                    calibration: calibration, loadRatio: ratio)
    }

    // MARK: - Number helpers

    static func fraction(_ stored: Double) -> Double { max(0, min(1, stored / StrainScorer.maxStrain)) }

    static func round(_ v: Double, _ decimals: Int) -> Double {
        let scale = decimals == 0 ? 1.0 : 10.0
        return (v * scale).rounded() / scale
    }

    static func display(_ stored: Double, _ factor: Double, _ decimals: Int) -> Double {
        round(stored * factor, decimals)
    }

    static func format(_ v: Double, decimals: Int) -> String {
        decimals == 0 ? "\(Int(v.rounded()))" : String(format: "%.1f", v)
    }
}
