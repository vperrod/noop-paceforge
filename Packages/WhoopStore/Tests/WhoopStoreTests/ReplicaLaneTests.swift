import XCTest
import GRDB
@testable import WhoopStore

final class ReplicaLaneTests: XCTestCase {
    private func storeWithJournal() async throws -> WhoopStore {
        let store = try await WhoopStore.inMemory()
        try await store.syncWrite { db in
            try db.execute(sql: "DELETE FROM __noop_sync_changes")
            for (table, key) in [("hrSample", "1"), ("dailyMetric", "2"), ("rrInterval", "3"), ("sleepSession", "4")] {
                try db.execute(sql: "INSERT INTO __noop_sync_changes(tableName,keyJSON,operation,rowJSON) VALUES(?,?,'upsert','{}')",
                               arguments: [table, key])
            }
        }
        return store
    }

    func testTheSummaryLaneCarriesOnlyTheDaysResults() async throws {
        let store = try await storeWithJournal()
        let tables = try await store.replicaChanges(after: 0, limit: 10, lane: .summary).map(\.table)
        XCTAssertEqual(tables, ["dailyMetric", "sleepSession"])
    }

    func testTheBulkLaneCarriesTheSamples() async throws {
        let store = try await storeWithJournal()
        let tables = try await store.replicaChanges(after: 0, limit: 10, lane: .bulk).map(\.table)
        XCTAssertEqual(tables, ["hrSample", "rrInterval"])
    }

    func testNoLaneCarriesTheWholeJournal() async throws {
        let store = try await storeWithJournal()
        let count = try await store.replicaChanges(after: 0, limit: 10).count
        XCTAssertEqual(count, 4)
    }

    func testPruneCutsEachLaneByItsOwnCursor() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.syncWrite { db in
            try db.execute(sql: "DELETE FROM __noop_sync_changes")
            for seq in 1...10 {
                try db.execute(sql: "INSERT INTO __noop_sync_changes(seq,tableName,keyJSON,operation,rowJSON) VALUES(?,?,?,'upsert','{}')",
                               arguments: [seq, seq % 2 == 0 ? "dailyMetric" : "hrSample", String(seq)])
            }
        }
        // summary lane sent up to seq 4, bulk lane up to seq 9, nothing kept as margin
        let pruned = try await store.pruneSentReplicaChanges(summaryCursor: 4, bulkCursor: 9, keep: 0)
        let left = try await store.syncRead { db in try Int.fetchAll(db, sql: "SELECT seq FROM __noop_sync_changes ORDER BY seq") }
        XCTAssertEqual(pruned, 7)
        XCTAssertEqual(left, [6, 8, 10])
    }
}
