import SwiftUI
import StrandDesign

// "Today so far": a read-only mini 24 h strip and a planned-versus-done line for the PaceForge Today
// screen. It uses only what the PaceForge snapshot already holds (today's sessions, the activities that
// started today, last night's sleep hours, when the brief was last written) and reads nothing from NOOP's
// database, so it draws the same with or without a strap. "Open My Day" is the way across to NOOP's own
// timeline of the day.

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
    /// Today's version: no strip (the day graph above is the timeline) and no "Open My Day" button; the card draws only while something
    /// was recorded today.
    var isRecordedOnly = false
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @State private var opened: PFWorkout?

    private var model: PFTodaySoFar { PFTodaySoFar.make(from: snapshot) }

    /// What the watch recorded today, in the order it started.
    private var recorded: [PFActivity] {
        snapshot.activities.values
            .filter { $0.startTime?.hasPrefix(snapshot.todayISO) == true }
            .sorted { ($0.startTime ?? "") < ($1.startTime ?? "") }
    }

    var body: some View {
        if !isRecordedOnly || !recorded.isEmpty {
            PFCard("Today so far", icon: "clock") {
                VStack(alignment: .leading, spacing: 10) {
                    PFTodaySoFarContent(model: model, showsStrip: !isRecordedOnly)
                    ForEach(recorded, id: \.id) { activity in recordedRow(activity) }
                }
            }
            .accessibilityElement(children: .contain)
            .containerIdentifier("pf-sofar-card")
            .sheet(item: $opened) { workout in
                PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: PFResultsSheet.askCoach(coach, router))
            }
        }
    }

    /// One recording with its numbers; a tap opens its results, as a done session does in the plan.
    private func recordedRow(_ activity: PFActivity) -> some View {
        Button { opened = PFAlertActivityRouter.workout(for: activity, in: snapshot) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name ?? PFFormat.words(activity.type ?? "Activity"))
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(metricsLine(activity))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-sofar-activity-\(activity.id)")
    }

    /// "08:12, 10.2 km, 52:10, 5:07 /km, 148 bpm, Garmin" joined with middle dots.
    private func metricsLine(_ activity: PFActivity) -> String {
        var parts: [String] = []
        if let time = PFFormat.timeOfDay(activity.startTime) { parts.append(time) }
        if let meters = activity.distanceM, meters > 0 { parts.append("\(PFFormat.oneDecimal(meters / 1000)) km") }
        if let seconds = activity.durationS, seconds > 0 { parts.append(PFFormat.clock(seconds)) }
        if activity.isRun, let pace = activity.avgPaceSecPerKm, pace > 0 { parts.append("\(PFFormat.pace(pace)) /km") }
        if let hr = activity.avgHr, hr > 0 { parts.append("\(Safe.int(hr)) bpm") }
        parts.append(PFRecording.source(activity))
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// The card's contents, a type of its own so the card's generic type stays small.
private struct PFTodaySoFarContent: View {
    let model: PFTodaySoFar
    var showsStrip = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsStrip {
                PFMiniStrip(model: model)
                    .frame(height: 34)
            }
            Text(planLine)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityIdentifier("pf-sofar-plan")
            if let detail = detailLine {
                Text(detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsStrip { openMyDay }
        }
    }

    private var openMyDay: some View {
        Button { MyDayDeepLink.open() } label: {
            Label("Open My Day", systemImage: "calendar.day.timeline.left")
                .font(StrandFont.subhead)
        }
        .buttonStyle(.bordered)
        .tint(StrandPalette.accent)
        .accessibilityIdentifier("pf-open-myday")
    }

    /// "Race today: <name>", "1 of 2 sessions done", or "Nothing planned today". A race day counts the race as the plan.
    private var planLine: String {
        let sessions = model.planned > 0
            ? "\(model.done) of \(model.planned) session\(model.planned == 1 ? "" : "s") done" : nil
        if let race = model.raceName { return ["Race today: \(race)", sessions].compactMap { $0 }.joined(separator: " \u{00B7} ") }
        return sessions ?? "Nothing planned today"
    }

    /// "Still to do: Synthetic 4 x 800 m. Slept 7h20 of 8h00. Brief written 08:12."
    private var detailLine: String? {
        var parts: [String] = []
        if !model.pending.isEmpty { parts.append("Still to do: " + model.pending.joined(separator: ", ") + ".") }
        if let sleep = model.sleepText { parts.append("Slept \(sleep).") }
        if let time = model.briefTime { parts.append("Brief written \(time).") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// The 24 h track: activities as bands, the brief as a diamond, now as a line. Labelled for VoiceOver.
private struct PFMiniStrip: View {
    let model: PFTodaySoFar

    var body: some View {
        Canvas { context, size in
            let track = CGRect(x: 0, y: 4, width: size.width, height: size.height - 18)
            context.fill(Path(roundedRect: track, cornerRadius: 8), with: .color(StrandPalette.surfaceInset))
            for hour in [6, 12, 18] {
                let x = size.width * CGFloat(hour) / 24
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: track.minY))
                tick.addLine(to: CGPoint(x: x, y: track.maxY))
                context.stroke(tick, with: .color(StrandPalette.hairline), lineWidth: 0.5)
                context.draw(Text(String(format: "%02d", hour)).font(StrandFont.caption)
                                .foregroundColor(StrandPalette.textTertiary),
                             at: CGPoint(x: x, y: size.height - 2), anchor: .bottom)
            }
            for band in model.bands {
                let x0 = size.width * CGFloat(band.from)
                let x1 = max(size.width * CGFloat(band.to), x0 + 4)
                context.fill(Path(roundedRect: CGRect(x: x0, y: track.minY + 3, width: x1 - x0, height: track.height - 6),
                                  cornerRadius: 4),
                             with: .color(PFColor.positive.opacity(0.85)))
            }
            if let f = model.briefFraction {
                let x = size.width * CGFloat(f)
                var diamond = Path()
                diamond.move(to: CGPoint(x: x, y: track.midY - 5))
                diamond.addLine(to: CGPoint(x: x + 5, y: track.midY))
                diamond.addLine(to: CGPoint(x: x, y: track.midY + 5))
                diamond.addLine(to: CGPoint(x: x - 5, y: track.midY))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(PFColor.sky))
            }
            if let f = model.nowFraction {
                let x = size.width * CGFloat(f)
                var now = Path()
                now.move(to: CGPoint(x: x, y: track.minY - 2))
                now.addLine(to: CGPoint(x: x, y: track.maxY))
                context.stroke(now, with: .color(StrandPalette.accent), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Today so far"]
        if !model.bands.isEmpty { parts.append(model.bands.map(\.title).joined(separator: ", ") + " done") }
        if let time = model.briefTime { parts.append("brief written at \(time)") }
        return parts.joined(separator: ", ")
    }
}
