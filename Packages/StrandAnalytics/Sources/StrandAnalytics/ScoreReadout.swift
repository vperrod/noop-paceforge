import Foundation

// ScoreReadout.swift - one plain verdict line per score, the single biggest driver in a sentence, and a calibration counter.
//
// Deterministic text built only from numbers the screen already holds (no model, no new score). The band cut-offs are
// NOOP's own: Charge 34 and 67 (`RecoveryScorer.bandRedMax` / `bandYellowMax`), Rest 70 and 85. Nothing is borrowed
// from another band's scale. The verdict lines are fixed phrases and double as localization keys; the driver sentence
// is composed from the engine's own driver labels and numbers.
//
// Presentation only: it changes no score, no band and no driver.

public enum ScoreReadout {

    public struct Lines: Equatable, Sendable {
        /// A fixed phrase (also a localization key), or nil when the score is not there.
        public let verdict: String?
        /// The biggest mover in a sentence, or nil.
        public let driver: String?
        /// While the baseline is still building: nights banked so far, and the nights it takes to trust it.
        public let calibrationHave: Int?
        public let calibrationNeed: Int?

        public init(verdict: String? = nil, driver: String? = nil, calibrationHave: Int? = nil, calibrationNeed: Int? = nil) {
            self.verdict = verdict
            self.driver = driver
            self.calibrationHave = calibrationHave
            self.calibrationNeed = calibrationNeed
        }

        public var isEmpty: Bool { verdict == nil && driver == nil && calibrationHave == nil }
    }

    // MARK: - Cut-offs and fixed phrases

    public static let restPoorBelow: Double = 70
    public static let restOptimalFrom: Double = 85
    /// A driver that moved Charge by fewer points than this is not "the" driver.
    public static let chargeMinPoints: Int = 1
    /// Within this share of its best a Rest part is not holding the night back.
    public static let restNearBest: Double = 0.05

    public static let chargeVerdicts = ["Run down: under-recovered, keep it light",
                                        "Steady: partly recovered, a moderate day suits",
                                        "Ready: well recovered, a hard day is fine"]
    public static let restVerdicts = ["Poor: a short or broken night",
                                      "Sufficient: a decent night, short of your best",
                                      "Optimal: a restorative night"]
    public static let effortVerdicts = ["Building toward today's target", "Inside today's target", "Above today's target"]

    // MARK: - Charge

    public static func charge(score: Double?, drivers: [ChargeDriver], hrvBaseline: BaselineState?) -> Lines {
        var have: Int?
        var need: Int?
        if let b = hrvBaseline, b.status == .calibrating || b.status == .provisional {
            have = b.nValid
            need = Baselines.minNightsTrust
        }
        guard let score else { return Lines(calibrationHave: have, calibrationNeed: need) }
        let verdict: String
        switch RecoveryScorer.band(score) {
        case "red": verdict = chargeVerdicts[0]
        case "yellow": verdict = chargeVerdicts[1]
        default: verdict = chargeVerdicts[2]
        }
        return Lines(verdict: verdict, driver: chargeDriverSentence(drivers), calibrationHave: have, calibrationNeed: need)
    }

    /// "Mostly lifted by heart rate variability, 62 ms against your 55 ms baseline." Drivers arrive biggest mover first.
    static func chargeDriverSentence(_ drivers: [ChargeDriver]) -> String? {
        guard !drivers.isEmpty else { return nil }
        let moved = drivers.filter { abs($0.deltaPoints) >= chargeMinPoints }
        guard let top = moved.max(by: { abs($0.deltaPoints) < abs($1.deltaPoints) }) else {
            return "Everything sits near your usual."
        }
        let lead = top.deltaPoints < 0 ? "Mostly pulled down by" : "Mostly lifted by"
        let against = top.baselineText.isEmpty ? "" : " against your \(top.baselineText)"
        return "\(lead) \(top.label.lowercased()), \(top.valueText)\(against)."
    }

    // MARK: - Rest

    /// The three Rest parts are each a percentage; any may be missing.
    public static func rest(score: Double?, hoursPct: Double?, consistencyPct: Double?, efficiencyPct: Double?) -> Lines {
        guard let score else { return Lines() }
        let verdict: String
        if score >= restOptimalFrom {
            verdict = restVerdicts[2]
        } else if score >= restPoorBelow {
            verdict = restVerdicts[1]
        } else {
            verdict = restVerdicts[0]
        }
        return Lines(verdict: verdict, driver: restDriverSentence(hoursPct: hoursPct, consistencyPct: consistencyPct,
                                                                   efficiencyPct: efficiencyPct))
    }

    /// The part furthest below its own best (hours 100 %, consistency 80 %, efficiency 85 %, the Optimal edges of the rows
    /// the Rest screen draws), as a share of that best.
    static func restDriverSentence(hoursPct: Double?, consistencyPct: Double?, efficiencyPct: Double?) -> String? {
        var parts: [(shortfall: Double, text: String)] = []
        if let h = hoursPct {
            parts.append((shortfall(h, best: 100), "hours slept, \(Int(h.rounded()))% of the sleep you needed"))
        }
        if let c = consistencyPct {
            parts.append((shortfall(c, best: 80), "sleep timing, \(Int(c.rounded()))% consistent"))
        }
        if let e = efficiencyPct {
            parts.append((shortfall(e, best: 85), "time awake in bed, \(Int(e.rounded()))% of it asleep"))
        }
        guard let worst = parts.max(by: { $0.shortfall < $1.shortfall }) else { return nil }
        if worst.shortfall <= restNearBest { return "Nothing is holding last night back." }
        return "Mostly held back by \(worst.text)."
    }

    private static func shortfall(_ value: Double, best: Double) -> Double {
        max(0, (best - value) / best)
    }

    // MARK: - Effort

    /// `progress` is today's Effort against its target band; the zone minutes are today's, in minutes.
    public static func effort(progress: EffortTarget.Progress?, zones13Min: Double?, zones45Min: Double?) -> Lines {
        var verdict: String?
        switch progress?.status {
        case .some(.toGo): verdict = effortVerdicts[0]
        case .some(.inRange): verdict = effortVerdicts[1]
        case .some(.above): verdict = effortVerdicts[2]
        default: verdict = nil
        }
        return Lines(verdict: verdict, driver: effortDriverSentence(zones13Min: zones13Min, zones45Min: zones45Min))
    }

    static func effortDriverSentence(zones13Min: Double?, zones45Min: Double?) -> String? {
        guard zones13Min != nil || zones45Min != nil else { return nil }
        let easy = max(0, zones13Min ?? 0)
        let hard = max(0, zones45Min ?? 0)
        let total = easy + hard
        guard total >= 1 else { return "No time in heart-rate zones yet today." }
        return "Zones 4-5 made up \(Int(hard.rounded())) of today's \(Int(total.rounded())) minutes in heart-rate zones."
    }
}
