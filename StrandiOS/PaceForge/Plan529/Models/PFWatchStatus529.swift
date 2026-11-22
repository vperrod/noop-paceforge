import Foundation

/// `GET api/watch-status`: for each upcoming planned session (today to 21 days ahead), where it stands on the way to the watch. The server
/// computes the state; the phone only words it. Only `on_watch` claims the watch, and only with Garmin's own read-back as its evidence.
struct PFWatchStatusDoc: Codable, Equatable {
    var asOf: String?
    var windowDays: Int?
    /// fresh | stale | none: how recent the read-back of Garmin's workout list is.
    var readback: String?
    var readbackAt: String?
    var sessions: [Session]?

    struct Session: Codable, Equatable {
        var sessionId: String?
        var name: String?
        var date: String?
        var workoutType: String?
        var sport: String?
        /// not_sent | sent_to_connect | on_watch | blocked_by_allowlist | failed
        var state: String?
        var reason: String?
        /// `garmin_library_readback` on an `on_watch` session.
        var evidence: String?
    }

    /// A session of the window; nil for one that is not in it (rest day, imported row, further than 21 days): no claim is made about it.
    func session(_ id: String?) -> Session? {
        guard let id, !id.isEmpty else { return nil }
        return (sessions ?? []).first { $0.sessionId == id }
    }
}

enum PFWatchStatus529 {
    enum Tone: Equatable { case onWatch, pending, blocked, failed }

    struct Line: Equatable {
        let text: String
        let detail: String?
        let tone: Tone
    }

    static let sentToConnect = Line(text: "Sent to Garmin Connect \u{2014} not yet confirmed on the watch", detail: nil, tone: .pending)

    /// What to tell the athlete about one session; nil for a state this build does not know (nothing is claimed).
    static func line(_ session: PFWatchStatusDoc.Session) -> Line? {
        switch session.state ?? "" {
        case "on_watch":
            // "On your watch" needs the read-back as evidence; without it the honest line is the one for a session Garmin Connect holds.
            guard session.evidence == "garmin_library_readback" else { return sentToConnect }
            return Line(text: "On your watch", detail: nil, tone: .onWatch)
        case "sent_to_connect":
            return sentToConnect
        case "not_sent":
            return Line(text: "Not sent to your watch yet", detail: sentence(session.reason), tone: .pending)
        case "blocked_by_allowlist":
            return Line(text: "Stays off your watch", detail: "\(sportName(session)) sessions are not sent to Garmin.", tone: .blocked)
        case "failed":
            return Line(text: "Not on your watch: the send failed", detail: sentence(session.reason), tone: .failed)
        default:
            return nil
        }
    }

    /// "strength_training" reads "Strength training"; a session that names neither sport nor type reads "This kind of".
    static func sportName(_ session: PFWatchStatusDoc.Session) -> String {
        let key = (session.sport ?? session.workoutType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "This kind of" }
        let words = key.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The server's reason as a sentence: first letter capital, a full stop at the end; nil when there is none.
    static func sentence(_ reason: String?) -> String? {
        let text = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let capitalised = text.prefix(1).uppercased() + text.dropFirst()
        return capitalised.hasSuffix(".") ? capitalised : capitalised + "."
    }
}
