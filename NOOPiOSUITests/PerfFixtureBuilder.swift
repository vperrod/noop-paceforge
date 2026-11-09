import Foundation

/// The perf tests' PaceForge documents: StrandTests/LiveShapes/PaceForgeRealShapes.json (the live documents' shapes with
/// every value replaced, a few items per list) grown to the live list lengths in `PerfRealCounts`. A copied item gets a
/// distinct id and, when its list is dated, an earlier date, so a 366-day series stays 366 different days in order.
enum PerfFixtureBuilder {
    private static let dateKeys: Set<String> = ["date", "day", "start_date", "week_start", "monday"]
    private static let idKeys: Set<String> = ["id", "activity_id", "activityId", "key"]

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The fixture as the app reads it (`PF_FIXTURE_JSON` / `PF_FIXTURE_DEFLATE`): request path -> document, plus "today".
    static func realSize(shapes url: URL) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let docs = root["docs"] as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        var out: [String: Any] = [:]
        for (path, doc) in docs { out[path] = grow(doc, path: path) }
        out["today"] = root["today"]
        out["_synthetic"] = root["_synthetic"]
        return try JSONSerialization.data(withJSONObject: out)
    }

    private static func grow(_ node: Any, path: String) -> Any {
        if let list = node as? [Any] {
            var items = list.map { grow($0, path: path + "[]") }
            if let target = PerfRealCounts.lengths[path], !items.isEmpty, items.count < target {
                items = extend(items, to: target)
            }
            return items
        }
        if let dict = node as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict { out[key] = grow(value, path: "\(path).\(key)") }
            return out
        }
        return node
    }

    /// Copies of the items in turn until there are `target`; dated items are moved one cycle earlier per copy, on the
    /// side of the list that already holds the older days.
    private static func extend(_ base: [Any], to target: Int) -> [Any] {
        let dates = base.compactMap { day(of: $0) }
        let newestFirst = dates.count >= 2 && dates.first! > dates.last!
        var older: [Any] = []
        var cycle = 1
        while base.count + older.count < target {
            for item in base where base.count + older.count < target {
                older.append(copy(item, cycle: cycle, span: base.count))
            }
            cycle += 1
        }
        if dates.isEmpty { return base + older }
        // Each copied cycle is older than the one before; keep the list's own order.
        let chunks = stride(from: 0, to: older.count, by: base.count).map { Array(older[$0..<min($0 + base.count, older.count)]) }
        if newestFirst { return base + chunks.flatMap { $0 } }
        return chunks.reversed().flatMap { $0 } + base
    }

    private static func day(of item: Any) -> String? {
        guard let dict = item as? [String: Any] else { return nil }
        for key in dateKeys { if let s = dict[key] as? String, s.count >= 10, isoDay.date(from: String(s.prefix(10))) != nil { return s } }
        return nil
    }

    private static func copy(_ item: Any, cycle: Int, span: Int) -> Any {
        guard var dict = item as? [String: Any] else { return item }
        for key in idKeys {
            if let s = dict[key] as? String { dict[key] = "\(s)-p\(cycle)" }
            else if let n = dict[key] as? Int { dict[key] = n + cycle * 10_000_000 }
        }
        for key in dateKeys {
            guard let s = dict[key] as? String, s.count >= 10, let date = isoDay.date(from: String(s.prefix(10))) else { continue }
            let shifted = date.addingTimeInterval(-Double(cycle * max(span, 1)) * 86_400)
            dict[key] = isoDay.string(from: shifted) + s.dropFirst(10)
        }
        return dict
    }
}
