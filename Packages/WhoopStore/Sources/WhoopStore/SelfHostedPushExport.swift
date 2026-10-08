import Foundation
import CryptoKit
import GRDB

/// One bounded, explicitly projected v1 record from the local store.
public struct SelfHostedPushRow: Sendable {
    public let rowId: Int64?
    public let keyJSON: Data
    public let dataJSON: Data
    public let keyFingerprint: String
    public let recordLine: Data

    public init(rowId: Int64?, keyJSON: Data, dataJSON: Data, keyFingerprint: String, recordLine: Data) {
        self.rowId = rowId
        self.keyJSON = keyJSON
        self.dataJSON = dataJSON
        self.keyFingerprint = keyFingerprint
        self.recordLine = recordLine
    }
}

/// Read-only v1 projections. The closed registry below intentionally excludes newer/raw tables.
extension WhoopStore {
    public func selfHostedPushAppendRows(stream: String, deviceId: String,
                                         afterRowId: Int64, limit: Int = 5_001) async throws -> [SelfHostedPushRow] {
        guard let spec = SelfHostedPushRegistry.append[stream], (1...5_001).contains(limit) else {
            throw SelfHostedPushExportError.unsupportedStream
        }
        return try syncRead { db in
            let projection = (spec.keys + spec.fields).joined(separator: ",")
            let estimate = try preflight(db, table: stream, columns: spec.keys + spec.fields,
                predicate: "deviceId = ? AND rowid > ?", selection: [deviceId, afterRowId],
                order: "rowid ASC", limit: limit)
            guard estimate <= SelfHostedPushRegistry.maxMaterializedBytes else {
                throw SelfHostedPushExportError.snapshotTooLarge
            }
            let sql = "SELECT rowid AS _pushRowId, \(projection) " +
                "FROM \(stream) WHERE deviceId = ? AND rowid > ? ORDER BY rowid ASC LIMIT ?"
            let rows = try Row.fetchAll(db, sql: sql, arguments: [deviceId, afterRowId, limit])
            return try rows.map { try SelfHostedPushRegistry.makeRow($0, spec: spec, deviceId: deviceId,
                                                                       stream: stream, append: true) }
        }
    }

    public func selfHostedPushMutableRows(stream: String, deviceId: String, start: String,
                                          end: String, startTimestamp: Int, endTimestamp: Int,
                                          limit: Int = 1_001) async throws -> [SelfHostedPushRow] {
        guard let spec = SelfHostedPushRegistry.mutable[stream], (1...1_001).contains(limit) else {
            throw SelfHostedPushExportError.unsupportedStream
        }
        return try syncRead { db in
            let rows: [Row]
            let selector = spec.selector ?? ""
            let predicate: String
            let args: [DatabaseValueConvertible]
            let order = spec.keys.joined(separator: ",") + " ASC"
            if selector == "day" {
                predicate = "deviceId = ? AND day >= ? AND day < ?"
                args = [deviceId, start, end]
            } else {
                predicate = "deviceId = ? AND startTs >= ? AND startTs < ?"
                args = [deviceId, startTimestamp, endTimestamp]
            }
            let estimate = try preflight(db, table: stream, columns: spec.keys + spec.fields,
                predicate: predicate, selection: args, order: order, limit: limit)
            guard estimate <= SelfHostedPushRegistry.maxMaterializedBytes else {
                throw SelfHostedPushExportError.snapshotTooLarge
            }
            if spec.selector == "day" {
                rows = try Row.fetchAll(db,
                    sql: "SELECT \((spec.keys + spec.fields).joined(separator: ",")) FROM \(stream) " +
                        "WHERE deviceId = ? AND day >= ? AND day < ? " +
                        "ORDER BY \(spec.keys.joined(separator: ",")) ASC LIMIT ?",
                    arguments: [deviceId, start, end, limit])
            } else {
                rows = try Row.fetchAll(db,
                    sql: "SELECT \((spec.keys + spec.fields).joined(separator: ",")) FROM \(stream) " +
                        "WHERE deviceId = ? AND startTs >= ? AND startTs < ? " +
                        "ORDER BY \(spec.keys.joined(separator: ",")) ASC LIMIT ?",
                    arguments: [deviceId, startTimestamp, endTimestamp, limit])
            }
            return try rows.map { try SelfHostedPushRegistry.makeRow($0, spec: spec, deviceId: deviceId,
                                                                       stream: stream, append: false) }
        }
    }

    private func preflight(_ db: Database, table: String, columns: [String], predicate: String,
                           selection: [DatabaseValueConvertible], order: String, limit: Int) throws -> Int64 {
        let size = columns.map { column in
            "(CASE WHEN \(column) IS NULL THEN 4 WHEN typeof(\(column)) = 'text' " +
                "THEN length(CAST(\(column) AS BLOB)) * 6 + 2 WHEN typeof(\(column)) = 'blob' " +
                "THEN 50331649 ELSE 32 END)"
        }.joined(separator: " + ")
        let sql = "SELECT COALESCE(SUM(4096 + \(size)),0) FROM (SELECT \(columns.joined(separator: ",")) " +
            "FROM \(table) WHERE \(predicate) ORDER BY \(order) LIMIT ?)"
        var arguments = selection
        arguments.append(limit)
        return try Int64.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) ?? 0
    }
}

public enum SelfHostedPushExportError: Error {
    case unsupportedStream
    case snapshotTooLarge
}

public enum SelfHostedPushExport {
    public static let appendStreams = ["hrSample", "rrInterval", "event", "battery", "spo2Sample", "skinTempSample", "respSample", "gravitySample"]
    public static let mutableStreams = ["dailyMetric", "sleepSession", "workout", "journal"]
}

private enum SelfHostedPushRegistry {
    static let maxMaterializedBytes: Int64 = 48 * 1024 * 1024
    struct Spec {
        let keys: [String]
        let fields: [String]
        let selector: String?
        let booleans: Set<String>
    }

    static let append: [String: Spec] = [
        "hrSample": Spec(keys: ["ts"], fields: ["bpm"], selector: nil, booleans: []),
        "rrInterval": Spec(keys: ["ts", "rrMs", "seq"], fields: ["ord", "srcChannel", "tsSuspect"], selector: nil, booleans: []),
        "event": Spec(keys: ["ts", "kind"], fields: ["payloadJSON"], selector: nil, booleans: []),
        "battery": Spec(keys: ["ts"], fields: ["soc", "mv", "charging"], selector: nil, booleans: ["charging"]),
        "spo2Sample": Spec(keys: ["ts"], fields: ["red", "ir"], selector: nil, booleans: []),
        "skinTempSample": Spec(keys: ["ts"], fields: ["raw", "aux1Raw", "aux2Raw"], selector: nil, booleans: []),
        "respSample": Spec(keys: ["ts"], fields: ["raw"], selector: nil, booleans: []),
        "gravitySample": Spec(keys: ["ts"], fields: ["x", "y", "z", "dynAccel"], selector: nil, booleans: []),
    ]
    static let mutable: [String: Spec] = [
        "dailyMetric": Spec(keys: ["day"], fields: ["totalSleepMin", "efficiency", "deepMin", "remMin", "lightMin", "disturbances", "restingHr", "avgHrv", "recovery", "strain", "exerciseCount", "spo2Pct", "skinTempDevC", "respRateBpm", "steps", "activeKcalEst", "spo2Red", "spo2Ir"], selector: "day", booleans: []),
        "sleepSession": Spec(keys: ["startTs"], fields: ["endTs", "efficiency", "restingHr", "avgHrv", "stagesJSON", "userEdited", "startTsAdjusted", "motionJSON", "sleepStateJSON", "stagingSparse"], selector: "startTs", booleans: ["userEdited", "stagingSparse"]),
        "workout": Spec(keys: ["startTs", "sport"], fields: ["endTs", "source", "durationS", "energyKcal", "avgHr", "maxHr", "strain", "distanceM", "zonesJSON", "notes", "routePolyline", "steps"], selector: "startTs", booleans: []),
        "journal": Spec(keys: ["day", "question"], fields: ["answeredYes", "notes", "numericValue"], selector: "day", booleans: ["answeredYes"]),
    ]

    static func makeRow(_ row: Row, spec: Spec, deviceId: String, stream: String,
                        append: Bool) throws -> SelfHostedPushRow {
        let key = try object(row, columns: spec.keys, booleans: spec.booleans)
        let data = try object(row, columns: spec.fields, booleans: spec.booleans)
        let keyJSON = try canonical(key)
        let dataJSON = try canonical(data)
        let orderedKey = try orderedObject(key, columns: spec.keys)
        let fingerprint = sha256(Data("\(stream)\n\(deviceId)\n\(orderedKey)".utf8))
        let record = "{\"data\":\(String(decoding: dataJSON, as: UTF8.self)),\"key\":\(String(decoding: keyJSON, as: UTF8.self)),\"type\":\"record\"}\n"
        let rowId: Int64? = append ? row["_pushRowId"] : nil
        return SelfHostedPushRow(rowId: rowId,
                                 keyJSON: keyJSON, dataJSON: dataJSON,
                                 keyFingerprint: fingerprint, recordLine: Data(record.utf8))
    }

    private static func object(_ row: Row, columns: [String], booleans: Set<String>) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for column in columns {
            // Decode through GRDB's public Row subscript. databaseValue(at:) is
            // intentionally internal, so this API keeps the projection typed
            // while preserving SQLite nulls as DatabaseValue.null.
            let value: DatabaseValue = row[column]
            switch value.storage {
            case .null: result[column] = NSNull()
            case .int64(let integer): result[column] = booleans.contains(column) ? (integer != 0) as Any : integer as Any
            case .double(let number): result[column] = number
            case .string(let string): result[column] = string
            case .blob(_): throw SelfHostedPushExportError.unsupportedStream
            }
        }
        return result
    }

    private static func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    private static func orderedObject(_ object: [String: Any], columns: [String]) throws -> String {
        let members = try columns.map { key -> String in
            let encodedKey = try canonicalString(key)
            let encodedValue = try JSONSerialization.data(withJSONObject: object[key] ?? NSNull(),
                                                          options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return "\(encodedKey):\(String(decoding: encodedValue, as: UTF8.self))"
        }
        return "{\(members.joined(separator: ","))}"
    }

    private static func canonicalString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
