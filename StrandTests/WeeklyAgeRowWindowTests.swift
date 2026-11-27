import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

/// A weekly Fitness Age row is built from the week ending its Saturday and takes no later day.
@MainActor
final class WeeklyAgeRowWindowTests: XCTestCase {
    private let source = "my-whoop"

    private func row(_ day: String, restingHr: Int) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 450, efficiency: 0.9, deepMin: 90, remMin: 100, lightMin: 260,
                    disturbances: 1, restingHr: restingHr, avgHrv: 50, recovery: 60, strain: 40, exerciseCount: 0)
    }

    private func day(_ key: String, plus days: Int) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: Calendar.current.date(byAdding: .day, value: days, to: format.date(from: key)!)!)
    }

    private func savedFitnessAge(_ rows: [DailyMetric]) async throws -> Double? {
        let defaults = UserDefaults.standard
        let keys = ["profile.dateOfBirth", "profile.age", "profile.sex", "profile.weightKg",
                    "profile.heightCm", "profile.waistCm"]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let store = try await WhoopStore.inMemory()
        _ = try await store.upsertDailyMetrics(rows, deviceId: source + "-noop")
        let repo = Repository(deviceId: source)
        repo.setStoreForTesting(store)
        let profile = ProfileStore()
        _ = await IntelligenceEngine(repo: repo, profile: profile, deviceId: source).recomputeFitnessAgeOnly()
        return try await store.metricSeries(deviceId: source + "-noop", key: "fitness_age",
                                            from: "0000-01-01", to: "9999-12-31").last?.value
    }

    private var saturday: String { IntelligenceEngine.saturdayKey(onOrBefore: Repository.localDayKey(Date())) }

    func testDaysAfterTheSaturdayDoNotChangeThatWeeksRow() async throws {
        let week = (-6...0).map { row(day(saturday, plus: $0), restingHr: 50) }
        let later = (1...6).map { row(day(saturday, plus: $0), restingHr: 90) }
        let alone = try await savedFitnessAge(week)
        let withLaterDays = try await savedFitnessAge(week + later)
        XCTAssertNotNil(alone)
        XCTAssertEqual(withLaterDays, alone)
    }

    func testAWeekWithNoSavedDaysWritesNoRow() async throws {
        let before = (-13...(-7)).map { row(day(saturday, plus: $0), restingHr: 50) }
        let value = try await savedFitnessAge(before)
        XCTAssertNil(value)
    }
}
