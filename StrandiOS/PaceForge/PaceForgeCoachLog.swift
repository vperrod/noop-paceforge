import Foundation

// The coach log: everything the coach said or did, newest first, from `api/coach-log`. Foundation only, so the parsing and the
// day grouping are compiled into the macOS unit-test bundle. Read-only: the phone lays the entries out and never writes them.

struct PFCoachLogEntry: Equatable, Identifiable {
    let date: Date
    /// The server's kind, kept as sent so a kind this build does not know still shows.
    let kind: String
    let title: String
    let text: String

    var id: String { "\(date.timeIntervalSince1970)|\(kind)|\(title)" }

    /// Plain words for the known kinds; an unknown kind shows capitalised.
    var kindLabel: String {
        switch kind {
        case "brief": return "Daily brief"
        case "pulse": return "Check-in"
        case "review": return "Week review"
        case "proposal": return "Proposal"
        case "decision": return "Your answer"
        case "chat": return "Chat"
        case "analysis": return "Analysis"
        case "alert": return "Alert"
        case "change": return "Change"
        case "failure": return "Failed"
        default: return kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }
}

struct PFCoachLogDay: Equatable, Identifiable {
    let day: Date
    let entries: [PFCoachLogEntry]
    var id: Date { day }
}

enum PFCoachLog {
    /// Entries newest first. A row without a readable time is dropped; anything else missing becomes empty text.
    static func parse(_ data: Data?) -> [PFCoachLogEntry] {
        guard let data, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        let entries = rows.compactMap { row -> PFCoachLogEntry? in
            guard let stamp = row["ts"] as? String, let date = date(stamp) else { return nil }
            return PFCoachLogEntry(date: date, kind: (row["kind"] as? String) ?? "",
                                   title: (row["title"] as? String) ?? "", text: (row["text"] as? String) ?? "")
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// Entries from the last `days` calendar days (today counts as one), grouped by local day, newest day first.
    static func days(_ entries: [PFCoachLogEntry], last days: Int, now: Date = Date(),
                     calendar: Calendar = .current) -> [PFCoachLogDay] {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let kept = entries.filter { calendar.startOfDay(for: $0.date) >= first }
        let grouped = Dictionary(grouping: kept) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { PFCoachLogDay(day: $0, entries: grouped[$0] ?? []) }
    }

    private static func date(_ stamp: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: stamp) ?? plain.date(from: stamp)
    }
}
