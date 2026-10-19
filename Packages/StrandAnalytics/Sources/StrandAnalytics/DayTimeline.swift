import Foundation

// DayTimeline.swift: the pure model and builder behind "My Day".
//
// One calendar day, laid out as a list of things that happened (sleep, naps, workouts, planned
// sessions, caffeine, water, step bursts, stretches with no data, a journal note) beside the curves a
// 24 h strip draws (heart rate, hourly stress, cumulative steps).
//
// Pure and headless: no I/O, no clock, no localisation. Every input is a plain value the app layer
// assembles from the store (and, on iPhone, from the PaceForge snapshot), and `now` is passed in. The
// day is given as an explicit [dayStart, dayEnd) pair rather than 24 h, so a DST day (23 h or 25 h) is
// laid out over its real length. Strings built here are English and number-only; the screen owns
// clock times and unit formatting.
//
// Rules that matter, each pinned by DayTimelineTests:
//  - Workouts from different sources are ONE event when they overlap by at least half of the shorter
//    one AND start within ten minutes of each other (the same rule PaceForge's workout-matches.json
//    uses). The event lists every source badge; the Garmin record is canonical for metrics.
//  - A planned session is "done" when it is matched to an activity, "missed" once its day has passed.
//    A matched plan folds into the workout it was done as instead of showing twice.
//  - A stretch with no heart rate for 10 minutes or more becomes a no-data event while the day is not
//    over. The heart-rate curve lifts the pen across it; nothing is ever interpolated.
//  - Journal answers are one untimed day note.
//  - A detected stretch is shown as a Walk (not a workout) when `DetectedSegmentClassifier` says so, and
//    is marked "Already recorded", with that workout's sport, when a recorded workout covers more than
//    half of it. A saved workout that explains less than half of it still hides it (the old rule).

public struct DayTimeline: Equatable, Sendable {

    // MARK: Vocabulary

    public enum Kind: String, Sendable, CaseIterable {
        case sleep, nap, workout, detected, planned, weighIn, caffeine, water, stepsBurst, noData, dayNote
    }

    /// Where a record came from, shown as a badge. `plan` is the PaceForge plan the record was matched to.
    public enum Source: String, Sendable, CaseIterable {
        case strap, garmin, apple, paceforge, plan, imported

        public var badge: String {
            switch self {
            case .strap: return "Strap"
            case .garmin: return "Garmin"
            case .apple: return "Apple"
            case .paceforge: return "PaceForge"
            case .plan: return "Plan"
            case .imported: return "Imported"
            }
        }
    }

    public enum Status: String, Sendable {
        case none, planned, done, missed
    }

    /// Why a stretch has no heart rate, chosen from the hints that exist; `noHeartRate` is the plain fallback.
    public enum NoDataReason: String, Sendable {
        case charging, batteryEmpty, syncPending, noHeartRate

        public var text: String {
            switch self {
            case .charging: return "Strap was charging"
            case .batteryEmpty: return "Strap battery ran out"
            case .syncPending: return "Not synced yet"
            case .noHeartRate: return "No heart rate recorded"
            }
        }
    }

    /// Where a row opens. The app resolves the key against the rows it loaded.
    public enum Route: Equatable, Sendable {
        case none
        case workout(key: String)
        case sleep(startTs: Int)
        /// A bike ride PaceForge logged with a ride id ("bike:<date>"); the iPhone app opens its ride screen.
        case ride(id: String)
    }

    public struct Metrics: Equatable, Sendable {
        public var durationSec: Int?
        public var avgHr: Int?
        public var maxHr: Int?
        public var kcal: Double?
        public var distanceM: Double?
        public var weightKg: Double?
        public var mg: Double?
        public var ml: Int?
        public var steps: Int?

        public init(durationSec: Int? = nil, avgHr: Int? = nil, maxHr: Int? = nil, kcal: Double? = nil,
                    distanceM: Double? = nil, weightKg: Double? = nil, mg: Double? = nil, ml: Int? = nil,
                    steps: Int? = nil) {
            self.durationSec = durationSec; self.avgHr = avgHr; self.maxHr = maxHr; self.kcal = kcal
            self.distanceM = distanceM; self.weightKg = weightKg; self.mg = mg; self.ml = ml; self.steps = steps
        }
    }

    public struct Event: Identifiable, Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let start: Date
        public let end: Date?
        /// No clock time (a plan with no slot, a weigh-in, the journal note): listed under "All day".
        public let isUntimed: Bool
        public let title: String
        public let subtitle: String
        public let sources: [Source]
        public let status: Status
        public let route: Route
        public let metrics: Metrics
        public let noDataReason: NoDataReason?
        /// A sleep that began on the previous day / runs on past this one. The real start and end are kept;
        /// the strip clips them to the day.
        public let continuesFromPreviousDay: Bool
        public let continuesToNextDay: Bool
        /// Set on `.detected` rows only: what the suggestion looks like and whether it is already recorded.
        public let suggestion: Suggestion?

        public init(id: String, kind: Kind, start: Date, end: Date? = nil, isUntimed: Bool = false,
                    title: String, subtitle: String = "", sources: [Source] = [], status: Status = .none,
                    route: Route = .none, metrics: Metrics = Metrics(), noDataReason: NoDataReason? = nil,
                    continuesFromPreviousDay: Bool = false, continuesToNextDay: Bool = false,
                    suggestion: Suggestion? = nil) {
            self.id = id; self.kind = kind; self.start = start; self.end = end; self.isUntimed = isUntimed
            self.title = title; self.subtitle = subtitle; self.sources = sources; self.status = status
            self.route = route; self.metrics = metrics; self.noDataReason = noDataReason
            self.continuesFromPreviousDay = continuesFromPreviousDay
            self.continuesToNextDay = continuesToNextDay
            self.suggestion = suggestion
        }
    }

    /// A detected, unsaved stretch. `guess` says walk or workout; `recordedAs` is the sport of the recorded
    /// workout that already covers it (more than half of it), in which case there is nothing to save.
    public struct Suggestion: Equatable, Sendable {
        public let guess: DetectedSegmentClassifier.Guess
        public let recordedAs: String?
        public var isRecorded: Bool { recordedAs != nil }
        public init(guess: DetectedSegmentClassifier.Guess, recordedAs: String? = nil) {
            self.guess = guess; self.recordedAs = recordedAs
        }
    }

    public struct HRPoint: Equatable, Sendable {
        public let ts: Int
        public let bpm: Double
        /// Lift the pen before this point: nothing was recorded for at least `gapSec` before it.
        public let startsRun: Bool
        public init(ts: Int, bpm: Double, startsRun: Bool) {
            self.ts = ts; self.bpm = bpm; self.startsRun = startsRun
        }
    }

    public struct StressPoint: Equatable, Sendable {
        public let ts: Int
        /// The 0-3 stress proxy, or nil for an hour left unscored (no data, or masked as exertion).
        public let level: Double?
        public let maskedForActivity: Bool
        public init(ts: Int, level: Double?, maskedForActivity: Bool = false) {
            self.ts = ts; self.level = level; self.maskedForActivity = maskedForActivity
        }
    }

    public struct StepPoint: Equatable, Sendable {
        public let ts: Int
        public let cumulative: Int
        public init(ts: Int, cumulative: Int) { self.ts = ts; self.cumulative = cumulative }
    }

    /// One reading of a 0-100 curve that comes from an outside source (Garmin Body Battery, Garmin stress).
    /// Kept apart from NOOP's own series: the two are never merged into one curve.
    public struct SeriesPoint: Equatable, Sendable {
        public let ts: Int
        public let value: Double
        public init(ts: Int, value: Double) { self.ts = ts; self.value = value }
    }

    /// The last stretch where the outside energy curve climbed, for a "last recharge" line. The times may
    /// fall before this day's start: a night's recharge begins the evening before.
    public struct Recharge: Equatable, Sendable {
        public let startTs: Int?
        public let endTs: Int?
        public let from: Double?
        public let to: Double?
        public let minutes: Int?
        public init(startTs: Int?, endTs: Int?, from: Double?, to: Double?, minutes: Int?) {
            self.startTs = startTs; self.endTs = endTs; self.from = from; self.to = to; self.minutes = minutes
        }

        /// "Last recharge 22:10\u{2013}06:05 \u{00B7} 22 \u{2192} 71 \u{00B7} 8h 00m", or nil when nothing is known.
        /// The screen owns clock formatting, so it passes the clock in.
        public func text(clock: (Int) -> String) -> String? {
            var parts: [String] = []
            if let startTs, let endTs {
                parts.append("\(clock(startTs))\u{2013}\(clock(endTs))")
            } else if let endTs {
                parts.append("ended \(clock(endTs))")
            }
            if let from, let to {
                parts.append("\(Int(from.rounded())) \u{2192} \(Int(to.rounded()))")
            } else if let to {
                parts.append("to \(Int(to.rounded()))")
            }
            if let minutes, minutes > 0 { parts.append(DayTimeline.durationText(minutes * 60)) }
            return parts.isEmpty ? nil : "Last recharge " + parts.joined(separator: " \u{00B7} ")
        }
    }

    // MARK: Constants

    /// No heart rate for this long makes a no-data event.
    public static let gapSec = 600
    /// The heart-rate curve never carries more points than this, whatever the day's length.
    public static let maxCurvePoints = 600
    /// Two workouts are the same when they overlap by this share of the shorter one...
    public static let sameWorkoutOverlap = 0.5
    /// ...and start within this many seconds of each other.
    public static let sameWorkoutStartSec = 600

    // MARK: Output

    public let dayStart: Date
    public let dayEnd: Date
    public let now: Date
    /// "All day" rows first, then timed rows newest first.
    public let events: [Event]
    public let hr: [HRPoint]
    public let stress: [StressPoint]
    public let stepsCumulative: [StepPoint]
    /// Garmin Body Battery (0-100) and Garmin stress (0-100), when the platform brought them. Empty on a
    /// device without PaceForge; a separate curve each, never mixed with `stress` above.
    public let energy: [SeriesPoint]
    public let garminStress: [SeriesPoint]
    public let recharge: Recharge?

    public var dayLengthSec: Int { Int(dayEnd.timeIntervalSince(dayStart)) }
    public var isDayOver: Bool { now >= dayEnd }
    public var hasHeartRate: Bool { !hr.isEmpty }
    /// Anything the strap or a log recorded: heart rate, or an event that is not just a plan or a gap.
    public var hasRecordedData: Bool {
        hasHeartRate || events.contains { $0.kind != .noData && $0.kind != .planned }
    }

    /// Where `now` falls across the day, 0...1, or nil when it is outside the day.
    public var nowFraction: Double? {
        guard now >= dayStart, now < dayEnd, dayLengthSec > 0 else { return nil }
        return now.timeIntervalSince(dayStart) / Double(dayLengthSec)
    }

    /// The start and end of the calendar day holding `date`. A DST day is 23 or 25 hours long.
    public static func dayBounds(containing date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}
