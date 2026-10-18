import Foundation

// MARK: - StepsSourceResolver
//
// One answer to "which steps do we show for this day, and who counted them". The order is the steps column
// of `MetricArbitrationPolicy`: a phone or band that counts directly (Apple Health, Health Connect, Mi Band),
// then the Garmin watch PaceForge mirrors in, then any strap estimate. Every screen that prints a step count
// goes through here so the number and its label cannot disagree. Pure and Foundation-only so it runs on Linux.

/// One source's step count for a single day.
public struct StepsReading: Equatable, Sendable {
    public let source: FusionSource
    public let value: Double
    public init(source: FusionSource, value: Double) {
        self.source = source
        self.value = value
    }
}

/// The step count a day shows, with the source that supplied it and the label to print next to it.
public struct ResolvedSteps: Equatable, Sendable {
    public let value: Double
    public let source: FusionSource
    public let label: String
    public init(value: Double, source: FusionSource, label: String) {
        self.value = value
        self.source = source
        self.label = label
    }
}

public enum StepsSourceResolver {

    /// UserDefaults flag the Apple Health bridge sets while its last sync could not read steps, so shared
    /// screens (which do not link the iOS-only bridge) can explain a missing Apple count.
    public static let appleStepsUnavailableKey = "appleHealth.stepsUnavailable"

    /// Label printed beside a step count: "Garmin", "Apple Health", "Health Connect", "Mi Band", or
    /// "strap estimate" for anything the strap itself produced. A count that only survives in the merged
    /// daily cache (an activity file, say) keeps the neutral "Cached".
    public static func label(for source: FusionSource) -> String {
        switch source {
        case .whoopImport, .noopComputed:
            return "strap estimate"
        case .appleHealth, .healthConnect, .xiaomiBand, .paceforgeGarmin, .nutritionCsv, .localCache:
            return source.displayName
        }
    }

    /// Map a stored device id onto a fusion source. Every id that is not one of the four step counters is
    /// a strap (imported "my-whoop", its "-noop" sibling, or the motion estimate under them).
    public static func source(forStoredId id: String) -> FusionSource {
        switch id {
        case FusionSource.appleHealth.rawValue: return .appleHealth
        case FusionSource.healthConnect.rawValue: return .healthConnect
        case FusionSource.paceforgeGarmin.rawValue: return .paceforgeGarmin
        case FusionSource.xiaomiBand.rawValue: return .xiaomiBand
        default: return .noopComputed
        }
    }

    /// The best step count among `readings`. A source that reports a positive count always beats one that
    /// reports zero (a stopped phone or a strap that banked nothing must not hide a real count); a day where
    /// every source says zero resolves to zero from the best-ranked source. nil only when no source reported.
    public static func resolve(_ readings: [StepsReading]) -> ResolvedSteps? {
        let usable = readings.filter { $0.value.isFinite && $0.value >= 0 }
        let positive = usable.filter { $0.value > 0 }
        let pool = positive.isEmpty ? usable : positive
        guard let point = FusionResolver.resolve(
            metricKey: "steps", inputs: pool.map { FusionInput(source: $0.source, value: $0.value) })
        else { return nil }
        return ResolvedSteps(value: point.value, source: point.winningSource, label: label(for: point.winningSource))
    }

    /// Which source's SERIES to chart or compare when each source's newest day is known. The source that
    /// reaches the latest day wins, so a phone whose sync stopped weeks ago cannot hide a watch that is
    /// current; on the same latest day the policy order decides.
    public static func preferredSeriesSource(latestDayBySource: [FusionSource: String]) -> FusionSource? {
        latestDayBySource.min { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            let lt = MetricArbitrationPolicy.tier(metric: .steps, source: lhs.key)
            let rt = MetricArbitrationPolicy.tier(metric: .steps, source: rhs.key)
            if lt != rt { return lt < rt }
            return MetricArbitrationPolicy.sourcePriority(lhs.key) < MetricArbitrationPolicy.sourcePriority(rhs.key)
        }?.key
    }

    /// The steps column after the day-cycle pass. A wake day the cycle pass has no count for keeps the
    /// value the row already carried; the pass must never replace a real count with nothing.
    public static func cycleSteps(established: Bool, cycle: Int?, existing: Int?) -> Int? {
        established ? (cycle ?? existing) : existing
    }

    /// The explanation to show when the last Apple Health sync could not read steps. nil when it could, or
    /// when the day's count is Apple Health's own.
    public static func unavailableNotice(appleUnavailable: Bool, resolved: ResolvedSteps?) -> String? {
        guard appleUnavailable else { return nil }
        guard let resolved else { return "Steps from Apple Health unavailable" }
        switch resolved.source {
        case .appleHealth: return nil
        case .paceforgeGarmin: return "Steps from Apple Health unavailable — showing Garmin"
        default: return "Steps from Apple Health unavailable — showing \(resolved.label)"
        }
    }
}
