import Foundation
import CoreFoundation
import GRDB

public struct ReplicaChange: Sendable, Equatable {
    public let seq: Int64
    public let table: String
    public let keyJSON: String
    public let operation: String
    public let rowJSON: String?
    public init(seq: Int64, table: String, keyJSON: String, operation: String, rowJSON: String?) {
        self.seq = seq; self.table = table; self.keyJSON = keyJSON
        self.operation = operation; self.rowJSON = rowJSON
    }
}

public enum ReplicaSyncError: Error {
    case invalidChange
    case unsupportedTable
}

extension WhoopStore {
    /// Latest local change-journal sequence, including changes already sent to the peer.
    public func replicaChangeCursor() async throws -> Int64 {
        try syncRead { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(seq), 0) FROM __noop_sync_changes") ?? 0
        }
    }

    public func replicaChanges(after cursor: Int64, limit: Int = 200) async throws -> [ReplicaChange] {
        guard (1...1_000).contains(limit) else { throw ReplicaSyncError.invalidChange }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT seq, tableName, keyJSON, operation, rowJSON
                FROM __noop_sync_changes WHERE seq > ? ORDER BY seq ASC LIMIT ?
                """, arguments: [cursor, limit]).map {
                    ReplicaChange(seq: $0["seq"], table: $0["tableName"], keyJSON: $0["keyJSON"],
                                  operation: $0["operation"], rowJSON: $0["rowJSON"])
                }
        }
    }

    /// Apply peer-owned rows atomically while suppressing echo events from the local change triggers.
    public func applyReplicaChanges(_ changes: [ReplicaChange]) async throws {
        guard changes.count <= 1_000 else { throw ReplicaSyncError.invalidChange }
        try syncWrite { db in
            try db.execute(sql: "UPDATE __noop_sync_state SET applying = 1 WHERE id = 1")
            defer { try? db.execute(sql: "UPDATE __noop_sync_state SET applying = 0 WHERE id = 1") }
            for change in changes {
                guard let (columns, primaryKey) = try Self.replicaSchema(table: change.table, db: db),
                      let key = try JSONSerialization.jsonObject(with: Data(change.keyJSON.utf8)) as? [String: Any]
                else { throw ReplicaSyncError.unsupportedTable }
                let quotedTable = Self.quoteIdentifier(change.table)
                let whereClause = primaryKey.map { "\(Self.quoteIdentifier($0)) = ?" }.joined(separator: " AND ")
                guard primaryKey.allSatisfy({ key[$0] != nil }) else { throw ReplicaSyncError.invalidChange }
                let keyArgs = try primaryKey.map { try Self.sqliteValue(key[$0]!) }
                if change.operation == "delete" {
                    try db.execute(sql: "DELETE FROM \(quotedTable) WHERE \(whereClause)",
                                   arguments: StatementArguments(keyArgs))
                    continue
                }
                guard change.operation == "upsert", let rowJSON = change.rowJSON,
                      let object = try JSONSerialization.jsonObject(with: Data(rowJSON.utf8)) as? [String: Any],
                      Set(object.keys).isSubset(of: Set(columns)), !object.isEmpty else {
                    throw ReplicaSyncError.invalidChange
                }
                let insertColumns = columns.filter { object[$0] != nil }
                let sql = "INSERT OR REPLACE INTO \(quotedTable) (\(insertColumns.map(Self.quoteIdentifier).joined(separator: ","))) VALUES (\(Array(repeating: "?", count: insertColumns.count).joined(separator: ",")))"
                let values = try insertColumns.map { column -> DatabaseValueConvertible in
                    guard let raw = object[column] else { throw ReplicaSyncError.invalidChange }
                    return try Self.sqliteValue(raw)
                }
                try db.execute(sql: sql, arguments: StatementArguments(values))
            }
        }
    }

    private static func sqliteValue(_ value: Any) throws -> DatabaseValueConvertible {
        if value is NSNull { return DatabaseValue.null }
        if let wrapped = value as? [String: String], let hex = wrapped["__pf_blob_hex"] {
            guard hex.count % 2 == 0 else { throw ReplicaSyncError.invalidChange }
            var bytes = [UInt8]()
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                guard let byte = UInt8(hex[index..<next], radix: 16) else { throw ReplicaSyncError.invalidChange }
                bytes.append(byte); index = next
            }
            return Data(bytes)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? 1 : 0 }
            let type = String(cString: number.objCType)
            if ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(type) {
                return number.int64Value
            }
            return number.doubleValue
        }
        if let string = value as? String { return string }
        throw ReplicaSyncError.invalidChange
    }

    fileprivate static func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    fileprivate static func replicaSchema(table: String, db: Database) throws -> ([String], [String])? {
        guard table.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil else { return nil }
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(quoteIdentifier(table)))")
        let columns = rows.compactMap { $0["name"] as String? }
        let keys = rows.compactMap { row -> (Int, String)? in
            let order = row["pk"] as Int
            return order > 0 ? (order, row["name"] as String) : nil
        }.sorted { $0.0 < $1.0 }.map(\.1)
        return columns.isEmpty || keys.isEmpty ? nil : (columns, keys)
    }

    /// Install database-native change capture on every persistent table with a primary key.
    static func installReplicaTriggers(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS __noop_sync_state(id INTEGER PRIMARY KEY CHECK(id=1), applying INTEGER NOT NULL DEFAULT 0);
            INSERT OR IGNORE INTO __noop_sync_state(id, applying) VALUES(1, 0);
            CREATE TABLE IF NOT EXISTS __noop_sync_changes(
              seq INTEGER PRIMARY KEY AUTOINCREMENT, tableName TEXT NOT NULL, keyJSON TEXT NOT NULL,
              operation TEXT NOT NULL, rowJSON TEXT, createdAt INTEGER NOT NULL DEFAULT (strftime('%s','now')));
            CREATE INDEX IF NOT EXISTS idx_noop_sync_changes_table_key ON __noop_sync_changes(tableName,keyJSON,seq);
            CREATE TABLE IF NOT EXISTS __noop_sync_received(peerId TEXT NOT NULL, clientSeq INTEGER NOT NULL,
              status TEXT NOT NULL, PRIMARY KEY(peerId,clientSeq));
            CREATE TABLE IF NOT EXISTS __noop_sync_conflicts(id INTEGER PRIMARY KEY AUTOINCREMENT,
              peerId TEXT NOT NULL, clientSeq INTEGER NOT NULL, tableName TEXT NOT NULL, keyJSON TEXT NOT NULL,
              phoneJSON TEXT, serverJSON TEXT, createdAt INTEGER NOT NULL DEFAULT (strftime('%s','now')),
              UNIQUE(peerId,clientSeq));
            CREATE TABLE IF NOT EXISTS __noop_sync_peers(peerId TEXT PRIMARY KEY, clientCursor INTEGER NOT NULL DEFAULT 0);
            """)
        let tables = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'
              AND name NOT LIKE 'grdb_%' AND name NOT LIKE '__noop_sync_%'
            """)
        for table in tables {
            guard let (columns, keys) = try replicaSchema(table: table, db: db) else { continue }
            let qTable = quoteIdentifier(table)
            let token = table
            let keyExpr: (String) -> String = { prefix in
                "json_object(" + keys.map { "'\($0)', \(prefix).\(quoteIdentifier($0))" }.joined(separator: ",") + ")"
            }
            let rowExpr: (String) -> String = { prefix in
                "json_object(" + columns.map { column in
                    let quoted = "\(prefix).\(quoteIdentifier(column))"
                    return "'\(column)', CASE WHEN typeof(\(quoted))='blob' THEN json_object('__pf_blob_hex',hex(\(quoted))) ELSE \(quoted) END"
                }.joined(separator: ",") + ")"
            }
            let gate = "COALESCE((SELECT applying FROM __noop_sync_state WHERE id=1),0)=0"
            for operation in ["insert", "update", "delete"] {
                try db.execute(sql: "DROP TRIGGER IF EXISTS \(quoteIdentifier("__noop_sync_\(token)_\(operation)"))")
            }
            let changedKey = keys.map { "OLD.\(quoteIdentifier($0)) IS NOT NEW.\(quoteIdentifier($0))" }
                .joined(separator: " OR ")
            try db.execute(sql: """
                CREATE TRIGGER \(quoteIdentifier("__noop_sync_\(token)_insert")) AFTER INSERT ON \(qTable)
                WHEN \(gate) BEGIN
                  INSERT INTO __noop_sync_changes(tableName,keyJSON,operation,rowJSON)
                  VALUES('\(token)',\(keyExpr("NEW")),'upsert',\(rowExpr("NEW")));
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER \(quoteIdentifier("__noop_sync_\(token)_update")) AFTER UPDATE ON \(qTable)
                WHEN \(gate) BEGIN
                  INSERT INTO __noop_sync_changes(tableName,keyJSON,operation,rowJSON)
                  SELECT '\(token)',\(keyExpr("OLD")),'delete',NULL WHERE \(changedKey);
                  INSERT INTO __noop_sync_changes(tableName,keyJSON,operation,rowJSON)
                  VALUES('\(token)',\(keyExpr("NEW")),'upsert',\(rowExpr("NEW")));
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER \(quoteIdentifier("__noop_sync_\(token)_delete")) AFTER DELETE ON \(qTable)
                WHEN \(gate) BEGIN
                  INSERT INTO __noop_sync_changes(tableName,keyJSON,operation,rowJSON)
                  VALUES('\(token)',\(keyExpr("OLD")),'delete',NULL);
                END
                """)
        }
    }
}
