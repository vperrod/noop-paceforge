import SwiftUI
import StrandDesign

// "Today so far": the plan line for the PaceForge Today screen. It uses only what the PaceForge snapshot already holds (today's sessions,
// the race of the day, when the brief was last written) and reads nothing from NOOP's database, so it draws the same with or without a
// strap. Build 529 took the mini strip and "Open My Day" (the day graph under the rings is the one timeline), the "still to do" and
// "Slept" lines (the Today card and How you are carry them) and the recorded rows (Today's workouts is the one list) off it.

struct PFTodaySoFar: Equatable {
    struct Band: Equatable, Identifiable {
        let id: String
        let title: String
        /// 0...1 across the day.
        let from: Double
        let to: Double
    }

    var bands: [Band] = []
    var planned = 0
    var done = 0
    /// Today's race, when today is a race day: the race is the plan, whether or not any session is planned beside it.
    var raceName: String?
    /// Names of the sessions still to do.
    var pending: [String] = []
    /// "7h20 of 8h00", or just the hours when the need is not known.
    var sleepText: String?
    var briefFraction: Double?
    var briefTime: String?
    /// Where the clock is across the day, only when the snapshot is for today.
    var nowFraction: Double?

    var hasAnything: Bool { planned > 0 || raceName != nil || !bands.isEmpty || sleepText != nil || briefFraction != nil }

    static func make(from s: PFSnapshot, now: Date = Date(), calendar: Calendar = .current) -> PFTodaySoFar {
        var out = PFTodaySoFar()
        let dayStart = calendar.startOfDay(for: PFFormat.date(s.todayISO))
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return out }
        let length = dayEnd.timeIntervalSince(dayStart)
        func fraction(_ date: Date) -> Double {
            min(max(date.timeIntervalSince(dayStart) / length, 0), 1)
        }

        let sessions = s.today.sessions.filter { $0.status != "optional" }
        out.planned = sessions.count
        out.done = sessions.filter { $0.status == "done" || $0.status == "partial" }.count
        let call = s.todayCall ?? PFTodayCallParse.fallback(from: s)
        if call.today.kind == "race" { out.raceName = call.today.title ?? call.nextRace?.name ?? "race day" }
        out.pending = sessions.filter { $0.status != "done" && $0.status != "partial" }.map { $0.name ?? "Workout" }

        for activity in s.activities.values {
            guard let text = activity.startTime, text.hasPrefix(s.todayISO),
                  let start = PFMyDay.parse(text), let seconds = activity.durationS, seconds > 0 else { continue }
            out.bands.append(Band(id: activity.id, title: activity.name ?? "Activity", from: fraction(start),
                                  to: fraction(start.addingTimeInterval(seconds))))
        }
        out.bands.sort { $0.from < $1.from }

        if let sleep = s.today.sleep, let hours = sleep.hoursText {
            out.sleepText = sleep.needText.map { "\(hours) of \($0)" } ?? hours
        }
        if let stamp = s.today.brief?.updatedAt, stamp.hasPrefix(s.todayISO), let when = PFMyDay.parse(stamp) {
            out.briefFraction = fraction(when)
            out.briefTime = PFFormat.timeOfDay(stamp)
        }
        if s.todayISO == PFFormat.isoString(now) { out.nowFraction = fraction(now) }
        return out
    }
}

struct PFTodaySoFarCard: View {
    let snapshot: PFSnapshot

    private var model: PFTodaySoFar { PFTodaySoFar.make(from: snapshot) }

    var body: some View {
        PFCard("Today so far", icon: "clock") {
            PFTodaySoFarContent(model: model)
        }
        .accessibilityElement(children: .contain)
        .containerIdentifier("pf-sofar-card")
    }
}

/// The card's contents, a type of its own so the card's generic type stays small.
private struct PFTodaySoFarContent: View {
    let model: PFTodaySoFar

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(planLine)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityIdentifier("pf-sofar-plan")
            if let time = model.briefTime {
                Text("Brief written \(time).")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Race today: <name>", "1 of 2 sessions done", or "Nothing planned today". A race day counts the race as the plan.
    private var planLine: String {
        let sessions = model.planned > 0
            ? "\(model.done) of \(model.planned) session\(model.planned == 1 ? "" : "s") done" : nil
        if let race = model.raceName { return ["Race today: \(race)", sessions].compactMap { $0 }.joined(separator: " \u{00B7} ") }
        return sessions ?? "Nothing planned today"
    }
}
