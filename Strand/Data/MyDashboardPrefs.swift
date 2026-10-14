import Foundation

// MARK: - My Dashboard (the user's chosen metrics on Today)
//
// "My Dashboard" is a short list of metrics the user picks and orders, drawn as today-versus-30-days rows. The list is
// kept on the phone as one comma-joined string of metric ids ("my-whoop:hrv", the `MetricCatalog` id of source and key) in
// UserDefaults, the same mechanism the Today layout and the More-tab sections use. Foundation only and pure, so it is unit
// tested: an unset value is the default list, an empty string is a real (empty) choice, unknown ids are resolved against the
// catalog by the screen and never here, and a duplicate or blank id is dropped.

enum MyDashboardPrefs {
    /// The `@AppStorage` / UserDefaults key.
    static let storageKey = "noop.myDashboard.metrics"

    /// What a fresh install shows.
    static let defaultIDs: [String] = [
        "my-whoop:hrv", "my-whoop:sleep_performance", "my-whoop:sleep_consistency", "my-whoop:hours_vs_needed_pct",
        "my-whoop:rhr",
    ]

    /// The metrics offered under "+ Add", in the order the list shows them. Every id exists in the metric catalog
    /// (a unit test pins that).
    static let addableIDs: [String] = [
        "my-whoop:avg_hr", "my-whoop:hrv", "my-whoop:rhr", "my-whoop:recovery", "my-whoop:strain", "my-whoop:sleep_performance",
        "my-whoop:sleep_consistency", "my-whoop:hours_vs_needed_pct", "my-whoop:sleep_efficiency", "my-whoop:sleep_total_min",
        "my-whoop:sleep_debt_min", "my-whoop:restorative_min", "my-whoop:resp_rate", "my-whoop:spo2", "my-whoop:stress",
        "my-whoop:steps", "my-whoop:energy_kcal", "my-whoop:hr_zones13_min", "my-whoop:hr_zones45_min",
        "my-whoop:strength_min", "apple-health:weight",
    ]

    static var defaultCSV: String { encode(defaultIDs) }

    static func encode(_ ids: [String]) -> String { ids.joined(separator: ",") }

    /// The ids in a stored string, in order, without blanks or repeats. An empty string is the empty list.
    static func decode(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for token in raw.split(separator: ",") {
            let id = token.trimmingCharacters(in: .whitespaces)
            if !id.isEmpty, seen.insert(id).inserted { out.append(id) }
        }
        return out
    }

    /// `ids` with `id` appended, unless it is already there.
    static func adding(_ id: String, to ids: [String]) -> [String] {
        ids.contains(id) ? ids : ids + [id]
    }

    static func removing(_ id: String, from ids: [String]) -> [String] {
        ids.filter { $0 != id }
    }

    /// `ids` with the row at `from` dropped onto position `to` (the index it should end up at); unchanged for a bad index.
    static func moving(_ ids: [String], from: Int, to: Int) -> [String] {
        guard ids.indices.contains(from), ids.indices.contains(to), from != to else { return ids }
        var out = ids
        let item = out.remove(at: from)
        out.insert(item, at: to)
        return out
    }

    /// The addable ids not already chosen.
    static func available(excluding chosen: [String]) -> [String] {
        let taken = Set(chosen)
        return addableIDs.filter { !taken.contains($0) }
    }
}
