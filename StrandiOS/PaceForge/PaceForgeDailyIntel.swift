import Foundation

// "Daily intel": PaceForge's daily-intel.json, five rules-written items that join last night, today's effort and
// tonight's sleep (Today's call, sleep need tonight, Health monitor, What moved it, Day in review). Foundation only,
// so the parsing and every small rule the cards draw from (verdict wording, tile text, bedtime from a wake time,
// range-band positions, the evening switch) are compiled into the macOS unit-test bundle and the Linux logic tests.
//
// Every field is optional on the wire. A missing file, a missing item or an item with `available: false` leaves that
// card out or shows the server's own reason; nothing is worked out from the athlete's data on the phone, and the app
// only reads. NOOP (strap) and PaceForge (Garmin) scores stay separate: every number carries the source the server
// named for it.

// MARK: - Ids

enum PFIntelID {
    static let todaysCall = "todays_call"
    static let sleepNeed = "sleep_need_tonight"
    static let healthMonitor = "health_monitor"
    static let whatMoved = "what_moved_it"
    static let dayInReview = "day_in_review"

    static let canonical = [todaysCall, sleepNeed, healthMonitor, whatMoved, dayInReview]
}

// MARK: - Shared small types

/// A session in the plan, as Today's call and Day in review list it.
struct PFIntelSession: Equatable {
    var name: String
    var type: String?
    var sport: String?
    var minutes: Int?
    var hard: Bool
    var done: Bool

    /// "Un1t hyrox · 45 min · hard · done".
    var lineText: String {
        var parts = [name]
        if let minutes { parts.append("\(minutes) min") }
        if hard { parts.append("hard") }
        if done { parts.append("done") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// How far today's Effort is from its target range, in the server's words and numbers (0-100 axis).
struct PFEffortProgress: Equatable {
    /// no_target, not_scored, to_go, in_range or above.
    var status: String?
    var effort: Double?
    var low: Double?
    var high: Double?
    var toGoLow: Double?
    var toGoHigh: Double?
    var aboveBy: Double?
    var text: String?
    var source: String?
    var scale: String?
}

/// A score from one device, labelled with whose it is. Never merged with the other device's.
struct PFCallScore: Equatable {
    var score: Double
    /// green, yellow or red.
    var band: String?
    /// NOOP or PaceForge.
    var source: String?
    var label: String?
    /// The day the score is from when it is not today's (Charge carried over).
    var carriedFrom: String?
    var reason: String?

    var rounded: Int { Int(score.rounded()) }

    /// "NOOP Charge" / "PaceForge Readiness": the owner and the name, as the card captions the dial.
    var caption: String {
        let owner = (source?.isEmpty == false) ? (source ?? "?") : "?"
        return "\(owner) \(label ?? "score")"
    }
}

// MARK: - Today's call

enum PFCallVerdict: Equatable {
    case ease, keep, go, unknown

    init(label: String?) {
        switch label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ease": self = .ease
        case "keep": self = .keep
        case "go": self = .go
        default: self = .unknown
        }
    }

    /// The chip on the card.
    var chipText: String {
        switch self {
        case .ease: return "EASE"
        case .keep: return "KEEP"
        case .go: return "GO"
        case .unknown: return "NO CALL"
        }
    }

    /// Spoken by VoiceOver.
    var spokenText: String {
        switch self {
        case .ease: return "Ease today"
        case .keep: return "Keep the plan"
        case .go: return "Go"
        case .unknown: return "No call yet"
        }
    }

    /// Go is the good end, ease the one to look at, keep is neutral.
    var tone: PFInsightTone {
        switch self {
        case .go: return .positive
        case .keep: return .neutral
        case .ease: return .caution
        case .unknown: return .unknown
        }
    }
}

struct PFCallDisagreement: Equatable {
    /// hrv, resting_hr or sleep: the input that explains the gap, when one does.
    var input: String?
    var text: String
}

struct PFEffortTarget: Equatable {
    var low: Double
    var high: Double
    var chargeBand: String?
    /// "0-100" on the wire.
    var scale: String?
    var basis: String?
    var progress: PFEffortProgress?
    var effortNow: Double?
    var effortSource: String?

    var maxValue: Double { scale == "0-21" ? 21 : 100 }

    /// The target range as circle fractions (start, end), clamped; nil when it collapses to nothing.
    var arc: (start: Double, end: Double)? {
        let a = min(max(min(low, high) / maxValue, 0), 1)
        let b = min(max(max(low, high) / maxValue, 0), 1)
        return b > a ? (a, b) : nil
    }

    /// Effort so far as a circle fraction.
    var effortFraction: Double? {
        guard let effortNow, effortNow.isFinite else { return nil }
        return min(max(effortNow / maxValue, 0), 1)
    }

    /// "67\u{2013}86".
    var rangeText: String { "\(Int(low.rounded()))\u{2013}\(Int(high.rounded()))" }
}

struct PFTodaysCall: Equatable {
    var asOf: String?
    var charge: PFCallScore?
    var readiness: PFCallScore?
    /// single, agree, mixed or disagree.
    var agreement: String?
    var disagreement: PFCallDisagreement?
    var effortTarget: PFEffortTarget?
    var planned: [PFIntelSession] = []
    var leadSession: PFIntelSession?
    var tomorrowSession: PFIntelSession?
    var acwr: Double?
    var loadFlag: String?
    var loadIsHigh = false
    var call = PFCallVerdict.unknown
    var verdict: String?

    /// The session the card names: the lead session, else the first one planned today.
    var plannedSession: PFIntelSession? { leadSession ?? planned.first }

    /// Whether there is anything to draw: a score, a target or a call.
    var hasContent: Bool { charge != nil || readiness != nil || effortTarget != nil || call != .unknown }
}

// MARK: - Sleep need tonight

struct PFSleepRow: Equatable {
    /// baseline, effort, debt or naps.
    var key: String
    var label: String
    /// Signed: naps are negative, so the rows add up to the need.
    var minutes: Int
    var detail: String?
}

struct PFSleepTier: Equatable {
    /// getBy, perform or peak: the planner's preset names.
    var id: String
    var title: String
    var percent: Int
    var sleepMin: Int
    var timeInBedMin: Int
    var bedtime: String?
}

struct PFSleepNeed: Equatable {
    var asOf: String?
    /// provisional (before 18:00) or evening.
    var phase: String?
    var needMin: Int
    var needText: String?
    var rows: [PFSleepRow] = []
    var baselineMin: Int?
    var effortBasis: String?
    var tiers: [PFSleepTier] = []
    var recommended: String?
    var wakeTime: String?
    var wakeBasis: String?
    /// The typical sleep efficiency the time in bed is worked out with (0...1), when the server says it.
    var efficiency: Double?
    /// Server status: baseline, raised or high.
    var statusLabel: String?

    var isProvisional: Bool { phase == "provisional" }

    func tier(_ id: String) -> PFSleepTier? { tiers.first { $0.id == id } }

    /// The tier the server recommends, else the middle one.
    var recommendedTier: PFSleepTier? { tier(recommended ?? "") ?? tier("perform") ?? tiers.first }

    /// A wake time held on the phone (minutes after midnight) wins over the server's; a value outside a day is ignored.
    static func validWake(_ minutes: Int?) -> Int? {
        guard let minutes, (0..<1440).contains(minutes) else { return nil }
        return minutes
    }

    /// The wake time in use, in minutes after midnight.
    func wakeMinutes(userWake: Int?) -> Int? {
        Self.validWake(userWake) ?? PFSleepClock.minutes(of: wakeTime)
    }

    /// Bedtime in minutes after midnight: the user's wake time minus the tier's time in bed, else the server's own bedtime.
    func bedtimeMinutes(_ tier: PFSleepTier, userWake: Int?) -> Int? {
        if let wake = Self.validWake(userWake) { return ((wake - tier.timeInBedMin) % 1440 + 1440) % 1440 }
        return PFSleepClock.minutes(of: tier.bedtime)
    }

    func bedtimeText(_ tier: PFSleepTier, userWake: Int?) -> String? {
        bedtimeMinutes(tier, userWake: userWake).map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
    }

    /// One goal for tonight: the tier, the wake time in use and the bedtime that reaches it.
    func nightPlan(tierID: String, userWake: Int?) -> PFSleepNightPlan? {
        guard let tier = tier(tierID), let wake = wakeMinutes(userWake: userWake),
              let bed = bedtimeMinutes(tier, userWake: userWake) else { return nil }
        return PFSleepNightPlan(tier: tier, bedtimeMinutes: bed, wakeMinutes: wake,
                                usesPhoneWake: Self.validWake(userWake) != nil)
    }

    /// "Plans on 97 % sleep efficiency": how the time in bed is worked out, in the server's terms.
    var efficiencyText: String? {
        efficiency.map { "time in bed = sleep \u{00F7} your typical sleep efficiency (\(Int(($0 * 100).rounded())) %)" }
    }

    /// Hours and minutes, 514 gives "8:34".
    static func hoursMinutes(_ minutes: Int) -> String {
        let m = max(minutes, 0)
        return "\(m / 60):" + (m % 60 < 10 ? "0" : "") + "\(m % 60)"
    }

    /// "+0:17", "\u{2212}0:25", "0:00".
    static func signedHoursMinutes(_ minutes: Int) -> String {
        if minutes == 0 { return "0:00" }
        return (minutes > 0 ? "+" : "\u{2212}") + hoursMinutes(abs(minutes))
    }

    /// The row's caption: the Effort row says whether it is today's or yesterday's.
    func label(of row: PFSleepRow) -> String {
        switch row.key {
        case "baseline": return "Your baseline"
        case "effort":
            let yesterday = effortBasis?.lowercased().contains("yesterday") == true
            return yesterday ? "Yesterday's effort" : "Today's effort"
        case "debt": return "Sleep debt"
        case "naps": return "Naps today"
        default: return row.label
        }
    }
}

/// One goal's night: bedtime and wake as minutes after midnight, and the time in bed between them.
struct PFSleepNightPlan: Equatable {
    var tier: PFSleepTier
    var bedtimeMinutes: Int
    var wakeMinutes: Int
    /// True when the wake time is the one set on the phone, false when it is the server's.
    var usesPhoneWake: Bool

    /// Minutes between lying down and being asleep, as the server's efficiency leaves them.
    var latencyMin: Int { max(tier.timeInBedMin - tier.sleepMin, 0) }

    var bedtimeText: String { Self.clock(bedtimeMinutes) }
    var wakeText: String { Self.clock(wakeMinutes) }

    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// The next wake-up after `now` and the bedtime before it, as instants, so a night across midnight or a clock
    /// change still holds the planned time in bed.
    func dates(after now: Date, calendar: Calendar = .current) -> (bedtime: Date, wake: Date)? {
        let parts = DateComponents(hour: wakeMinutes / 60, minute: wakeMinutes % 60)
        guard let wake = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) else { return nil }
        return (wake.addingTimeInterval(-Double(tier.timeInBedMin) * 60), wake)
    }
}

// MARK: - Health monitor

/// Where a value and its typical range sit on a bar, as 0...1 positions, with room either side.
struct PFRangeBand: Equatable {
    var low: Double
    var high: Double
    var marker: Double
    var markerIsInside: Bool

    static func make(value: Double, low: Double, high: Double) -> PFRangeBand? {
        guard value.isFinite, low.isFinite, high.isFinite, high >= low else { return nil }
        let pad = max((high - low) * 0.6, 0.5)
        let start = min(low, value) - pad
        let end = max(high, value) + pad
        let width = end - start
        guard width > 0 else { return nil }
        func position(_ x: Double) -> Double { (x - start) / width }
        return PFRangeBand(low: position(low), high: position(high), marker: position(value),
                           markerIsInside: value >= low && value <= high)
    }
}

struct PFVital: Equatable, Identifiable {
    /// hrv, resting_hr, resp, skin_temp or spo2.
    var key: String
    var label: String
    var unit: String?
    /// NOOP or Garmin.
    var source: String?
    var available: Bool
    var value: Double?
    var nights: Int?
    var typicalLow: Double?
    var typicalHigh: Double?
    var typicalCenter: Double?
    var z: Double?
    /// within, elevated or low.
    var status: String?
    /// WITHIN RANGE, ELEVATED, VERY ELEVATED, LOW or VERY LOW.
    var word: String?
    var illnessDirection: Bool
    var reason: String?
    var id: String { key }

    var isOut: Bool { available && status != nil && status != "within" }
    var isVeryOut: Bool { word?.uppercased().hasPrefix("VERY") == true }

    /// "NOOP strap" for the strap, "Garmin" for the watch; anything else as the server wrote it.
    var sourceLabel: String {
        let name = source ?? ""
        if name.isEmpty { return "Source not named" }
        return name == "NOOP" ? "NOOP strap" : name
    }

    private var decimals: Int { (key == "resp" || key == "skin_temp") ? 1 : 0 }

    /// "41", "15.0", "+0.2" (skin temperature is a difference from usual, so it carries its sign).
    var valueText: String? {
        guard let value else { return nil }
        return key == "skin_temp" ? PFNumber.signed(value, decimals: decimals) : String(format: "%.\(decimals)f", value)
    }

    /// The unit as printed beside the value: the skin-temperature unit drops "vs usual", which the row says itself.
    var unitText: String {
        guard let unit, !unit.isEmpty else { return "" }
        return unit.replacingOccurrences(of: " vs usual", with: "")
    }

    /// "35\u{2013}41 ms" or the signed pair for skin temperature.
    var rangeText: String? {
        guard let low = typicalLow, let high = typicalHigh else { return nil }
        let a = key == "skin_temp" ? PFNumber.signed(low, decimals: decimals) : String(format: "%.\(decimals)f", low)
        let b = key == "skin_temp" ? PFNumber.signed(high, decimals: decimals) : String(format: "%.\(decimals)f", high)
        return "\(a)\u{2013}\(b) \(unitText)".trimmingCharacters(in: .whitespaces)
    }

    var band: PFRangeBand? {
        guard available, let value, let typicalLow, let typicalHigh else { return nil }
        return PFRangeBand.make(value: value, low: typicalLow, high: typicalHigh)
    }
}

struct PFHealthAlert: Equatable {
    var title: String
    var body: String?
    /// watch or similar.
    var severity: String?
    var push: Bool
    var vitals: [String]
    var whatToDo: [String]
}

enum PFHealthTileState: Equatable {
    case withinRange, attention, alert
}

/// What the Health monitor tile on Today prints.
struct PFHealthTile: Equatable {
    var state: PFHealthTileState
    /// "WITHIN RANGE" or "VERY ELEVATED".
    var status: String
    /// "4/4 metrics" or "Respiratory rate".
    var detail: String
    /// Red: an alert, or a vital that is "very" far out.
    var isRed: Bool

    /// "WITHIN RANGE \u{00B7} 4/4 metrics" / "VERY ELEVATED \u{00B7} Respiratory rate".
    var text: String { "\(status) \u{00B7} \(detail)" }
}

struct PFHealthMonitor: Equatable {
    var asOf: String?
    var windowDays: Int?
    var vitals: [PFVital] = []
    var tileState: String?
    var tileText: String?
    var within: Int?
    var total: Int?
    var alert: PFHealthAlert?

    var available: [PFVital] { vitals.filter { $0.available } }
    var outOfRange: [PFVital] { vitals.filter { $0.isOut } }

    /// The vital furthest from its range.
    var worst: PFVital? { outOfRange.max { abs($0.z ?? 0) < abs($1.z ?? 0) } }

    var tile: PFHealthTile {
        let have = available.count
        let inside = within ?? (have - outOfRange.count)
        let count = total ?? have
        var state: PFHealthTileState = outOfRange.isEmpty ? .withinRange : .attention
        if alert != nil || tileState == "alert" { state = .alert }
        else if tileState == "attention", state == .withinRange { state = .attention }
        guard state != .withinRange else {
            return PFHealthTile(state: .withinRange, status: "WITHIN RANGE", detail: "\(inside)/\(count) metrics", isRed: false)
        }
        if let worst {
            let word = worst.word ?? "OUT OF RANGE"
            return PFHealthTile(state: state, status: word, detail: worst.label, isRed: state == .alert || worst.isVeryOut)
        }
        // No vital rows to read: fall back to the server's own text, "VERY ELEVATED \u{00B7} Respiratory rate".
        let parts = (tileText ?? "").components(separatedBy: " \u{00B7} ")
        let status = parts.first.flatMap { $0.isEmpty ? nil : $0 } ?? "OUT OF RANGE"
        let detail = parts.count > 1 ? parts[1] : "\(inside)/\(count) metrics"
        return PFHealthTile(state: state, status: status, detail: detail,
                            isRed: state == .alert || status.uppercased().hasPrefix("VERY"))
    }
}

// MARK: - What moved it

struct PFMoveChange: Equatable {
    var days: Int
    var current: Double?
    var previous: Double?
    var delta: Double?
    var pct: Double?
}

struct PFMoveLink: Equatable {
    var behaviour: String?
    var label: String?
    var sentence: String
    /// weak, moderate or strong.
    var strength: String?
}

struct PFMovedMetric: Equatable, Identifiable {
    /// hrv, resting_hr, sleep_hours, charge, effort or weight.
    var key: String
    var label: String
    var unit: String?
    var source: String?
    /// ok or not enough data.
    var state: String?
    var reason: String?
    var change7: PFMoveChange?
    var change30: PFMoveChange?
    var moved: Bool
    var movedOverDays: Int?
    /// up or down.
    var direction: String?
    /// better or worse.
    var assessment: String?
    var links: [PFMoveLink] = []
    var action: PFInsightAction?
    var id: String { key }

    var hasData: Bool { state == nil || state == "ok" }

    /// The change that tripped "moved", else the 30-day one, else the 7-day one.
    var headlineChange: PFMoveChange? {
        if moved, let days = movedOverDays { return days <= 7 ? change7 : change30 }
        return change30 ?? change7
    }

    /// "Down 7.1 ms over 30 days", "Steady over 30 days", or the reason there is no reading.
    var headline: String {
        guard hasData else { return reason ?? "Not enough data yet" }
        guard let change = headlineChange, let delta = change.delta else { return "Not enough data yet" }
        let decimals = abs(delta) >= 10 ? 0 : 1
        let size = String(format: "%.\(decimals)f", abs(delta))
        let unitSuffix = (unit?.isEmpty == false) ? " \(unit ?? "")" : ""
        if !moved { return "Steady over \(change.days) days" }
        let way = delta < 0 ? "Down" : "Up"
        return "\(way) \(size)\(unitSuffix) over \(change.days) days"
    }

    /// The chip beside the headline: worse, better or steady.
    var chipText: String {
        guard hasData else { return "NOT ENOUGH DATA" }
        guard moved else { return "STEADY" }
        switch assessment {
        case "better": return "BETTER"
        case "worse": return "WORSE"
        default: return direction == "down" ? "DOWN" : "UP"
        }
    }
}

struct PFWhatMoved: Equatable {
    var asOf: String?
    var windowDays: Int?
    var metrics: [PFMovedMetric] = []

    func metric(_ key: String) -> PFMovedMetric? { metrics.first { $0.key == key } }
}

/// Which what_moved_it metric a screen's metric belongs to. nil means the server says nothing about it.
enum PFMovedMetricMap {
    /// A NOOP catalog key (recovery, strain, hrv, rhr, sleep_total_min, weight).
    static func intelKey(forCatalogKey key: String) -> String? {
        switch key {
        case "recovery": return "charge"
        case "strain": return "effort"
        case "hrv": return "hrv"
        case "rhr": return "resting_hr"
        case "sleep_total_min": return "sleep_hours"
        case "weight", "weight_kg": return "weight"
        default: return nil
        }
    }

    /// A trend metric id as the repository trends build it: "my-whoop:recovery" or a bare key.
    static func intelKey(forMetricID id: String) -> String? {
        let key = id.split(separator: ":").last.map(String.init) ?? id
        return intelKey(forCatalogKey: key)
    }
}

// MARK: - Day in review

struct PFTonight: Equatable {
    var needMin: Int?
    var needText: String?
    var bedtime: String?
    var tier: String?
    var timeInBedMin: Int?
    var wake: String?
}

enum PFReviewOutcome: Equatable {
    case met, notMet, noTarget
}

struct PFDayReview: Equatable {
    var asOf: String?
    var effort: PFEffortProgress?
    var targetMet: Bool?
    var sessionsToday: [PFIntelSession] = []
    var tonight: PFTonight?
    var tomorrow: PFIntelSession?
    var sentence: String?

    var outcome: PFReviewOutcome {
        if let targetMet { return targetMet ? .met : .notMet }
        return .noTarget
    }

    var outcomeText: String {
        switch outcome {
        case .met: return effort?.status == "above" ? "TARGET PASSED" : "TARGET MET"
        case .notMet: return "TARGET NOT MET"
        case .noTarget: return "NO TARGET TODAY"
        }
    }

    /// "54 of 67\u{2013}86", or nil without a scored Effort and a range.
    var effortText: String? {
        guard let effort, let value = effort.effort else { return nil }
        guard let low = effort.low, let high = effort.high else { return "\(Int(value.rounded()))" }
        return "\(Int(value.rounded())) of \(Int(low.rounded()))\u{2013}\(Int(high.rounded()))"
    }
}

// MARK: - Evening switch

enum PFEvening {
    static let startHour = 18

    /// The review card shows from 18:00 local.
    static func isEvening(_ now: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) >= startHour
    }
}

// MARK: - The document

/// One item with its generic fields (status, meaning, actions, confidence, data note) and the sources the server named.
struct PFIntelItem: Equatable {
    var base: PFInsightItem
    var sources: [String]

    var id: String { base.id }
    var available: Bool { base.available }

    /// "NOOP \u{00B7} PaceForge", or empty.
    var sourceText: String { sources.joined(separator: " \u{00B7} ") }
}

struct PFDailyIntel: Equatable {
    var version: Int?
    var generatedAt: String?
    var asOf: String?
    var order: [String] = []
    var items: [String: PFIntelItem] = [:]
    var call: PFTodaysCall?
    var sleepNeed: PFSleepNeed?
    var health: PFHealthMonitor?
    var moved: PFWhatMoved?
    var review: PFDayReview?

    func item(_ id: String) -> PFIntelItem? { items[id] }

    /// Whether the file was written for `todayISO`. A file from another day is not today's call.
    func isCurrent(for todayISO: String) -> Bool { asOf == todayISO }

    /// The item when it has something to say: available, with its typed metric parsed.
    var callItem: PFIntelItem? { call == nil ? nil : item(PFIntelID.todaysCall) }
    var reviewItem: PFIntelItem? { review == nil ? nil : item(PFIntelID.dayInReview) }
    var healthItem: PFIntelItem? { health == nil ? nil : item(PFIntelID.healthMonitor) }
    var sleepItem: PFIntelItem? { sleepNeed == nil ? nil : item(PFIntelID.sleepNeed) }

    /// Why an item is unavailable, in the server's words.
    func unavailableReason(_ id: String) -> String? {
        guard let it = item(id), !it.available else { return nil }
        return it.base.meaning ?? it.base.status.reason ?? it.base.dataNote
    }
}

// MARK: - Parsing

enum PFDailyIntelParse {
    static func document(_ j: PFJ) -> PFDailyIntel? {
        guard j.exists, j.raw is [String: Any] else { return nil }
        var out = PFDailyIntel()
        out.version = j["version"].int
        out.generatedAt = j["generated_at"].text
        out.asOf = j["as_of"].text
        out.order = j["order"].array.compactMap { $0.idString }
        for (key, value) in j["items"].dict {
            guard let base = PFInsightsV2Parse.item(value, key: key) else { continue }
            out.items[base.id] = PFIntelItem(base: base, sources: value["source"].strings)
        }
        guard !out.items.isEmpty else { return nil }
        func metric(_ id: String) -> PFJ? {
            guard let it = out.items[id], it.available else { return nil }
            let m = j["items"][id]["metric"]
            return m.exists ? m : nil
        }
        if let m = metric(PFIntelID.todaysCall) { out.call = call(m) }
        if let m = metric(PFIntelID.sleepNeed) { out.sleepNeed = sleepNeed(m, status: out.items[PFIntelID.sleepNeed]?.base.status.label) }
        if let m = metric(PFIntelID.healthMonitor) { out.health = health(m) }
        if let m = metric(PFIntelID.whatMoved) { out.moved = moved(m) }
        if let m = metric(PFIntelID.dayInReview) { out.review = review(m) }
        return out
    }

    // MARK: shared

    static func session(_ s: PFJ) -> PFIntelSession? {
        guard s.exists, s.raw is [String: Any], let name = s["name"].text else { return nil }
        return PFIntelSession(name: name, type: s["type"].text, sport: s["sport"].text, minutes: s["minutes"].int,
                              hard: s["hard"].bool ?? false, done: s["done"].bool ?? false)
    }

    static func progress(_ p: PFJ) -> PFEffortProgress? {
        guard p.exists, p.raw is [String: Any] else { return nil }
        return PFEffortProgress(status: p["status"].text, effort: p["effort"].double, low: p["low"].double,
                                high: p["high"].double, toGoLow: p["to_go_low"].double, toGoHigh: p["to_go_high"].double,
                                aboveBy: p["above_by"].double, text: p["text"].text, source: p["source"].text,
                                scale: p["scale"].text)
    }

    private static func score(_ s: PFJ) -> PFCallScore? {
        guard s.exists, s.raw is [String: Any], let value = s["score"].double else { return nil }
        return PFCallScore(score: value, band: s["band"].text, source: s["source"].text, label: s["label"].text,
                           carriedFrom: s["carried_from"].text, reason: s["reason"].text)
    }

    // MARK: todays_call

    static func call(_ m: PFJ) -> PFTodaysCall? {
        var out = PFTodaysCall()
        out.asOf = m["as_of"].text
        out.charge = score(m["charge"])
        out.readiness = score(m["readiness"])
        out.agreement = m["agreement"].text
        if let text = m["disagreement"]["text"].text {
            out.disagreement = PFCallDisagreement(input: m["disagreement"]["input"].text, text: text)
        }
        let t = m["effort_target"]
        if let low = t["low"].double, let high = t["high"].double {
            out.effortTarget = PFEffortTarget(
                low: low, high: high, chargeBand: t["charge_band"].text, scale: t["scale"].text, basis: t["basis"].text,
                progress: progress(t["progress"]), effortNow: t["effort_now"]["value"].double,
                effortSource: t["effort_now"]["source"].text)
        }
        out.planned = m["planned"].array.compactMap(session)
        out.leadSession = session(m["lead_session"])
        out.tomorrowSession = session(m["tomorrow_session"])
        out.acwr = m["load"]["acwr"].double
        out.loadFlag = m["load"]["flag"].text
        out.loadIsHigh = m["load"]["high"].bool ?? false
        out.call = PFCallVerdict(label: m["call"].text)
        out.verdict = m["verdict"].text
        return out.hasContent ? out : nil
    }

    // MARK: sleep_need_tonight

    static func sleepNeed(_ m: PFJ, status: String?) -> PFSleepNeed? {
        guard let need = m["need_min"].int else { return nil }
        var out = PFSleepNeed(asOf: m["as_of"].text, phase: m["phase"].text, needMin: need, needText: m["need_text"].text)
        out.rows = m["breakdown"].array.compactMap { r in
            guard let key = r["key"].text, let minutes = r["minutes"].int else { return nil }
            return PFSleepRow(key: key, label: r["label"].text ?? key, minutes: minutes, detail: r["detail"].text)
        }
        out.baselineMin = m["baseline_min"].int
        out.effortBasis = m["effort"]["basis"].text
        out.tiers = m["tiers"].array.compactMap { t in
            guard let id = t["id"].text, let sleep = t["sleep_min"].int, let bed = t["time_in_bed_min"].int else { return nil }
            return PFSleepTier(id: id, title: t["title"].text ?? id, percent: t["percent"].int ?? 0, sleepMin: sleep,
                               timeInBedMin: bed, bedtime: t["bedtime"].text)
        }
        out.recommended = m["recommended"].text
        out.wakeTime = m["wake"]["time"].text
        out.wakeBasis = m["wake"]["basis"].text
        out.efficiency = m["efficiency"]["value"].double
        out.statusLabel = status
        return out
    }

    // MARK: health_monitor

    static func vital(_ v: PFJ) -> PFVital? {
        guard let key = v["key"].text else { return nil }
        return PFVital(
            key: key, label: v["label"].text ?? PFBand.titleFromId(key), unit: v["unit"].text, source: v["source"].text,
            available: v["available"].bool ?? false, value: v["value"].double, nights: v["n"].int,
            typicalLow: v["typical"]["low"].double, typicalHigh: v["typical"]["high"].double,
            typicalCenter: v["typical"]["center"].double, z: v["z"].double, status: v["status"].text, word: v["word"].text,
            illnessDirection: v["illness_direction"].bool ?? false, reason: v["reason"].text)
    }

    static func health(_ m: PFJ) -> PFHealthMonitor? {
        let vitals = m["vitals"].array.compactMap(vital)
        guard !vitals.isEmpty else { return nil }
        var out = PFHealthMonitor(asOf: m["as_of"].text, windowDays: m["window_days"].int, vitals: vitals)
        out.tileState = m["tile"]["state"].text
        out.tileText = m["tile"]["text"].text
        out.within = m["tile"]["within"].int
        out.total = m["tile"]["total"].int
        let a = m["alert"]
        if a.exists, a.raw is [String: Any], let title = a["title"].text {
            // `what_to_do` is a list of sentences; an object with `text` reads too.
            let steps = a["what_to_do"].array.compactMap { $0.text ?? $0["text"].text }
            out.alert = PFHealthAlert(title: title, body: a["body"].text, severity: a["severity"].text,
                                      push: a["push"].bool ?? false,
                                      vitals: a["vitals"].array.compactMap { $0["label"].text }, whatToDo: steps)
        }
        return out
    }

    // MARK: what_moved_it

    private static func change(_ c: PFJ) -> PFMoveChange? {
        guard c.exists, c.raw is [String: Any], let days = c["days"].int else { return nil }
        return PFMoveChange(days: days, current: c["current"].double, previous: c["previous"].double,
                            delta: c["delta"].double, pct: c["pct"].double)
    }

    static func moved(_ m: PFJ) -> PFWhatMoved? {
        let metrics: [PFMovedMetric] = m["metrics"].array.compactMap { x in
            guard let key = x["key"].text else { return nil }
            return PFMovedMetric(
                key: key, label: x["label"].text ?? PFBand.titleFromId(key), unit: x["unit"].text, source: x["source"].text,
                state: x["state"].text, reason: x["reason"].text, change7: change(x["change_7d"]),
                change30: change(x["change_30d"]), moved: x["moved"].bool ?? false, movedOverDays: x["moved_over_days"].int,
                direction: x["direction"].text, assessment: x["assessment"].text,
                links: x["links"].array.compactMap { l in
                    guard let sentence = l["sentence"].text else { return nil }
                    return PFMoveLink(behaviour: l["behaviour"].text, label: l["label"].text, sentence: sentence,
                                      strength: l["strength"].text)
                },
                action: PFInsightsV2Parse.action(x["action"]))
        }
        guard !metrics.isEmpty else { return nil }
        return PFWhatMoved(asOf: m["as_of"].text, windowDays: m["window_days"].int, metrics: metrics)
    }

    // MARK: day_in_review

    static func review(_ m: PFJ) -> PFDayReview? {
        var out = PFDayReview(asOf: m["as_of"].text)
        out.effort = progress(m["effort"])
        out.targetMet = m["target_met"].bool
        out.sessionsToday = m["sessions_today"].array.compactMap(session)
        let t = m["tonight"]
        if t.exists, t.raw is [String: Any] {
            out.tonight = PFTonight(needMin: t["need_min"].int, needText: t["need_text"].text, bedtime: t["bedtime"].text,
                                    tier: t["tier"].text, timeInBedMin: t["time_in_bed_min"].int, wake: t["wake"].text)
        }
        out.tomorrow = session(m["tomorrow_session"])
        out.sentence = m["sentence"].text
        let hasContent = out.effort != nil || out.tonight != nil || out.tomorrow != nil || !out.sessionsToday.isEmpty
        return hasContent ? out : nil
    }
}
