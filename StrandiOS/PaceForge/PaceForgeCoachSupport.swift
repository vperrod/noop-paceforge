import Foundation

// Small pure helpers of the Coach screen. Foundation only, so they are compiled into the macOS unit-test bundle.

enum PFCoachRead {
    /// The first `count` sentences of `paragraphs`, joined by a space. A sentence ends at ".", "!" or "?" followed by a space or the end
    /// of the text, so "7.5 hours" does not end one. Empty paragraphs are skipped.
    static func summary(paragraphs: [String], sentences count: Int) -> String {
        guard count > 0 else { return "" }
        var out: [String] = []
        for paragraph in paragraphs {
            for sentence in split(paragraph) {
                out.append(sentence)
                if out.count == count { return out.joined(separator: " ") }
            }
        }
        return out.joined(separator: " ")
    }

    static func split(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for (index, char) in chars.enumerated() {
            current.append(char)
            guard char == "." || char == "!" || char == "?" else { continue }
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            if next == nil || next == " " || next == "\n" {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }
}

enum PFPlanDiff {
    /// The days (`yyyy-MM-dd`, oldest first) whose planned sessions differ between two snapshots' weeks: a session added, dropped, moved
    /// to or from the day, renamed, resized or given another state. A day that holds the same sessions in both is not listed.
    static func changedDays(before: [PFWeek], after: [PFWeek]) -> [String] {
        let old = signatures(before)
        let new = signatures(after)
        let days = Set(old.keys).union(new.keys)
        return days.filter { (old[$0] ?? []) != (new[$0] ?? []) }.sorted()
    }

    private static func signatures(_ weeks: [PFWeek]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for week in weeks {
            for day in week.days where !day.workouts.isEmpty {
                out[day.date] = day.workouts.map { workout in
                    [workout.coachSessionID ?? workout.id, workout.name ?? "", workout.kind ?? "", workout.status,
                     workout.durationMin.map { String($0) } ?? "", workout.distanceKm.map { String($0) } ?? ""].joined(separator: "|")
                }.sorted()
            }
        }
        return out
    }
}
