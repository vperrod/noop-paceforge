import Foundation

/// PaceForge's morning brief as the text NOOP's brief scheduler stores and notifies, so the brief needs no AI key on the phone.
enum PaceForgeBriefSource {
    enum Outcome {
        /// PaceForge is not connected: the unified iPhone Coach cannot generate a brief yet.
        case notSetUp
        /// A refresh is still loading or today's overnight data has not arrived; retry at the next wake without an alert.
        case notReady(String)
        /// PaceForge is configured, but the refresh or today's brief has failed in a way the athlete can act on.
        case unavailable(String)
        case text(String, readiness: String)
    }

    /// `timeReached`: the chosen latest time has passed, so a brief still waiting for sleep goes out as it is, saying so.
    @MainActor static func today(timeReached: Bool) async -> Outcome {
        let model = PFUnified.model
        await model.refreshIfStale()
        switch model.phase {
        case .notSetUp: return .notSetUp
        case .ready: break
        case .failed(let message): return .unavailable(model.failureDetail ?? message)
        case .loading: return .notReady("PaceForge is still loading the latest sync.")
        }
        guard let snapshot = model.snapshot else { return .notReady("PaceForge has no current snapshot yet.") }
        guard let brief = snapshot.today.brief, !brief.headline.isEmpty else {
            guard timeReached else { return .notReady("Today's PaceForge briefing has not been published yet.") }
            return .unavailable(model.failureDetail
                ?? "PaceForge has not published today's brief. Check that today's data has synced.")
        }
        guard brief.date == snapshot.todayISO else {
            let reason = brief.date.map { "PaceForge has a brief dated \($0), not today (\(snapshot.todayISO))." }
                ?? "PaceForge's brief has no date, so the app cannot confirm it belongs to today."
            guard timeReached else { return .notReady(reason + " Waiting until today's brief is available.") }
            return .unavailable(reason + " Check that today's data has synced and the brief was refreshed.")
        }
        // The server rewrites the brief when the night's sleep and HRV arrive; `missing` lists what it is still waiting for.
        // That arrival is the wake-up signal, so hold the notification until it is in, or until the latest time.
        let waiting = brief.partial
        if waiting && !timeReached {
            let missing = brief.missing.isEmpty ? "the remaining required overnight data" : brief.missing.joined(separator: ", ")
            return .notReady("Waiting for: " + missing + ".")
        }
        // The first line is the notification body (`oneLineSummary`); the rest is what Coach and the widget keep.
        var lines = [brief.headline] + brief.outlook
        if waiting {
            let missing = brief.missing.isEmpty ? "the remaining required overnight data" : brief.missing.joined(separator: ", ")
            lines.append("Still waiting for: " + missing + ".")
        }
        let readiness = waiting
            ? "partial brief published at selected latest time; still missing: \(brief.missing.isEmpty ? "required overnight data (not specified by server)" : brief.missing.joined(separator: ", "))"
            : "today's required data is ready"
        return .text(lines.joined(separator: "\n"), readiness: readiness)
    }
}
