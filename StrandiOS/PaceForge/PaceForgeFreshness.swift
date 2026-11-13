import Foundation

// How old the data on screen is and why it could not be refreshed, in words. Foundation only (no RelativeDateTimeFormatter, which the
// Linux Foundation lacks), so it is compiled into the macOS unit-test bundle.

enum PFFreshness {
    /// "just now", "5 min ago", "3 h ago", "2 days ago".
    static func age(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86_400 { return "\(Int(s / 3600)) h ago" }
        let days = Int(s / 86_400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    /// The moment a PaceForge timestamp names; nil when it cannot be read.
    static func date(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return PFFormat.isoWithFraction.date(from: timestamp) ?? PFFormat.isoPlain.date(from: timestamp)
            ?? PFFormat.isoLocalSeconds.date(from: timestamp)
    }

    /// "Showing the copy saved 3 h ago." from the snapshot's `generatedAt`; "Showing the last saved copy." when no time is known.
    static func savedCopy(generatedAt: String?, now: Date = Date()) -> String {
        guard let when = date(generatedAt) else { return "Showing the last saved copy." }
        return "Showing the copy saved \(age(now.timeIntervalSince(when)))."
    }

    /// The line under the offline banner: which documents could not be refreshed, and how old the copy on screen is.
    static func staleLine(names: [String], generatedAt: String?, now: Date = Date()) -> String {
        let more = names.count > 3 ? " and \(names.count - 3) more" : ""
        return "Couldn't refresh " + names.prefix(3).joined(separator: ", ") + more + ". " + savedCopy(generatedAt: generatedAt, now: now)
    }
}

/// Whether a failed request means the server could not be asked at all.
enum PFReachability {
    /// No connection, no route, no host or no answer in time. Every other failure means something answered (an error status, a login
    /// page, a certificate, a reply that does not parse).
    static func isUnreachable(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            return true
        default:
            return false
        }
    }
}

/// The words of the offline banner and of the first-load failure card.
enum PFOfflineNote {
    /// Above a screen that shows saved data because the refresh failed.
    static func banner(unreachable: Bool, status: Int?) -> String {
        unreachable
            ? "Can't reach PaceForge. Showing the data last saved on this iPhone."
            : "PaceForge answered with an error" + (status.map { " (HTTP \($0))" } ?? "") + ". Showing the data last saved on this iPhone."
    }

    /// The title of the card shown when there is nothing saved to fall back on.
    static func failedTitle(unreachable: Bool) -> String {
        unreachable ? "Can't reach PaceForge" : "PaceForge answered with an error"
    }
}

/// When the app asks again by itself after a refresh failed: 10 s, 30 s and 2 min after the first, second and third failure in a row,
/// then not again (the Retry button stays).
enum PFRetrySchedule {
    static let delays: [TimeInterval] = [10, 30, 120]

    /// The wait before the next automatic try after `failures` failures in a row (1 for the first); nil when the tries are used up.
    static func delay(afterFailures failures: Int) -> TimeInterval? {
        guard failures >= 1, failures <= delays.count else { return nil }
        return delays[failures - 1]
    }
}
