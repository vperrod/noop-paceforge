import Foundation
import StrandAnalytics

/// The iPhone's contribution to My Day: the PaceForge plan for the shown day, the activities it was matched
/// to, PaceForge's workout matches and its scale readings. Read from the copy PaceForge last saved on the
/// phone; My Day never goes to the network for this (the PaceForge tab refreshes it).
@MainActor
enum PFMyDay {
    /// Wires the shared My Day screen to this file and to the widget summary writer. Called once at launch.
    static func install() {
        MyDayExternalSource.provider = { dayStart in await inputs(for: dayStart) }
        MyDayWidgetBridge.publisher = { timeline in MyDaySummaryWriter.publish(timeline) }
    }

    // MARK: Inputs

    static func inputs(for dayStart: Date) async -> MyDayExternalInputs {
        guard PFAPI.isConfigured, let snapshot = await loadSnapshot() else { return MyDayExternalInputs() }
        let dayISO = PFFormat.isoString(dayStart)
        var out = MyDayExternalInputs()

        let sessions = snapshot.weeks.flatMap(\.days).filter { $0.date == dayISO }.flatMap(\.workouts)
        out.planned = sessions.filter { $0.status != "optional" }.map(plannedInput)
        out.planActivities = snapshot.activities.values.compactMap(planActivity)
        out.canonicalOf = await workoutMatches()

        for reading in snapshot.body?.series ?? [] where reading.date.hasPrefix(dayISO) {
            guard let kg = reading.values["weight_kg"] else { continue }
            let stamp = reading.date.count > 10 ? parse(reading.date).map { Int($0.timeIntervalSince1970) } : nil
            out.weighIns.append(DayTimeline.Input.WeighIn(ts: stamp, kg: kg, source: .paceforge))
        }
        return out
    }

    private static func plannedInput(_ w: PFWorkout) -> DayTimeline.Input.Planned {
        // A session PaceForge marks done with no activity attached still happened; the placeholder id only
        // tells the builder it is done.
        let done = w.status == "done" || w.status == "partial"
        let matched = w.activityId.map { [$0] } ?? (done ? ["pf-done"] : [])
        return DayTimeline.Input.Planned(id: w.id, title: w.name ?? "Workout", detail: PFSummaryWriter.detail(w),
                                         durationMin: w.durationMin.map { Int($0.rounded()) },
                                         matchedActivityIds: matched)
    }

    private static func planActivity(_ a: PFActivity) -> DayTimeline.Input.PlanActivity? {
        guard let start = a.startTime.flatMap(parse), let seconds = a.durationS, seconds > 0 else { return nil }
        let startTs = Int(start.timeIntervalSince1970)
        return DayTimeline.Input.PlanActivity(id: a.id, startTs: startTs, endTs: startTs + Int(seconds))
    }

    /// `canonical_of` from PaceForge's workout-matches.json: "noop:<device>:<startTs>:<sport>" -> Garmin id.
    /// Empty when the server does not serve the file (older servers) or it was never fetched.
    private static func workoutMatches() async -> [String: String] {
        let data: Data? = PFAPI.isFixture ? await PFAPI.fetchOptional("data/workout-matches.json")
                                          : PFStore.read(path: "data/workout-matches.json")
        return PFJ(data: data)["canonical_of"].dict.compactMapValues { $0.idString }
    }

    // MARK: Snapshot

    private static var cached: (stamp: Date?, today: String, snapshot: PFSnapshot)?

    private static func loadSnapshot() async -> PFSnapshot? {
        let today = PFAPI.todayISO
        let stamp = PFStore.savedAt(path: "api/state")
        if let cached, cached.stamp == stamp, cached.today == today, !PFAPI.isFixture { return cached.snapshot }
        let bundle: PFRawBundle?
        if PFAPI.isFixture {
            bundle = try? await PFAPI.fetchBundle()
        } else {
            bundle = PFStore.cachedBundle()
        }
        guard let bundle, let built = PFBuilder.snapshot(from: bundle, today: today) else { return nil }
        cached = (stamp, today, built)
        return built
    }

    // MARK: Dates

    /// "2030-03-11T07:10:00" is the phone's local time; a stamp with a zone is read as written.
    static func parse(_ text: String) -> Date? {
        let zoned = ISO8601DateFormatter()
        zoned.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        if let d = zoned.date(from: text) ?? plain.date(from: text) { return d }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: text)
    }
}
