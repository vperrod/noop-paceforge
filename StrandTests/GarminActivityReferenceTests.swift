import XCTest
import WhoopStore
@testable import Strand

/// The coach gets Garmin's steps and active energy as labelled reference lines of their own.
@MainActor
final class GarminActivityReferenceTests: XCTestCase {

    private func row(_ day: String, steps: Int?, kcal: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: 50, avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil,
                    spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil, steps: steps, activeKcalEst: kcal)
    }

    func testEachFigureIsItsOwnLabelledLine() {
        XCTAssertEqual(
            GarminActivityReference.lines([row("2026-10-01", steps: 8000, kcal: 500)], from: "2026-10-01", to: "2026-10-01"),
            ["Garmin (reference only): steps 8000", "Garmin (reference only): active energy 500 kcal"])
    }

    func testAnAbsentFigureHasNoLine() {
        XCTAssertEqual(
            GarminActivityReference.lines([row("2026-10-01", steps: 8000, kcal: nil)], from: "2026-10-01", to: "2026-10-01"),
            ["Garmin (reference only): steps 8000"])
    }

    func testCoachContextKeepsGarminStepsOutOfTheStrapAverage() async throws {
        let store = try await WhoopStore.inMemory()
        let today = Repository.localDayKey(Date())
        _ = try await store.upsertDailyMetrics([row(today, steps: 3000, kcal: nil)], deviceId: "my-whoop-noop")
        _ = try await store.upsertDailyMetrics([row(today, steps: 9000, kcal: nil)], deviceId: "paceforge-garmin")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        await repo.refresh()

        let context = AICoachEngine(repo: repo).buildContext()

        XCTAssertTrue(context.contains("steps: 3000/day"), context)
        XCTAssertTrue(context.contains("\n  Garmin (reference only): steps 9000/day"), context)
    }
}
