#if DEBUG
import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - My Day synthetic day (DEBUG only)
//
// A made-up Wednesday, 2030-03-13 (the day PaceForgeFixture.json is written for), built through the real
// `DayTimeline` builder so the screen under test runs the same rules as the shipped one. Launch with
// `-MyDayFixture full | gap | empty`; nothing is read from or written to the store. Every number below is
// invented: no personal data lives here.

enum MyDayFixture {

    enum Variant: String {
        /// A whole day: night, a merged run, a nap, a suggestion, the plan, logs and one short gap.
        case full
        /// The same day with three gaps, so every no-data reason and the trailing "not synced" show.
        case gap
        /// Nothing recorded at all; the plan and a sync hint remain.
        case empty
    }

    static let variant: Variant? = {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "-MyDayFixture"), args.index(after: flag) < args.endIndex else { return nil }
        return Variant(rawValue: args[args.index(after: flag)])
    }()

    /// Midnight of the fixture day, or nil when the fixture is off.
    static let dayStart: Date? = variant == nil
        ? nil
        : Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: 13))

    static func loaded() -> DayTimelineLoader.Loaded? {
        guard let variant, let dayStart else { return nil }
        let calendar = Calendar.current
        let bounds = DayTimeline.dayBounds(containing: dayStart, calendar: calendar)
        let start = Int(bounds.start.timeIntervalSince1970)
        func ts(_ hour: Int, _ minute: Int = 0) -> Int { start + hour * 3600 + minute * 60 }

        var input = DayTimeline.Input(dayStart: bounds.start, dayEnd: bounds.end,
                                      now: Date(timeIntervalSince1970: TimeInterval(ts(15, 30))))
        input.syncPending = true
        input.hrSampleSpanSec = 60

        // The plan is there on every variant, as it is on a real day with nothing recorded.
        input.planned = [
            .init(id: "s-wed", title: "Synthetic 4 x 800 m", detail: "8.0 km \u{00B7} 55 min", durationMin: 55),
            .init(id: "s-wed2", title: "Synthetic mobility", detail: "30 min", durationMin: 30,
                  matchedActivityIds: ["9000000003"]),
        ]
        input.planActivities = [.init(id: "9000000003", startTs: ts(7, 55), endTs: ts(8, 25))]

        var rows: [String: WorkoutRow] = [:]
        if variant != .empty {
            input.hr = heartRate(start: start, holes: holes(for: variant, ts: ts))
            input.battery = [.init(ts: ts(10, 25), soc: 62, charging: true)]
            input.sleeps = [
                .init(startTs: ts(0) - 40 * 60, endTs: ts(6, 50), isNap: false),
                .init(startTs: ts(13, 10), endTs: ts(13, 45), isNap: true),
            ]
            input.workouts = [
                .init(key: "strap", startTs: ts(7, 12), endTs: ts(7, 46), title: "Running", sources: [.strap],
                      avgHr: 151, maxHr: 174),
                .init(key: "garmin", startTs: ts(7, 10), endTs: ts(7, 48), title: "Running",
                      sources: [.garmin, .paceforge], avgHr: 149, kcal: 402, distanceM: 6100,
                      externalId: "9000000009"),
                .init(key: "apple", startTs: ts(7, 11), endTs: ts(7, 47), title: "Running", sources: [.apple],
                      kcal: 380),
                .init(key: "mobility", startTs: ts(7, 55), endTs: ts(8, 25), title: "Mobility", sources: [.strap],
                      avgHr: 96),
            ]
            rows["garmin"] = WorkoutRow(startTs: ts(7, 10), endTs: ts(7, 48), sport: "Running", source: "paceforge",
                                        durationS: 2280, energyKcal: 402, avgHr: 149, maxHr: 174, strain: nil,
                                        distanceM: 6100, zonesJSON: nil, notes: nil, steps: nil)
            input.detected = [.init(startTs: ts(12, 20), endTs: ts(12, 50), avgBpm: 128, peakBpm: 141)]
            input.weighIns = [.init(ts: nil, kg: 90.8, source: .apple)]
            input.caffeine = [.init(ts: ts(8, 5), mg: 95), .init(ts: ts(13, 50), mg: nil)]
            input.water = [.init(ts: ts(9, 30), ml: 250), .init(ts: ts(12, 10), ml: 500)]
            let hourlySteps: [(Int, Int)] = [(7, 3200), (8, 900), (12, 1800), (13, 400), (14, 1500)]
            input.steps = hourlySteps.map { DayTimeline.Input.StepBucket(ts: ts($0.0), seconds: 3600, steps: $0.1) }
            // Hour 7 is the run: the stress read masks it as exertion rather than scoring it.
            let hourlyStress: [(Int, Double?)] = [(7, nil), (8, 1.1), (9, 1.6), (10, 1.9), (11, 1.4), (12, 1.2),
                                                  (13, 2.2), (14, 1.7), (15, 1.3)]
            input.stress = hourlyStress.map {
                DayTimeline.Input.StressSample(ts: ts($0.0, 30), level: $0.1, maskedForActivity: $0.1 == nil)
            }
            input.journal = [.init(label: "Caffeine", yes: true), .init(label: "Alcohol", yes: false),
                             .init(label: "Late meal", yes: true)]
        }

        let detected = input.detected.reduce(into: [String: DetectedWorkout]()) { acc, d in
            acc["detected-\(d.startTs)-\(d.endTs)"] = DetectedWorkout(
                startSec: d.startTs, endSec: d.endTs, avgBpm: d.avgBpm, peakBpm: d.peakBpm,
                durationMin: (d.endTs - d.startTs) / 60)
        }
        return DayTimelineLoader.Loaded(timeline: DayTimeline.build(input), workoutRows: rows, detected: detected)
    }

    // MARK: Pieces

    /// Stretches with no heart rate, as (from, to) seconds.
    private static func holes(for variant: Variant, ts: (Int, Int) -> Int) -> [(Int, Int)] {
        switch variant {
        case .full: return [(ts(10, 20), ts(11, 5))]
        case .gap: return [(ts(2, 10), ts(3, 0)), (ts(10, 20), ts(11, 5)), (ts(14, 0), ts(15, 30))]
        case .empty: return []
        }
    }

    /// Per-minute heart rate from midnight to 15:30, shaped like a day: asleep, a run, ordinary hours, and
    /// a gentler 30 minutes at midday that the detector would flag.
    private static func heartRate(start: Int, holes: [(Int, Int)]) -> [DayTimeline.Input.HRSample] {
        var out: [DayTimeline.Input.HRSample] = []
        for minute in 0..<(15 * 60 + 30) {
            let t = start + minute * 60
            if holes.contains(where: { t >= $0.0 && t < $0.1 }) { continue }
            let m = Double(minute)
            let bpm: Double
            switch minute {
            case 0..<410: bpm = 53 + 3 * sin(m / 37)
            case 410..<430: bpm = 72
            case 430..<468: bpm = 150 + 12 * sin(m / 3)
            case 468..<475: bpm = 118 - Double(minute - 468) * 6
            case 740..<770: bpm = 128 + 6 * sin(m / 4)
            default: bpm = 72 + 8 * sin(m / 53)
            }
            out.append(.init(ts: t, bpm: bpm))
        }
        return out
    }
}
#endif
