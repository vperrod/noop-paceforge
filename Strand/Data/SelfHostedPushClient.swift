import CryptoKit
import Foundation
import Security
import WhoopStore

/// iOS sender for NOOP's existing, one-way self-hosted push protocol 1.0.
enum SelfHostedPushClient {
    static let enabledKey = "noop.selfHostedPush.enabled"
    static let endpointKey = "noop.selfHostedPush.endpoint"
    private static let sourceIdKey = "noop.selfHostedPush.sourceId"
    private static let receiverIdKey = "noop.selfHostedPush.receiverStateId"
    static let lastSuccessKey = "noop.selfHostedPush.lastSuccess"
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
        return try await discover(endpoint: endpoint, token: token).streams
    }

    @MainActor
    static func pushIfEnabled(repo: Repository) async {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        do { _ = try await push(repo: repo) }
        catch { NSLog("NOOP self-hosted push deferred: %@", error.localizedDescription) }
    }

    @MainActor
    @discardableResult
    static func push(repo: Repository) async throws -> Int {
        let (endpoint, token) = try configuration()
        guard let store = await repo.storeHandle() else { throw Failure.configuration("NOOP's local database is unavailable.") }
        let capability = try await discover(endpoint: endpoint, token: token)
        let sourceId = stableSourceId()
        let defaults = UserDefaults.standard
        if defaults.string(forKey: receiverIdKey) != capability.receiverStateId {
            defaults.set(capability.receiverStateId, forKey: receiverIdKey)
            // A receiver reset means every stream gets a fresh baseline.
            for name in SelfHostedPushExport.appendStreams {
                defaults.removeObject(forKey: cursorKey(endpoint, sourceId, name))
            }
            for name in SelfHostedPushExport.mutableStreams {
                defaults.removeObject(forKey: snapshotKey(endpoint, sourceId, name))
            }
        }
        var accepted = 0
        for stream in SelfHostedPushExport.appendStreams where capability.streams.contains(stream) {
            accepted += try await pushAppend(stream: stream, endpoint: endpoint, token: token,
                                              sourceId: sourceId, deviceId: repo.deviceId,
                                              store: store, defaults: defaults)
        }
        for stream in SelfHostedPushExport.mutableStreams where capability.streams.contains(stream) {
            accepted += try await pushMutable(stream: stream, endpoint: endpoint, token: token,
                                               sourceId: sourceId, deviceId: repo.deviceId, store: store)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSuccessKey)
        return accepted
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
        guard let from = calendar.date(byAdding: .day, value: -13, to: today),
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
            throw Failure.configuration("Enter a PaceForge HTTPS endpoint and bearer token in Self-hosted push settings.")
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
    static func usesDay(_ stream: String) -> Bool { ["dailyMetric", "journal"].contains(stream) }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
