import Foundation
import WidgetKit

/// Turns a fetched PaceForge snapshot into the small App Group summary the widgets, Siri and Shortcuts
/// read, writes it, and asks WidgetKit to reload the PaceForge widgets.
enum PFSummaryWriter {
    static func publish(_ snapshot: PFSnapshot) {
        make(from: snapshot, previous: PFSummary.load()).save()
        for kind in PFWidgetKind.all { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        Task { @MainActor in
            await PFReminders.update(for: snapshot)
            // Heart recovery for Siri comes from the phone's own workouts; it has to be written after the
            // summary above, which carries the previous value over rather than computing a new one.
            if let model = AppModel.shared {
                await PFHeartRecovery.updateSummary(repo: model.repo, hrMax: model.profile.hrMax)
            }
        }
    }

    /// Applies a changed privacy choice to the saved summary at once, so the body widget follows without
    /// waiting for the next fetch.
    static func applyPrivacy() {
        guard var summary = PFSummary.load() else { return }
        summary.hideBody = hidesBody(server: summary.serverHidesBody)
        summary.hideScores = HideScoresPrefs.isOn(.scores)
        summary.save()
        for kind in PFWidgetKind.all { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }

    /// The Lock Screen privacy choice, or the Settings > Hide numbers body switch: either one hides body figures.
    private static func hidesBody(server: Bool?) -> Bool {
        PFPrivacy.hidesBody(server: server, choice: PFPrivacy.savedOverride()) || HideScoresPrefs.isOn(.body)
    }

    /// `previous` is the file this one replaces. The server serves no per-night HRV history, so the
    /// trend widget keeps the nights it has seen, and a heart-recovery reading the app computed from the
    /// phone's own workouts is carried over rather than lost on every fetch.
    static func make(from s: PFSnapshot, previous: PFSummary? = nil, now: Date = Date()) -> PFSummary {
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
        out.ctl = s.insights.ctl
        out.atl = s.insights.atl
        addWeek(to: &out, from: s)
        addNights(to: &out, from: s, previous: previous)
        out.body = bodyReading(s.body)
        out.heartRecovery = previous?.heartRecovery
        out.hrr1 = latestHRR1(in: s)
        out.standing = PFGlanceBuilder.standing(s.standing)
        out.garminRecovery = PFGlanceBuilder.garminRecovery(s.activities.values.map {
            PFGlanceBuilder.Activity(name: $0.name, startTime: $0.startTime, hrrGarmin: $0.hrrGarmin)
        })
        out.rides = PFGlanceBuilder.rides(s.rides, sessions: glanceSessions(in: s), today: s.todayISO)
        out.openAlerts = s.alerts.count
        out.answerTrain = s.readiness?.answers?.train?.level.word
        out.answerHard = s.readiness?.answers?.trainHard?.level.word
        if let week = s.raceWeek { out.raceWeek = PFSummary.RaceWeek(title: week.event.name, line: week.summaryLine) }
        out.serverHidesBody = s.serverHidesBody
        out.hideBody = hidesBody(server: s.serverHidesBody)
        out.hideScores = HideScoresPrefs.isOn(.scores)
        if let next = nextSession(in: s) {
            out.nextSession = next.session
            out.nextSessionDate = next.date
        }
        return out
    }

    /// The first-minute recovery of the newest session that has a scored `post` figure. Walking, interval
    /// and not-measurable results never reach the widget.
    private static func latestHRR1(in s: PFSnapshot) -> PFSummary.HRR1? {
        let newest = s.activities.values
            .filter { $0.hrr1?.kind == PFHRR1.post && $0.hrr1?.bpm != nil }
            .max { ($0.startTime ?? "") < ($1.startTime ?? "") }
        guard let activity = newest, let hrr = activity.hrr1, let bpm = hrr.bpm else { return nil }
        return PFSummary.HRR1(bpm: bpm, kind: hrr.kind, band: hrr.personalBand, sessionName: activity.name,
                              date: activity.startTime.map { String($0.prefix(10)) })
    }

    private static func addWeek(to out: inout PFSummary, from s: PFSnapshot) {
        guard s.weeks.indices.contains(s.currentWeekIndex) else { return }
        let week = s.weeks[s.currentWeekIndex]
        var doneMinutes = 0.0
        var plannedMinutes = 0.0
        out.weekDays = week.days.map { day in
            let planned = day.workouts.filter { $0.status != "optional" }
            let done = planned.filter { $0.status == "done" || $0.status == "partial" }
            for w in planned {
                let isDone = w.status == "done" || w.status == "partial"
                plannedMinutes += w.durationMin ?? 0
                if isDone { doneMinutes += w.compliance?.actualMin ?? w.durationMin ?? 0 }
            }
            return PFSummary.WeekDay(date: day.date, label: String(day.dow.prefix(1)).uppercased(),
                                     planned: planned.count, done: done.count, isToday: day.date == s.todayISO)
        }
        out.weekDoneMinutes = doneMinutes
        // The week's own target when the plan states one, else what its sessions add up to.
        let hours = week.targetHours ?? week.plannedHours
        out.weekTargetMinutes = hours.map { $0 * 60 } ?? (plannedMinutes > 0 ? plannedMinutes : nil)
    }

    private static func addNights(to out: inout PFSummary, from s: PFSnapshot, previous: PFSummary?) {
        let t = s.today
        var hrvByDate: [String: Double] = [:]
        for night in previous?.nights ?? [] {
            if let hrv = night.hrv { hrvByDate[night.date] = hrv }
        }
        if let hrv = t.hrv { hrvByDate[s.todayISO] = hrv }
        let sleepByDate = Dictionary(s.sleepNights.map { ($0.date, $0.minutes) }, uniquingKeysWith: { _, last in last })
        let oldest = PFFormat.addDays(s.todayISO, -14)
        let dates = Set(sleepByDate.keys).union(hrvByDate.keys)
            .filter { $0 <= s.todayISO && $0 > oldest }
            .sorted()
            .suffix(7)
        out.nights = dates.map { PFSummary.Night(date: $0, sleepMinutes: sleepByDate[$0], hrv: hrvByDate[$0]) }
        out.sleepNeedMinutes = t.sleep?.needText.flatMap(minutes(fromHoursText:))
        out.hrvBaseline = t.hrvBaselineMs
        out.hrvLow = t.hrvLowMs
        out.hrvHigh = t.hrvHighMs
    }

    /// "8h00" or "7h20" as minutes.
    private static func minutes(fromHoursText text: String) -> Double? {
        let parts = text.lowercased().split(separator: "h", omittingEmptySubsequences: false)
        guard parts.count == 2, let hours = Double(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        let rest = Double(parts[1].filter(\.isNumber)) ?? 0
        return hours * 60 + rest
    }

    private static func bodyReading(_ body: PFBodyDoc?) -> PFSummary.BodyReading? {
        guard let body else { return nil }
        let last = body.series.last?.values ?? [:]
        let before = body.series.dropLast().last?.values ?? [:]
        func change(_ key: String) -> Double? {
            guard let a = last[key], let b = before[key] else { return nil }
            return a - b
        }
        return PFSummary.BodyReading(date: body.date, score: body.score, band: body.band,
                                     weightKg: body.latest["weight_kg"], weightDelta: change("weight_kg"),
                                     fatPct: body.latest["body_fat_pct"], fatPctDelta: change("body_fat_pct"))
    }

    /// Every planned session in the loaded weeks, for the next-ride pick.
    private static func glanceSessions(in s: PFSnapshot) -> [PFGlanceBuilder.Session] {
        s.weeks.flatMap(\.days).flatMap { day in
            day.workouts.map { w in
                PFGlanceBuilder.Session(name: w.name ?? "Ride", sport: w.sport, kind: w.kind, date: day.date,
                                        isOpen: w.status != "optional" && w.status != "done" && w.status != "partial",
                                        detail: detail(w), target: primaryTarget(w))
            }
        }
    }

    /// The first session still to do after today, with its day.
    private static func nextSession(in s: PFSnapshot) -> (session: PFSummary.Session, date: String)? {
        let upcoming = s.weeks.flatMap(\.days)
            .filter { $0.date > s.todayISO }
            .sorted { $0.date < $1.date }
        for day in upcoming {
            if let w = day.workouts.first(where: { $0.status != "optional" && $0.status != "done" && $0.status != "partial" }) {
                let session = PFSummary.Session(name: w.name ?? "Workout", sport: w.sport ?? w.kind, detail: detail(w),
                                                target: primaryTarget(w), mainSet: mainSet(w), done: false)
                return (session, day.date)
            }
        }
        return nil
    }

    static func detail(_ w: PFWorkout) -> String? {
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

    static func primaryTarget(_ w: PFWorkout) -> String? {
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
