import Foundation

// DayTimelineBuilder.swift: the inputs and the pure builder for `DayTimeline`. See DayTimeline.swift
// for the rules. Everything is unix seconds; nothing here reads a clock or the store.

extension DayTimeline {

    // MARK: Inputs

    public struct Input: Sendable {
        public struct HRSample: Sendable {
            public let ts: Int
            public let bpm: Double
            public init(ts: Int, bpm: Double) { self.ts = ts; self.bpm = bpm }
        }
        public struct StressSample: Sendable {
            public let ts: Int
            public let level: Double?
            public let maskedForActivity: Bool
            public init(ts: Int, level: Double?, maskedForActivity: Bool = false) {
                self.ts = ts; self.level = level; self.maskedForActivity = maskedForActivity
            }
        }
        /// Steps counted in `[ts, ts + seconds)`.
        public struct StepBucket: Sendable {
            public let ts: Int
            public let seconds: Int
            public let steps: Int
            public init(ts: Int, seconds: Int, steps: Int) { self.ts = ts; self.seconds = seconds; self.steps = steps }
        }
        public struct Sleep: Sendable {
            public let startTs: Int
            public let endTs: Int
            public let isNap: Bool
            public let source: Source
            public init(startTs: Int, endTs: Int, isNap: Bool, source: Source = .strap) {
                self.startTs = startTs; self.endTs = endTs; self.isNap = isNap; self.source = source
            }
        }
        public struct Workout: Sendable {
            /// Unique among the day's workouts; the route hands it back so the app can find its row.
            public let key: String
            public let startTs: Int
            public let endTs: Int
            public let title: String
            public let sources: [Source]
            public let avgHr: Int?
            public let maxHr: Int?
            public let kcal: Double?
            public let distanceM: Double?
            /// The PaceForge / Garmin activity id this record is, when it carries one.
            public let externalId: String?
            public init(key: String, startTs: Int, endTs: Int, title: String, sources: [Source],
                        avgHr: Int? = nil, maxHr: Int? = nil, kcal: Double? = nil, distanceM: Double? = nil,
                        externalId: String? = nil) {
                self.key = key; self.startTs = startTs; self.endTs = endTs; self.title = title
                self.sources = sources; self.avgHr = avgHr; self.maxHr = maxHr; self.kcal = kcal
                self.distanceM = distanceM; self.externalId = externalId
            }
        }
        /// Two workout keys an outside matcher (PaceForge's workout-matches.json) says are one workout.
        public struct WorkoutPair: Sendable {
            public let a: String
            public let b: String
            public init(a: String, b: String) { self.a = a; self.b = b }
        }
        /// A sustained-effort window the opt-in detector suggests; not saved until the user says so.
        public struct Detected: Sendable {
            public let startTs: Int
            public let endTs: Int
            public let avgBpm: Int
            public let peakBpm: Int
            public init(startTs: Int, endTs: Int, avgBpm: Int, peakBpm: Int) {
                self.startTs = startTs; self.endTs = endTs; self.avgBpm = avgBpm; self.peakBpm = peakBpm
            }
        }
        public struct Planned: Sendable {
            public let id: String
            public let title: String
            /// "6.0 km · 37 min", from the plan.
            public let detail: String?
            /// The planned slot, when the plan has one; most do not, and then the row is untimed.
            public let startTs: Int?
            public let durationMin: Int?
            /// Activity ids the plan was matched to (empty until the session is done).
            public let matchedActivityIds: [String]
            public init(id: String, title: String, detail: String? = nil, startTs: Int? = nil,
                        durationMin: Int? = nil, matchedActivityIds: [String] = []) {
                self.id = id; self.title = title; self.detail = detail; self.startTs = startTs
                self.durationMin = durationMin; self.matchedActivityIds = matchedActivityIds
            }
        }
        /// A finished activity from the plan's side, so a matched plan can be placed on the day.
        public struct PlanActivity: Sendable {
            public let id: String
            public let startTs: Int
            public let endTs: Int
            public init(id: String, startTs: Int, endTs: Int) { self.id = id; self.startTs = startTs; self.endTs = endTs }
        }
        public struct WeighIn: Sendable {
            public let ts: Int?
            public let kg: Double
            public let source: Source
            public init(ts: Int?, kg: Double, source: Source) { self.ts = ts; self.kg = kg; self.source = source }
        }
        public struct Caffeine: Sendable {
            public let ts: Int
            public let mg: Double?
            public init(ts: Int, mg: Double?) { self.ts = ts; self.mg = mg }
        }
        public struct Water: Sendable {
            public let ts: Int
            public let ml: Int
            public init(ts: Int, ml: Int) { self.ts = ts; self.ml = ml }
        }
        public struct JournalAnswer: Sendable {
            public let label: String
            public let yes: Bool
            public init(label: String, yes: Bool) { self.label = label; self.yes = yes }
        }
        /// A timed or day-level note from outside, such as a niggle PaceForge logged.
        public struct Note: Sendable {
            public let id: String
            /// nil for a note with no clock time: it is listed under "All day".
            public let ts: Int?
            public let title: String
            public let subtitle: String
            public let source: Source
            public init(id: String, ts: Int?, title: String, subtitle: String = "", source: Source = .paceforge) {
                self.id = id; self.ts = ts; self.title = title; self.subtitle = subtitle; self.source = source
            }
        }
        public struct Battery: Sendable {
            public let ts: Int
            public let soc: Double?
            public let charging: Bool?
            public init(ts: Int, soc: Double?, charging: Bool?) { self.ts = ts; self.soc = soc; self.charging = charging }
        }

        public var dayStart: Date
        public var dayEnd: Date
        public var now: Date
        public var hr: [HRSample] = []
        /// How long each heart-rate sample stands for (1 for raw samples, 60 for per-minute means).
        public var hrSampleSpanSec = 1
        public var stress: [StressSample] = []
        public var steps: [StepBucket] = []
        public var stepsSource: Source = .apple
        public var sleeps: [Sleep] = []
        public var workouts: [Workout] = []
        public var sameWorkoutPairs: [WorkoutPair] = []
        public var detected: [Detected] = []
        public var planned: [Planned] = []
        public var planActivities: [PlanActivity] = []
        public var weighIns: [WeighIn] = []
        public var caffeine: [Caffeine] = []
        public var water: [Water] = []
        public var journal: [JournalAnswer] = []
        public var battery: [Battery] = []
        public var notes: [Note] = []
        /// Garmin Body Battery and stress, from outside. Each stays its own curve.
        public var energy: [SeriesPoint] = []
        public var garminStress: [SeriesPoint] = []
        public var recharge: Recharge?
        /// True when the strap has not been synced and the day is still running, so a gap at its tail is
        /// most likely data still on the strap.
        public var syncPending = false
        /// Off when the heart-rate series was deliberately not loaded, so a day with no series is not
        /// reported as one long gap.
        public var detectsGaps = true

        public init(dayStart: Date, dayEnd: Date, now: Date) {
            self.dayStart = dayStart; self.dayEnd = dayEnd; self.now = now
        }
    }

    // MARK: Builder

    public static func build(_ input: Input) -> DayTimeline {
        let dayStartTs = Int(input.dayStart.timeIntervalSince1970)
        let dayEndTs = Int(input.dayEnd.timeIntervalSince1970)
        let nowTs = Int(input.now.timeIntervalSince1970)
        // Nothing is read or drawn past "now": the rest of today has not happened.
        let horizon = min(nowTs, dayEndTs)
        func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

        // Heart rate: sorted, one sample per second, inside [dayStart, horizon).
        let hrSamples = dedupedSorted(input.hr.filter { $0.ts >= dayStartTs && $0.ts < horizon })
        let span = max(1, input.hrSampleSpanSec)
        let gaps = input.detectsGaps ? noDataGaps(hrTs: hrSamples.map(\.ts), span: span, from: dayStartTs, to: horizon) : []
        let curve = hrCurve(hrSamples, gaps: gaps, dayStartTs: dayStartTs, dayEndTs: dayEndTs)

        var events: [Event] = []

        // No data.
        for gap in gaps {
            let reason = noDataReason(gap: gap, input: input, horizon: horizon)
            let length = durationText(gap.end - gap.start)
            events.append(Event(id: "gap-\(gap.start)", kind: .noData, start: date(gap.start), end: date(gap.end),
                                title: "No data", subtitle: "\(reason.text) \u{00B7} \(length)",
                                noDataReason: reason))
        }

        // Sleep and naps.
        for s in input.sleeps where s.endTs > s.startTs && s.endTs > dayStartTs && s.startTs < dayEndTs {
            let length = s.endTs - s.startTs
            events.append(Event(
                id: "sleep-\(s.startTs)", kind: s.isNap ? .nap : .sleep,
                start: date(s.startTs), end: date(s.endTs),
                title: s.isNap ? "Nap" : "Sleep", subtitle: durationText(length), sources: [s.source],
                route: .sleep(startTs: s.startTs), metrics: Metrics(durationSec: length),
                continuesFromPreviousDay: s.startTs < dayStartTs, continuesToNextDay: s.endTs > dayEndTs))
        }

        // Workouts, grouped, then the plan folded in.
        let dayWorkouts = input.workouts.filter { $0.endTs >= $0.startTs && $0.endTs >= dayStartTs && $0.startTs < dayEndTs }
        var clusters = clusterWorkouts(dayWorkouts, pairs: input.sameWorkoutPairs)
        var linkedPlanIds = Set<String>()
        for plan in input.planned where !plan.matchedActivityIds.isEmpty {
            guard let idx = clusterIndex(for: plan, in: clusters, activities: input.planActivities) else { continue }
            clusters[idx].planTitles.append(plan.title)
            linkedPlanIds.insert(plan.id)
        }
        for cluster in clusters {
            events.append(workoutEvent(cluster))
        }

        // Detected, unsaved suggestions that no saved workout or sleep already explains.
        let saved = events.filter { $0.kind == .workout || $0.kind == .sleep || $0.kind == .nap }
        for d in input.detected where d.endTs > d.startTs && d.endTs >= dayStartTs && d.startTs < dayEndTs {
            let covered = saved.contains { e in
                guard let end = e.end else { return false }
                return overlapsEnough(aStart: d.startTs, aEnd: d.endTs,
                                      bStart: Int(e.start.timeIntervalSince1970), bEnd: Int(end.timeIntervalSince1970))
            }
            if covered { continue }
            let length = d.endTs - d.startTs
            events.append(Event(
                id: "detected-\(d.startTs)-\(d.endTs)", kind: .detected, start: date(d.startTs), end: date(d.endTs),
                title: "Looks like a workout", subtitle: "\(durationText(length)) \u{00B7} avg \(d.avgBpm) bpm",
                sources: [.strap],
                metrics: Metrics(durationSec: length, avgHr: d.avgBpm, maxHr: d.peakBpm)))
        }

        // Planned sessions not already shown as the workout they became.
        let dayIsOver = nowTs >= dayEndTs
        for plan in input.planned where !linkedPlanIds.contains(plan.id) {
            events.append(plannedEvent(plan, activities: input.planActivities, dayIsOver: dayIsOver,
                                       dayStartTs: dayStartTs, dayEndTs: dayEndTs))
        }

        // Weigh-ins (day-level unless the source stamped a time).
        for (i, w) in input.weighIns.enumerated() {
            let timed = w.ts.map { $0 >= dayStartTs && $0 < dayEndTs } ?? false
            events.append(Event(
                id: "weigh-\(i)-\(w.ts ?? 0)", kind: .weighIn, start: date(timed ? (w.ts ?? dayStartTs) : dayStartTs),
                isUntimed: !timed, title: "Weigh-in", subtitle: String(format: "%.1f kg", w.kg), sources: [w.source],
                metrics: Metrics(weightKg: w.kg)))
        }

        // Caffeine and water.
        for c in input.caffeine where c.ts >= dayStartTs && c.ts < dayEndTs {
            events.append(Event(
                id: "caffeine-\(c.ts)", kind: .caffeine, start: date(c.ts), title: "Caffeine",
                subtitle: c.mg.map { "\(Int($0.rounded())) mg" } ?? "Amount not logged",
                metrics: Metrics(mg: c.mg)))
        }
        for w in input.water where w.ts >= dayStartTs && w.ts < dayEndTs {
            events.append(Event(id: "water-\(w.ts)", kind: .water, start: date(w.ts), title: "Water",
                                subtitle: "\(w.ml) ml", metrics: Metrics(ml: w.ml)))
        }

        // Steps: the cumulative curve and the stretches of real walking.
        let buckets = input.steps.filter { $0.seconds > 0 && $0.steps >= 0 && $0.ts >= dayStartTs && $0.ts < dayEndTs }
            .sorted { $0.ts < $1.ts }
        let stepsCurve = cumulativeSteps(buckets, dayStartTs: dayStartTs)
        for burst in stepBursts(buckets) {
            events.append(Event(
                id: "steps-\(burst.start)", kind: .stepsBurst, start: date(burst.start), end: date(burst.end),
                title: "Walking", subtitle: "\(burst.steps) steps", sources: [input.stepsSource],
                metrics: Metrics(durationSec: burst.end - burst.start, steps: burst.steps)))
        }

        // Notes from outside (a niggle): timed when the source stamped a time, else listed under "All day".
        for note in input.notes {
            let timed = note.ts.map { $0 >= dayStartTs && $0 < dayEndTs } ?? false
            events.append(Event(
                id: "note-\(note.id)", kind: .dayNote, start: date(timed ? (note.ts ?? dayStartTs) : dayStartTs),
                isUntimed: !timed, title: note.title, subtitle: note.subtitle, sources: [note.source]))
        }

        // Journal: one untimed note.
        if !input.journal.isEmpty {
            let yes = input.journal.filter(\.yes).map(\.label)
            let subtitle: String
            if yes.isEmpty {
                subtitle = "No to all \(input.journal.count) answered"
            } else {
                let head = yes.prefix(3).joined(separator: ", ")
                subtitle = yes.count > 3 ? "\(head) +\(yes.count - 3)" : head
            }
            events.append(Event(id: "journal", kind: .dayNote, start: input.dayStart, isUntimed: true,
                                title: "Journal", subtitle: subtitle))
        }

        let stress = input.stress.filter { $0.ts >= dayStartTs && $0.ts < dayEndTs }
            .sorted { $0.ts < $1.ts }
            .map { StressPoint(ts: $0.ts, level: $0.level, maskedForActivity: $0.maskedForActivity) }

        // The outside curves: inside the day, in time order, nothing past now (the rest of today has not happened).
        func inDay(_ points: [SeriesPoint]) -> [SeriesPoint] {
            points.filter { $0.ts >= dayStartTs && $0.ts < horizon }
                .sorted { $0.ts < $1.ts }
        }

        return DayTimeline(dayStart: input.dayStart, dayEnd: input.dayEnd, now: input.now,
                           events: ordered(events, dayStartTs: dayStartTs),
                           hr: curve, stress: stress, stepsCumulative: stepsCurve,
                           energy: inDay(input.energy), garminStress: inDay(input.garminStress),
                           recharge: input.recharge)
    }

    // MARK: Ordering

    /// "All day" rows first (plans, weigh-ins, the note), then timed rows newest first.
    private static func ordered(_ events: [Event], dayStartTs: Int) -> [Event] {
        let untimed = events.filter(\.isUntimed).sorted { kindRank($0.kind) < kindRank($1.kind) || ($0.kind == $1.kind && $0.id < $1.id) }
        let timed = events.filter { !$0.isUntimed }.sorted { a, b in
            let sa = max(Int(a.start.timeIntervalSince1970), dayStartTs)
            let sb = max(Int(b.start.timeIntervalSince1970), dayStartTs)
            return sa != sb ? sa > sb : a.id < b.id
        }
        return untimed + timed
    }

    private static func kindRank(_ kind: Kind) -> Int {
        switch kind {
        case .planned: return 0
        case .weighIn: return 1
        case .dayNote: return 2
        default: return 3
        }
    }

    // MARK: Heart rate, gaps

    private static func dedupedSorted(_ samples: [Input.HRSample]) -> [Input.HRSample] {
        var out: [Input.HRSample] = []
        out.reserveCapacity(samples.count)
        for s in samples.sorted(by: { $0.ts < $1.ts }) {
            if let last = out.last, last.ts == s.ts { continue }
            out.append(s)
        }
        return out
    }

    struct Gap: Equatable {
        let start: Int
        let end: Int
    }

    /// Every stretch of `gapSec` or more, inside [from, to), that no sample covers. A sample at `ts`
    /// stands for `[ts, ts + span)`.
    static func noDataGaps(hrTs: [Int], span: Int, from: Int, to: Int) -> [Gap] {
        guard to > from else { return [] }
        var out: [Gap] = []
        var covered = from
        for ts in hrTs {
            if ts - covered >= gapSec { out.append(Gap(start: covered, end: ts)) }
            covered = max(covered, ts + span)
        }
        if to - covered >= gapSec { out.append(Gap(start: covered, end: to)) }
        return out
    }

    private static func noDataReason(gap: Gap, input: Input, horizon: Int) -> NoDataReason {
        let near = input.battery.contains { $0.charging == true && $0.ts >= gap.start - 900 && $0.ts <= gap.end + 900 }
        if near { return .charging }
        let lastReading = input.battery
            .filter { $0.ts <= gap.start + 60 && gap.start - $0.ts <= 10_800 }
            .max { $0.ts < $1.ts }
        if let soc = lastReading?.soc, soc <= 5 { return .batteryEmpty }
        if input.syncPending && gap.end >= horizon - 60 { return .syncPending }
        return .noHeartRate
    }

    /// At most `maxCurvePoints` points over the real length of the day: the mean of each equal slice.
    /// The pen lifts wherever a no-data gap sits between two points.
    private static func hrCurve(_ samples: [Input.HRSample], gaps: [Gap], dayStartTs: Int, dayEndTs: Int) -> [HRPoint] {
        guard !samples.isEmpty else { return [] }
        let length = max(1, dayEndTs - dayStartTs)
        let slice = max(1, Int((Double(length) / Double(maxCurvePoints)).rounded(.up)))
        var sums: [Int: (ts: Int, bpm: Double, n: Int)] = [:]
        for s in samples {
            let key = (s.ts - dayStartTs) / slice
            var acc = sums[key] ?? (ts: 0, bpm: 0, n: 0)
            acc.ts += s.ts; acc.bpm += s.bpm; acc.n += 1
            sums[key] = acc
        }
        var out: [HRPoint] = []
        out.reserveCapacity(sums.count)
        var previousTs: Int?
        for key in sums.keys.sorted() {
            guard let acc = sums[key], acc.n > 0 else { continue }
            let ts = acc.ts / acc.n
            let lifted: Bool
            if let previousTs {
                lifted = gaps.contains { $0.start >= previousTs && $0.end <= ts }
            } else {
                lifted = true
            }
            out.append(HRPoint(ts: ts, bpm: acc.bpm / Double(acc.n), startsRun: lifted))
            previousTs = ts
        }
        return out
    }

    // MARK: Workouts

    struct Cluster {
        var members: [Input.Workout]
        var planTitles: [String] = []
    }

    /// Half the shorter one overlaps, and the starts are within ten minutes: the same-workout rule.
    static func isSameWorkout(_ a: Input.Workout, _ b: Input.Workout) -> Bool {
        abs(a.startTs - b.startTs) <= sameWorkoutStartSec
            && overlapsEnough(aStart: a.startTs, aEnd: a.endTs, bStart: b.startTs, bEnd: b.endTs)
    }

    static func overlapsEnough(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int) -> Bool {
        let overlap = min(aEnd, bEnd) - max(aStart, bStart)
        guard overlap > 0 else { return false }
        let shorter = max(1, min(aEnd - aStart, bEnd - bStart))
        return Double(overlap) >= sameWorkoutOverlap * Double(shorter)
    }

    private static func clusterWorkouts(_ workouts: [Input.Workout], pairs: [Input.WorkoutPair]) -> [Cluster] {
        var parent = Array(workouts.indices)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root { let next = parent[node]; parent[node] = root; node = next }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        for i in workouts.indices {
            for j in workouts.indices where j > i && isSameWorkout(workouts[i], workouts[j]) { union(i, j) }
        }
        var indexByKey: [String: Int] = [:]
        for (i, w) in workouts.enumerated() where indexByKey[w.key] == nil { indexByKey[w.key] = i }
        for pair in pairs {
            if let a = indexByKey[pair.a], let b = indexByKey[pair.b] { union(a, b) }
        }
        var groups: [Int: [Input.Workout]] = [:]
        for i in workouts.indices { groups[find(i), default: []].append(workouts[i]) }
        return groups.keys.sorted().compactMap { key in groups[key].map { Cluster(members: $0) } }
    }

    /// The canonical record first: Garmin's, then the one with the most figures, then the longest.
    private static func ranked(_ members: [Input.Workout]) -> [Input.Workout] {
        func figures(_ w: Input.Workout) -> Int {
            [w.avgHr != nil, w.maxHr != nil, w.kcal != nil, w.distanceM != nil].filter { $0 }.count
        }
        return members.sorted { a, b in
            let ga = a.sources.contains(.garmin), gb = b.sources.contains(.garmin)
            if ga != gb { return ga }
            if figures(a) != figures(b) { return figures(a) > figures(b) }
            let da = a.endTs - a.startTs, db = b.endTs - b.startTs
            if da != db { return da > db }
            return a.key < b.key
        }
    }

    private static func clusterIndex(for plan: Input.Planned, in clusters: [Cluster],
                                     activities: [Input.PlanActivity]) -> Int? {
        let ids = Set(plan.matchedActivityIds)
        if let byId = clusters.firstIndex(where: { c in c.members.contains { $0.externalId.map(ids.contains) ?? false } }) {
            return byId
        }
        for activity in activities where ids.contains(activity.id) {
            let hit = clusters.firstIndex { c in
                c.members.contains { overlapsEnough(aStart: $0.startTs, aEnd: $0.endTs,
                                                    bStart: activity.startTs, bEnd: activity.endTs)
                                      && abs($0.startTs - activity.startTs) <= sameWorkoutStartSec }
            }
            if let hit { return hit }
        }
        return nil
    }

    private static func workoutEvent(_ cluster: Cluster) -> Event {
        let order = ranked(cluster.members)
        let canonical = order[0]
        func first<T>(_ pick: (Input.Workout) -> T?) -> T? {
            for w in order { if let v = pick(w) { return v } }
            return nil
        }
        let avgHr: Int? = first { $0.avgHr }
        let maxHr: Int? = first { $0.maxHr }
        let kcal: Double? = first { $0.kcal }
        let distance: Double? = first { $0.distanceM }
        let length = max(0, canonical.endTs - canonical.startTs)

        var badges = cluster.members.flatMap(\.sources)
        if !cluster.planTitles.isEmpty { badges += [.plan, .paceforge] }
        let sources = Source.allCases.filter { badges.contains($0) }

        var parts = [durationText(length)]
        if let avgHr { parts.append("avg \(avgHr) bpm") }
        if let kcal, kcal > 0 { parts.append("\(Int(kcal.rounded())) kcal") }
        if !cluster.planTitles.isEmpty { parts.append("Plan: \(cluster.planTitles.joined(separator: ", "))") }

        return Event(
            id: "workout-\(canonical.key)", kind: .workout,
            start: Date(timeIntervalSince1970: TimeInterval(canonical.startTs)),
            end: Date(timeIntervalSince1970: TimeInterval(canonical.endTs)),
            title: canonical.title, subtitle: parts.joined(separator: " \u{00B7} "), sources: sources,
            route: .workout(key: canonical.key),
            metrics: Metrics(durationSec: length, avgHr: avgHr, maxHr: maxHr, kcal: kcal, distanceM: distance))
    }

    // MARK: Plan

    private static func plannedEvent(_ plan: Input.Planned, activities: [Input.PlanActivity], dayIsOver: Bool,
                                     dayStartTs: Int, dayEndTs: Int) -> Event {
        let ids = Set(plan.matchedActivityIds)
        let matched = activities.first { ids.contains($0.id) }
        let isDone = !plan.matchedActivityIds.isEmpty
        let status: Status = isDone ? .done : (dayIsOver ? .missed : .planned)
        let lead = isDone ? "Done" : (dayIsOver ? "Missed" : "Planned")
        let subtitle = ([lead] + [plan.detail].compactMap { $0 }).joined(separator: " \u{00B7} ")

        var start: Int?
        var end: Int?
        if let matched, matched.startTs >= dayStartTs, matched.startTs < dayEndTs {
            start = matched.startTs; end = matched.endTs
        } else if !isDone, let slot = plan.startTs, slot >= dayStartTs, slot < dayEndTs {
            start = slot
            end = plan.durationMin.map { slot + $0 * 60 }
        }
        return Event(
            id: "plan-\(plan.id)", kind: .planned,
            start: Date(timeIntervalSince1970: TimeInterval(start ?? dayStartTs)),
            end: end.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            isUntimed: start == nil, title: plan.title, subtitle: subtitle,
            sources: [.plan, .paceforge], status: status,
            metrics: Metrics(durationSec: plan.durationMin.map { $0 * 60 }))
    }

    // MARK: Steps

    private static func cumulativeSteps(_ buckets: [Input.StepBucket], dayStartTs: Int) -> [StepPoint] {
        guard !buckets.isEmpty else { return [] }
        var out = [StepPoint(ts: dayStartTs, cumulative: 0)]
        var total = 0
        for b in buckets {
            total += b.steps
            out.append(StepPoint(ts: b.ts + b.seconds, cumulative: total))
        }
        return out
    }

    private struct Burst {
        var start: Int
        var end: Int
        var steps: Int
    }

    /// A bucket is walking when it holds at least 500 steps and 15 a minute; touching buckets merge.
    private static func stepBursts(_ buckets: [Input.StepBucket]) -> [Burst] {
        var out: [Burst] = []
        for b in buckets {
            let minutes = max(1, b.seconds / 60)
            guard b.steps >= max(500, 15 * minutes) else { continue }
            if var last = out.last, b.ts <= last.end {
                last.end = max(last.end, b.ts + b.seconds)
                last.steps += b.steps
                out[out.count - 1] = last
            } else {
                out.append(Burst(start: b.ts, end: b.ts + b.seconds, steps: b.steps))
            }
        }
        return out
    }

    // MARK: Text

    /// "42 min", "1h 05m", "7h 12m".
    public static func durationText(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 60 { return "\(max(1, minutes)) min" }
        return "\(minutes / 60)h " + String(format: "%02d", minutes % 60) + "m"
    }
}
