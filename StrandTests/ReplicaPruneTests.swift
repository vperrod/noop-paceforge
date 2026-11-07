import XCTest
@testable import WhoopStore

final class ReplicaPruneTests: XCTestCase {
    func testPruneCutsEachLaneByItsOwnCursor() async throws {
        let store = try await WhoopStore.inMemory()
        try store.registryWriter.write { db in
            try db.execute(sql: "DELETE FROM __noop_sync_changes")
            for seq in 1...10 {
                try db.execute(sql: "INSERT INTO __noop_sync_changes(seq,tableName,keyJSON,operation,rowJSON) VALUES(?,?,?,'upsert','{}')",
                               arguments: [seq, seq % 2 == 0 ? "dailyMetric" : "hrSample", String(seq)])
            }
        }
        // summary lane sent up to seq 4, bulk lane up to seq 9, no margin kept
        let pruned = try await store.pruneSentReplicaChanges(summaryCursor: 4, bulkCursor: 9, keep: 0)
        let left = try store.registryWriter.read { db in try Int.fetchAll(db, sql: "SELECT seq FROM __noop_sync_changes ORDER BY seq") }
        XCTAssertEqual(pruned, 7)
        XCTAssertEqual(left, [6, 8, 10])
    }
}
