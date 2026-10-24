import Foundation

/// PaceForge's morning brief as the text NOOP's brief scheduler stores and notifies, so the brief needs no AI key on the phone.
enum PaceForgeBriefSource {
    enum Outcome {
        /// PaceForge is not connected: the unified iPhone Coach cannot generate a brief yet.
        case notSetUp
        /// A refresh is still loading or today's overnight data has not arrived; retry at the next wake without an alert.
        case notReady
        /// PaceForge is configured, but the refresh or today's brief has failed in a way the athlete can act on.
        case unavailable(String)
        case text(String)
    }

    /// `timeReached`: the chosen latest time has passed, so a brief still waiting for sleep goes out as it is, saying so.
    @MainActor static func today(timeReached: Bool) async -> Outcome {
        let model = PFUnified.model
        await model.refreshIfStale()
        switch model.phase {
        case .notSetUp: return .notSetUp
        case .ready: break
        case .failed(let message): return .unavailable(model.failureDetail ?? message)
        case .loading: return .notReady
        }
        guard let snapshot = model.snapshot else { return .notReady }
        guard let brief = snapshot.today.brief, !brief.headline.isEmpty,
              brief.date == nil || brief.date == snapshot.todayISO else {
            guard timeReached else { return .notReady }
            return .unavailable(model.failureDetail
                ?? "PaceForge has not published today's brief. Check that today's data has synced.")
        }
        // The server rewrites the brief when the night's sleep and HRV arrive; `missing` lists what it is still waiting for.
        // That arrival is the wake-up signal, so hold the notification until it is in, or until the latest time.
        let waiting = brief.partial && !brief.missing.isEmpty
        if waiting && !timeReached { return .notReady }
        // The first line is the notification body (`oneLineSummary`); the rest is what Coach and the widget keep.
        var lines = [brief.headline] + brief.outlook
        if waiting { lines.append("Still waiting for: " + brief.missing.joined(separator: ", ") + ".") }
        return .text(lines.joined(separator: "\n"))
    }
}
