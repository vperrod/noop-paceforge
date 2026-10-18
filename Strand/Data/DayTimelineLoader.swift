import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// MARK: - My Day loader
//
// Reads one calendar day out of the store (and the on-device logs) into the plain inputs of the pure
// `DayTimeline` builder, then builds it. All the rules live in the builder (StrandAnalytics); this file
// only knows where each input comes from, so it stays free of decisions the tests cannot reach.

/// Inputs a platform layer adds to a My Day load. On iPhone this is the PaceForge plan and its workout
/// matches; macOS adds nothing and the day is built from the store alone.
struct MyDayExternalInputs {
    var planned: [DayTimeline.Input.Planned] = []
    /// Bike rides PaceForge logged without a Garmin activity; each opens the ride screen.
    var rides: [DayTimeline.Input.Ride] = []
    var planActivities: [DayTimeline.Input.PlanActivity] = []
    /// PaceForge's workout-matches.json `canonical_of`: "noop:<device>:<startTs>:<sport>" -> Garmin activity id.
    var canonicalOf: [String: String] = [:]
    var weighIns: [DayTimeline.Input.WeighIn] = []
    /// Notes from outside (a niggle PaceForge logged) and Garmin's Body Battery and stress, which the strip
    /// draws as curves of their own.
    var notes: [DayTimeline.Input.Note] = []
    var energy: [DayTimeline.SeriesPoint] = []
    var garminStress: [DayTimeline.SeriesPoint] = []
    var recharge: DayTimeline.Recharge?
}

enum MyDayExternalSource {
    /// Set once at launch by the iPhone app. Takes the start of the day being shown.
    @MainActor static var provider: ((Date) async -> MyDayExternalInputs)?
}

@MainActor
enum DayTimelineLoader {

    struct Options {
        /// Off for a surface that only wants the day's events (the Stress screen's context bands).
        var includeHeartRate = true
        /// The hourly stress curve reads a day of R-R and motion, so it is opt-in.
        var includeStress = false
        /// Detector suggestions, step buckets and battery. Off for a surface that only wants the events.
        var includeContext = true
        /// Max HR and zone 3 start from the profile; the loader adds the resting HR. Decides walk or workout.
        var segmentProfile = DetectedSegmentClassifier.Profile()
    }

    struct Loaded {
        let timeline: DayTimeline
        /// The stored row behind each `.workout(key:)` route.
        let workoutRows: [String: WorkoutRow]
        /// The suggestion behind each `.detected` event id.
        let detected: [String: DetectedWorkout]
    }

    static func load(repo: Repository, day: Date, options: Options = Options(), now: Date = Date(),
                     calendar: Calendar = .current) async -> Loaded {
        let bounds = DayTimeline.dayBounds(containing: day, calendar: calendar)
        let startTs = Int(bounds.start.timeIntervalSince1970)
        let endTs = Int(bounds.end.timeIntervalSince1970)
        let nowTs = Int(now.timeIntervalSince1970)
        let horizon = min(nowTs, endTs)
        let dayKey = Repository.localDayKey(bounds.start)
        let isToday = isLogicalToday(day: day, dayStart: bounds.start, now: now, calendar: calendar)
        // The repo reads are relative to now; the +3 pads a night that straddles midnight.
        let daysBack = max(0, Int(now.timeIntervalSince(bounds.start) / 86_400)) + 3

        var input = DayTimeline.Input(dayStart: bounds.start, dayEnd: bounds.end, now: now)
        input.detectsGaps = options.includeHeartRate
        input.syncPending = isToday
        let external = await MyDayExternalSource.provider?(bounds.start) ?? MyDayExternalInputs()

        // Heart rate, per-minute means.
        if options.includeHeartRate, horizon > startTs {
            let buckets = await repo.hrBuckets(from: startTs, to: horizon, bucketSeconds: 60)
            input.hr = buckets.map { DayTimeline.Input.HRSample(ts: $0.ts, bpm: $0.bpm) }
            input.hrSampleSpanSec = 60
        }

        // Sleep, split into the night and naps the way the Sleep tab splits them.
        let sessions = await repo.allSleepSessions(days: daysBack)
        let habitual = await habitualMidsleep(repo)
        let naps = napStarts(sessions, habitual: habitual, calendar: calendar)
        input.sleeps = sessions.compactMap { s -> DayTimeline.Input.Sleep? in
            guard s.endTs > startTs, s.effectiveStartTs < endTs else { return nil }
            let apple = (s.deviceId ?? "").lowercased().contains("apple")
            return DayTimeline.Input.Sleep(startTs: s.effectiveStartTs, endTs: s.endTs,
                                           isNap: naps.contains(s.startTs), source: apple ? .apple : .strap)
        }

        // Workouts.
        let rows = await repo.workoutRows(days: daysBack).filter { $0.endTs >= startTs && $0.startTs < endTs }
        var rowsByKey: [String: WorkoutRow] = [:]
        input.workouts = rows.map { row -> DayTimeline.Input.Workout in
            let key = workoutKey(row)
            rowsByKey[key] = row
            return DayTimeline.Input.Workout(
                key: key, startTs: row.startTs, endTs: row.endTs, title: WorkoutSource.displaySport(row.sport),
                sources: badges(for: row), avgHr: row.avgHr, maxHr: row.maxHr, kcal: row.energyKcal,
                distanceM: row.distanceM, externalId: paceForgeActivityId(row))
        }
        input.sameWorkoutPairs = pairs(from: external.canonicalOf, rows: rows)

        // Opt-in detector suggestions. Saved workouts are NOT passed to the detector: the builder compares each
        // window with them, so one a recorded workout covers shows as "Already recorded" instead of vanishing.
        let suggestions = options.includeContext
            ? await repo.autoDetectCandidates(from: startTs, to: horizon, savedSpans: []) : []
        var profile = options.segmentProfile
        if profile.restingHr == nil {
            profile.restingHr = repo.days.last(where: { $0.restingHr != nil })?.restingHr.map(Double.init)
        }
        input.segmentProfile = profile
        var detectedInputs: [DayTimeline.Input.Detected] = []
        for d in suggestions {
            let gait = await repo.gaitMix(from: d.startSec, to: d.endSec)
            detectedInputs.append(DayTimeline.Input.Detected(startTs: d.startSec, endTs: d.endSec, avgBpm: d.avgBpm,
                                                             peakBpm: d.peakBpm, gait: gait))
        }
        input.detected = detectedInputs
        var detectedByEvent: [String: DetectedWorkout] = [:]
        for d in suggestions { detectedByEvent["detected-\(d.startSec)-\(d.endSec)"] = d }

        // The plan, if the platform brought one.
        input.planned = external.planned
        input.rides = external.rides
        input.planActivities = external.planActivities
        input.weighIns = external.weighIns
        input.notes = external.notes
        input.energy = external.energy
        input.garminStress = external.garminStress
        input.recharge = external.recharge

        // Day-level and on-device logs.
        if let weight = await repo.appleDailyRows(days: daysBack).first(where: { $0.day == dayKey })?.weightKg {
            input.weighIns.append(.init(ts: nil, kg: weight, source: .apple))
        }
        input.caffeine = CaffeineLogStore.shared.intakes
            .filter { $0.at >= bounds.start && $0.at < bounds.end }
            .map { DayTimeline.Input.Caffeine(ts: Int($0.at.timeIntervalSince1970), mg: $0.mg) }
        if UserDefaults.standard.bool(forKey: HydrationStore.enabledKey) {
            input.water = repo.hydrationEntries(day: dayKey).map {
                DayTimeline.Input.Water(ts: Int($0.loggedAt.timeIntervalSince1970), ml: $0.amountMl)
            }
        }
        input.journal = await repo.journalEntries(days: daysBack)
            .filter { $0.day == dayKey }
            .map { DayTimeline.Input.JournalAnswer(label: $0.question, yes: $0.answeredYes) }

        if options.includeContext, let store = await repo.storeHandle() {
            let hours = (try? await store.appleStepHours(deviceId: Repository.appleHealthSource,
                                                         fromTs: startTs, toTs: endTs - 1)) ?? []
            input.steps = hours.map { DayTimeline.Input.StepBucket(ts: $0.ts, seconds: 3600, steps: $0.steps) }
            let battery = (try? await store.batterySamples(deviceId: repo.deviceId, from: startTs - 10_800,
                                                           to: endTs, limit: 4000)) ?? []
            input.battery = battery.map { DayTimeline.Input.Battery(ts: $0.ts, soc: $0.soc, charging: $0.charging) }
        }

        if options.includeStress, horizon > startTs {
            input.stress = await stressCurve(repo: repo, from: startTs, to: horizon, dayStart: bounds.start,
                                             calendar: calendar)
        }

        return Loaded(timeline: DayTimeline.build(input), workoutRows: rowsByKey, detected: detectedByEvent)
    }

    /// Saves, as Walk workouts, the walks the user asked to have saved by themselves (Settings, off by default):
    /// calm stretches classified as walks, 15 minutes or longer, finished, that no recorded workout covers.
    /// Returns how many were saved; the caller then reloads, where they show as ordinary Walk entries.
    static func autoSaveWalks(repo: Repository, loaded: Loaded, now: Date = Date()) async -> Int {
        let enabled = MyDayWalkPrefs.autoSaveEnabled
        guard enabled else { return 0 }
        let nowTs = Int(now.timeIntervalSince1970)
        var count = 0
        for event in loaded.timeline.events where event.kind == .detected {
            guard let suggestion = event.suggestion, let found = loaded.detected[event.id] else { continue }
            let length = found.endSec - found.startSec
            guard DetectedSegmentClassifier.shouldAutoSave(
                guess: suggestion.guess, isRecorded: suggestion.isRecorded, durationSec: length,
                endTs: found.endSec, nowTs: nowTs, enabled: enabled) else { continue }
            if await repo.saveDetectedWorkout(found, sport: DetectedSportChoice.walk.sportName) { count += 1 }
        }
        return count
    }

    /// True when the day being loaded is the logical day of `now` (it rolls over at the user's rollover hour,
    /// the same test My Day's stepper uses). Callers pass either an instant inside the day (the widget writer
    /// passes `now`) or the day's own midnight (My Day), so both reads count: the instant's logical day, and
    /// the loaded calendar day's start against the logical day's start.
    static func isLogicalToday(day: Date, dayStart: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let today = Repository.logicalDayStart(now, calendar: calendar)
        return dayStart == today || Repository.logicalDayStart(day, calendar: calendar) == today
    }

    // MARK: Sleep

    /// `habitualMidsleepSec` reads every sleep block, which the Sleep tab pays once per refresh; so do we.
    private static var habitualMemo: (seq: Int, value: Int?)?

    static func habitualMidsleep(_ repo: Repository) async -> Int? {
        if let memo = habitualMemo, memo.seq == repo.refreshSeq { return memo.value }
        let value = await repo.habitualMidsleepSec()
        habitualMemo = (repo.refreshSeq, value)
        return value
    }

    /// The `startTs` of every block that is not part of its wake day's main-night group: the naps. The same
    /// split the Sleep tab's Naps card makes, so the two screens cannot disagree about what a nap is.
    nonisolated static func napStarts(_ sessions: [CachedSleepSession], habitual: Int?, calendar: Calendar) -> Set<Int> {
        let byWakeDay = Dictionary(grouping: sessions) {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.endTs)))
        }
        var naps = Set<Int>()
        for blocks in byWakeDay.values {
            let main = Set(SleepView.mainNightGroup(blocks, habitualMidsleepSec: habitual).map { $0.startTs })
            for block in blocks where !main.contains(block.startTs) { naps.insert(block.startTs) }
        }
        return naps
    }

    // MARK: Workouts

    static func workoutKey(_ row: WorkoutRow) -> String {
        "\(row.startTs)-\(row.endTs)-\(row.sport)-\(row.source)"
    }

    private static func badges(for row: WorkoutRow) -> [DayTimeline.Source] {
        switch WorkoutSource.classify(row.source) {
        case .whoop, .manual, .detected: return [.strap]
        case .apple: return [.apple]
        // PaceForge's own copy of a Garmin activity: the record is Garmin's, reached through PaceForge.
        case .paceforge: return [.garmin, .paceforge]
        case .lifting, .activityFile: return [.imported]
        }
    }

    /// The Garmin activity id in a mirrored row's notes ("PaceForge #123: Easy run"), or nil.
    static func paceForgeActivityId(_ row: WorkoutRow) -> String? {
        guard WorkoutSource.classify(row.source) == .paceforge,
              let notes = row.notes, notes.hasPrefix("PaceForge #") else { return nil }
        let id = notes.dropFirst("PaceForge #".count).prefix { $0 != ":" }
        return id.isEmpty ? nil : String(id)
    }

    /// PaceForge's `canonical_of` turned into key pairs: the duplicate's row (found by start and sport) and
    /// the Garmin row carrying the canonical activity id. The PaceForge mirror row is its own canonical, so
    /// a duplicate that already carries that id adds nothing and is skipped.
    private static func pairs(from canonicalOf: [String: String],
                              rows: [WorkoutRow]) -> [DayTimeline.Input.WorkoutPair] {
        var out: [DayTimeline.Input.WorkoutPair] = []
        for (duplicateKey, garminId) in canonicalOf {
            let parts = duplicateKey.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let start = Int(parts[2]) else { continue }
            let sport = String(parts[3])
            guard let canonical = rows.first(where: { paceForgeActivityId($0) == garminId }),
                  let duplicate = rows.first(where: {
                      $0.startTs == start && $0.sport == sport && paceForgeActivityId($0) != garminId
                  }) else { continue }
            out.append(DayTimeline.Input.WorkoutPair(a: workoutKey(canonical), b: workoutKey(duplicate)))
        }
        return out
    }

    // MARK: Stress

    /// The hourly stress read, placed at the middle of each hour window it scores.
    private static func stressCurve(repo: Repository, from: Int, to: Int, dayStart: Date,
                                    calendar: Calendar) async -> [DayTimeline.Input.StressSample] {
        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard hr.count >= DaytimeStress.minHourHRSamples else { return [] }
        let rr = await repo.rrIntervals(from: from, to: to, limit: 200_000)
        let gravity = await repo.gravitySamplesUnion(from: from, to: to, limit: 200_000)
        let tz = TimeZone.current.secondsFromGMT(for: dayStart)
        let mode = await DaytimeStressMode.selected(repo: repo, startOfToday: dayStart, calendar: calendar,
                                                    personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled)
        let result = await runUnescalated(priority: .userInitiated) {
            DaytimeStress.analyze(hr: hr, rr: rr, gravity: gravity, tzOffsetSeconds: tz, mode: mode,
                                  includeTimeline: true)
        }
        return result.timeline.map {
            DayTimeline.Input.StressSample(ts: $0.startTs + 1800, level: $0.level,
                                           maskedForActivity: $0.maskedForActivity)
        }
    }
}

// MARK: - Detector suggestions for a window

extension Repository {
    /// The strap's gait ticks (stepSample.activityClass: 0 still, 1 walk, 2 run) inside `[from, to]`, read from
    /// the first id that has classed ticks, active strap first. Nil when the strap classed nothing there (a 4.0
    /// strap, a window not offloaded yet), and the heart rate alone then decides walk or workout.
    func gaitMix(from: Int, to: Int) async -> DetectedSegmentClassifier.GaitMix? {
        guard to > from, let store = await storeHandle() else { return nil }
        for id in importedReadIds {
            let samples = (try? await store.stepSamples(deviceId: id, from: from, to: to, limit: 200_000)) ?? []
            if let mix = DetectedSegmentClassifier.GaitMix.from(classes: samples.map(\.activityClass)) { return mix }
        }
        return nil
    }

    /// Every sustained-effort window the opt-in detector finds in `[from, to)` that no saved workout covers
    /// and the user has not dismissed. `autoDetectCandidate` returns only the newest; My Day lists them all.
    /// A pure read: nothing is saved, and the toggle that gates the detector gates this too.
    func autoDetectCandidates(from: Int, to: Int, savedSpans: [SavedWorkoutSpan]) async -> [DetectedWorkout] {
        guard PuffinExperiment.autoDetectWorkoutsEnabled, to > from else { return [] }
        let samples = await hrSamples(from: from, to: to, limit: 200_000)
        guard samples.count >= 2 else { return [] }
        let hr = samples.map { (ts: $0.ts, bpm: $0.bpm) }
        let resting = days.last(where: { $0.restingHr != nil })?.restingHr
        let found = AutoWorkoutDetector.detect(hr: hr, restingBpm: resting, motion: nil, savedSpans: savedSpans,
                                               minimumSustainedMinutes: AutoWorkoutDetector.minSustainedMin)
        // `selectAutoDetectCandidate` applies both dismissal contracts; asking it about one window at a
        // time keeps each survivor instead of only the newest.
        return found.filter {
            Self.selectAutoDetectCandidate([$0], autoDismissedTokens: autoDetectDismissedSpans,
                                           detectedDismissedTokens: dismissedDetectedSpans) != nil
        }
    }
}
