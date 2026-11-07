import Foundation

// ChargeSplit.swift - Charge read in two parts: what the body signals say, and how last night's sleep went.
//
// Presentation only. The Charge score and its drivers (`RecoveryScorer.recovery`, `chargeDrivers`) are untouched; this
// re-reads the SAME z-scores two ways, built with the same expressions and weights `recovery(...)` uses:
//
//   Body signals = the weighted mean z of heart rate variability, resting heart rate, respiration and skin temperature,
//                  each at its Charge weight, renormalised over the terms that are present. Sleep is left out.
//   Sleep        = the Rest term's z, (Rest - 85 %) / 12 points, the same centre and scale Charge scores it with.
//
// Both go on a signed -10...+10 scale, clamp(3.3 x z), where 0 is the athlete's usual (body signals) or a good night
// (sleep). The scale and the three cut-offs below are NOOP's own, not a published standard.
//
// Pure and side-effect-free. Returns nil in the same cold-start cases `chargeDrivers` returns nothing: no usable HRV baseline.

public struct ChargeSignal: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case settled
        case behind
        case wellBehind
    }

    /// On the signed -10...+10 scale, one decimal.
    public let value: Double
    /// The z-score it comes from, two decimals.
    public let z: Double
    public let state: State
    /// One plain line. Also a localization key.
    public let line: String

    public init(value: Double, z: Double, state: State, line: String) {
        self.value = value
        self.z = z
        self.state = state
        self.line = line
    }
}

public struct ChargeSplit: Equatable, Sendable {
    public let body: ChargeSignal?
    public let sleep: ChargeSignal?
    /// Which body terms were present, in a fixed order: "hrv", "rhr", "respiration", "skin_temp".
    public let bodyInputs: [String]

    public init(body: ChargeSignal?, sleep: ChargeSignal?, bodyInputs: [String]) {
        self.body = body
        self.sleep = sleep
        self.bodyInputs = bodyInputs
    }

    // Fixed copy; every literal is also a localization key in Strand's Localizable.xcstrings.
    public static let bodyLines = ["Body signals: nervous system settled",
                                   "Body signals: a little behind your usual",
                                   "Body signals: well behind your usual"]
    public static let sleepLines = ["Sleep: a good night or better",
                                    "Sleep: a little short of a good night",
                                    "Sleep: well short of a good night"]
    public static let bodyGloss = "Body signals read your overnight heart-rate variability (HRV, the beat-to-beat variation), resting heart rate, breathing rate and skin temperature against your own usual. 0 is your usual; below 0 is behind it."
    public static let sleepGloss = "Sleep is last night's Rest score against a good night. 0 is a good night; below 0 is short of it."
}

extension RecoveryScorer {

    /// Scale: points on the -10...+10 reading per z-unit, and its clamp.
    public static let splitScalePerZ: Double = 3.3
    public static let splitScaleLimit: Double = 10.0
    /// A z at or above this reads "settled"; at or above `splitWellBehindZ` "a little behind"; below it "well behind".
    public static let splitSettledZ: Double = -0.5
    public static let splitWellBehindZ: Double = -1.5

    /// The two-part read from the SAME inputs `chargeDrivers(...)` takes. Nil when Charge itself cannot score
    /// (HRV baseline not usable) or when neither part has an input.
    public static func chargeSplit(hrv: Double,
                                   rhr: Double,
                                   resp: Double?,
                                   hrvBaseline: BaselineState,
                                   rhrBaseline: BaselineState?,
                                   respBaseline: BaselineState?,
                                   sleepPerf: Double?,
                                   skinTempDev: Double? = nil) -> ChargeSplit? {
        guard hrvBaseline.usable else { return nil }

        var terms: [(key: String, z: Double, w: Double)] = []
        terms.append(("hrv", zScore(hrv, mean: hrvBaseline.baseline, spread: hrvBaseline.spread), wHRV))
        if let b = rhrBaseline, b.usable {
            terms.append(("rhr", zScore(b.baseline, mean: rhr, spread: b.spread), wRHR))
        }
        if let r = resp, let b = respBaseline {
            terms.append(("respiration", zScore(b.baseline, mean: r, spread: b.spread), wResp))
        }
        if let dev = skinTempDev {
            terms.append(("skin_temp", -abs(dev) / skinTempScaleC, wSkinTemp))
        }
        var body: ChargeSignal?
        let weight = terms.reduce(0.0) { $0 + $1.w }
        if weight > 0 {
            let weighted = terms.reduce(0.0) { $0 + $1.z * $1.w }
            body = splitSignal(z: weighted / weight, lines: ChargeSplit.bodyLines)
        }
        var sleep: ChargeSignal?
        if let sp = sleepPerf {
            sleep = splitSignal(z: (sp - sleepPerfCenter) / sleepPerfScale, lines: ChargeSplit.sleepLines)
        }
        if body == nil && sleep == nil { return nil }
        return ChargeSplit(body: body, sleep: sleep, bodyInputs: terms.map { $0.key })
    }

    /// The -10...+10 reading of a z-score, one decimal.
    static func splitValue(_ z: Double) -> Double {
        let scaled = max(-splitScaleLimit, min(splitScaleLimit, splitScalePerZ * z))
        return (scaled * 10).rounded(.toNearestOrAwayFromZero) / 10
    }

    private static func splitSignal(z: Double, lines: [String]) -> ChargeSignal {
        let tier: Int
        let state: ChargeSignal.State
        if z >= splitSettledZ {
            tier = 0
            state = .settled
        } else if z >= splitWellBehindZ {
            tier = 1
            state = .behind
        } else {
            tier = 2
            state = .wellBehind
        }
        return ChargeSignal(value: splitValue(z), z: (z * 100).rounded(.toNearestOrAwayFromZero) / 100,
                            state: state, line: lines[tier])
    }
}
