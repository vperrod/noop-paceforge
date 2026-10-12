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

    static func recovery() -> String {
        guard let s = PFSummary.load(), !s.isStale(), let recovery = s.recovery else { return refresh }
        var parts = ["Recovery \(Int(recovery.rounded()))" + (s.recoveryBand.map { ", \($0)" } ?? "") + "."]
        if let hrv = s.hrv { parts.append("HRV \(Int(hrv.rounded())) milliseconds.") }
        if let rhr = s.restingHr { parts.append("Resting heart rate \(Int(rhr.rounded())).") }
        if let sleep = s.sleep { parts.append("Sleep score \(Int(sleep.rounded())).") }
        return parts.joined(separator: " ")
    }

    static func heartRecovery() -> String {
        guard let h = PFSummary.load()?.heartRecovery else {
            return "No heart rate recovery has been measured for a recent workout yet."
        }
        let when = "your \(h.sport.lowercased()) on \(PFWidgetFormat.dayLine(h.date))"
        switch (h.after1Minute, h.after2Minutes) {
        case let (one?, two?):
            return "After \(when), your heart rate fell \(one) beats in the first minute and \(two) by two minutes."
        case let (one?, nil):
            return "After \(when), your heart rate fell \(one) beats in the first minute."
        case let (nil, two?):
            return "After \(when), your heart rate fell \(two) beats by two minutes."
        default:
            return "No heart rate recovery has been measured for a recent workout yet."
        }
    }

    static func nextSession() -> String {
        guard let s = PFSummary.load(), !s.isStale() else { return refresh }
        if let today = s.sessions.first(where: { !$0.done }) {
            return "Next up is today's \(describe(today))."
        }
        if let next = s.nextSession, let date = s.nextSessionDate {
            return "Next is \(PFWidgetFormat.dayLine(date)): \(describe(next))."
        }
        return "No further session is planned."
    }

    private static func describe(_ session: PFSummary.Session) -> String {
        var line = session.name
        if let detail = session.detail { line += ", " + detail.replacingOccurrences(of: " \u{00B7} ", with: ", ") }
        if let target = session.target { line += ", target \(target)" }
        return line
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

struct PaceForgeRecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "How is my recovery"
    static var description = IntentDescription("Hear your PaceForge recovery, HRV, resting heart rate and sleep.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = PFSpoken.recovery()
        return .result(dialog: "\(text)")
    }
}

struct PaceForgeHeartRecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "What is my heart recovery"
    static var description = IntentDescription("Hear how fast your heart rate fell after your latest hard workout.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = PFSpoken.heartRecovery()
        return .result(dialog: "\(text)")
    }
}

struct NextPaceForgeSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "What's my next session"
    static var description = IntentDescription("Hear your next PaceForge session.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = PFSpoken.nextSession()
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
