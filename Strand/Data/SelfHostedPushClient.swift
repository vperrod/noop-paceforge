import CryptoKit
import Foundation
import Security
import WhoopStore
import WhoopProtocol

/// iOS client for the self-hosted NOOP ↔ PaceForge sync.
enum SelfHostedPushClient {
    struct GarminMetricsImportSummary {
        let days: Int
        let stepDays: Int
        let spo2Days: Int
    }
    struct HumeMetricsImportSummary { let measurements: Int }

    static let enabledKey = "noop.selfHostedPush.enabled"
    static let endpointKey = "noop.selfHostedPush.endpoint"
    private static let sourceIdKey = "noop.selfHostedPush.sourceId"
    private static let receiverIdKey = "noop.selfHostedPush.receiverStateId"
    static let lastSuccessKey = "noop.selfHostedPush.lastSuccess"
    static let lastActivityFetchKey = "noop.selfHostedPush.lastActivityFetch"
    static let lastGarminMetricsFetchKey = "noop.selfHostedPush.lastGarminMetricsFetch"
    static let lastHumeMetricsFetchKey = "noop.selfHostedPush.lastHumeMetricsFetch"
    static let replicaConflictCountKey = "noop.selfHostedPush.replicaConflictCount"
    @MainActor private static var replicationTask: Task<Int, Error>?
    private static let service = "com.noop.self-hosted-push"
    private static let account = "bearer-token"
    private static let version = "1.0"
    private static let maxBytes = 4 * 1024 * 1024

    enum Failure: Error, LocalizedError {
        case configuration(String)
        case receiver(String)
        case oversizedSnapshot(String)
        var errorDescription: String? {
            switch self {
            case .configuration(let message), .receiver(let message), .oversizedSnapshot(let message): message
            }
        }
    }

    static var tokenIsSet: Bool { loadToken() != nil }

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty else { clearToken(); return true }
        SecItemDelete(keychainQuery as CFDictionary)
        var query = keychainQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func clearToken() { SecItemDelete(keychainQuery as CFDictionary) }

    @MainActor
    static func testConnection() async throws -> [String] {
        let (endpoint, token) = try configuration()
        let (data, response) = try await getData(databaseEndpoint(from: endpoint, suffix: "status"), token: token)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let status = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.receiver("PaceForge did not return a valid NOOP replica status.")
        }
        return status["ready"] as? Bool == true
            ? ["phone-seeded SQLite replica", "two-way change journal"]
            : ["Mini PC receiver reachable", "database seed required"]
    }

    @MainActor
    static func pushIfEnabled(repo: Repository) async {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        do { _ = try await push(repo: repo) }
        catch { NSLog("NOOP self-hosted sync deferred: %@", error.localizedDescription) }
    }

    @MainActor
    @discardableResult
    static func push(repo: Repository) async throws -> Int {
        if let replicationTask { return try await replicationTask.value }
        let task = Task { try await performPush(repo: repo) }
        replicationTask = task
        defer { replicationTask = nil }
        return try await task.value
    }

    @MainActor
    private static func performPush(repo: Repository) async throws -> Int {
        let (endpoint, token) = try configuration()
        guard let store = await repo.storeHandle() else { throw Failure.configuration("NOOP's local database is unavailable.") }
        try await seedReplicaIfNeeded(endpoint: endpoint, token: token, store: store)
        let accepted = try await replicateChanges(endpoint: endpoint, token: token,
                                                   peerId: stableSourceId(), store: store)
        if accepted > 0 {
            await repo.refresh()
            repo.appleHealthCache = nil
            repo.appleHealthLoadedSeq = -1
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSuccessKey)
        return accepted
    }

    /// Fetch PaceForge's recent Garmin activities into NOOP's separate `paceforge` source.
    /// Upserts use the workout's start time and sport, so repeating a foreground sync is safe.
    @MainActor
    @discardableResult
    static func pullActivities(repo: Repository) async throws -> Int {
        let (endpoint, token) = try configuration()
        let response = try await fetchPaceForgeActivities(
            endpoint: activitiesEndpoint(from: endpoint), token: token)
        guard let store = await repo.storeHandle() else {
            throw Failure.configuration("NOOP's local database is unavailable.")
        }
        let rows = try response.map { item -> WorkoutRow in
            guard let start = item["startTs"] as? Int,
                  let end = item["endTs"] as? Int,
                  end >= start,
                  let sport = item["sport"] as? String, !sport.isEmpty,
                  let identifier = item["id"] as? String else {
                throw Failure.receiver("PaceForge returned an invalid activity record.")
            }
            let duration = item["durationS"] as? Double ?? Double(end - start)
            let distance = item["distanceM"] as? Double
            let energy = item["energyKcal"] as? Double
            let avgHr = item["avgHr"] as? Int
            let maxHr = item["maxHr"] as? Int
            let name = item["name"] as? String ?? sport
            let power = item["avgPower"] as? Double
            let aerobicEffect = item["aerobicEffect"] as? Double
            let powerNote = power.map { " · \(Int($0.rounded())) W avg" } ?? ""
            let effectNote = aerobicEffect.map { " · Garmin aerobic effect \(String(format: "%.1f", $0))" } ?? ""
            let notes = "PaceForge #\(identifier): \(name)" + powerNote + effectNote
            return WorkoutRow(startTs: start, endTs: end, sport: sport, source: "paceforge",
                              durationS: duration, energyKcal: energy, avgHr: avgHr, maxHr: maxHr,
                              strain: nil, distanceM: distance, zonesJSON: nil, notes: notes, steps: nil)
        }
        _ = try await store.upsertWorkouts(rows, deviceId: "paceforge")
        // Import Garmin's actual timestamped workout HR under its own source. Never borrow nearby
        // WHOOP readings to fill these workouts; both apps calculate effort independently.
        let hr = response.flatMap { item -> [HRSample] in
            guard let start = item["startTs"] as? Int,
                  let samples = item["hrSamples"] as? [[String: Any]] else { return [] }
            return samples.compactMap { sample in
                guard let elapsed = (sample["t"] as? NSNumber)?.intValue,
                      let bpm = (sample["bpm"] as? NSNumber)?.intValue,
                      elapsed >= 0, (25...240).contains(bpm) else { return nil }
                return HRSample(ts: start + elapsed, bpm: bpm)
            }
        }
        if !hr.isEmpty { _ = try await store.insert(Streams(hr: hr), deviceId: "paceforge-garmin") }
        if !rows.isEmpty { await repo.refresh() }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastActivityFetchKey)
        return rows.count
    }

    /// Fetch Garmin's own daily steps and SpO₂ from PaceForge into a separate source, preserving NOOP values.
    @MainActor
    @discardableResult
    static func pullGarminMetrics(repo: Repository) async throws -> GarminMetricsImportSummary {
        let (endpoint, token) = try configuration()
        let response = try await fetchPaceForgeGarminMetrics(
            endpoint: garminMetricsEndpoint(from: endpoint), token: token)
        guard let store = await repo.storeHandle() else {
            throw Failure.configuration("NOOP's local database is unavailable.")
        }
        let rows = try response.map { item -> DailyMetric in
            guard let day = item["date"] as? String, day.count == 10 else {
                throw Failure.receiver("PaceForge returned an invalid Garmin metric date.")
            }
            let steps = (item["steps"] as? NSNumber)?.intValue
            let spo2 = (item["spo2Pct"] as? NSNumber)?.doubleValue
            let restingHr = (item["restingHr"] as? NSNumber)?.intValue
            let avgHrv = (item["avgHrv"] as? NSNumber)?.doubleValue
            let sleepSeconds = (item["sleepSeconds"] as? NSNumber)?.doubleValue
            let deepSeconds = (item["deepSeconds"] as? NSNumber)?.doubleValue
            let remSeconds = (item["remSeconds"] as? NSNumber)?.doubleValue
            let lightSeconds = (item["lightSeconds"] as? NSNumber)?.doubleValue
            if let steps, steps < 0 { throw Failure.receiver("PaceForge returned negative Garmin steps.") }
            if let spo2, !(50...100).contains(spo2) {
                throw Failure.receiver("PaceForge returned an invalid Garmin SpO₂ value.")
            }
            guard steps != nil || spo2 != nil || restingHr != nil || avgHrv != nil || sleepSeconds != nil else {
                throw Failure.receiver("PaceForge returned an empty Garmin metric record.")
            }
            return DailyMetric(day: day, totalSleepMin: sleepSeconds.map { Int(($0 / 60).rounded()) },
                               efficiency: nil,
                               deepMin: deepSeconds.map { Int(($0 / 60).rounded()) },
                               remMin: remSeconds.map { Int(($0 / 60).rounded()) },
                               lightMin: lightSeconds.map { Int(($0 / 60).rounded()) },
                               disturbances: nil, restingHr: restingHr,
                               avgHrv: avgHrv.map { Int($0.rounded()) }, recovery: nil, strain: nil, exerciseCount: nil,
                               spo2Pct: spo2, steps: steps)
        }
        _ = try await store.upsertDailyMetrics(rows, deviceId: "paceforge-garmin")
        let pointKeys: [String: String] = [
            "vo2max": "vo2max", "sleepScore": "sleep_score", "stressAvg": "stress",
            "respRate": "resp_rate", "spo2Lowest": "spo2_lowest",
            "trainingReadiness": "training_readiness", "trainingLoad7d": "training_load_7day",
            "bodyBattery": "body_battery", "weightKg": "weight", "bodyFatPct": "body_fat",
            "leanMassKg": "lean_mass", "bmi": "bmi",
        ]
        let points = response.flatMap { item -> [MetricPoint] in
            guard let day = item["date"] as? String else { return [] }
            return pointKeys.compactMap { field, key in
                guard let value = (item[field] as? NSNumber)?.doubleValue, value.isFinite, value > 0 else { return nil }
                return MetricPoint(day: day, key: key, value: value)
            }
        }
        if !points.isEmpty { _ = try await store.upsertMetricSeries(points, deviceId: "paceforge-garmin") }
        if !rows.isEmpty { await repo.refresh() }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastGarminMetricsFetchKey)
        return GarminMetricsImportSummary(days: rows.count,
                                          stepDays: rows.filter { $0.steps != nil }.count,
                                          spo2Days: rows.filter { $0.spo2Pct != nil }.count)
    }

    @MainActor
    @discardableResult
    static func pullHumeMetrics(repo: Repository) async throws -> HumeMetricsImportSummary {
        let (endpoint, token) = try configuration()
        let response = try await fetchPaceForgeHumeMetrics(endpoint: humeMetricsEndpoint(from: endpoint), token: token)
        guard let store = await repo.storeHandle() else {
            throw Failure.configuration("NOOP's local database is unavailable.")
        }
        let keyMap = ["weight": "weight", "body_fat": "body_fat", "lean_mass": "lean_mass",
                      "bmi": "bmi", "fat_mass": "fat_mass", "skeletal_muscle": "skeletal_muscle",
                      "total_body_water": "total_body_water", "visceral_fat": "visceral_fat", "bmr": "bmr"]
        var points: [MetricPoint] = []
        for item in response {
            guard let day = item["date"] as? String, day.count == 10 else {
                throw Failure.receiver("PaceForge returned an invalid Hume measurement date.")
            }
            for (field, key) in keyMap {
                if let value = (item[field] as? NSNumber)?.doubleValue, value.isFinite, value > 0 {
                    points.append(MetricPoint(day: day, key: key, value: value))
                }
            }
        }
        if !points.isEmpty {
            _ = try await store.upsertMetricSeries(points, deviceId: "paceforge-hume")
            await repo.refresh()
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastHumeMetricsFetchKey)
        return HumeMetricsImportSummary(measurements: Set(points.map(\.day)).count)
    }

    private static func fetchPaceForgeActivities(endpoint: URL, token: String) async throws -> [[String: Any]] {
        let session = noRedirectSession()
        defer { session.finishTasksAndInvalidate() }
        var result: [[String: Any]] = []
        var offset = 0
        var expectedTotal: Int?
        repeat {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            components?.queryItems = (components?.queryItems ?? []) + [
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: "20"),
            ]
            guard let url = components?.url else { throw Failure.configuration("Invalid PaceForge activities URL.") }
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 2 * 1024 * 1024,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "paceforge_activities",
                  json["version"] as? String == "1",
                  (json["offset"] as? Int) == offset,
                  let total = json["total"] as? Int, total >= 0,
                  let page = json["activities"] as? [[String: Any]], page.count <= 20,
                  !page.isEmpty || offset >= total else {
                throw Failure.receiver("PaceForge returned an invalid Garmin activity page at offset \(offset).")
            }
            if let expectedTotal, expectedTotal != total {
                throw Failure.receiver("PaceForge's Garmin activity count changed during sync; retry to avoid a partial import.")
            }
            expectedTotal = total
            result.append(contentsOf: page)
            offset += page.count
        } while offset < (expectedTotal ?? 0)
        return result
    }

    /// First sync seeds the Mini PC with a consistent SQLite backup of the phone's existing database.
    /// Subsequent incremental bidirectional changes are handled by the replication journal protocol.
    private static func seedReplicaIfNeeded(endpoint: URL, token: String, store: WhoopStore) async throws {
        let statusURL = databaseEndpoint(from: endpoint, suffix: "status")
        let (data, response) = try await getData(statusURL, token: token)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.receiver("Could not check the Mini PC NOOP database status.")
        }
        if json["ready"] as? Bool == true {
            let peerId = stableSourceId()
            if let seedPeerId = json["seedPeerId"] as? String, seedPeerId != peerId {
                throw Failure.receiver("The Mini PC database was seeded from a different NOOP iPhone. Sync stopped to protect both databases.")
            }
            let uploadKey = replicaCursorKey(endpoint, peerId, "upload")
            let downloadKey = replicaCursorKey(endpoint, peerId, "download")
            if let cursor = json["baseCursor"] as? Int {
                if UserDefaults.standard.object(forKey: uploadKey) == nil {
                    UserDefaults.standard.set(cursor, forKey: uploadKey)
                }
                if UserDefaults.standard.object(forKey: downloadKey) == nil {
                    UserDefaults.standard.set(cursor, forKey: downloadKey)
                }
            }
            return
        }

        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        let directory = appSupport.appendingPathComponent("NOOPReplicaSeed", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateKey = "noop.selfHostedPush.replicaSeedState"
        let seedPeerId = stableSourceId()
        let saved = UserDefaults.standard.dictionary(forKey: stateKey)
        let savedPath = saved?["path"] as? String
        let snapshot = savedPath.map { URL(fileURLWithPath: $0) }
            ?? directory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let canResumeSnapshot = savedPath != nil && fm.fileExists(atPath: snapshot.path)
        if !canResumeSnapshot {
            try await store.backupDatabase(to: snapshot.path)
        }
        let attributes = try fm.attributesOfItem(atPath: snapshot.path)
        guard let totalBytes = attributes[.size] as? Int, totalBytes > 0 else {
            throw Failure.receiver("The NOOP database backup is empty.")
        }
        let chunkBytes = 512 * 1024
        let chunkCount = (totalBytes + chunkBytes - 1) / chunkBytes
        let uploadId = canResumeSnapshot
            ? (saved?["uploadId"] as? String ?? UUID().uuidString.lowercased())
            : UUID().uuidString.lowercased()
        let file = try FileHandle(forReadingFrom: snapshot)
        defer { try? file.close() }
        var hasher = SHA256()
        while let chunk = try file.read(upToCount: chunkBytes), !chunk.isEmpty { hasher.update(data: chunk) }
        let wholeHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(["uploadId": uploadId, "path": snapshot.path, "bytes": totalBytes,
                                   "chunkBytes": chunkBytes, "chunks": chunkCount,
                                   "sha256": wholeHash, "nextChunk": saved?["nextChunk"] as? Int ?? 0],
                                  forKey: stateKey)
        let beginResult = try await postJSON(databaseEndpoint(from: endpoint, suffix: "bootstrap"), token: token,
            payload: ["action": "begin", "uploadId": uploadId, "bytes": totalBytes,
                      "chunkBytes": chunkBytes, "chunks": chunkCount, "sha256": wholeHash,
                      "seedPeerId": seedPeerId])
        let acceptedChunks = Set(beginResult["receivedChunks"] as? [Int] ?? [])
        try file.seek(toOffset: 0)
        for index in 0..<chunkCount {
            guard let chunk = try file.read(upToCount: chunkBytes), !chunk.isEmpty else {
                throw Failure.receiver("The database backup changed during transfer; retry the seed.")
            }
            if acceptedChunks.contains(index) { continue }
            let digest = SHA256.hash(data: chunk).map { String(format: "%02x", $0) }.joined()
            _ = try await postJSON(databaseEndpoint(from: endpoint, suffix: "bootstrap"), token: token,
                payload: ["action": "chunk", "uploadId": uploadId, "index": index,
                          "sha256": digest, "data": chunk.base64EncodedString()])
            UserDefaults.standard.set(["uploadId": uploadId, "path": snapshot.path, "bytes": totalBytes,
                                       "chunkBytes": chunkBytes, "chunks": chunkCount,
                                       "sha256": wholeHash, "nextChunk": index + 1], forKey: stateKey)
        }
        let result = try await postJSON(databaseEndpoint(from: endpoint, suffix: "bootstrap"), token: token,
                                         payload: ["action": "commit", "uploadId": uploadId])
        guard result["activated"] as? Bool == true, result["seedPeerId"] as? String == seedPeerId else {
            throw Failure.receiver("The Mini PC did not activate the validated NOOP database backup.")
        }
        UserDefaults.standard.removeObject(forKey: stateKey)
        if let cursor = result["changeCursor"] as? Int {
            let peerId = stableSourceId()
            UserDefaults.standard.set(cursor, forKey: replicaCursorKey(endpoint, peerId, "upload"))
            UserDefaults.standard.set(cursor, forKey: replicaCursorKey(endpoint, peerId, "download"))
        }
        try? fm.removeItem(at: snapshot)
    }

    private static func getData(_ url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = noRedirectSession()
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    private static func postJSON(_ url: URL, token: String, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let session = noRedirectSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw Failure.receiver(message ?? "Mini PC replica transfer failed.")
        }
        return json
    }

    /// Exchange all committed, journaled NOOP rows in bounded, retry-safe batches.
    @MainActor
    private static func replicateChanges(endpoint: URL, token: String, peerId: String,
                                         store: WhoopStore) async throws -> Int {
        var exchanged = 0
        let uploadKey = replicaCursorKey(endpoint, peerId, "upload")
        let downloadKey = replicaCursorKey(endpoint, peerId, "download")
        var uploadCursor = Int64(UserDefaults.standard.integer(forKey: uploadKey))
        let baseServerCursor = Int64(UserDefaults.standard.integer(forKey: downloadKey))
        for _ in 0..<1_000 {
            let page = try await store.replicaChanges(after: uploadCursor, limit: 500)
            guard !page.isEmpty else { break }
        let changes: [[String: Any]] = page.map { change in
            ["seq": change.seq, "table": change.table, "key": change.keyJSON,
             "operation": change.operation, "row": change.rowJSON.map { $0 as Any } ?? NSNull()]
            }
            let response = try await postJSON(databaseEndpoint(from: endpoint, suffix: "changes"), token: token,
                payload: ["peerId": peerId, "baseServerCursor": baseServerCursor, "changes": changes])
            guard let ack = response["ackCursor"] as? Int64 ?? (response["ackCursor"] as? Int).map(Int64.init),
                  ack >= uploadCursor else {
                throw Failure.receiver("The Mini PC did not acknowledge the NOOP change batch.")
            }
            uploadCursor = ack
            UserDefaults.standard.set(uploadCursor, forKey: uploadKey)
            exchanged += page.count
            let conflicts = (response["conflicts"] as? [Int])?.count ?? 0
            if conflicts > 0 {
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: replicaConflictCountKey) + conflicts,
                                          forKey: replicaConflictCountKey)
            }
        }

        var downloadCursor = Int64(UserDefaults.standard.integer(forKey: downloadKey))
        for _ in 0..<1_000 {
            var components = URLComponents(url: databaseEndpoint(from: endpoint, suffix: "changes"),
                                           resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "after", value: String(downloadCursor)),
                                      URLQueryItem(name: "limit", value: "500")]
            guard let url = components?.url else { throw Failure.configuration("Invalid replica changes URL.") }
            let (data, response) = try await getData(url, token: token)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawChanges = json["changes"] as? [[String: Any]],
                  let next = json["nextCursor"] as? Int64 ?? (json["nextCursor"] as? Int).map(Int64.init),
                  next >= downloadCursor else {
                throw Failure.receiver("The Mini PC returned an invalid change batch.")
            }
            guard !rawChanges.isEmpty else { break }
            let changes = try rawChanges.map { row -> ReplicaChange in
                guard let seq = row["seq"] as? Int64 ?? (row["seq"] as? Int).map(Int64.init),
                      let table = row["table"] as? String, let key = row["key"] as? String,
                      let operation = row["operation"] as? String else { throw Failure.receiver("Invalid replica record.") }
                return ReplicaChange(seq: seq, table: table, keyJSON: key, operation: operation,
                                     rowJSON: row["row"] as? String)
            }
            try await store.applyReplicaChanges(changes)
            downloadCursor = next
            UserDefaults.standard.set(downloadCursor, forKey: downloadKey)
            exchanged += changes.count
        }
        if let (data, response) = try? await getData(databaseEndpoint(from: endpoint, suffix: "status"), token: token),
           let http = response as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let conflicts = json["conflicts"] as? Int {
            UserDefaults.standard.set(conflicts, forKey: replicaConflictCountKey)
        }
        return exchanged
    }

    private static func databaseEndpoint(from endpoint: URL, suffix: String) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return endpoint }
        if components.path.hasSuffix("/push") {
            components.path = String(components.path.dropLast("push".count)) + "db/" + suffix
        }
        return components.url ?? endpoint
    }

    private static func fetchPaceForgeGarminMetrics(endpoint: URL, token: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = noRedirectSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 20 * 1024 * 1024,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "paceforge_garmin_metrics",
              json["version"] as? String == "1",
              let metrics = json["metrics"] as? [[String: Any]], metrics.count <= 25_000 else {
            throw Failure.receiver("PaceForge did not return a valid Garmin metrics list.")
        }
        return metrics
    }

    private static func fetchPaceForgeHumeMetrics(endpoint: URL, token: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = noRedirectSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 5 * 1024 * 1024,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "paceforge_hume_metrics",
              json["version"] as? String == "1",
              let metrics = json["metrics"] as? [[String: Any]], metrics.count <= 10_000 else {
            throw Failure.receiver("PaceForge did not return a valid Hume metrics list.")
        }
        return metrics
    }

    private static func activitiesEndpoint(from endpoint: URL) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint
        }
        if components.path.hasSuffix("/push") {
            components.path = String(components.path.dropLast("push".count)) + "activities"
        }
        return components.url ?? endpoint
    }

    private static func garminMetricsEndpoint(from endpoint: URL) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint
        }
        if components.path.hasSuffix("/push") {
            components.path = String(components.path.dropLast("push".count)) + "garmin-metrics"
        }
        return components.url ?? endpoint
    }

    private static func humeMetricsEndpoint(from endpoint: URL) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return endpoint }
        if components.path.hasSuffix("/push") {
            components.path = String(components.path.dropLast("push".count)) + "hume-metrics"
        }
        return components.url ?? endpoint
    }

    private static func pushAppend(stream: String, endpoint: URL, token: String, sourceId: String,
                                   deviceId: String, store: WhoopStore, defaults: UserDefaults) async throws -> Int {
        let key = cursorKey(endpoint, sourceId, stream)
        var cursor = defaults.dictionary(forKey: key) as? [String: Any]
        var after = (cursor?["rowId"] as? Int64) ?? (cursor?["rowId"] as? Int).map(Int64.init) ?? 0
        if after > 0 {
            let check = try await store.selfHostedPushAppendRows(stream: stream, deviceId: deviceId,
                                                                 afterRowId: after - 1, limit: 1)
            if check.first?.rowId != after || check.first?.keyFingerprint != cursor?["keySha256"] as? String {
                after = 0; cursor = nil; defaults.removeObject(forKey: key)
            }
        }
        var total = 0
        while true {
            let rows = try await store.selfHostedPushAppendRows(stream: stream, deviceId: deviceId,
                                                                afterRowId: after, limit: 5_001)
            guard !rows.isEmpty else { return total }
            var page = Array(rows.prefix(5_000))
            var final = page[page.count - 1]
            guard let finalRowId = final.rowId else { throw Failure.receiver("NOOP could not read the stream cursor.") }
            let startCursor = cursor
            var endCursor: [String: Any] = ["rowId": finalRowId, "keySha256": final.keyFingerprint]
            var identity: [String: Any] = [:]
            var batchId = ""
            var body = Data()
            while !page.isEmpty {
                final = page[page.count - 1]
                guard let selectedEndRowId = final.rowId else { throw Failure.receiver("NOOP could not read the stream cursor.") }
                endCursor = ["rowId": selectedEndRowId, "keySha256": final.keyFingerprint]
                identity = ["type": "batch", "protocolVersion": version,
                    "sourceId": sourceId, "deviceId": deviceId, "stream": stream,
                    "delivery": "append", "recordCount": page.count,
                    "startCursor": (startCursor as Any?) ?? NSNull(), "endCursor": endCursor]
                batchId = stableUUID(identity: identity, lines: page.map(\.recordLine))
                body = try makeBody(header: identity, batchId: batchId, lines: page.map(\.recordLine))
                if body.count <= maxBytes { break }
                page.removeLast()
            }
            guard !page.isEmpty else { throw Failure.oversizedSnapshot("A single \(stream) record exceeds 4 MiB.") }
            let ack = try await post(body, endpoint: endpoint, token: token)
            try validateAck(ack, stream: stream, deviceId: deviceId, batchId: batchId,
                            rows: page.count, endCursor: endCursor)
            cursor = endCursor
            defaults.set(endCursor, forKey: key)
            after = (endCursor["rowId"] as? Int64) ?? (endCursor["rowId"] as? Int).map(Int64.init) ?? finalRowId
            total += page.count
            if rows.count <= 5_000 { return total }
        }
    }

    private static func pushMutable(stream: String, endpoint: URL, token: String, sourceId: String,
                                    deviceId: String, store: WhoopStore) async throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -89, to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return 0 }
        let startDay = SelfHostedPushRegistry.day(from)
        let endDay = SelfHostedPushRegistry.day(tomorrow)
        let fromTs = Int(from.timeIntervalSince1970), toTs = Int(tomorrow.timeIntervalSince1970)
        let rows = try await store.selfHostedPushMutableRows(stream: stream, deviceId: deviceId,
                                                              start: startDay, end: endDay,
                                                              startTimestamp: fromTs, endTimestamp: toTs)
        guard rows.count <= 1_000 else {
            throw Failure.oversizedSnapshot("The recent \(stream) snapshot exceeds NOOP's 1,000-record safety limit.")
        }
        let lines = rows.map(\.recordLine)
        guard lines.reduce(0, { $0 + $1.count }) <= 2 * 1024 * 1024 else {
            throw Failure.oversizedSnapshot("The recent \(stream) snapshot exceeds NOOP's 2 MiB safety limit.")
        }
        let snapshotHash = hashSnapshot(stream: stream, lines: lines)
        let progressKey = snapshotKey(endpoint, sourceId, stream)
        if UserDefaults.standard.string(forKey: progressKey) == snapshotHash { return 0 }
        let selector = SelfHostedPushRegistry.usesDay(stream) ? "day" : "startTs"
        let startBound: Any
        let endBound: Any
        if SelfHostedPushRegistry.usesDay(stream) {
            startBound = startDay; endBound = endDay
        } else {
            startBound = fromTs; endBound = toTs
        }
        let bounds: [String: Any] = ["selector": selector, "startInclusive": startBound,
                                     "endExclusive": endBound]
        let replacementId = stableUUID(identity: ["deviceId": deviceId, "delivery": "replace_window",
            "protocolVersion": version, "sourceId": sourceId, "stream": stream, "window": bounds], lines: lines)
        let window: [String: Any] = ["replacementId": replacementId, "selector": selector,
            "startInclusive": startBound, "endExclusive": endBound,
            "part": 1, "parts": 1]
        let identity: [String: Any] = ["type": "batch", "protocolVersion": version,
            "sourceId": sourceId, "deviceId": deviceId, "stream": stream,
            "delivery": "replace_window", "recordCount": rows.count,
            "startCursor": NSNull(), "endCursor": NSNull(), "window": window]
        let batchId = stableUUID(identity: identity, lines: lines)
        let body = try makeBody(header: identity, batchId: batchId, lines: lines)
        guard body.count <= maxBytes else { throw Failure.oversizedSnapshot("The \(stream) snapshot exceeds 4 MiB.") }
        let ack = try await post(body, endpoint: endpoint, token: token)
        try validateAck(ack, stream: stream, deviceId: deviceId, batchId: batchId,
                        rows: rows.count, endCursor: NSNull())
        UserDefaults.standard.set(snapshotHash, forKey: progressKey)
        return rows.count
    }

    private struct Capabilities { let receiverStateId: String; let streams: [String] }

    private static func discover(endpoint: URL, token: String) async throws -> Capabilities {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(version, forHTTPHeaderField: "NOOP-Push-Accept-Version")
        let session = noRedirectSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 16 * 1024,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "capabilities",
              json["protocolVersion"] as? String == version,
              let receiver = json["receiverStateId"] as? String,
              UUID(uuidString: receiver)?.uuidString.lowercased() == receiver,
              let streams = json["streams"] as? [String],
              Set(streams).count == streams.count,
              streams.allSatisfy(SelfHostedPushRegistry.allNames.contains) else {
            throw Failure.receiver("PaceForge did not return valid NOOP push capabilities.")
        }
        return Capabilities(receiverStateId: receiver, streams: streams)
    }

    private static func post(_ body: Data, endpoint: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-ndjson; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = noRedirectSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 16 * 1024,
              let ack = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.receiver("PaceForge upload was not accepted; NOOP will retry after its next sync.")
        }
        return ack
    }

    private static func validateAck(_ ack: [String: Any], stream: String, deviceId: String,
                                    batchId: String, rows: Int, endCursor: Any) throws {
        guard ack["protocolVersion"] as? String == version,
              ack["batchId"] as? String == batchId, ack["stream"] as? String == stream,
              ack["deviceId"] as? String == deviceId,
              (ack["acceptedRows"] as? Int) == rows, ack["status"] as? String == "accepted",
              SelfHostedPushClient.canonical(ack["endCursor"] ?? NSNull()) == canonical(endCursor) else {
            throw Failure.receiver("PaceForge's acknowledgement did not match the NOOP batch.")
        }
    }

    private static func makeBody(header: [String: Any], batchId: String, lines: [Data]) throws -> Data {
        var header = header
        header["batchId"] = batchId
        var body = try canonical(header)
        body.append(0x0a)
        for line in lines { body.append(line) }
        return body
    }

    private static func stableUUID(identity: [String: Any], lines: [Data]) -> String {
        var digestInput = (try? canonical(identity)) ?? Data()
        digestInput.append(0x0a)
        lines.forEach { digestInput.append($0) }
        var bytes = SHA256.hash(data: digestInput).prefix(16).map { $0 }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.suffix(12))"
    }

    private static func canonical(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
    }

    private static func noRedirectSession() -> URLSession {
        URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    private static func configuration() throws -> (URL, String) {
        guard let raw = UserDefaults.standard.string(forKey: endpointKey),
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil,
              let token = loadToken(), !token.isEmpty else {
            throw Failure.configuration("Enter a PaceForge HTTPS endpoint and bearer token in PaceForge sync settings.")
        }
        return (url, token)
    }

    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func loadToken() -> String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func stableSourceId() -> String {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: sourceIdKey), UUID(uuidString: value) != nil { return value }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: sourceIdKey)
        return value
    }

    private static func cursorKey(_ endpoint: URL, _ sourceId: String, _ stream: String) -> String {
        namespaceKey(endpoint, sourceId, stream, prefix: "cursor")
    }

    private static func snapshotKey(_ endpoint: URL, _ sourceId: String, _ stream: String) -> String {
        namespaceKey(endpoint, sourceId, stream, prefix: "snapshot")
    }

    private static func namespaceKey(_ endpoint: URL, _ sourceId: String, _ stream: String,
                                     prefix: String) -> String {
        let namespace = SHA256.hash(data: Data("\(endpoint.absoluteString)\n\(sourceId)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "noop.selfHostedPush.\(prefix).\(namespace).\(stream)"
    }

    private static func replicaCursorKey(_ endpoint: URL, _ peerId: String, _ direction: String) -> String {
        namespaceKey(endpoint, peerId, direction, prefix: "replica")
    }

    private static func hashSnapshot(stream: String, lines: [Data]) -> String {
        var data = Data("noop-push-day-hash\n\(version)\n\(stream)\n".utf8)
        lines.forEach { data.append($0) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum SelfHostedPushRegistry {
    static let allNames = SelfHostedPushExport.appendStreams + SelfHostedPushExport.mutableStreams
    static func usesDay(_ stream: String) -> Bool { ["dailyMetric", "journal", "appleDaily"].contains(stream) }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
