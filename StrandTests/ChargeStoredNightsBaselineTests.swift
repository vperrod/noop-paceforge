import XCTest
import WhoopProtocol
import WhoopStore
import StrandAnalytics
@testable import Strand

/// A night is scored against the nights before it, including the stored ones older than the scoring window, and
/// scoring leaves those stored nights as they were.
@MainActor
final class ChargeStoredNightsBaselineTests: XCTestCase {
    private let source = "my-whoop"
    private var computed: String { source + "-noop" }

    private func withPreferences<T>(_ body: () async throws -> T) async throws -> T {
        let defaults = UserDefaults.standard
        let keys = [
            "profile.dateOfBirth", "profile.age", "profile.sex", "profile.weightKg",
            "profile.heightCm", "profile.waistCm", "profile.hrMaxOverride", "profile.stepTicksPerStep",
            "profile.stepsCalibrationCoefficient", "profile.stepsCalibrationSampleDays",
            "profile.stepsCalibrationConfidence", "profile.stepsCalibrationManual",
            "profile.stepsManualCoefficient", "profile.stepsHasBankedMotion",
            "noop.analyzeWatermark", "analyzeRecent.stepsMotionCache.v1",
            "noop.hrvBaselineEpoch", "noop.recoveryBaselineEpoch", UnitPrefs.hrvWindowKey,
            RescoreBackgroundScheduler.owedKey, RescoreBackgroundScheduler.owedTokenKey,
            RescoreBackgroundScheduler.lastPassSecondsKey, DayCycleMode.storageKey,
            PuffinExperiment.experimentalSleepV2Key, PuffinExperiment.motionAwareWakeKey,
        ]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.set(DayCycleMode.midnight.rawValue, forKey: DayCycleMode.storageKey)
        defaults.set(true, forKey: PuffinExperiment.experimentalSleepV2Key)
        defaults.set(false, forKey: PuffinExperiment.motionAwareWakeKey)
        return try await body()
    }

    private func midnight(daysAgo: Int) -> Int {
        let offset = TimeZone.current.secondsFromGMT()
        return IntelligenceEngine.midnightLocal(Int(Date().timeIntervalSince1970), offsetSec: offset) - daysAgo * 86_400
    }

    private func key(daysAgo: Int) -> String {
        AnalyticsEngine.dayString(midnight(daysAgo: daysAgo) + 43_200, offsetSec: TimeZone.current.secondsFromGMT())
    }

    private func stored(_ day: String, hrv: Double) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 450, efficiency: 0.9, deepMin: 90, remMin: 100, lightMin: 260,
                    disturbances: 1, restingHr: 50, avgHrv: hrv, recovery: 61, strain: 10, exerciseCount: 0)
    }

    /// Yesterday as raw strap data (two still hours at 50 bpm with beats 1200 / 1240 ms), and `storedDays` as
    /// already-scored nights with no raw data left. Scores a three-day window, then returns the store.
    private func scoreYesterday(storedDaysAgo: [Int], storedHrv: Double) async throws -> WhoopStore {
        try await withPreferences {
            let store = try await WhoopStore.inMemory()
            try DeviceRegistryStore(dbQueue: store.registryWriter).add(PairedDevice(
                id: source, brand: "WHOOP", model: "4.0", sourceKind: .liveBLE, capabilities: [.hr, .hrv],
                status: .active, addedAt: 1, lastSeenAt: 1))
            let start = midnight(daysAgo: 1) + 2 * 3_600, end = start + 2 * 3_600
            let hr = stride(from: start - 900, through: end, by: 5).map { HRSample(ts: $0, bpm: 50) }
            let gravity = stride(from: start, through: end, by: 5).map { GravitySample(ts: $0, x: 0, y: 0, z: 1, unit: "g") }
            var beats: [RRInterval] = []
            var elapsedMs = 0
            while elapsedMs < (end - start) * 1_000 {
                let interval = beats.count.isMultiple(of: 2) ? 1_200 : 1_240
                beats.append(RRInterval(ts: start + elapsedMs / 1_000, rrMs: interval, srcChannel: .whoop4Historical))
                elapsedMs += interval
            }
            _ = try await store.insert(Streams(hr: hr, rr: beats, gravity: gravity), deviceId: source)
            if !storedDaysAgo.isEmpty {
                _ = try await store.upsertDailyMetrics(storedDaysAgo.map { stored(key(daysAgo: $0), hrv: storedHrv) },
                                                       deviceId: computed)
            }
            let repo = Repository(deviceId: source)
            repo.setStoreForTesting(store)
            await IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: source).analyzeRecent(maxDays: 3)
            return store
        }
    }

    private func night(_ store: WhoopStore, daysAgo: Int) async throws -> DailyMetric? {
        try await store.dailyMetrics(deviceId: computed, from: key(daysAgo: daysAgo), to: key(daysAgo: daysAgo)).first
    }

    func testStoredNightsOlderThanTheWindowGiveTheNightItsCharge() async throws {
        let store = try await scoreYesterday(storedDaysAgo: Array(3...22), storedHrv: 40)
        let yesterday = try await night(store, daysAgo: 1)
        XCTAssertNotNil(yesterday?.avgHrv, "Precondition: the raw night has an HRV.")
        XCTAssertNotNil(yesterday?.recovery)
    }

    func testWithoutEarlierNightsTheNightHasNoCharge() async throws {
        let store = try await scoreYesterday(storedDaysAgo: [], storedHrv: 40)
        let yesterday = try await night(store, daysAgo: 1)
        XCTAssertNotNil(yesterday?.avgHrv, "Precondition: the raw night has an HRV.")
        XCTAssertNil(yesterday?.recovery)
    }

    func testTheStoredNightsValuesAreTheBaseline() async throws {
        let usual = try await scoreYesterday(storedDaysAgo: Array(3...22), storedHrv: 40)
        let high = try await scoreYesterday(storedDaysAgo: Array(3...22), storedHrv: 90)
        let againstUsual = try await night(usual, daysAgo: 1)?.recovery
        let againstHigh = try await night(high, daysAgo: 1)?.recovery
        XCTAssertLessThan(try XCTUnwrap(againstHigh), try XCTUnwrap(againstUsual))
    }

    func testScoringKeepsTheOlderStoredNightsAsTheyWere() async throws {
        let store = try await scoreYesterday(storedDaysAgo: Array(3...22), storedHrv: 40)
        let older = try await night(store, daysAgo: 10)
        XCTAssertEqual(older, stored(key(daysAgo: 10), hrv: 40))
    }

    func testAPastNightsExplanationReadsOnlyTheDaysBeforeIt() async throws {
        let store = try await WhoopStore.inMemory()
        _ = try await store.upsertDailyMetrics((1...40).map { stored(key(daysAgo: $0), hrv: 40) }, deviceId: computed)
        let repo = Repository(deviceId: source)
        repo.setStoreForTesting(store)
        await repo.refresh()

        let history = repo.chargeBaselines(scoring: key(daysAgo: 10))?.hrvHistory

        XCTAssertEqual(history?.dayKeys, (11...31).reversed().map { key(daysAgo: $0) })
    }

    func testTheScreensBaselineLeavesOutAWearableImportScoredDay() async throws {
        let store = try await WhoopStore.inMemory()
        let imported = key(daysAgo: 5)
        _ = try await store.upsertDailyMetrics([stored(imported, hrv: 120)], deviceId: "oura-import")
        try await store.persistComputedScores(
            dailyMetrics: (2...8).map { stored(key(daysAgo: $0), hrv: 40) }, metricPoints: [],
            provenance: [ScoreInputProvenanceRow(day: imported, key: "recovery", sourceId: "oura-import")],
            deviceId: computed, from: key(daysAgo: 8), to: key(daysAgo: 2))
        let repo = Repository(deviceId: source)
        repo.setStoreForTesting(store)
        await repo.refresh()

        let history = repo.chargeBaselines(scoring: key(daysAgo: 1))?.hrvHistory

        XCTAssertEqual(history?.dayKeys, [8, 7, 6, 4, 3, 2].map { key(daysAgo: $0) })
    }
}
