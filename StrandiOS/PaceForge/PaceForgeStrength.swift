import Foundation

// Strength imports and the server's strength history: the inputs of `strength-import-preview` / `strength-import`, how the preview and the
// result read, and `GET strength-history` with the rule that keeps the phone's own Lift Log from being drawn twice. Foundation only, so it
// is compiled into the macOS unit-test bundle. Field names are docs/app-job-contract.md's "Strength imports, PR history, outcome review and
// guides" section; every limit below is the server's own (`strength_import.py`), so the app never sends what it would refuse.

/// The file formats the server reads. `hevy` is a per-set CSV; `strava` and `garmin` are strength summary files with no per-set data.
enum PFStrengthProvider: String, CaseIterable, Identifiable {
    case hevy, strava, garmin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hevy: return "Hevy"
        case .strava: return "Strava"
        case .garmin: return "Garmin"
        }
    }

    /// Whether the file holds one summary per session (never sets).
    var isSummary: Bool { self != .hevy }

    var hint: String {
        isSummary
            ? "A strength summary file: date and duration of each session. It is kept as a summary, never turned into sets."
            : "A per-set CSV export: date, exercise, set, reps and weight with its unit."
    }
}

enum PFStrengthImport {
    /// The longest file text the server takes.
    static let maxChars = 400_000

    /// A preview id is the SHA-256 of the parsed content, 64 lowercase hex digits.
    static func isPreviewID(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { "0123456789abcdef".contains($0) }
    }

    /// Why a file's text cannot be sent, or nil when it can.
    static func problem(with content: String) -> String? {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "That file is empty." }
        if content.unicodeScalars.count > maxChars { return tooBig }
        return nil
    }

    static let tooBig = "That file is too big to send (more than \(maxChars / 1000) thousand characters). Export a shorter period."
}

extension PFJobInputs {
    /// `strength-import-preview`: `{provider, content, exercise_map?}`. Writes nothing on the server.
    static func strengthImportPreview(provider: PFStrengthProvider, content: String, exerciseMap: [String: String] = [:]) -> [String: Any]? {
        guard PFStrengthImport.problem(with: content) == nil else { return nil }
        var inputs: [String: Any] = ["provider": provider.rawValue, "content": content]
        let names = exerciseMap.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty && $0.key.count <= 80 && !$0.value.isEmpty }
        if !names.isEmpty { inputs["exercise_map"] = names }
        return inputs
    }

    /// `strength-import`: the same fields plus `confirm`, the `preview_id` of the preview the athlete accepted.
    static func strengthImport(provider: PFStrengthProvider, content: String, exerciseMap: [String: String] = [:], confirm: String) -> [String: Any]? {
        guard PFStrengthImport.isPreviewID(confirm),
              var inputs = strengthImportPreview(provider: provider, content: content, exerciseMap: exerciseMap) else { return nil }
        inputs["confirm"] = confirm
        return inputs
    }
}

// MARK: The preview

/// What `strength-import-preview` says saving the file would do.
struct PFStrengthPreview: Equatable {
    struct Counts: Equatable {
        var new = 0, duplicate = 0, conflict = 0, rejected = 0, skipped = 0, items = 0
    }

    /// One workout (or one summary) of the file. `status` is new | duplicate | conflict.
    struct Item: Equatable, Identifiable {
        var id: String
        var date: String
        var title: String?
        var status: String
        var reason: String?
        var setCount: Int?
        var durationSeconds: Int?
        var exercises: [String]
    }

    /// One exercise name of the file and the library exercise it was placed on (nil when it was not, and its rows were rejected).
    struct Mapping: Equatable, Identifiable {
        var providerName: String
        var exerciseID: String?
        var name: String?
        var rows: Int
        var id: String { providerName }
        var isMapped: Bool { exerciseID != nil }
    }

    /// A rejected or skipped row of the file: its 1-based data row (the header is not counted) and the reason.
    struct Row: Equatable, Identifiable {
        var row: Int
        var reason: String
        var id: String { "\(row)|\(reason)" }
    }

    struct Reason: Equatable, Identifiable {
        var text: String
        var count: Int
        var id: String { text }
    }

    var provider: String
    /// sets | summary
    var kind: String
    var previewID: String
    var canConfirm: Bool
    /// Set when saving would push older records out of the store; the import is then not offered.
    var blocked: String?
    var counts: Counts
    var items: [Item]
    var mapping: [Mapping]
    var kgCount: Int
    var lbCount: Int
    var rejected: [Row]
    var rejectedReasons: [Reason]
    var skipped: [Row]
    var note: String?

    var isSummary: Bool { kind == "summary" }

    /// The names the server could not place; their rows are rejected.
    var unmapped: [Mapping] { mapping.filter { !$0.isMapped } }

    /// "workouts" for a set file, "summaries" for a summary file.
    var noun: String { isSummary ? "summaries" : "workouts" }

    /// The button that saves: "Save 3 workouts".
    var confirmTitle: String {
        let singular = isSummary ? "summary" : "workout"
        return counts.new == 1 ? "Save 1 \(singular)" : "Save \(counts.new) \(noun)"
    }

    /// The counts in words, only the ones that are not zero: "3 new", "1 already saved", "2 rows rejected".
    var countLines: [String] {
        var out: [String] = []
        if counts.new > 0 { out.append("\(counts.new) new") }
        if counts.duplicate > 0 { out.append("\(counts.duplicate) already saved") }
        if counts.conflict > 0 { out.append("\(counts.conflict) differ from what is saved (left unchanged)") }
        if counts.rejected > 0 { out.append("\(counts.rejected) \(counts.rejected == 1 ? "row" : "rows") rejected") }
        if counts.skipped > 0 { out.append("\(counts.skipped) \(counts.skipped == 1 ? "row" : "rows") skipped") }
        return out
    }

    /// The first line of a preview with nothing to save, so a file that adds nothing says why.
    var nothingToSave: String? {
        guard counts.new == 0 else { return nil }
        if counts.items == 0 { return "No workout could be read from this file." }
        return "Everything in this file is already saved or cannot be saved."
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "new": return "New"
        case "duplicate": return "Already saved"
        case "conflict": return "Differs from saved"
        default: return PFFormat.capitalized(status)
        }
    }

    /// The preview in a `strength-import-preview` job result; nil when it has no `preview_id` or provider.
    static func parse(_ result: PFJ) -> PFStrengthPreview? {
        guard let provider = result["provider"].text, let id = result["preview_id"].text else { return nil }
        let counts = result["counts"]
        let items: [Item] = result["items"].array.compactMap { row in
            guard let id = row["id"].text, let date = row["date"].text else { return nil }
            return Item(id: id, date: date, title: row["title"].text, status: row["status"].text ?? "new", reason: row["reason"].text,
                        setCount: row["set_count"].int, durationSeconds: row["duration_seconds"].int, exercises: row["exercises"].strings)
        }
        let mapping: [Mapping] = result["mapping"].array.compactMap { row in
            guard let name = row["provider_name"].text else { return nil }
            return Mapping(providerName: name, exerciseID: row["exercise_id"].text, name: row["name"].text, rows: row["rows"].int ?? 0)
        }
        func rows(_ list: PFJ) -> [Row] {
            list.array.compactMap { row in
                guard let number = row["row"].int, let reason = row["reason"].text else { return nil }
                return Row(row: number, reason: reason)
            }
        }
        let reasons = result["rejected_reasons"].dict.compactMap { entry -> Reason? in
            guard let count = entry.value.int else { return nil }
            return Reason(text: entry.key, count: count)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text }
        return PFStrengthPreview(
            provider: provider, kind: result["kind"].text ?? "sets", previewID: id,
            canConfirm: result["can_confirm"].bool ?? false, blocked: result["blocked"].text,
            counts: Counts(new: counts["new"].int ?? 0, duplicate: counts["duplicate"].int ?? 0, conflict: counts["conflict"].int ?? 0,
                           rejected: counts["rejected"].int ?? 0, skipped: counts["skipped"].int ?? 0, items: counts["items"].int ?? items.count),
            items: items, mapping: mapping,
            kgCount: result["units_normalised"]["kg"].int ?? 0, lbCount: result["units_normalised"]["lb"].int ?? 0,
            rejected: rows(result["rejected"]), rejectedReasons: reasons, skipped: rows(result["skipped"]), note: result["note"].text)
    }
}

/// What `strength-import` saved.
struct PFStrengthImportResult: Equatable {
    var kind: String
    var saved: Int
    var alreadyImported: Int
    var conflicts: Int
    var rejected: Int
    var skipped: Int

    static func parse(_ result: PFJ) -> PFStrengthImportResult? {
        guard let saved = result["saved"].int else { return nil }
        return PFStrengthImportResult(kind: result["kind"].text ?? "sets", saved: saved, alreadyImported: result["already_imported"].int ?? 0,
                                      conflicts: result["conflicts"].int ?? 0, rejected: result["rejected"].int ?? 0,
                                      skipped: result["skipped"].int ?? 0)
    }

    /// "Saved 3 workouts. 1 was already saved."
    var line: String {
        let noun = kind == "summary" ? (saved == 1 ? "summary" : "summaries") : (saved == 1 ? "workout" : "workouts")
        var text = saved == 0 ? "Nothing new was saved." : "Saved \(saved) \(noun)."
        if alreadyImported > 0 { text += " \(alreadyImported) already saved." }
        if conflicts > 0 { text += " \(conflicts) differ from what is saved and were left unchanged." }
        return text
    }
}

// MARK: History

/// `GET strength-history`: bests and dated history from recorded working sets (the manual logger, confirmed imports and the phone's Lift
/// Log), with the strength summaries listed apart. A summary never counts toward a best.
struct PFStrengthHistory: Equatable {
    /// The source label of sets that came from this iPhone's own Lift Log.
    static let phoneSource = "noop_phone_log"

    struct Best: Equatable {
        var weightKg: Double
        var reps: Int
        var e1rmKg: Double?
        var date: String?
        var source: String?
    }

    struct Point: Equatable, Identifiable {
        var date: String
        var weightKg: Double
        var reps: Int
        var e1rmKg: Double?
        var rpe: Double?
        var source: String
        var isPR: Bool
        var id: String { "\(date)|\(weightKg)|\(reps)|\(source)" }
    }

    struct Exercise: Equatable, Identifiable {
        var key: String
        var name: String
        var exerciseID: String?
        var sets: Int
        var prCount: Int
        var bestWeight: Best?
        var bestE1RM: Best?
        /// Newest first, at most 200.
        var history: [Point]
        var id: String { key }
    }

    struct Summary: Equatable, Identifiable {
        var id: String
        var provider: String
        var date: String
        var title: String?
        var durationSeconds: Int?
    }

    var since: String?
    var through: String?
    var equation: String?
    var exercises: [Exercise]
    var summaries: [Summary]
    var summariesNote: String?

    /// The exercises this phone's own Lift Log does not already show: those with at least one set from another source, each with only
    /// those sets. An exercise whose every set is the phone's own is left out; it is drawn from the phone's own log above.
    var beyondThisPhone: [Exercise] {
        exercises.compactMap { exercise in
            let others = exercise.history.filter { $0.source != Self.phoneSource }
            guard !others.isEmpty else { return nil }
            var kept = exercise
            kept.history = others
            return kept
        }
    }

    /// "Hevy", "PaceForge log", "This iPhone's Lift Log".
    static func sourceLabel(_ source: String?) -> String {
        switch source ?? "" {
        case "paceforge_log": return "PaceForge log"
        case phoneSource: return "This iPhone's Lift Log"
        case "": return "Unknown source"
        default: return PFFormat.capitalized(PFFormat.words(source ?? ""))
        }
    }

    /// The sources behind one exercise's shown sets, in the order they first appear, as one line ("Hevy, PaceForge log").
    static func sourcesLine(_ points: [Point]) -> String {
        var seen: [String] = []
        for point in points where !seen.contains(point.source) { seen.append(point.source) }
        return seen.map { sourceLabel($0) }.joined(separator: ", ")
    }

    /// "90 kg" or, for an iPhone set to pounds, "198 lb".
    static func weightText(kg: Double, pounds: Bool) -> String {
        guard pounds else { return "\(PFFormat.trimmed((kg * 10).rounded() / 10)) kg" }
        return "\(PFFormat.trimmed((kg * 2.2046226218 * 10).rounded() / 10)) lb"
    }

    /// "90 kg x 3".
    static func setText(weightKg: Double, reps: Int, pounds: Bool) -> String {
        "\(weightText(kg: weightKg, pounds: pounds)) \u{00D7} \(reps)"
    }

    static func parse(_ doc: PFJ) -> PFStrengthHistory? {
        guard doc["exercises"].exists else { return nil }
        func best(_ node: PFJ) -> Best? {
            guard let weight = node["weight_kg"].double, let reps = node["reps"].int else { return nil }
            return Best(weightKg: weight, reps: reps, e1rmKg: node["e1rm_kg"].double, date: node["date"].text, source: node["source"].text)
        }
        let exercises: [Exercise] = doc["exercises"].array.compactMap { row in
            guard let key = row["key"].text, let name = row["name"].text else { return nil }
            let history: [Point] = row["history"].array.compactMap { point in
                guard let date = point["date"].text, let weight = point["weight_kg"].double, let reps = point["reps"].int else { return nil }
                return Point(date: date, weightKg: weight, reps: reps, e1rmKg: point["e1rm_kg"].double, rpe: point["rpe"].double,
                             source: point["source"].text ?? "", isPR: point["pr"].bool ?? false)
            }
            return Exercise(key: key, name: name, exerciseID: row["exercise_id"].text, sets: row["sets"].int ?? history.count,
                            prCount: row["pr_count"].int ?? 0, bestWeight: best(row["best_weight"]), bestE1RM: best(row["best_e1rm"]),
                            history: history)
        }
        let summaries: [Summary] = doc["summaries"].array.compactMap { row in
            guard let id = row["summary_id"].text, let date = row["date"].text else { return nil }
            return Summary(id: id, provider: row["provider"].text ?? "", date: date, title: row["title"].text,
                           durationSeconds: row["duration_seconds"].int)
        }
        return PFStrengthHistory(since: doc["since"].text, through: doc["through"].text, equation: doc["equation"].text, exercises: exercises,
                                 summaries: summaries, summariesNote: doc["summaries_note"].text)
    }

    /// "Mon 9 Nov \u{00B7} Push day", or the day alone when the title is empty.
    static func heading(date: String, title: String?) -> String {
        guard let title, !title.isEmpty else { return PFFormat.dayTitle(date) }
        return PFFormat.dayTitle(date) + " \u{00B7} " + title
    }

    /// "1:05 h" for a long session, "45 min" for a short one.
    static func durationText(seconds: Int) -> String {
        let minutes = max(1, (seconds + 30) / 60)
        guard minutes >= 60 else { return "\(minutes) min" }
        return String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }
}
