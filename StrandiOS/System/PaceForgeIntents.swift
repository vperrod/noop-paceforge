#if os(iOS)
import Foundation
import AppIntents

/// Spoken answers built from the PaceForge summary the app last wrote to the App Group.
enum PFSpoken {
    private static let refresh = "Open NOOP to refresh PaceForge first."

    static func session() -> String {
        guard let s = PFSummary.load(), !s.isStale() else { return refresh }
        var parts: [String] = []
        if s.sessions.isEmpty {
            parts.append("Rest day today.")
        } else {
            for session in s.sessions {
                var line = session.done ? "Done: \(session.name)" : "Today: \(session.name)"
                if let detail = session.detail { line += ", " + detail.replacingOccurrences(of: " \u{00B7} ", with: ", ") }
                if let main = session.mainSet, !session.done { line += ". Main set \(main)" }
                parts.append(line + ".")
            }
        }
        if let recovery = s.recovery { parts.append("Recovery \(Int(recovery.rounded())).") }
        return parts.joined(separator: " ")
    }

    static func race() -> String {
        guard let s = PFSummary.load(), let race = s.race else { return refresh }
        let days = s.raceDaysNow ?? race.days
        switch days {
        case ..<0: return "\(race.name) has passed."
        case 0: return "\(race.name) is today."
        case 1: return "\(race.name) is tomorrow."
        default: return "\(race.name) is in \(days) days."
        }
    }
}

struct TodaysPaceForgeSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's PaceForge session"
    static var description = IntentDescription("Hear today's PaceForge session and your recovery.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = PFSpoken.session()
        return .result(dialog: "\(text)")
    }
}

struct DaysToNextRaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Days to my next race"
    static var description = IntentDescription("Hear how many days are left until your next PaceForge race.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = PFSpoken.race()
        return .result(dialog: "\(text)")
    }
}
#endif
