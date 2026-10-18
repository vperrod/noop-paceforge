import Foundation
import StrandAnalytics

extension Repository {
    /// The step count a day shows and where it came from. Gathers every source's count (the phone's, the
    /// source-tagged daily rows for the strap and the PaceForge Garmin mirror, the merged-cache count and
    /// the strap motion estimate) and lets `StepsSourceResolver` pick, so a tile never goes blank while any
    /// source has a value and always names the source it shows.
    func daySteps(day: String, apple: Int?, merged: Int?, estimate: Double?) -> ResolvedSteps? {
        Self.resolveDaySteps(rows: vitalMetricRows, day: day, apple: apple, merged: merged, estimate: estimate)
    }

    nonisolated static func resolveDaySteps(rows: [SourcedDailyMetric], day: String, apple: Int?,
                                            merged: Int?, estimate: Double?) -> ResolvedSteps? {
        var readings: [StepsReading] = []
        if let apple { readings.append(StepsReading(source: .appleHealth, value: Double(apple))) }
        for row in rows where row.metric.day == day {
            guard let steps = row.metric.steps else { continue }
            readings.append(StepsReading(source: fusionSource(of: row.source), value: Double(steps)))
        }
        if let estimate { readings.append(StepsReading(source: .noopComputed, value: estimate)) }
        if let merged { readings.append(StepsReading(source: .localCache, value: Double(merged))) }
        return StepsSourceResolver.resolve(readings)
    }

    nonisolated private static func fusionSource(of source: DailyMetricSource) -> FusionSource {
        switch source {
        case .whoopImport: return .whoopImport
        case .noopComputed: return .noopComputed
        case .paceForgeGarmin: return .paceforgeGarmin
        case .appleHealth: return .appleHealth
        case .localCache: return .localCache
        }
    }
}
