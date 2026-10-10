import Foundation
import GRDB

/// Source-specific counts for Apple Health data saved in NOOP.
/// Metric counts are days with a value for that metric, not raw HealthKit samples.
public struct AppleHealthDataInventory: Equatable, Sendable {
    public let dailyDays: Int
    public let earliestDay: String?
    public let latestDay: String?
    public let metricDays: [String: Int]
    public let workouts: Int
    public let sleepSessions: Int
    public let hourlyStepEntries: Int

    public init(dailyDays: Int, earliestDay: String?, latestDay: String?,
                metricDays: [String: Int], workouts: Int, sleepSessions: Int,
                hourlyStepEntries: Int) {
        self.dailyDays = dailyDays
        self.earliestDay = earliestDay
        self.latestDay = latestDay
        self.metricDays = metricDays
        self.workouts = workouts
        self.sleepSessions = sleepSessions
        self.hourlyStepEntries = hourlyStepEntries
    }
}

extension WhoopStore {
    /// Counts rows saved under one source ID. This is intentionally a read-only diagnostic so the
    /// Settings screen can distinguish "Apple Health has no imported data" from "the dashboard
    /// isn't displaying data that is already in the local database".
    public func appleHealthDataInventory(deviceId: String = "apple-health") async throws -> AppleHealthDataInventory {
        try syncRead { db in
            let daily = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM appleDaily WHERE deviceId = ?
                """, arguments: [deviceId]) ?? 0
            let span = try Row.fetchOne(db, sql: """
                SELECT MIN(day) AS firstDay, MAX(day) AS lastDay
                FROM appleDaily WHERE deviceId = ?
                """, arguments: [deviceId])
            let firstDay: String? = span?["firstDay"]
            let lastDay: String? = span?["lastDay"]
            let metricRows = try Row.fetchAll(db, sql: """
                SELECT key, COUNT(*) AS dayCount
                FROM metricSeries WHERE deviceId = ?
                GROUP BY key
                """, arguments: [deviceId])
            var metricDays: [String: Int] = [:]
            for row in metricRows {
                let key: String = row["key"]
                let count: Int = row["dayCount"]
                metricDays[key] = count
            }
            let workouts = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM workout WHERE deviceId = ?
                """, arguments: [deviceId]) ?? 0
            let sleeps = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sleepSession WHERE deviceId = ?
                """, arguments: [deviceId]) ?? 0
            let stepHours = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM appleStepHour WHERE deviceId = ?
                """, arguments: [deviceId]) ?? 0
            return AppleHealthDataInventory(dailyDays: daily, earliestDay: firstDay, latestDay: lastDay,
                                            metricDays: metricDays, workouts: workouts,
                                            sleepSessions: sleeps, hourlyStepEntries: stepHours)
        }
    }
}
