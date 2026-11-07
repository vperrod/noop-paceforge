import Foundation

// "Insights v2": PaceForge's insights-v2.json, six rules-written items that say what a number means and what to
// do about it (power curve and FTP, race countdown, weight goal, efficiency, sleep, next best action). Foundation
// only, so the parsing, the ordering and the small pure helpers the charts draw from (finish range, FTP rows,
// sleep clock, projected date) are compiled into the macOS unit-test bundle as well.
//
// Every field is optional on the wire. A missing file, a missing item or an item with `available: false` leaves
// that part out or shows the server's own reason; nothing here is ever worked out from the athlete's data on the
// phone, and the app only reads: guidance is a suggestion, nothing changes a plan.

// MARK: - Ids

enum PFInsightID {
    static let powerCurve = "power_curve"
    static let raceCountdown = "race_countdown"
    static let weightGoal = "weight_goal"
    static let efficiency = "efficiency"
    static let sleep = "sleep"
    static let nextBestAction = "next_best_action"

    /// The server's order, used for any item its own `order` does not name.
    static let canonical = [powerCurve, raceCountdown, weightGoal, efficiency, sleep, nextBestAction]

    private static let aliases = ["power": powerCurve, "ftp": powerCurve, "race": raceCountdown, "weight": weightGoal,
                                  "next": nextBestAction, "next_action": nextBestAction]

    /// The item a `noop://paceforge/...` path names, from its path components (the leading "/" is ignored):
    /// `insights/power-curve`, `insights/sleep` or the short form `power-curve`. nil for anything else, including a bare
    /// `insights`, which opens the Insights tab as it always has.
    static func linkedID(pathComponents: [String]) -> String? {
        let parts = pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = parts.first?.lowercased() else { return nil }
        let candidate = (first == "insights" || first == "insight") ? parts.dropFirst().first : first
        guard let id = normalised(candidate), canonical.contains(id) else { return nil }
        return id
    }

    /// The id a deep-link segment names: "power-curve", "Power_Curve" and "power" all give "power_curve".
    /// nil for an empty segment; an id the app does not know is returned as written (lower-cased).
    static func normalised(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        let id = text.replacingOccurrences(of: "-", with: "_")
        return aliases[id] ?? id
    }
}

// MARK: - Status, effort, action

/// How a status chip is coloured. Neutral wording: a position on a scale, never a grade.
enum PFInsightTone: Equatable {
    case positive, neutral, caution, unknown
}

struct PFInsightStatus: Equatable {
    var label: String?
    var scale: [String] = []
    /// The rule that produced the label, in the server's words.
    var threshold: String?
    /// Why there is no label (the data cannot place the athlete).
    var reason: String?

    /// "on-track" gives "On track"; nil label gives "Not rated".
    var chipText: String {
        guard let label, !label.isEmpty else { return "Not rated" }
        let spaced = label.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// The first scale entry is the one to look at, the second is neutral, the rest are the good end. A label that is
    /// not on the scale (or a scale too short to rank) is neutral rather than guessed at.
    var tone: PFInsightTone {
        guard let label, !label.isEmpty else { return .unknown }
        guard let index = scale.firstIndex(of: label), scale.count >= 3 else { return .neutral }
        if index == 0 { return .caution }
        return index == 1 ? .neutral : .positive
    }
}

struct PFInsightEffort: Equatable {
    var value: Int?
    /// min, min/day, min/week or min/session.
    var unit: String?
    var label: String?

    /// "no extra time", "10 min/day": the server's label, else built from the value and unit, else "effort unknown".
    var text: String {
        if let label, !label.isEmpty { return label }
        guard let value else { return "effort unknown" }
        if value == 0 { return "no extra time" }
        return "\(value) \(unit ?? "min")"
    }

    var chipText: String { text.prefix(1).uppercased() + text.dropFirst() }
    var isFree: Bool { value == 0 }
}

struct PFInsightAction: Identifiable, Equatable {
    var id: String
    var text: String
    /// Cites the athlete's own numbers.
    var why: String?
    var effort: PFInsightEffort?
    /// 1 (small) to 5 (large).
    var impact: Int?
    var topic: String?
    var tags: [String] = []

    var impactText: String? { impact.map { "Impact \($0) of 5" } }
}

// MARK: - Per-item metrics

struct PFPowerBest: Equatable {
    var watts: Double
    var date: String?
    var workout: String?
}

struct PFPowerDuration: Identifiable, Equatable {
    var seconds: Int
    var label: String
    var best90: PFPowerBest?
    var bestAll: PFPowerBest?
    var wPerKg90: Double?
    var id: Int { seconds }
}

struct PFPowerCurvePoint: Identifiable, Equatable {
    var seconds: Int
    var last90: Double?
    var allTime: Double?
    var id: Int { seconds }
}

struct PFGarminFTP: Equatable {
    var value: Double
    var date: String?
    var isStale: Bool
    var source: String?
}

struct PFPowerProfileRow: Identifiable, Equatable {
    var seconds: Int
    var label: String
    var watts: Double?
    var pctFtp: Int?
    var expected: String?
    /// gap, typical or strong.
    var verdict: String?
    var id: String { label }
}

struct PFFTPRow: Identifiable, Equatable {
    var id: String
    var label: String
    var watts: Double
    var note: String?
}

struct PFPowerMetric: Equatable {
    var asOf: String?
    var windowDays: Int?
    var durations: [PFPowerDuration] = []
    var curve: [PFPowerCurvePoint] = []
    var estimateW: Double?
    var method: String?
    var evidence: PFPowerBest?
    var cpW: Double?
    var wPrimeKj: Double?
    var allTimeEstimateW: Double?
    var inUseW: Double?
    var inUseBasis: String?
    var garmin: PFGarminFTP?
    var wPerKg: Double?
    var vsInUsePct: Double?
    var retestDue: Bool?
    var retestNextDate: String?
    var retestReason: String?
    var profile: [PFPowerProfileRow] = []
    var rideCount: Int?

    /// Whether the plot has anything to draw: at least one duration with a recent best.
    var hasCurve: Bool { curve.contains { $0.last90 != nil } }

    /// The three FTP figures side by side: this estimate, Garmin's own and the one the ride maths uses. A figure the
    /// server did not send is left out, so an empty list means there is nothing to compare.
    var ftpRows: [PFFTPRow] {
        var rows: [PFFTPRow] = []
        if let estimateW {
            rows.append(PFFTPRow(id: "estimate", label: "Estimate", watts: estimateW, note: method))
        }
        if let garmin {
            let when = garmin.date.map { " from \($0)" } ?? ""
            rows.append(PFFTPRow(id: "garmin", label: "Garmin", watts: garmin.value,
                                 note: garmin.isStale ? "Flagged stale\(when)" : "Garmin's own figure\(when)"))
        }
        if let inUseW {
            rows.append(PFFTPRow(id: "in-use", label: "In use", watts: inUseW, note: inUseBasis))
        }
        return rows
    }
}

struct PFFinishRange: Equatable {
    var discipline: String?
    var centralS: Double?
    var lowS: Double?
    var highS: Double?
    var central: String?
    var low: String?
    var high: String?
    var goalS: Double?
    var goal: String?
    var gapToGoalS: Int?
    var goalInRange: Bool?
    var method: String?
    var rangeBasis: String?

    /// Where the range sits on a bar: positions 0...1 of the low end, the central time and the goal, with a margin
    /// around everything. nil when the range is not complete.
    var bar: (low: Double, central: Double, high: Double, goal: Double?)? {
        guard let lowS, let highS, let centralS, highS >= lowS else { return nil }
        let points = [lowS, highS, centralS] + (goalS.map { [$0] } ?? [])
        guard let first = points.min(), let last = points.max() else { return nil }
        let span = max(last - first, 1)
        let margin = span * 0.12
        let start = first - margin, width = span + 2 * margin
        func position(_ value: Double) -> Double { (value - start) / width }
        return (position(lowS), position(centralS), position(highS), goalS.map(position))
    }

    /// "4 min 10 s faster than the goal" / "slower"; nil when there is no goal.
    var gapText: String? {
        guard let gapToGoalS else { return nil }
        if gapToGoalS == 0 { return "On the goal time" }
        let magnitude = abs(gapToGoalS)
        let clock = magnitude >= 3600
            ? String(format: "%d:%02d:%02d", magnitude / 3600, (magnitude % 3600) / 60, magnitude % 60)
            : String(format: "%d:%02d", magnitude / 60, magnitude % 60)
        return "\(clock) \(gapToGoalS > 0 ? "slower" : "faster") than the goal"
    }
}

struct PFGarminPrediction: Identifiable, Equatable {
    var distance: String
    var display: String?
    var id: String { distance }

    /// "10K" stays "10K"; "HALF_MARATHON" gives "Half marathon".
    var label: String {
        if distance.first?.isNumber == true { return distance }
        let words = distance.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

struct PFRacePhase: Identifiable, Equatable {
    var id: String
    var label: String
    var from: String?
    var to: String?
    var protects: String?
    var cuts: String?
    var isCurrent: Bool
}

struct PFFormPoint: Identifiable, Equatable {
    var date: String
    var ctl: Double
    var atl: Double
    var tsb: Double
    var id: String { date }
}

struct PFTaper: Equatable {
    /// adequate, short, not enough, over-tapered or unknown.
    var verdict: String?
    var reason: String?
    var tsbLow: Double?
    var tsbHigh: Double?
    var raceMorningTsb: Double?
    var scenarioTsb: Double?

    var hasWindow: Bool { tsbLow != nil && tsbHigh != nil }
}

struct PFRaceMetric: Equatable {
    var name: String?
    var date: String?
    var type: String?
    var goalTime: String?
    var daysTo: Int?
    /// build, sharpen, taper, eve or day.
    var phase: String?
    var phases: [PFRacePhase] = []
    var raceWeekStarts: String?
    var finish: PFFinishRange?
    var garminPredictions: [PFGarminPrediction] = []
    var garminPredictionsDate: String?
    var form: [PFFormPoint] = []
    var taper: PFTaper?

    /// "In 38 days", "Tomorrow", "Today", "Done".
    var countdownText: String? {
        guard let daysTo else { return nil }
        switch daysTo {
        case ..<0: return "Done"
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(daysTo) days"
        }
    }
}

struct PFWeightReading: Identifiable, Equatable {
    var date: String
    var weightKg: Double?
    var trendKg: Double?
    var bandLowKg: Double?
    var bandHighKg: Double?
    var id: String { date }
}

struct PFWeightPathPoint: Identifiable, Equatable {
    var date: String
    var weightKg: Double
    var id: String { date }
}

struct PFWeightMetric: Equatable {
    var asOf: String?
    var targetKg: Double?
    var targetDate: String?
    var startKg: Double?
    var startDate: String?
    var trendKg: Double?
    var lastReadingKg: Double?
    var kgToGo: Double?
    var weeksLeft: Double?
    var neededKgPerWeek: Double?
    var actualKgPerWeek: Double?
    var paceRatio: Double?
    var projectedDate: String?
    var projectedDaysVsTarget: Int?
    var noiseKg: Double?
    var noiseBasis: String?
    var pathTodayKg: Double?
    var vsPathKg: Double?
    var withinNoise: Bool?
    var aggressive: Bool?
    var safeKgPerWeek: Double?
    var deficitKcalPerDay: Double?
    var readings: Int?
    var series: [PFWeightReading] = []
    var path: [PFWeightPathPoint] = []
    var bodyFatTargetPct: Double?
    var bodyFatTrendPct: Double?

    /// The trend needs two readings to be a line.
    var hasTrend: Bool { series.filter { $0.trendKg != nil }.count >= 2 }

    /// The needed path (start to target) when the server sent both ends.
    var neededPath: [PFWeightPathPoint] { path.count >= 2 ? path : [] }

    /// From today's trend to the target on the projected date; empty when no date can be projected.
    var projectedLine: [PFWeightPathPoint] {
        guard let asOf, let trendKg, let projectedDate, let targetKg else { return [] }
        return [PFWeightPathPoint(date: asOf, weightKg: trendKg), PFWeightPathPoint(date: projectedDate, weightKg: targetKg)]
    }

    /// "Projected 12 Dec (3 days late)", "Projected 2 Dec (4 days early)", "Projected on the target day", or the reason no
    /// date exists. `dateText` formats an ISO day for the screen.
    func scheduleText(dateText: (String) -> String) -> String {
        guard let projectedDate else {
            if let kgToGo, kgToGo <= 0 { return "At or below the target" }
            return "No date can be projected yet"
        }
        let day = dateText(projectedDate)
        guard let days = projectedDaysVsTarget else { return "Projected \(day)" }
        if days == 0 { return "Projected \(day), on the target day" }
        return "Projected \(day) (\(abs(days)) day\(abs(days) == 1 ? "" : "s") \(days > 0 ? "late" : "early"))"
    }

    /// Whether the trend sits inside the scale's noise band around the straight line to the target.
    var pathText: String? {
        guard let vsPathKg else { return nil }
        let size = PFNumber.trimmedOne(abs(vsPathKg))
        let side = vsPathKg > 0 ? "above" : "below"
        let noise = withinNoise == true ? "inside the scale's noise" : "outside the scale's noise"
        return abs(vsPathKg) < 0.05 ? "On the straight line to the target" : "\(size) kg \(side) the straight line, \(noise)"
    }
}

struct PFRunEfficiencyPoint: Identifiable, Equatable {
    var date: String
    var paceAtRefHrS: Double?
    var ef: Double?
    var id: String { date }
}

struct PFBikeEfficiencyPoint: Identifiable, Equatable {
    var date: String
    var z2PowerW: Double?
    var id: String { date }
}

struct PFRunEfficiency: Equatable {
    /// improving, steady, declining or insufficient_data.
    var verdict: String?
    var threshold: String?
    var changePct: Double?
    var recentRuns: Int?
    var priorRuns: Int?
    var referenceHr: Int?
    var paceRecentS: Double?
    var pacePriorS: Double?
    var decouplingPct: Double?
    var decouplingVerdict: String?
    var treadmillRunsLeftOut: Int?
    var series: [PFRunEfficiencyPoint] = []
    var eligibility: String?

    var isReadable: Bool { (verdict ?? "insufficient_data") != "insufficient_data" }
}

struct PFBikeEfficiency: Equatable {
    var verdict: String?
    var threshold: String?
    var changePct: Double?
    var recentRides: Int?
    var priorRides: Int?
    var powerRecentW: Double?
    var powerPriorW: Double?
    var series: [PFBikeEfficiencyPoint] = []
    var eligibility: String?

    var isReadable: Bool { (verdict ?? "insufficient_data") != "insufficient_data" }
}

struct PFZoneSplit: Equatable {
    var weeks: Int
    var available: Bool
    var sessions: Int?
    var perWeekMin: Int?
    var lowPct: Double?
    var midPct: Double?
    var highPct: Double?
    /// polarized, acceptable or too_much_mid.
    var grade: String?
    var onTarget: Bool?
    var midToMoveMinPerWeek: Int?

    /// The share of time in zones 1-2 an 80/20 pattern aims for.
    static let easyTargetPct = 80.0

    var gradeText: String? {
        switch grade {
        case "polarized": return "Polarized"
        case "acceptable": return "Acceptable"
        case "too_much_mid": return "Too much in the middle"
        default: return nil
        }
    }

    /// The three shares as bar fractions (easy, middle, hard); nil unless all three are present.
    var shares: (easy: Double, mid: Double, hard: Double)? {
        guard available, let lowPct, let midPct, let highPct else { return nil }
        return (lowPct, midPct, highPct)
    }
}

struct PFEfficiencyMetric: Equatable {
    var running = PFRunEfficiency()
    var bike = PFBikeEfficiency()
    /// Runs only, by window ("4", "12" weeks).
    var runZones: [String: PFZoneSplit] = [:]
    var zonesThreshold: String?
    var easyHrCap: Int?

    /// The 4-week split first, else the 12-week one, else nil.
    var zoneSplit: PFZoneSplit? {
        for key in ["4", "12"] {
            if let split = runZones[key], split.available { return split }
        }
        return nil
    }
}

struct PFSleepWindow: Identifiable, Equatable {
    var date: String
    var bedtime: String?
    var wake: String?
    /// Minutes after 18:00, so a bedtime either side of midnight sits on one scale.
    var bedMin: Double?
    var wakeMin: Double?
    var hours: Double?
    var isTravel: Bool
    var id: String { date }
}

struct PFSleepDebt: Equatable {
    var days: Int?
    var nights: Int?
    var debtH: Double?
    var avgH: Double?
    var shortfallNights: Int?
}

struct PFSleepMetric: Equatable {
    var nights: Int?
    var regularityNights: Int?
    var bedtimeMean: String?
    var bedtimeSdMin: Double?
    var wakeMedian: String?
    var wakeSdMin: Double?
    var regularityIndex: Double?
    var needH: Double?
    var needBasis: String?
    var debt7: PFSleepDebt?
    var debt14: PFSleepDebt?
    var garminDebtH: Double?
    var garminNeedH: Double?
    var targetWake: String?
    var targetBedtime: String?
    var targetWindow: [String] = []
    var timeInBedH: Double?
    var shiftMin: Int?
    var paybackExtraMinPerNight: Int?
    var paybackNights: Int?
    var series: [PFSleepWindow] = []

    /// Spread needs enough nights; the server leaves both null otherwise.
    var hasSpread: Bool { bedtimeSdMin != nil && wakeSdMin != nil }
    var hasNights: Bool { series.contains { $0.bedMin != nil || $0.wakeMin != nil } }
}

/// Clock-time maths for the sleep charts. Bedtimes are drawn on a scale of minutes after 18:00.
enum PFSleepClock {
    static let eveningOffsetMin = 18 * 60

    /// "23:10" gives 1390; nil for text that is not HH:mm.
    static func minutes(of clock: String?) -> Int? {
        guard let clock else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// "23:10" gives 310 (minutes after 18:00); "00:30" gives 390.
    static func sinceEvening(_ clock: String?) -> Double? {
        guard let total = minutes(of: clock) else { return nil }
        return Double((total - eveningOffsetMin + 1440) % 1440)
    }

    /// 310 gives "23:10"; the inverse of `sinceEvening`.
    static func clock(sinceEvening value: Double) -> String {
        let total = (Safe.int(value) + eveningOffsetMin) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 450 gives "07:30".
    static func clock(minutesOfDay value: Double) -> String {
        let total = ((Safe.int(value) % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct PFRankedAction: Identifiable, Equatable {
    var action: PFInsightAction
    var source: String?
    var ease: Int?
    var relevance: Int?
    var modifier: Double?
    var score: Double?
    /// "impact 4 x ease 5 x relevance 3 = 60".
    var reason: String?
    var alsoSuggestedBy: [String] = []
    var id: String { action.id }
}

struct PFNextActionMetric: Equatable {
    var chosen: PFRankedAction?
    var runnerUps: [PFRankedAction] = []
    var considered: Int?
    var topics: Int?
    var readinessWord: String?
    var readinessStrained: Bool?
    var readinessEvidence: [String] = []
    var rankingBasis: String?
}

// MARK: - Verdict wording

/// The words and tones for the server's trend verdicts and the profile / taper verdicts.
enum PFInsightVerdict {
    /// improving, steady, declining or insufficient_data (running and bike efficiency).
    static func trendTone(_ verdict: String?) -> PFInsightTone {
        switch verdict {
        case "improving": return .positive
        case "steady": return .neutral
        case "declining": return .caution
        default: return .unknown
        }
    }

    static func trendText(_ verdict: String?) -> String {
        switch verdict {
        case "improving": return "Improving"
        case "steady": return "Steady"
        case "declining": return "Declining"
        default: return "Not enough data"
        }
    }

    /// gap, typical or strong (a power-profile row).
    static func profileTone(_ verdict: String?) -> PFInsightTone {
        switch verdict {
        case "gap": return .caution
        case "typical": return .neutral
        case "strong": return .positive
        default: return .unknown
        }
    }

    static func profileText(_ verdict: String?) -> String {
        switch verdict {
        case "gap": return "Gap"
        case "typical": return "Typical"
        case "strong": return "Strong"
        default: return "Not rated"
        }
    }

    /// The taper verdict: inside the window is good; short, not enough and over-tapered are the ones to look at.
    static func taperTone(_ verdict: String?) -> PFInsightTone {
        switch verdict {
        case "adequate": return .positive
        case "short", "not enough", "over-tapered": return .caution
        default: return .unknown
        }
    }

    static func taperText(_ verdict: String?) -> String {
        switch verdict {
        case "adequate": return "Taper on track"
        case "short": return "Taper a little short"
        case "not enough": return "Taper not enough"
        case "over-tapered": return "Over-tapered"
        default: return "Taper not known yet"
        }
    }
}

// MARK: - Item and document

struct PFInsightItem: Identifiable, Equatable {
    var id: String
    var title: String
    /// False when the data does not exist; then `meaning` says why and there are no actions.
    var available: Bool
    var status = PFInsightStatus()
    var meaning: String?
    var actions: [PFInsightAction] = []
    /// high, medium or low.
    var confidence: String?
    /// What is missing, estimated or assumed.
    var dataNote: String?
    var power: PFPowerMetric?
    var race: PFRaceMetric?
    var weight: PFWeightMetric?
    var efficiency: PFEfficiencyMetric?
    var sleep: PFSleepMetric?
    var next: PFNextActionMetric?

    /// The one card line under the title: the meaning, else the status reason, else the data note.
    var summaryText: String? { meaning ?? status.reason ?? dataNote }

    var chipText: String {
        id == PFInsightID.nextBestAction && status.label != nil ? "Priority \(status.chipText.lowercased())" : status.chipText
    }

    /// The next-best-action label is a priority, not a verdict, so it is never coloured good or bad.
    var tone: PFInsightTone { id == PFInsightID.nextBestAction && status.label != nil ? .neutral : status.tone }

    var confidenceText: String? { confidence.map { "\($0.prefix(1).uppercased() + $0.dropFirst()) confidence" } }

    /// What "Not today" hashes: the chosen action's id and wording, so the card comes back when the advice changes,
    /// not when its ranking score does.
    var dismissText: String {
        guard let action = actions.first else { return id }
        return "\(action.id)|\(action.text)"
    }

    /// The Hide-numbers switch that covers this item's figures: body weight for the weight goal. The other items show
    /// power, times and durations, which neither switch covers (sentences go through PFRedact for the figures they do).
    var hideKind: PFRedact.Kind? { id == PFInsightID.weightGoal ? .body : nil }

    /// The one figure shown on the card in the Insights list, with what it is. nil when the item has no number to lead
    /// with (then the card shows its meaning).
    var headline: PFInsightHeadline? {
        guard available else { return nil }
        switch id {
        case PFInsightID.powerCurve:
            guard let watts = power?.estimateW else { return nil }
            var caption = "FTP estimate"
            if let pct = power?.vsInUsePct { caption += ", \(PFNumber.signed(pct, decimals: 0)) % against the FTP in use" }
            return PFInsightHeadline(value: "\(Safe.int(watts)) W", caption: caption)
        case PFInsightID.raceCountdown:
            guard let race, let days = race.daysTo else { return nil }
            return PFInsightHeadline(value: days > 1 ? "\(days) days" : (race.countdownText ?? "\(days) days"),
                                     caption: race.name ?? "to the race")
        case PFInsightID.weightGoal:
            guard let trend = weight?.trendKg else { return nil }
            let togo = weight?.kgToGo.map { $0 > 0 ? "\(PFNumber.trimmedOne($0)) kg to go" : "at or below the target" }
            return PFInsightHeadline(value: "\(PFNumber.trimmedOne(trend)) kg", caption: togo ?? "weight trend")
        case PFInsightID.efficiency:
            if let run = efficiency?.running, run.isReadable, let change = run.changePct {
                return PFInsightHeadline(value: "\(PFNumber.signed(change)) %", caption: "Running, \(run.verdict ?? "steady")")
            }
            if let bike = efficiency?.bike, bike.isReadable, let change = bike.changePct {
                return PFInsightHeadline(value: "\(PFNumber.signed(change)) %", caption: "Bike, \(bike.verdict ?? "steady")")
            }
            if let split = efficiency?.zoneSplit, let low = split.lowPct {
                return PFInsightHeadline(value: "\(Safe.int(low)) %", caption: "easy running time, \(split.weeks) weeks")
            }
            return nil
        case PFInsightID.sleep:
            if let debt = sleep?.debt7?.debtH {
                return PFInsightHeadline(value: "\(PFNumber.trimmedOne(debt)) h", caption: "owed over 7 nights")
            }
            if let bed = sleep?.bedtimeSdMin, let wake = sleep?.wakeSdMin {
                return PFInsightHeadline(value: "\(Safe.int(max(bed, wake))) min", caption: "bed and wake spread")
            }
            return nil
        case PFInsightID.nextBestAction:
            guard let action = actions.first else { return nil }
            return PFInsightHeadline(value: action.effort?.chipText ?? "", caption: "to do it")
        default:
            return nil
        }
    }
}

/// A key figure and what it is, for the Insights list.
struct PFInsightHeadline: Equatable {
    var value: String
    var caption: String
}

struct PFInsightsV2: Equatable {
    var version: Int?
    var generatedAt: String?
    var asOf: String?
    /// The ids the server listed, in its order.
    var order: [String] = []
    var items: [String: PFInsightItem] = [:]

    func item(_ id: String) -> PFInsightItem? { items[id] }

    /// Every item in screen order: the server's `order` (ids with no item skipped, repeats dropped), then any item it
    /// did not name in the canonical order, then any id the app has never heard of by name.
    var ordered: [PFInsightItem] {
        var seen = Set<String>()
        var ids: [String] = []
        for id in order + PFInsightID.canonical + items.keys.sorted() where items[id] != nil && seen.insert(id).inserted {
            ids.append(id)
        }
        return ids.compactMap { items[$0] }
    }

    /// The cards for the Insights tab: everything except the next best action, which lives on Today.
    var insightCards: [PFInsightItem] { ordered.filter { $0.id != PFInsightID.nextBestAction } }

    var nextBestAction: PFInsightItem? { items[PFInsightID.nextBestAction] }

    /// The item behind the Today card; nil when there is no advice to show (an unavailable item is not worth a card).
    var todayCard: PFInsightItem? {
        guard let next = nextBestAction, next.available, !next.actions.isEmpty else { return nil }
        return next
    }

    /// Whether any item has something to show (an unavailable item still shows its reason).
    var hasContent: Bool { !items.isEmpty }
}

// MARK: - Parsing

enum PFInsightsV2Parse {
    static func document(_ j: PFJ) -> PFInsightsV2? {
        guard j.exists, j.raw is [String: Any] else { return nil }
        var out = PFInsightsV2()
        out.version = j["version"].int
        out.generatedAt = j["generated_at"].text
        out.asOf = j["as_of"].text
        out.order = j["order"].array.compactMap { $0.idString }
        for (key, value) in j["items"].dict {
            if let item = item(value, key: key) { out.items[item.id] = item }
        }
        return out.items.isEmpty ? nil : out
    }

    static func item(_ i: PFJ, key: String) -> PFInsightItem? {
        guard i.exists, i.raw is [String: Any] else { return nil }
        let id = i["id"].idString ?? key
        let metric = i["metric"]
        var out = PFInsightItem(id: id, title: i["title"].text ?? PFBand.titleFromId(id),
                                available: i["available"].bool ?? !metric.dict.isEmpty)
        out.status = status(i["status"])
        out.meaning = i["meaning"].text
        out.actions = i["actions"].array.compactMap(action)
        out.confidence = i["confidence"].text
        out.dataNote = i["data_note"].text
        guard out.available else { out.actions = []; return out }
        switch id {
        case PFInsightID.powerCurve: out.power = power(metric)
        case PFInsightID.raceCountdown: out.race = race(metric)
        case PFInsightID.weightGoal: out.weight = weight(metric)
        case PFInsightID.efficiency: out.efficiency = efficiency(metric)
        case PFInsightID.sleep: out.sleep = sleep(metric)
        case PFInsightID.nextBestAction: out.next = nextAction(metric)
        default: break
        }
        return out
    }

    static func status(_ s: PFJ) -> PFInsightStatus {
        PFInsightStatus(label: s["label"].text, scale: s["scale"].strings, threshold: s["threshold"].text,
                        reason: s["reason"].text)
    }

    static func effort(_ e: PFJ) -> PFInsightEffort? {
        guard e.exists else { return nil }
        let out = PFInsightEffort(value: e["value"].int, unit: e["unit"].text, label: e["label"].text)
        return out.value == nil && out.label == nil ? nil : out
    }

    static func action(_ a: PFJ) -> PFInsightAction? {
        guard let id = a["id"].idString, let text = a["text"].text else { return nil }
        return PFInsightAction(id: id, text: text, why: a["why"].text, effort: effort(a["effort"]),
                               impact: a["impact"].int, topic: a["topic"].text, tags: a["tags"].strings)
    }

    // MARK: power_curve

    private static func best(_ b: PFJ) -> PFPowerBest? {
        guard let watts = b["watts"].double else { return nil }
        return PFPowerBest(watts: watts, date: b["date"].text, workout: b["workout"].text)
    }

    static func power(_ m: PFJ) -> PFPowerMetric {
        var out = PFPowerMetric()
        out.asOf = m["as_of"].text
        out.windowDays = m["window_days"].int
        out.durations = m["durations"].array.compactMap { d in
            guard let seconds = d["seconds"].int, let label = d["label"].text else { return nil }
            return PFPowerDuration(seconds: seconds, label: label, best90: best(d["best_90d"]),
                                   bestAll: best(d["best_all_time"]), wPerKg90: d["w_per_kg_90d"].double)
        }
        let seconds = m["curve"]["seconds"].array, recent = m["curve"]["last_90d"].array, all = m["curve"]["all_time"].array
        out.curve = seconds.enumerated().compactMap { index, s in
            guard let value = s.int else { return nil }
            return PFPowerCurvePoint(seconds: value, last90: index < recent.count ? recent[index].double : nil,
                                     allTime: index < all.count ? all[index].double : nil)
        }
        let ftp = m["ftp"]
        out.estimateW = ftp["estimate_w"].double
        out.method = ftp["method"].text
        out.evidence = best(ftp["evidence"])
        out.cpW = ftp["cp_fit"]["cp_w"].double
        out.wPrimeKj = ftp["cp_fit"]["w_prime_kj"].double
        out.allTimeEstimateW = ftp["all_time_estimate_w"].double
        out.inUseW = ftp["in_use_w"].double
        out.inUseBasis = ftp["in_use_basis"].text
        if let value = ftp["garmin"]["value"].double {
            out.garmin = PFGarminFTP(value: value, date: ftp["garmin"]["date"].text,
                                     isStale: ftp["garmin"]["stale"].bool ?? false, source: ftp["garmin"]["source"].text)
        }
        out.wPerKg = ftp["w_per_kg"].double
        out.vsInUsePct = ftp["vs_in_use_pct"].double
        out.retestDue = ftp["retest"]["due"].bool
        out.retestNextDate = ftp["retest"]["next_date"].text
        out.retestReason = ftp["retest"]["reason"].text
        out.profile = m["profile"].array.compactMap { p in
            guard let seconds = p["seconds"].int, let label = p["label"].text else { return nil }
            return PFPowerProfileRow(seconds: seconds, label: label, watts: p["watts"].double, pctFtp: p["pct_ftp"].int,
                                     expected: p["expected"].text, verdict: p["verdict"].text)
        }
        out.rideCount = m["ride_count"].int
        return out
    }

    // MARK: race_countdown

    static func race(_ m: PFJ) -> PFRaceMetric {
        var out = PFRaceMetric()
        out.name = m["event"]["name"].text
        out.date = m["event"]["date"].text
        out.type = m["event"]["type"].text
        out.goalTime = m["event"]["goal_time"].text
        out.daysTo = m["days_to"].int
        out.phase = m["phase"].text
        out.phases = m["phases"].array.compactMap { p in
            guard let id = p["id"].idString, let label = p["label"].text else { return nil }
            return PFRacePhase(id: id, label: label, from: p["from"].text, to: p["to"].text, protects: p["protect"].text,
                               cuts: p["cut"].text, isCurrent: p["current"].bool ?? false)
        }
        out.raceWeekStarts = m["race_week_starts"].text
        out.finish = finish(m["finish"])
        out.garminPredictions = m["garmin_predictions"].array.compactMap { p in
            guard let distance = p["distance"].text else { return nil }
            return PFGarminPrediction(distance: distance, display: p["display"].text)
        }
        out.garminPredictionsDate = m["garmin_predictions_date"].text
        out.form = form(m["form_curve"])
        out.taper = taper(m["taper"])
        return out
    }

    private static func finish(_ f: PFJ) -> PFFinishRange? {
        guard f.exists, f.raw is [String: Any] else { return nil }
        let out = PFFinishRange(discipline: f["discipline"].text, centralS: f["central_s"].double, lowS: f["low_s"].double,
                                highS: f["high_s"].double, central: f["central"].text, low: f["low"].text,
                                high: f["high"].text, goalS: f["goal_s"].double, goal: f["goal"].text,
                                gapToGoalS: f["gap_to_goal_s"].int, goalInRange: f["goal_in_range"].bool,
                                method: f["method"].text, rangeBasis: f["range_basis"].text)
        return out.centralS == nil && out.central == nil ? nil : out
    }

    private static func form(_ f: PFJ) -> [PFFormPoint] {
        let dates = f["dates"].array, ctl = f["ctl"].array, atl = f["atl"].array, tsb = f["tsb"].array
        return dates.enumerated().compactMap { index, d in
            guard let date = d.text, index < ctl.count, index < atl.count, index < tsb.count,
                  let c = ctl[index].double, let a = atl[index].double, let t = tsb[index].double else { return nil }
            return PFFormPoint(date: date, ctl: c, atl: a, tsb: t)
        }
    }

    private static func taper(_ t: PFJ) -> PFTaper? {
        guard t.exists, t.raw is [String: Any] else { return nil }
        return PFTaper(verdict: t["verdict"].text, reason: t["reason"].text, tsbLow: t["target_window"]["tsb_low"].double,
                       tsbHigh: t["target_window"]["tsb_high"].double, raceMorningTsb: t["race_morning"]["tsb"].double,
                       scenarioTsb: t["scenario"]["tsb"].double)
    }

    // MARK: weight_goal

    static func weight(_ m: PFJ) -> PFWeightMetric {
        var out = PFWeightMetric()
        out.asOf = m["as_of"].text
        out.targetKg = m["target_kg"].double
        out.targetDate = m["target_date"].text
        out.startKg = m["start_kg"].double
        out.startDate = m["start_date"].text
        out.trendKg = m["trend_kg"].double
        out.lastReadingKg = m["last_reading_kg"].double
        out.kgToGo = m["kg_to_go"].double
        out.weeksLeft = m["weeks_left"].double
        out.neededKgPerWeek = m["needed_kg_per_week"].double
        out.actualKgPerWeek = m["actual_kg_per_week"].double
        out.paceRatio = m["pace_ratio"].double
        out.projectedDate = m["projected_date"].text
        out.projectedDaysVsTarget = m["projected_days_vs_target"].int
        out.noiseKg = m["noise_kg"].double
        out.noiseBasis = m["noise_basis"].text
        out.pathTodayKg = m["path_today_kg"].double
        out.vsPathKg = m["vs_path_kg"].double
        out.withinNoise = m["within_noise"].bool
        out.aggressive = m["aggressive"].bool
        out.safeKgPerWeek = m["safe_kg_per_week"].double
        out.deficitKcalPerDay = m["deficit_kcal_per_day"].double
        out.readings = m["readings"].int
        out.series = m["series"].array.compactMap { r in
            guard let date = r["date"].text else { return nil }
            return PFWeightReading(date: date, weightKg: r["weight_kg"].double, trendKg: r["trend_kg"].double,
                                   bandLowKg: r["band_low_kg"].double, bandHighKg: r["band_high_kg"].double)
        }
        out.path = m["path"].array.compactMap { p in
            guard let date = p["date"].text, let kg = p["weight_kg"].double else { return nil }
            return PFWeightPathPoint(date: date, weightKg: kg)
        }
        out.bodyFatTargetPct = m["body_fat"]["target_pct"].double
        out.bodyFatTrendPct = m["body_fat"]["trend_pct"].double
        return out
    }

    // MARK: efficiency

    static func efficiency(_ m: PFJ) -> PFEfficiencyMetric {
        var out = PFEfficiencyMetric()
        let r = m["running"]
        out.running = PFRunEfficiency(
            verdict: r["verdict"].text, threshold: r["threshold"].text, changePct: r["change_pct"].double,
            recentRuns: r["recent_runs"].int, priorRuns: r["prior_runs"].int, referenceHr: r["reference_hr"].int,
            paceRecentS: r["pace_at_ref_hr_recent_s"].double, pacePriorS: r["pace_at_ref_hr_prior_s"].double,
            decouplingPct: r["decoupling_pct"].double, decouplingVerdict: r["decoupling_verdict"].text,
            treadmillRunsLeftOut: r["treadmill_runs_left_out"].int,
            series: r["series"].array.compactMap { p in
                guard let date = p["date"].text else { return nil }
                return PFRunEfficiencyPoint(date: date, paceAtRefHrS: p["pace_at_ref_hr_s"].double, ef: p["ef"].double)
            },
            eligibility: r["eligibility"].text)
        let b = m["bike"]
        out.bike = PFBikeEfficiency(
            verdict: b["verdict"].text, threshold: b["threshold"].text, changePct: b["change_pct"].double,
            recentRides: b["recent_rides"].int, priorRides: b["prior_rides"].int,
            powerRecentW: b["power_at_z2_recent_w"].double, powerPriorW: b["power_at_z2_prior_w"].double,
            series: b["series"].array.compactMap { p in
                guard let date = p["date"].text else { return nil }
                return PFBikeEfficiencyPoint(date: date, z2PowerW: p["z2_power_w"].double)
            },
            eligibility: b["eligibility"].text)
        for (key, z) in m["zones"]["runs"].dict {
            out.runZones[key] = PFZoneSplit(
                weeks: z["weeks"].int ?? Int(key) ?? 0, available: z["available"].bool ?? false, sessions: z["sessions"].int,
                perWeekMin: z["per_week_min"].int, lowPct: z["low_pct"].double, midPct: z["mid_pct"].double,
                highPct: z["high_pct"].double, grade: z["grade"].text, onTarget: z["on_target"].bool,
                midToMoveMinPerWeek: z["mid_to_move_min_per_week"].int)
        }
        out.zonesThreshold = m["zones"]["threshold"].text
        out.easyHrCap = m["easy_hr_cap"].int
        return out
    }

    // MARK: sleep

    private static func debt(_ d: PFJ) -> PFSleepDebt? {
        guard d.exists, d.raw is [String: Any] else { return nil }
        return PFSleepDebt(days: d["days"].int, nights: d["nights"].int, debtH: d["debt_h"].double, avgH: d["avg_h"].double,
                           shortfallNights: d["shortfall_nights"].int)
    }

    static func sleep(_ m: PFJ) -> PFSleepMetric {
        var out = PFSleepMetric()
        out.nights = m["nights"].int
        out.regularityNights = m["regularity_nights"].int
        out.bedtimeMean = m["bedtime"]["mean"].text
        out.bedtimeSdMin = m["bedtime"]["sd_min"].double
        out.wakeMedian = m["wake"]["median"].text
        out.wakeSdMin = m["wake"]["sd_min"].double
        out.regularityIndex = m["regularity_index"].double
        out.needH = m["need_h"].double
        out.needBasis = m["need_basis"].text
        out.debt7 = debt(m["debt_7d"])
        out.debt14 = debt(m["debt_14d"])
        out.garminDebtH = m["garmin"]["debt_h"].double
        out.garminNeedH = m["garmin"]["need_h"].double
        out.targetWake = m["target"]["wake"].text
        out.targetBedtime = m["target"]["bedtime"].text
        out.targetWindow = m["target"]["window"].strings
        out.timeInBedH = m["target"]["time_in_bed_h"].double
        out.shiftMin = m["target"]["shift_min"].int
        out.paybackExtraMinPerNight = m["payback"]["extra_min_per_night"].int
        out.paybackNights = m["payback"]["nights"].int
        out.series = m["series"].array.compactMap { n in
            guard let date = n["date"].text else { return nil }
            return PFSleepWindow(date: date, bedtime: n["bedtime"].text, wake: n["wake"].text, bedMin: n["bed_min"].double,
                                wakeMin: n["wake_min"].double, hours: n["hours"].double, isTravel: n["travel"].bool ?? false)
        }
        return out
    }

    // MARK: next_best_action

    private static func ranked(_ r: PFJ) -> PFRankedAction? {
        guard let a = action(r) else { return nil }
        return PFRankedAction(action: a, source: r["source"].text, ease: r["ease"].int, relevance: r["relevance"].int,
                              modifier: r["modifier"].double, score: r["score"].double, reason: r["reason"].text,
                              alsoSuggestedBy: r["also_suggested_by"].strings)
    }

    static func nextAction(_ m: PFJ) -> PFNextActionMetric {
        var out = PFNextActionMetric()
        out.chosen = ranked(m["chosen"])
        out.runnerUps = m["runner_ups"].array.compactMap(ranked)
        out.considered = m["considered"].int
        out.topics = m["topics"].int
        out.readinessWord = m["readiness"]["word"].text
        out.readinessStrained = m["readiness"]["strained"].bool
        out.readinessEvidence = m["readiness"]["evidence"].strings
        out.rankingBasis = m["ranking_basis"].text
        return out
    }
}
