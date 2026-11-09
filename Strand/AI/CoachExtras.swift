import Foundation

// Coach extras: the response-length setting, the "Ask about this" question, the history of past
// conversations and the local feedback log. Foundation only (no networking, no UI), so every rule here is
// unit-tested. Nothing in this file leaves the device: history and feedback are plain JSON files in
// Application Support, written only by the person using the app.

// MARK: - Response length

/// How long the coach's replies should be. `condensed` adds one instruction to the system prompt; the default
/// adds nothing, so the prompt a person has edited (or the built-in one) is sent exactly as before.
enum CoachResponseLength: String, CaseIterable, Identifiable {
    case standard
    case condensed

    var id: String { rawValue }

    static let storageKey = "ai.responseLength"

    var label: String {
        switch self {
        case .standard: return "Default"
        case .condensed: return "Condensed"
        }
    }

    /// Appended to the system prompt. Empty for the default length.
    var promptAddition: String {
        switch self {
        case .standard:
            return ""
        case .condensed:
            return "Keep every reply condensed: lead with the answer, then at most a few short sentences or "
                + "bullets, around 120 words in all. No preamble, no recap of the question, and no headings or "
                + "tables unless the person asks for them."
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> CoachResponseLength {
        defaults.string(forKey: storageKey).flatMap(CoachResponseLength.init(rawValue:)) ?? .standard
    }

    static func save(_ length: CoachResponseLength, to defaults: UserDefaults = .standard) {
        defaults.set(length.rawValue, forKey: storageKey)
    }

    /// The system prompt actually sent: `base` plus this length's instruction, on its own paragraph.
    func systemPrompt(base: String) -> String {
        promptAddition.isEmpty ? base : base + "\n\n" + promptAddition
    }
}

// MARK: - Ask about this

enum CoachAskPrompt {
    /// The question the "Ask about this" button in a metric's info sheet hands to Coach.
    static func question(about metric: String) -> String {
        let name = metric.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Can you explain my scores and what to do about them?" }
        return "Can you explain my \(name) in plain language: what it means for me right now, what is moving it, and what I should do about it?"
    }
}

// MARK: - History of past conversations

/// A message as kept in history: the role's raw value and the text, nothing else.
struct CoachStoredMessage: Codable, Equatable {
    var role: String
    var text: String
}

/// A past conversation. `title` is the first thing the person asked.
struct CoachConversationRecord: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    /// When the conversation was put away (the last time it was current).
    var archivedAt: Date
    var messages: [CoachStoredMessage]

    var messageCount: Int { messages.count }
}

enum CoachHistory {
    static let maxConversations = 30
    static let maxTitleLength = 48

    /// The first user message, collapsed to one line and cut to `maxTitleLength` with an ellipsis. A
    /// conversation with no user message (a lone morning brief) is titled by its first line instead.
    static func title(from messages: [CoachStoredMessage]) -> String {
        let source = messages.first { $0.role == "user" }?.text ?? messages.first?.text ?? ""
        let oneLine = source.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        guard !oneLine.isEmpty else { return "Conversation" }
        guard oneLine.count > maxTitleLength else { return oneLine }
        return String(oneLine.prefix(maxTitleLength - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// A record of the current conversation, or nil when the person asked nothing (nothing worth keeping).
    static func record(from messages: [CoachStoredMessage], now: Date, id: String) -> CoachConversationRecord? {
        guard messages.contains(where: { $0.role == "user" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }
        return CoachConversationRecord(id: id, title: title(from: messages), archivedAt: now, messages: messages)
    }

    /// `list` with `record` first. A record with the same id, or the very same messages, replaces the old one
    /// (the same chat put away twice is one entry); only the newest `maxConversations` are kept.
    static func archiving(_ list: [CoachConversationRecord], record: CoachConversationRecord) -> [CoachConversationRecord] {
        var out = list.filter { $0.id != record.id && $0.messages != record.messages }
        out.insert(record, at: 0)
        out.sort { $0.archivedAt > $1.archivedAt }
        return Array(out.prefix(maxConversations))
    }

    static func removing(_ list: [CoachConversationRecord], id: String) -> [CoachConversationRecord] {
        list.filter { $0.id != id }
    }
}

// MARK: - Feedback on a reply

enum CoachFeedbackRating: String, Codable {
    case up, down
}

/// Why a reply got a thumbs-down.
enum CoachFeedbackReason: String, Codable, CaseIterable, Identifiable {
    case inaccurate
    case unhelpful
    case offTopic = "off_topic"
    case unsafe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inaccurate: return "Inaccurate"
        case .unhelpful: return "Unhelpful"
        case .offTopic: return "Off-topic"
        case .unsafe: return "Unsafe"
        }
    }
}

/// One thumbs on one reply. Only the reply's id is kept, never its text.
struct CoachFeedbackEntry: Codable, Equatable {
    var messageId: String
    var rating: CoachFeedbackRating
    var reason: CoachFeedbackReason?
    var at: Date
}

enum CoachFeedbackLog {
    static let maxEntries = 200

    /// `list` with `entry` first, replacing any earlier feedback on the same reply. A thumbs-up carries no
    /// reason, whatever the entry says.
    static func recording(_ list: [CoachFeedbackEntry], entry: CoachFeedbackEntry) -> [CoachFeedbackEntry] {
        var clean = entry
        if clean.rating == .up { clean.reason = nil }
        var out = list.filter { $0.messageId != entry.messageId }
        out.insert(clean, at: 0)
        return Array(out.prefix(maxEntries))
    }

    static func removing(_ list: [CoachFeedbackEntry], messageId: String) -> [CoachFeedbackEntry] {
        list.filter { $0.messageId != messageId }
    }

    static func entry(for messageId: String, in list: [CoachFeedbackEntry]) -> CoachFeedbackEntry? {
        list.first { $0.messageId == messageId }
    }
}

// MARK: - Files

/// The two JSON files, in Application Support. A missing or unreadable file reads as empty; a failed write is
/// silent (the in-memory list is what the screen shows).
enum CoachLocalFiles {
    static func directory() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("NOOP", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var historyURL: URL? { directory()?.appendingPathComponent("coach-history.json") }
    static var feedbackURL: URL? { directory()?.appendingPathComponent("coach-feedback.json") }

    static func load<T: Decodable>(_ type: [T].Type, from url: URL?) -> [T] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([T].self, from: data)) ?? []
    }

    static func save<T: Encodable>(_ list: [T], to url: URL?) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(list) { try? data.write(to: url, options: .atomic) }
    }
}
