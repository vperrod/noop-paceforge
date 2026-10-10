import Foundation
import WhoopStore
import StrandImport

private enum AppleHealthImportFailure: LocalizedError {
    case noSupportedRecords

    var errorDescription: String? {
        switch self {
        case .noSupportedRecords:
            return "This file contained no Apple Health records NOOP can import. Choose export.zip from Health → your profile → Export All Health Data."
        }
    }
}

/// Maps a parsed + aggregated Apple Health export into the on-device store under its own
/// source id ("apple-health"), so it sits BESIDE Whoop for the per-source pages and cross-source
/// consensus. Populates appleDaily, dailyMetric, the generic metricSeries, and workouts.
enum AppleHealthImport {

    /// Apple's per-day aggregates arrive as `Double`, and a step total genuinely can be fractional: the
    /// aggregator accumulates per source (`stepsBySource[…] += v`) before taking the winning source's
    /// figure, and nothing constrains a source to whole counts.
    ///
    /// ROUNDS, for two reasons. It matches every other count/rate converted on the same rows — `avgHr`,
    /// `maxHr`, `walkingHr`, `restingHr` all use `Int($0.rounded())` — and it matches the Kotlin twin's
    /// `Math.round(it).toInt()`. Truncating made the same Apple export store a step total one LOWER on
    /// Apple than on Android for any fractional day, which is stored-data divergence on an imported
    /// column. (#1535 follow-up)
    ///
    /// The two rules agree here because step counts are non-negative: Swift's `.rounded()` is
    /// half-away-from-zero and Kotlin's `Math.round` is half-up, which differ only for negatives.
    static func stepsInt(_ v: Double) -> Int { Int(v.rounded()) }


    /// The Apple Health mapping revision, stamped into the Import test-mode parser line. Bump when this
    /// importer's aggregate->store mapping changes.
    static let importerVersion = 1

    @discardableResult
    static func importExport(url: URL, into store: WhoopStore, deviceId: String,
                             trace: (@Sendable ([String]) -> Void)? = nil,
                             progress: (@Sendable (Int) -> Void)? = nil,
                             phase: (@Sendable (String) -> Void)? = nil) async throws -> ImportSummary {
        // Parsing and aggregation are CPU-heavy, especially for multi-year exports. This method is
        // called from the UI model; doing either step inline inherits its actor and freezes the UI
        // until the full XML file has been parsed. Keep the bounded-memory streaming parser, but run
        // the complete parse + fold on a utility executor so the import status remains responsive.
        let (result, daily) = try await Task.detached(priority: .utility) {
            let result = try ImportCoordinator().importAppleHealth(from: url, retainRawSamples: false,
                                                                    progress: progress, phase: phase)
            phase?("Organizing Apple Health readings…")
            let daily = AppleHealthAggregator.aggregate(result)
            guard !daily.isEmpty || !result.workouts.isEmpty else {
                throw AppleHealthImportFailure.noSupportedRecords
            }
            return (result, daily)
        }.value

        // Commit in bounded day batches. An interrupted import may leave completed batches in the
        // source-scoped tables; rerunning is safe because every write is an upsert on the natural key.
        let batchSize = 90
        var appleWritten = 0
        var dmWritten = 0
        var pointsMapped = 0
        var pointsWritten = 0
        for lower in stride(from: 0, to: daily.count, by: batchSize) {
            let upper = min(lower + batchSize, daily.count)
            let batch = Array(daily[lower..<upper])
            phase?("Saving Apple Health daily totals… (\(upper) of \(daily.count) days)")
            let appleRows = batch.map { d in
                AppleDaily(day: d.day,
                           steps: d.steps.map(stepsInt),
                           activeKcal: d.activeKcal, basalKcal: d.basalKcal, vo2max: d.vo2max,
                           avgHr: d.avgHr.map { Int($0.rounded()) },
                           maxHr: d.maxHr.map { Int($0.rounded()) },
                           walkingHr: d.walkingHr.map { Int($0.rounded()) },
                           weightKg: d.weightKg)
            }
            appleWritten += try await store.upsertAppleDaily(appleRows, deviceId: deviceId)

            // Recovery-relevant subset into dailyMetric (recovery/strain are nil — Apple doesn't compute them).
            phase?("Saving Apple Health metrics… (\(upper) of \(daily.count) days)")
            let dm = batch.map { d in
                DailyMetric(day: d.day,
                            totalSleepMin: d.asleepMin, efficiency: nil,
                            deepMin: d.deepMin, remMin: d.remMin, lightMin: d.coreMin,
                            disturbances: nil,
                            restingHr: d.restingHr.map { Int($0.rounded()) },
                            avgHrv: d.hrvSDNN, recovery: nil, strain: nil, exerciseCount: nil,
                            spo2Pct: d.spo2Pct, skinTempDevC: nil, respRateBpm: d.respRate,
                            steps: d.steps.map(stepsInt), avgSdnn: d.hrvSDNN)
            }
            dmWritten += try await store.upsertDailyMetrics(dm, deviceId: deviceId)

            // Metric explorer/correlation rows are generated and committed per day batch too.
            let points = AppleHealthAggregator.metricPoints(batch)
                .map { MetricPoint(day: $0.day, key: $0.key, value: $0.value) }
            pointsMapped += points.count
            pointsWritten += try await store.upsertMetricSeries(points, deviceId: deviceId)
        }

        phase?("Saving Apple Health workouts…")
        var workoutsWritten = 0
        for lower in stride(from: 0, to: result.workouts.count, by: batchSize) {
            let upper = min(lower + batchSize, result.workouts.count)
            let workouts = result.workouts[lower..<upper].map { w in
                WorkoutRow(startTs: Int(w.start.timeIntervalSince1970),
                           endTs: Int(w.end.timeIntervalSince1970),
                           sport: w.activityType, source: WorkoutSource.appleHealthSource,
                           durationS: w.durationS, energyKcal: w.energyKcal,
                           avgHr: w.avgHr.map { Int($0.rounded()) },
                           maxHr: w.maxHr.map { Int($0.rounded()) }, strain: nil,
                           distanceM: w.distanceM, zonesJSON: nil, notes: nil, steps: nil)
            }
            workoutsWritten += try await store.upsertWorkouts(workouts, deviceId: deviceId)
        }

        // Import & Data Ingest test mode: emit the per-stage / reject / day-delta trace iff the mode is on
        // (the caller passes a non-nil `trace` only when TestCentre.active(.dataImport)). The numbers are
        // exactly the import's own parsed + persisted counts, so emission changes nothing about what saved.
        if let trace {
            let daysMapped = Set(daily.map { $0.day }).count
            let lines: [String] = [
                ImportTrace.parserVersionLine(sourceKind: .appleHealth, importerVersion: importerVersion),
                ImportTrace.stageLine(category: "appleDaily", rowsIn: daily.count, rowsOut: appleWritten),
                ImportTrace.stageLine(category: "dailyMetric", rowsIn: daily.count, rowsOut: dmWritten),
                ImportTrace.stageLine(category: "metricSeries", rowsIn: pointsMapped, rowsOut: pointsWritten),
                ImportTrace.stageLine(category: "workouts", rowsIn: result.workouts.count, rowsOut: workoutsWritten),
                // Apple Health is tolerant: skippedSpans counts XML spans the sanitizer scrubbed / a partial
                // parse. The aggregator drops nothing further, so droppedRows is 0 here.
                ImportTrace.rejectLine(droppedRows: 0, skippedSpans: result.summary.skippedSpans),
                ImportTrace.dayDeltaLine(category: "appleDaily", daysMapped: daysMapped, daysPersisted: appleWritten),
            ]
            trace(lines)
        }

        var summary = result.summary
        summary.countsByCategory["workouts"] = result.workouts.count
        summary.countsByCategory["dailyAggregates"] = daily.count
        return summary
    }
}
