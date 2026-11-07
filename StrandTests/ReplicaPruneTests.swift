import XCTest
@testable import WhoopStore

final class ReplicaPruneTests: XCTestCase {
    func testPruneCutsEachLaneByItsOwnCursor() async throws {
        let store = try await WhoopStore.inMemory()
        // `device` rides the bulk lane, `metricSeries` the summary lane.
        try await store.upsertDevice(id: "my-whoop", mac: nil, name: "WHOOP")
        let rows = (1...5).map { MetricPoint(day: "2026-06-2\($0)", key: "weight", value: 74.0 + Double($0)) }
        _ = try await store.upsertMetricSeries(rows, deviceId: "apple")
        let summaryBefore = try await store.replicaChanges(after: 0, limit: 1_000, lane: .summary).count
        let bulkBefore = try await store.replicaChanges(after: 0, limit: 1_000, lane: .bulk).count
        let top = try await store.replicaChangeCursor()

        // summary lane fully sent, bulk lane sent nothing, no margin kept
        let pruned = try await store.pruneSentReplicaChanges(summaryCursor: top, bulkCursor: 0, keep: 0)

        let summaryAfter = try await store.replicaChanges(after: 0, limit: 1_000, lane: .summary).count
        let bulkAfter = try await store.replicaChanges(after: 0, limit: 1_000, lane: .bulk).count
        XCTAssertGreaterThan(summaryBefore, 0)
        XCTAssertGreaterThan(bulkBefore, 0)
        XCTAssertEqual(pruned, summaryBefore)
        XCTAssertEqual(summaryAfter, 0)
        XCTAssertEqual(bulkAfter, bulkBefore)
    }
}
