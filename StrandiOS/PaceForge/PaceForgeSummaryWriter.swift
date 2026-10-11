import Foundation
import WidgetKit

/// Turns a fetched PaceForge snapshot into the small App Group summary the widgets, Siri and Shortcuts
/// read, writes it, and asks WidgetKit to reload the PaceForge widgets.
enum PFSummaryWriter {
    static func publish(_ snapshot: PFSnapshot) {
        make(from: snapshot).save()
        for kind in PFWidgetKind.all { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }

    static func make(from s: PFSnapshot, now: Date = Date()) -> PFSummary {
        var out = PFSummary(updated: now, date: s.todayISO)
        let t = s.today
        let sessions = t.sessions.map { w in
            PFSummary.Session(name: w.name ?? "Workout", sport: w.sport ?? w.kind, detail: detail(w),
                              target: primaryTarget(w), mainSet: mainSet(w),
                              done: w.status == "done" || w.status == "partial")
        }
        // Sessions still to do come first, so a widget with room for one shows what is next.
        out.sessions = sessions.filter { !$0.done } + sessions.filter { $0.done }
        out.recovery = t.recovery?.score
        out.recoveryBand = t.recovery?.band
        out.strain = t.strain?.value
        out.strainLow = t.strain?.targetLow
        out.strainHigh = t.strain?.targetHigh
        out.sleep = t.sleep?.score
        out.sleepHours = t.sleep?.hoursText
        out.sleepNeed = t.sleep?.needText
        out.hrv = t.hrv
        out.restingHr = t.restingHr
        out.acwr = t.acwr
        out.fitness = s.insights.ctl
        out.fatigue = s.insights.atl
        out.briefHeadline = t.brief?.headline
        out.briefDate = t.brief?.date
        if let race = t.nextRace { out.race = PFSummary.Race(name: race.name, date: race.date, days: race.daysOut) }
        return out
    }

    private static func detail(_ w: PFWorkout) -> String? {
        var bits: [String] = []
        if let km = w.distanceKm { bits.append("\(PFFormat.oneDecimal(km)) km") }
        if let min = w.durationMin { bits.append("\(Int(min.rounded())) min") }
        return bits.isEmpty ? nil : bits.joined(separator: " \u{00B7} ")
    }

    /// The steps that carry the session's intensity: the work step of the first repeat block, else the
    /// first step that is not a warm-up or cool-down.
    private static func workStep(_ w: PFWorkout) -> (step: PFStep, reps: Int?)? {
        if let block = w.steps.first(where: { $0.repeatCount != nil && !$0.steps.isEmpty }),
           let work = block.steps.first(where: { $0.type == "interval" }) ?? block.steps.first {
            return (work, block.repeatCount)
        }
        if let main = w.steps.first(where: { $0.type != "warmup" && $0.type != "cooldown" && $0.steps.isEmpty }) {
            return (main, nil)
        }
        return nil
    }

    private static func primaryTarget(_ w: PFWorkout) -> String? {
        workStep(w).flatMap { target($0.step) }
    }

    private static func mainSet(_ w: PFWorkout) -> String? {
        guard let (step, reps) = workStep(w), let size = quantity(step) else { return nil }
        let at = target(step).map { " @ \($0)" } ?? ""
        return (reps.map { "\($0) \u{00D7} " } ?? "") + size + at
    }

    private static func quantity(_ s: PFStep) -> String? {
        if let m = s.distanceM {
            if m >= 1000 {
                let km = m / 1000
                return (km.rounded() == km ? String(Int(km)) : String(format: "%.1f", km)) + " km"
            }
            return "\(Int(m.rounded())) m"
        }
        if let secs = s.durationSec {
            let total = Int(secs.rounded())
            return total < 60 ? "\(total) s" : "\(total / 60) min"
        }
        return nil
    }

    private static func target(_ s: PFStep) -> String? {
        guard let low = s.targetLow else { return nil }
        let high = s.targetHigh
        let range = high != nil && high != low
        switch s.targetType ?? "" {
        case "heart_rate":
            return "HR \(Int(low.rounded()))" + (range ? "\u{2013}\(Int((high ?? low).rounded()))" : "")
        case "power":
            return "\(Int(low.rounded()))" + (range ? "\u{2013}\(Int((high ?? low).rounded()))" : "") + " W"
        default:
            let a = min(low, high ?? low), b = max(low, high ?? low)
            return PFFormat.pace(a) + (a != b ? "\u{2013}\(PFFormat.pace(b))" : "") + "/km"
        }
    }
}
