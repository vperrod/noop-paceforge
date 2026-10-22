import Foundation

/// PaceForge's morning brief as the text NOOP's brief scheduler stores and notifies, so the brief needs no AI key on the phone.
enum PaceForgeBriefSource {
    enum Outcome {
        /// PaceForge is not connected: the scheduler falls back to NOOP's own key-based brief.
        case notSetUp
        /// Connected, but today's brief is not published (or the server is unreachable): try again at the next wake, say nothing.
        case notReady
        case text(String)
    }

    /// `timeReached`: the chosen latest time has passed, so a brief still waiting for sleep goes out as it is, saying so.
    @MainActor static func today(timeReached: Bool) async -> Outcome {
        let model = PFUnified.model
        await model.refreshIfStale()
        switch model.phase {
        case .notSetUp: return .notSetUp
        case .ready: break
        default: return .notReady
        }
        guard let snapshot = model.snapshot, let brief = snapshot.brief, !brief.headline.isEmpty,
              brief.date == nil || brief.date == snapshot.todayISO else { return .notReady }
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
