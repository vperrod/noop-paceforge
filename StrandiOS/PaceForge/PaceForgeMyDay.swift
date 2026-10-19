import Foundation
import SwiftUI
import StrandAnalytics

/// The iPhone's contribution to My Day: the PaceForge plan for the shown day, the activities it was matched
/// to, PaceForge's workout matches, its scale readings, its day notes and Garmin's Body Battery and stress.
/// The plan, matches and scale readings come from the copy PaceForge last saved on the phone. The day-events
/// and intraday files are asked of the server (a few seconds at most, a failure remembered for a minute) and
/// fall back to the saved copy, so My Day opens without waiting out a slow or absent server.
@MainActor
enum PFMyDay {
    /// Wires the shared My Day screen to this file and to the widget summary writer. Called once at launch.
    static func install() {
        MyDayExternalSource.provider = { dayStart in await inputs(for: dayStart) }
        MyDayWidgetBridge.publisher = { timeline in MyDaySummaryWriter.publish(timeline) }
        MyDayRideScreen.make = { rideId in AnyView(PFRideHost(rideId: rideId)) }
    }

    // MARK: Inputs

    static func inputs(for dayStart: Date) async -> MyDayExternalInputs {
        guard PFAPI.isConfigured, let loaded = await loadSnapshot() else { return MyDayExternalInputs() }
        let snapshot = loaded.snapshot
        let dayISO = PFFormat.isoString(dayStart)
        var out = MyDayExternalInputs()

        // day-events.json and the intraday file are optional: an older server serves neither and My Day then
        // shows the plan and the scale as before.
        async let eventsRequest = cachedOrFetched("data/day-events.json")
        async let intradayRequest = intraday(for: dayISO)
        let eventsDocument = PFJ(data: await eventsRequest)
        let events = PFWave3Parse.dayEvents(eventsDocument).filter { $0.date == dayISO }
        let slots = PFDayMerge.planned(events, day: dayISO)
        out.rides = rides(events: PFRideParse.dayRideEvents(eventsDocument).filter { $0.date == dayISO },
                          snapshot: snapshot, dayISO: dayISO)

        let sessions = snapshot.weeks.flatMap(\.days).filter { $0.date == dayISO }.flatMap(\.workouts)
        let known = Set(sessions.map(\.id))
        out.planned = sessions.filter { $0.status != "optional" }.map { plannedInput($0, slot: slots[$0.id]) }
        // A day outside the three weeks the tab loads still has its plan in day-events.json.
        let unseen = slots.values.filter { event in
            guard let id = event.sessionId else { return false }
            return !known.contains(id) && event.state != "optional"
        }
        out.planned += unseen
            .sorted { ($0.startTs ?? 0, $0.sessionId ?? "") < ($1.startTs ?? 0, $1.sessionId ?? "") }
            .map { plannedFromEvent($0) }
        out.planActivities = loaded.planActivities
        out.canonicalOf = await workoutMatches()

        var weighIns: [PFDayMerge.WeighIn] = []
        for reading in snapshot.body?.series ?? [] where reading.date.hasPrefix(dayISO) {
            guard let kg = reading.values["weight_kg"] else { continue }
            let stamp = reading.date.count > 10 ? parse(reading.date).map { Safe.int($0.timeIntervalSince1970, .towardZero) } : nil
            weighIns.append(PFDayMerge.WeighIn(ts: stamp, kg: kg))
        }
        out.weighIns = PFDayMerge.mergeWeighIns(existing: weighIns, events: PFDayMerge.weighIns(events, day: dayISO))
            .map { DayTimeline.Input.WeighIn(ts: $0.ts, kg: $0.kg, source: .paceforge) }
        out.notes = PFDayMerge.notes(events, day: dayISO).map {
            DayTimeline.Input.Note(id: $0.id, ts: $0.ts, title: $0.title, subtitle: $0.subtitle, source: .paceforge)
        }

        if let intraday = await intradayRequest {
            out.energy = intraday.energy.map { DayTimeline.SeriesPoint(ts: $0.ts, value: $0.value) }
            out.garminStress = intraday.stress.map { DayTimeline.SeriesPoint(ts: $0.ts, value: $0.value) }
            out.recharge = intraday.lastRecharge.map {
                DayTimeline.Recharge(startTs: $0.startTs, endTs: $0.endTs, from: $0.from, to: $0.to, minutes: $0.minutes)
            }
        }
        return out
    }

    /// `slot` is the same session's row in day-events.json, which carries the clock time when the plan has one.
    private static func plannedInput(_ w: PFWorkout, slot: PFDayEvent?) -> DayTimeline.Input.Planned {
        // A session PaceForge marks done with no activity attached still happened; the placeholder id only
        // tells the builder it is done.
        let done = w.status == "done" || w.status == "partial"
        let attachedId = w.activityId ?? slot?.matchedActivityId
        let matched: [String] = attachedId.map { [$0] } ?? (done ? ["pf-done"] : [])
        let minutes = w.durationMin ?? slot?.durationMin
        return DayTimeline.Input.Planned(id: w.id, title: w.name ?? "Workout", detail: PFSummaryWriter.detail(w),
                                         startTs: slot?.startTs, durationMin: minutes.map { Safe.int($0) },
                                         matchedActivityIds: matched)
    }

    /// A planned session known only from day-events.json.
    private static func plannedFromEvent(_ event: PFDayEvent) -> DayTimeline.Input.Planned {
        let minutes = event.durationMin.map { Safe.int($0) }
        let done = event.state == "done"
        let matched = event.matchedActivityId.map { [$0] } ?? (done ? ["pf-done"] : [])
        return DayTimeline.Input.Planned(id: event.sessionId ?? event.id ?? "plan", title: event.title ?? "Workout",
                                         detail: minutes.map { "\($0) min" }, startTs: event.startTs,
                                         durationMin: minutes, matchedActivityIds: matched)
    }

    nonisolated private static func planActivity(_ a: PFActivity) -> DayTimeline.Input.PlanActivity? {
        guard let start = a.startTime.flatMap(parse), let seconds = a.durationS, seconds > 0 else { return nil }
        let startTs = Safe.int(start.timeIntervalSince1970, .towardZero)
        return DayTimeline.Input.PlanActivity(id: a.id, startTs: startTs, endTs: startTs + Safe.int(seconds, .towardZero))
    }

    /// `canonical_of` from PaceForge's workout-matches.json: "noop:<device>:<startTs>:<sport>" -> Garmin id.
    /// Empty when the server does not serve the file (older servers) or it was never fetched.
    private static func workoutMatches() async -> [String: String] {
        let data: Data? = PFAPI.isFixture ? await PFAPI.fetchOptional("data/workout-matches.json")
                                          : PFStore.read(path: "data/workout-matches.json")
        return PFJ(data: data)["canonical_of"].dict.compactMapValues { $0.idString }
    }

    // MARK: Day events and intraday

    /// The shown day's bike rides: the ride rows of day-events.json (from the server when it answers, else the
    /// copy saved on the phone), then any ride in ride-metrics.json that day-events did not list.
    private static func rides(events: [PFRideEvent], snapshot: PFSnapshot, dayISO: String) -> [DayTimeline.Input.Ride] {
        var out: [DayTimeline.Input.Ride] = []
        var seen = Set<String>()
        for event in events where seen.insert(event.rideId).inserted {
            let known = snapshot.rides.first { $0.id == event.rideId }
            var figures = PFRide(id: event.rideId, dateKey: event.date)
            figures.avgPower = event.avgPower ?? known?.avgPower
            figures.np = event.np ?? known?.np
            figures.tss = event.tss ?? known?.tss
            figures.avgHr = event.avgHr ?? known?.avgHr
            let seconds: Double? = event.durationMin.map { $0 * 60 } ?? known?.durationS
            figures.durationS = seconds
            out.append(DayTimeline.Input.Ride(
                id: event.rideId, title: event.title ?? known?.title ?? "Ride",
                detail: figures.rowLine.isEmpty ? nil : figures.rowLine,
                startTs: event.startTs, endTs: event.endTs, durationSec: seconds.map { Safe.int($0, .towardZero) },
                avgHr: figures.avgHr.map { Safe.int($0) }))
        }
        for ride in snapshot.rides(on: dayISO) where seen.insert(ride.id).inserted {
            out.append(DayTimeline.Input.Ride(
                id: ride.id, title: ride.title, detail: ride.rowLine.isEmpty ? nil : ride.rowLine,
                durationSec: ride.durationS.map { Safe.int($0, .towardZero) }, avgHr: ride.avgHr.map { Safe.int($0) }))
        }
        return out
    }

    /// Garmin's Body Battery and stress for the shown day: `intraday-today.json` for today, else that day's own
    /// file. A finished day saved as final is read from the phone without asking the server again. A file that
    /// names a different day is ignored, so two days never share a curve.
    private static func intraday(for dayISO: String) async -> PFIntraday? {
        let isToday = dayISO == PFAPI.todayISO
        let path = isToday ? "data/intraday-today.json" : "data/intraday/\(dayISO).json"
        if !isToday, !PFAPI.isFixture, let saved = PFStore.read(path: path),
           let parsed = PFWave3Parse.intraday(PFJ(data: saved)), parsed.isFinal, parsed.date == dayISO {
            return parsed
        }
        guard let data = await cachedOrFetched(path), let parsed = PFWave3Parse.intraday(PFJ(data: data)) else { return nil }
        if let named = parsed.date, named != dayISO { return nil }
        return parsed
    }

    /// The file from the server when it answers within a few seconds, else the copy saved on the phone. My
    /// Day opens without waiting out a slow or absent server.
    private static func cachedOrFetched(_ path: String, within seconds: Double = 4) async -> Data? {
        // The screen reloads on every toggle and refresh; a file asked for a few seconds ago is reused.
        if let hit = recent[path], Date().timeIntervalSince(hit.at) < 30 { return hit.data }
        // A server that just failed to answer is not asked again for a minute, so a hung one costs one wait.
        let recentlyFailed = failed[path].map { Date().timeIntervalSince($0) < 60 } ?? false
        let fresh: Data?
        if recentlyFailed { fresh = nil } else { fresh = await fetchOptional(path, within: seconds) }
        if let fresh {
            recent[path] = (Date(), fresh)
            failed[path] = nil
            return fresh
        }
        if !recentlyFailed { failed[path] = Date() }
        return PFAPI.isFixture ? nil : PFStore.read(path: path)
    }

    /// The server's answer, or nil when it has none or has not answered within `seconds`.
    private static func fetchOptional(_ path: String, within seconds: Double) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { await PFAPI.fetchOptional(path) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static var recent: [String: (at: Date, data: Data)] = [:]
    private static var failed: [String: Date] = [:]

    // MARK: Snapshot

    /// The snapshot and its activities as My Day spans (one date parse per activity), built together off the main thread.
    private struct Loaded {
        let snapshot: PFSnapshot
        let planActivities: [DayTimeline.Input.PlanActivity]
    }

    private static var cached: (stamp: Date?, today: String, loaded: Loaded)?

    /// The build in flight, so callers that arrive while it runs share it (at launch Today, My Day and the widget writer each asked
    /// for it before the first had cached, and each built the whole snapshot: 30 builds in one launch).
    private static var building: (stamp: Date?, today: String, task: Task<Loaded?, Never>)?

    private static func loadSnapshot() async -> Loaded? {
        let today = PFAPI.todayISO
        let stamp = PFStore.savedAt(path: "api/state")
        if let cached, cached.stamp == stamp, cached.today == today, !PFAPI.isFixture { return cached.loaded }
        if let building, building.stamp == stamp, building.today == today, !PFAPI.isFixture {
            return await building.task.value
        }
        // Read, parsed and built off the main thread: NOOP Today's My Day section asks for this whenever the saved documents
        // changed (every PaceForge refresh rewrites them), and on the main thread it stalled Today.
        let isFixture = PFAPI.isFixture
        let task = Task.detached(priority: .userInitiated) { () -> Loaded? in
            let bundle: PFRawBundle?
            if isFixture {
                bundle = try? await PFAPI.fetchBundle()
            } else {
                bundle = NoopDiag.measure("myday.pf.cache.read") { PFStore.cachedBundle() }
            }
            guard let bundle,
                  let snapshot = NoopDiag.measure("myday.pf.build", { PFBuilder.snapshot(from: bundle, today: today) })
            else { return nil }
            return Loaded(snapshot: snapshot, planActivities: snapshot.activities.values.compactMap(planActivity))
        }
        building = (stamp, today, task)
        let built = await task.value
        if building?.stamp == stamp, building?.today == today { building = nil }
        guard let built else { return nil }
        cached = (stamp, today, built)
        return built
    }

    // MARK: Dates

    /// "2030-03-11T07:10:00" is the phone's local time; a stamp with a zone is read as written.
    /// Made once: building three formatters per call (once per activity, hundreds per My Day load) was the costliest
    /// NOOP function on the main thread while Today and My Day loaded. Date formatters are thread-safe.
    nonisolated(unsafe) private static let zoned: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()
    nonisolated(unsafe) private static let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    nonisolated static func parse(_ text: String) -> Date? {
        if let d = zoned.date(from: text) ?? plain.date(from: text) { return d }
        return local.date(from: text)
    }
}
