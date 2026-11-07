import Foundation

// Logging a body measure or a field test from the app: the phrase the sheet builds, the checks done before a
// request goes out, and how the server's answer reads. The server (POST /app/log) parses the phrase with the same
// code Telegram uses, so the phrase formats are Telegram's: `waist 92.5 hips 98` and `push-ups 35`, `grip 52 kg`,
// `squat 140 x 5`. The checks here only save a round trip; the server stays the judge of what is a valid number.
// Foundation only, so it is compiled into the macOS unit-test bundle.

enum PFLogKind: String, CaseIterable, Equatable {
    case tape
    case fieldTest = "field_test"

    var title: String {
        switch self {
        case .tape: return "Tape"
        case .fieldTest: return "Field test"
        }
    }
}

/// What the app shows after a save attempt. `refused` carries the server's own plain-English reason.
enum PFLogOutcome: Equatable {
    case saved(String)
    case refused(String)

    var message: String {
        switch self {
        case .saved(let text), .refused(let text): return text
        }
    }

    var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }

    /// No answer at all: offline, timed out or the host did not resolve. Nothing was saved.
    static let unreachable = PFLogOutcome.refused("Couldn't reach PaceForge, so nothing was saved. Check your connection and try again.")

    /// The server's answer to `POST /app/log`: 2xx is a save (its `message` is the confirmation line), anything else
    /// is a refusal whose `message` says why. A body with no message gets a generic line for the status.
    static func from(status: Int, body: Data?) -> PFLogOutcome {
        // Without a valid token the server answers 200 with its HTML login page; that is not a save.
        if (200..<300).contains(status), body?.first(where: { !isSpace($0) }) == UInt8(ascii: "<") {
            return .refused("PaceForge answered with its login page, so this iPhone's token was not accepted. Check More \u{203A} PaceForge sync.")
        }
        let said = PFJ(data: body)["message"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = said.flatMap { $0.isEmpty ? nil : String($0.prefix(400)) }
        if (200..<300).contains(status) { return .saved(text ?? "Saved.") }
        if let text { return .refused(text) }
        switch status {
        case 401, 403: return .refused("PaceForge did not accept this iPhone's token. Check More \u{203A} PaceForge sync.")
        case 429: return .refused("That is a lot of entries for one hour. Try again later.")
        default: return .refused("PaceForge could not save that (HTTP \(status)).")
        }
    }
}

enum PFLog {
    /// The server refuses anything longer.
    static let maxChars = 200

    struct TapeSite: Equatable {
        let key: String
        let title: String
    }

    /// The tape sites the server knows, in the web card's order.
    static let tapeSites: [TapeSite] = [
        TapeSite(key: "waist", title: "Waist"),
        TapeSite(key: "hips", title: "Hips"),
        TapeSite(key: "chest", title: "Chest"),
        TapeSite(key: "arm", title: "Arm"),
        TapeSite(key: "thigh", title: "Thigh"),
    ]

    struct FieldTest: Equatable {
        let title: String
        /// A phrase the server accepts as typed.
        let example: String
    }

    /// The tests Where you stand scores, each with a phrase in the format the server reads.
    static let fieldTests: [FieldTest] = [
        FieldTest(title: "Push-ups in a minute", example: "push-ups 35"),
        FieldTest(title: "Pull-ups", example: "pull-ups 12"),
        FieldTest(title: "Grip strength", example: "grip 52 kg"),
        FieldTest(title: "Standing broad jump", example: "broad jump 230"),
        FieldTest(title: "Sit and reach", example: "sit and reach 22"),
        FieldTest(title: "Single-leg stance", example: "single leg stance 45"),
        FieldTest(title: "Neck", example: "neck 40"),
        FieldTest(title: "Squat (weight x reps)", example: "squat 140 x 5"),
        FieldTest(title: "Deadlift (weight x reps)", example: "deadlift 180 x 3"),
        FieldTest(title: "Bench press (weight x reps)", example: "bench 100 x 5"),
        FieldTest(title: "Overhead press (weight x reps)", example: "press 65 x 5"),
        FieldTest(title: "Row (weight x reps)", example: "row 80 x 8"),
    ]

    /// One tape number as the server reads it: 2 or 3 digits and up to 2 decimals, a comma allowed as the
    /// decimal mark, an optional trailing "cm". Returns it with a dot, or nil when it is not that shape.
    static func normalizedCm(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if t.lowercased().hasSuffix("cm") { t = String(t.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = parts.first, (2...3).contains(whole.count) else { return nil }
        guard parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        if parts.count == 2 {
            guard (1...2).contains(parts[1].count) else { return nil }
        }
        return t
    }

    /// The first tape field that has text which is not a usable number, as a sentence; nil when every filled
    /// field is fine (an empty field is simply not logged).
    static func tapeProblem(_ values: [String: String]) -> String? {
        for site in tapeSites {
            let raw = (values[site.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, normalizedCm(raw) == nil {
                return "\(site.title): type the number in centimetres, like 92.5."
            }
        }
        return nil
    }

    /// `waist 92.5 hips 98` from the filled fields, in site order; nil when nothing usable is filled in.
    static func tapePhrase(_ values: [String: String]) -> String? {
        let pairs = tapeSites.compactMap { site -> String? in
            guard let number = normalizedCm(values[site.key] ?? "") else { return nil }
            return "\(site.key) \(number)"
        }
        return pairs.isEmpty ? nil : pairs.joined(separator: " ")
    }

    /// What was typed, with runs of spaces and line breaks folded to single spaces and the ends trimmed.
    static func cleanedPhrase(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Whether this phrase is worth sending: something to read, within the server's length limit.
    static func canSend(_ phrase: String) -> Bool {
        !phrase.isEmpty && phrase.unicodeScalars.count <= maxChars
    }

    /// The JSON body of `POST /app/log`.
    static func requestBody(kind: PFLogKind, text: String) -> [String: String] {
        ["kind": kind.rawValue, "text": text]
    }
}
