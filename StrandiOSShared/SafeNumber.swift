import Foundation

/// Number conversions that cannot trap. Swift's `Int(Double)` crashes the app on NaN, infinity and any value outside
/// `Int` range, and a server document or a division by zero can produce all three; every place that turns a score,
/// a duration or a pace into whole numbers goes through here instead.
enum Safe {
    /// Largest magnitude `int` returns: far beyond any score, duration or timestamp, and still safe to add to or
    /// multiply by a small number without overflowing.
    static let limit: Double = 9_007_199_254_740_992

    /// `value` rounded (to nearest by default) as an `Int`. NaN reads as 0 and out-of-range values clamp to `limit`.
    static func int(_ value: Double, _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        guard !value.isNaN else { return 0 }
        return Int(min(max(value.rounded(rule), -limit), limit))
    }
}
