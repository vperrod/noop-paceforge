import XCTest
import StrandDesign
import WhoopStore
@testable import Strand

/// WHOOP and Garmin figures are shown apart: never joined into one series and never averaged together.
@MainActor
final class SourceSplitTests: XCTestCase {

    private func row(_ day: String, hrv: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: nil, avgHrv: hrv, recovery: nil, strain: nil, exerciseCount: nil)
    }

    private func point(_ day: Int, _ value: Double) -> TrendPoint {
        TrendPoint(date: Date(timeIntervalSince1970: Double(day) * 86_400), value: value)
    }

    func testADayWithBothDevicesGivesTwoReadingsWhoopFirst() {
        let readings = SourceSplit.readings(day: "2026-10-01", whoop: [row("2026-10-01", hrv: 48)],
                                            garmin: [row("2026-10-01", hrv: 33)]) { $0.avgHrv }
        XCTAssertEqual(readings, [SourceReading(source: "WHOOP", value: 48), SourceReading(source: "Garmin", value: 33)])
    }

    func testAMissingWhoopDayIsNotFilledFromGarmin() {
        let readings = SourceSplit.readings(day: "2026-10-01", whoop: [row("2026-10-01", hrv: nil)],
                                            garmin: [row("2026-10-01", hrv: 33)]) { $0.avgHrv }
        XCTAssertEqual(readings, [SourceReading(source: "Garmin", value: 33)])
    }

    func testAveragesAreEachDevicesOwn() {
        XCTAssertEqual(SourceSplit.averages(whoop: [point(1, 40), point(2, 60)], garmin: [point(1, 30)]) { "\(Int($0))" },
                       "WHOOP 50 \u{00B7} Garmin 30")
    }

    func testAMissingDayBreaksTheLine() {
        XCTAssertEqual(SourceSplit.gapped([point(1, 1), point(2, 2), point(4, 3)]).map(\.segment), ["0", "0", "1"])
    }

    func testOnlyOneDayStretchesAreLonePoints() {
        let lone = TrendChart.loneSegmentPoints(SourceSplit.gapped([point(1, 1), point(2, 2), point(4, 3), point(6, 4)]))
        XCTAssertEqual(lone.map(\.value), [3, 4])
    }

    func testAWhoopRequestDropsTheDaysFilledFromGarminAndAppleHealth() {
        let points = [("2026-10-01", "my-whoop-noop"), ("2026-10-02", "paceforge-garmin"), ("2026-10-03", "apple-health")]
            .map { ResolvedMetricPoint(day: $0.0, value: 1, source: $0.1, sourceKey: "steps") }
        let resolution = MetricSeriesResolution(requestedSource: "my-whoop", candidates: [], points: points)
        XCTAssertEqual(resolution.whoopOnly.points.map(\.day), ["2026-10-01"])
    }

    func testAGarminRequestIsLeftAsItIs() {
        let points = [ResolvedMetricPoint(day: "2026-10-02", value: 1, source: "paceforge-garmin", sourceKey: "steps")]
        let resolution = MetricSeriesResolution(requestedSource: "paceforge-garmin", candidates: [], points: points)
        XCTAssertEqual(resolution.whoopOnly.points.map(\.day), ["2026-10-02"])
    }

    func testTheStreakAndStrapDaysHoldNoGarminOnlyDay() async throws {
        let store = try await WhoopStore.inMemory()
        let today = Repository.localDayKey(Date())
        _ = try await store.upsertDailyMetrics([row(today, hrv: 33)], deviceId: "paceforge-garmin")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)

        await repo.refresh()

        XCTAssertEqual(repo.garminDays.map(\.day), [today])
        XCTAssertTrue(repo.strapDays.isEmpty)
    }
}
