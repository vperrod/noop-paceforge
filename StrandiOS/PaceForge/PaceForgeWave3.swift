import Foundation

// Wave 3 documents from PaceForge: race week, race simulations, easy mode, the muscle check, tape
// measurements, heat on a session, the privacy setting, and the intraday and day-event files My Day
// reads. Foundation only, so the pure parsing and formatting below is compiled into the macOS
// unit-test bundle as well. Every field is optional on the wire: an older server or a friend's instance
// may not serve a file, a number may arrive as an int or a double, and the screens then hide the part.
// The app only reads these. Anything that changes state (easy mode, tape, race simulations, niggles) is
// done in Telegram, and the app shows the state and the phrase to say there.

// MARK: - Telegram hints

/// The phrases the app tells the athlete to say in Telegram. One place, so a wording change is one line.
enum PFTelegramHint {
    static let logRaceSim = "log race sim \u{2026}"
    /// What the server accepts after the phrase, as the athlete is told it.
    static let raceSimFormat = "Give up to 8 run times and up to 8 station times, each as m:ss."
    static let raceSimEmpty = "Log a race simulation in Telegram: \u{2018}\(logRaceSim)\u{2019}"
    static let tape = "Log tape measurements in Telegram."
    static let easyModeNone = "Not feeling 100 %? Say so in Telegram."
    static let easyModeAccept = "Accept in Telegram"
    static let doThisInTelegram = "Do this in Telegram"
}

// MARK: - Race week

struct PFRaceWeek: Equatable {
    struct Event: Equatable {
        var name: String
        var date: String?
        var goalTime: String?
        var priority: String?
        var location: String?
        var type: String?
    }

    struct CarbLoad: Equatable {
        var perKgLow: Double?
        var perKgHigh: Double?
        var gramsPerDay: Double?
        var weightKg: Double?
        var tips: [String] = []
        var label: String?
        var note: String?

        /// "8\u{2013}10 g/kg a day, about 640 g at 80 kg", from whichever figures the server sent.
        var line: String? {
            var parts: [String] = []
            if let low = perKgLow, let high = perKgHigh, high != low {
                parts.append(PFNumber.trimmed(low) + "\u{2013}" + PFNumber.trimmed(high) + " g/kg a day")
            } else if let single = perKgLow ?? perKgHigh {
                parts.append(PFNumber.trimmed(single) + " g/kg a day")
            }
            if let grams = gramsPerDay {
                var text = "about \(Int(grams.rounded())) g a day"
                if let weightKg { text += " at " + PFNumber.trimmed(weightKg) + " kg" }
                parts.append(text)
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    struct CheckItem: Identifiable, Equatable {
        var id: String
        var when: String?
        var text: String
    }

    struct MorningStep: Identifiable, Equatable {
        var tMinusMin: Int
        var text: String
        var id: String { "\(tMinusMin)|\(text)" }

        /// "3 h 30 min before", "45 min before", "Start".
        var whenText: String {
            if tMinusMin <= 0 { return "Start" }
            let hours = tMinusMin / 60, minutes = tMinusMin % 60
            if hours == 0 { return "\(minutes) min before" }
            return minutes == 0 ? "\(hours) h before" : "\(hours) h \(minutes) min before"
        }
    }

    struct Recovery: Equatable {
        var day: Int?
        var ofDays: Int?
        var suggestion: String?
    }

    /// The day the document was built for, which keys the local checklist ticks.
    var date: String?
    var event: Event
    var daysTo: Int?
    /// taper, race_eve, race_day or recovery.
    var phase: String
    var volumeTargetPct: Double?
    var weekVolumeCutPct: Double?
    var notes: [String] = []
    var carbLoad: CarbLoad?
    var checklist: [CheckItem] = []
    var raceMorning: [MorningStep] = []
    var suppressesAlerts = false
    var recovery: Recovery?

    /// Only the daily brief's short summary was served: no checklist, timeline or carb line.
    var isSummaryOnly: Bool { checklist.isEmpty && raceMorning.isEmpty && carbLoad == nil && recovery == nil }

    var phaseTitle: String {
        switch phase {
        case "taper": return "Taper"
        case "race_eve": return "Race eve"
        case "race_day": return "Race day"
        case "recovery": return "Recovery"
        default: return phase.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// "5 days to go", "Tomorrow", "Race day", or nil when the server gave no day count.
    var daysText: String? {
        guard let days = daysTo else { return nil }
        if phase == "recovery" || days < 0 { return nil }
        switch days {
        case 0: return "Race day"
        case 1: return "Tomorrow"
        default: return "\(days) days to go"
        }
    }

    /// One line for the widget and the chip: "Taper \u{00B7} 5 days to go \u{00B7} volume 60 %".
    var summaryLine: String {
        var parts = [phaseTitle]
        if let days = daysText { parts.append(days) }
        if let pct = volumeTargetPct { parts.append("volume \(Int(pct.rounded())) %") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// The local ticks on the race-week checklist, per day, in UserDefaults. Nothing is sent anywhere.
enum PFRaceWeekChecklist {
    static func key(date: String) -> String { "noop.paceforge.raceweek.ticks.\(date)" }

    static func checked(date: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key(date: date)) ?? [])
    }

    /// Flips one item and returns the new set.
    @discardableResult
    static func toggle(_ id: String, date: String, defaults: UserDefaults = .standard) -> Set<String> {
        var ticks = checked(date: date, defaults: defaults)
        if ticks.contains(id) { ticks.remove(id) } else { ticks.insert(id) }
        defaults.set(ticks.sorted(), forKey: key(date: date))
        return ticks
    }
}

// MARK: - Race simulations

struct PFHyroxSims: Equatable {
    struct Goal: Equatable {
        var event: String?
        var date: String?
        var goalSeconds: Double?
        var goalDisplay: String?
        var basis: String?
    }

    struct FreshRun: Equatable {
        var paceSec: Double?
        var display: String?
        var nRuns: Int?
        var basis: String?
    }

    struct CompromisedRun: Identifiable, Equatable {
        var run: Int
        var seconds: Double?
        var pctSlower: Double?
        var id: Int { run }
    }

    struct Latest: Equatable {
        var id: String?
        var date: String?
        var complete = true
        var totalSeconds: Double?
        var totalDisplay: String?
        var notes: String?
        var runFadePct: Double?
        var compromisedPct: Double?
        var compromisedRuns: [CompromisedRun] = []
        var maxDevPct: Double?
        var withinBand: Bool?
        var pacingNote: String?
    }

    struct Segment: Identifiable, Equatable {
        var index: Int
        var name: String
        /// run or station.
        var kind: String
        var display: String?
        var simSeconds: Double?
        var goalSeconds: Double?
        var deltaGoalS: Double?
        var prevSeconds: Double?
        var deltaPrevS: Double?
        var id: String { "\(index)|\(name)" }
        var isRun: Bool { kind == "run" }
    }

    struct Weak: Identifiable, Equatable {
        var station: String
        var display: String?
        var simSeconds: Double?
        var goalSeconds: Double?
        var overS: Double?
        var overPct: Double?
        var suggestion: String?
        var id: String { station }
    }

    var hasData: Bool
    var count = 0
    /// Garmin sessions that look like a race simulation but could not be split into stations.
    var unmappedCount = 0
    var goal: Goal?
    var freshRun: FreshRun?
    var latest: Latest?
    var segments: [Segment] = []
    var weakest: [Weak] = []
    var note: String?

    /// Total against the goal, in seconds: positive when the simulation was slower than the goal.
    var totalVsGoalS: Double? {
        guard let total = latest?.totalSeconds, let goal = goal?.goalSeconds else { return nil }
        return total - goal
    }
}

enum PFSimFormat {
    /// 4:32, or 1:04:32 from an hour up.
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// +0:12, \u{2212}0:05, or 0:00. Neutral: no colour is chosen from the sign.
    static func signed(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded == 0 { return "0:00" }
        return (rounded < 0 ? "\u{2212}" : "+") + clock(Double(abs(rounded)))
    }

    /// +3.2 %, \u{2212}1.0 %.
    static func signedPct(_ value: Double) -> String {
        let text = String(format: "%.1f", abs(value))
        if abs(value) < 0.05 { return "0.0 %" }
        return (value < 0 ? "\u{2212}" : "+") + text + " %"
    }
}

// MARK: - Easy mode

struct PFEasyMode: Equatable {
    struct Mode: Equatable {
        var level: Int
        var label: String
        var summary: String?
        var started: String?
        var until: String?
        var day: Int?
        var ofDays: Int?
        var daysLeft: Int?
        var returnsOn: String?
        /// How many sessions the mode changed, and which ones when the server names them.
        var changedCount: Int?
        var changedSessionIds: [String] = []
        var restorable = false

        /// "Day 3 of 7", or nil when the server sent neither number.
        var dayText: String? {
            guard let day else { return nil }
            return ofDays.map { "Day \(day) of \($0)" } ?? "Day \(day)"
        }
    }

    struct Proposal: Identifiable, Equatable {
        var proposalId: String
        var level: Int?
        var days: Int?
        var until: String?
        var title: String
        var id: String { proposalId }
    }

    struct Level: Identifiable, Equatable {
        var level: Int
        var label: String
        var summary: String?
        var id: Int { level }
    }

    var mode: Mode?
    var pending: [Proposal] = []
    var levels: [Level] = []

    var isIdle: Bool { mode == nil && pending.isEmpty }
}

// MARK: - Muscle check and tape

struct PFMuscleCheck: Equatable {
    struct Lean: Equatable {
        var currentTrendKg: Double?
        var noiseKg: Double?
        var noiseBasis: String?
        var perWeekKg: Double?
        var perWeekPct: Double?
        var change14dKg: Double?
        var change28dKg: Double?
        var readings: Int?
    }

    struct WeightTrend: Equatable {
        var currentTrendKg: Double?
        var perWeekKg: Double?
        var perWeekPct: Double?
    }

    struct Split: Identifiable, Equatable {
        /// "14d" or "28d".
        var window: String
        var days: Int?
        var weightKg: Double?
        var leanKg: Double?
        var fatKg: Double?
        var leanSharePct: Double?
        /// estimate or noisy.
        var quality: String?
        var id: String { window }

        var windowTitle: String { window == "14d" ? "14 days" : (window == "28d" ? "28 days" : window) }
    }

    struct Strength: Equatable {
        var hasData: Bool
        var basis: String?
        var measure: String?
        var pct: Double?
        var direction: String?
        var patterns: [String] = []
    }

    struct Advice: Identifiable, Equatable {
        var id: String
        var severity: String?
        var text: String
    }

    var hasData: Bool
    var stale = false
    var lean: Lean?
    var weight: WeightTrend?
    var splits: [Split] = []
    var flagRaised = false
    /// ok, flag or calibrating; nil when the server sent no flag.
    var flagStatus: String?
    var flagRule: String?
    var strength: Strength?
    var tapeHasData = false
    var tapeWaistChange28dCm: Double?
    var advice: [Advice] = []
    var proteinText: String?

    var isCalibrating: Bool { flagStatus == "calibrating" }
}

struct PFTape: Equatable {
    struct Reading: Identifiable, Equatable {
        var date: String
        var values: [String: Double]
        var id: String { date }
    }

    struct Site: Identifiable, Equatable {
        var key: String
        var latest: Double?
        var latestDate: String?
        var readings: Int?
        var perWeekCm: Double?
        var change28dCm: Double?
        var direction: String?
        /// The server's own say-so that there are enough readings to quote a change.
        var enough: Bool
        var id: String { key }

        var title: String { PFTape.siteTitles[key] ?? key.capitalized }
    }

    struct WaistToHip: Equatable {
        var ratio: Double?
        var waist: Double?
        var hips: Double?
        var date: String?
    }

    static let siteOrder = ["waist", "hips", "chest", "arm", "thigh"]
    static let siteTitles = ["waist": "Waist", "hips": "Hips", "chest": "Chest", "arm": "Arm", "thigh": "Thigh"]

    var readings: [Reading] = []
    var sites: [Site] = []
    var waistToHip: WaistToHip?
    var note: String?

    var hasData: Bool { !sites.isEmpty || !readings.isEmpty }
}

// MARK: - Heat on a session

struct PFHeat: Equatable {
    var tempC: Double?
    var feelsC: Double?
    var humidity: Double?
    var level: String?
    var paceCostPct: Double?
    var source: String?

    /// A session worth a thermometer: the server rates the heat above mild, or it cost pace.
    var isHot: Bool {
        if let cost = paceCostPct, cost >= 1 { return true }
        switch (level ?? "").lowercased() {
        case "warm", "hot", "very_hot", "very hot", "extreme", "high", "severe": return true
        default: return false
        }
    }

    /// "24\u{00B0} (feels 27\u{00B0}) \u{00B7} hot \u{00B7} pace +3 %".
    var chipText: String {
        var parts: [String] = []
        if let temp = tempC {
            var text = "\(Int(temp.rounded()))\u{00B0}"
            if let feels = feelsC, Int(feels.rounded()) != Int(temp.rounded()) { text += " (feels \(Int(feels.rounded()))\u{00B0})" }
            parts.append(text)
        }
        if let level, !level.isEmpty { parts.append(level.replacingOccurrences(of: "_", with: " ")) }
        if let cost = paceCostPct, abs(cost) >= 0.05 {
            let sign = cost < 0 ? "\u{2212}" : "+"
            parts.append("pace " + sign + PFNumber.trimmed(abs(cost)) + " %")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    var hasContent: Bool { !chipText.isEmpty }
}

// MARK: - Body estimate labels

/// body.json `latest.segmental_meta`: whether the left/right segment figures are our estimate.
struct PFSegmentalMeta: Equatable {
    var estimate: Bool
    var method: String?
    var clampPct: Double?
    var note: String?
    var shareRight: Double?
}

// MARK: - Privacy

enum PFPrivacy {
    /// The athlete's own choice in More \u{203A} PaceForge, else the server's, else hidden: the safe default.
    static func hidesBody(server: Bool?, choice: Bool?) -> Bool { choice ?? server ?? true }

    /// The override lives in UserDefaults and is absent until the athlete flips the switch.
    static func savedOverride(in defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: overrideKey) as? Bool
    }

    static let overrideKey = "noop.paceforge.privacyOverride"
}

// MARK: - Intraday (Garmin Body Battery and stress) and day events (My Day)

struct PFIntradayPoint: Equatable {
    var ts: Int
    var value: Double
}

struct PFRecharge: Equatable {
    var startTs: Int?
    var endTs: Int?
    var from: Double?
    var to: Double?
    var minutes: Int?
}

struct PFIntraday: Equatable {
    var date: String?
    /// Garmin Body Battery, 0 to 100.
    var energy: [PFIntradayPoint] = []
    /// Garmin stress, 0 to 100.
    var stress: [PFIntradayPoint] = []
    var isFinal = false
    var lastRecharge: PFRecharge?

    var isEmpty: Bool { energy.isEmpty && stress.isEmpty && lastRecharge == nil }
}

struct PFDayEvent: Equatable {
    var id: String?
    /// workout, planned, weighIn or note.
    var kind: String
    var date: String
    /// The instant, when `start` carried a time; nil for a bare date.
    var startTs: Int?
    var endTs: Int?
    var title: String?
    /// done, planned or missed.
    var state: String?
    var sessionId: String?
    var matchedActivityId: String?
    var workoutType: String?
    var durationMin: Double?
    var weightKg: Double?
    var niggleId: String?
    var niggleSite: String?
    var niggleSide: String?
    var niggleSeverity: Double?
    var niggleMovements: [String] = []
    var niggleResolved = false
}

/// ISO-8601 stamps as PaceForge writes them: with an offset, or local with none. A bare date has no time.
enum PFStamp {
    static func parse(_ text: String?) -> Date? {
        guard let text, text.count > 10 else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        if let date = withFraction.date(from: text) ?? plain.date(from: text) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: text)
    }
}

enum PFNumber {
    /// 8 or 8.5, never 8.0.
    static func trimmed(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// 62.1, always one decimal.
    static func trimmedOne(_ value: Double) -> String { String(format: "%.1f", value) }

    /// +0.4, \u{2212}1.2, or 0.0 for a value that rounds to nothing. Neutral: no colour is chosen from the sign.
    static func signed(_ value: Double, decimals: Int = 1) -> String {
        let text = String(format: "%.\(max(0, decimals))f", abs(value))
        if Double(text) == 0 { return text }
        return (value < 0 ? "\u{2212}" : "+") + text
    }
}

// MARK: - Parsing

enum PFWave3Parse {

    // MARK: race-week.json

    /// `doc` is race-week.json when it was served; `brief` is the state's daily brief, whose short
    /// `race_week` summary stands in when the document is not served. A served document with
    /// `race_week: null` means it is not race week, and the brief is not consulted.
    static func raceWeek(_ doc: PFJ, brief: PFJ) -> PFRaceWeek? {
        if doc.exists { return raceWeekDetail(doc["race_week"], documentDate: doc["date"].text) }
        return raceWeekSummary(brief)
    }

    private static func raceWeekDetail(_ j: PFJ, documentDate: String?) -> PFRaceWeek? {
        guard j.exists else { return nil }
        let eventJ = j["event"]
        guard let name = eventJ["name"].text ?? eventJ.text else { return nil }
        var out = PFRaceWeek(
            date: documentDate,
            event: PFRaceWeek.Event(name: name, date: eventJ["date"].text, goalTime: eventJ["goal_time"].text,
                                    priority: eventJ["priority"].text, location: eventJ["location"].text,
                                    type: eventJ["type"].text),
            daysTo: j["days_to"].int, phase: j["phase"].text ?? "taper")
        out.volumeTargetPct = j["volume_target_pct"].double
        out.weekVolumeCutPct = j["week_volume_cut_pct"].double
        out.notes = j["notes"].array.compactMap { $0.text }
        let carb = j["carb_load"]
        if carb.exists {
            out.carbLoad = PFRaceWeek.CarbLoad(
                perKgLow: carb["g_per_kg_per_day"][0].double, perKgHigh: carb["g_per_kg_per_day"][1].double,
                gramsPerDay: carb["grams_per_day"].double, weightKg: carb["weight_kg"].double,
                tips: carb["tips"].array.compactMap { $0.text }, label: carb["label"].text, note: carb["note"].text)
        }
        out.checklist = j["checklist"].array.compactMap { item in
            guard let id = item["id"].idString, let text = item["text"].text else { return nil }
            return PFRaceWeek.CheckItem(id: id, when: item["when"].text, text: text)
        }
        let steps: [PFRaceWeek.MorningStep] = j["race_morning"].array.compactMap { step in
            guard let minutes = step["t_minus_min"].int, let text = step["text"].text else { return nil }
            return PFRaceWeek.MorningStep(tMinusMin: minutes, text: text)
        }
        out.raceMorning = steps.sorted { $0.tMinusMin > $1.tMinusMin }
        out.suppressesAlerts = j["suppresses_alerts"].bool ?? false
        let recovery = j["recovery"]
        if recovery.exists {
            out.recovery = PFRaceWeek.Recovery(day: recovery["day"].int, ofDays: recovery["of_days"].int,
                                               suggestion: recovery["suggestion"].text)
        }
        return out
    }

    private static func raceWeekSummary(_ brief: PFJ) -> PFRaceWeek? {
        let j = brief["race_week"]
        guard j.exists, let name = j["event"].text ?? j["event"]["name"].text ?? j["name"].text else { return nil }
        var out = PFRaceWeek(
            date: brief["date"].text,
            event: PFRaceWeek.Event(name: name, date: j["date"].text),
            daysTo: j["days_to"].int, phase: j["phase"].text ?? "taper")
        out.volumeTargetPct = j["volume_target_pct"].double
        out.notes = j["notes"].array.compactMap { $0.text }
        return out
    }

    // MARK: easy-mode.json

    /// `doc` is easy-mode.json when it was served; `stateMode` is `state.mode` (or the brief's), which stands
    /// in when it was not. nil when the server has neither, so an older server shows nothing about it.
    static func easyMode(_ doc: PFJ, stateMode: PFJ) -> PFEasyMode? {
        if doc.exists {
            var out = PFEasyMode()
            out.mode = easyModeState(doc["mode"])
            out.pending = doc["pending"].array.compactMap { p in
                guard let id = p["proposal_id"].idString else { return nil }
                return PFEasyMode.Proposal(proposalId: id, level: p["level"].int, days: p["days"].int,
                                           until: p["until"].text, title: p["title"].text ?? "Easy mode proposal")
            }
            out.levels = doc["levels"].array.compactMap { l in
                guard let level = l["level"].int, let label = l["label"].text else { return nil }
                return PFEasyMode.Level(level: level, label: label, summary: l["summary"].text)
            }
            return out
        }
        guard let mode = easyModeState(stateMode) else { return nil }
        return PFEasyMode(mode: mode)
    }

    private static func easyModeState(_ j: PFJ) -> PFEasyMode.Mode? {
        guard j.exists, let level = j["level"].int else { return nil }
        var out = PFEasyMode.Mode(level: level, label: j["label"].text ?? "Level \(level)")
        out.summary = j["summary"].text
        out.started = j["started"].text
        out.until = j["until"].text
        out.day = j["day"].int
        out.ofDays = j["of_days"].int
        out.daysLeft = j["days_left"].int
        out.returnsOn = j["returns_on"].text
        let changed = j["changed_sessions"]
        if changed.raw is [Any] {
            out.changedSessionIds = changed.array.compactMap { $0.idString ?? $0["session_id"].idString ?? $0["id"].idString }
            out.changedCount = changed.array.count
        } else {
            out.changedCount = changed.int
        }
        out.restorable = j["restorable"].bool ?? false
        return out
    }

    // MARK: hyrox-sim-analysis.json and hyrox-sims.json

    /// nil only when neither document was served. Served but empty is a card with its empty state.
    static func hyroxSims(analysis: PFJ, sims: PFJ) -> PFHyroxSims? {
        guard analysis.exists || sims.exists else { return nil }
        let simRows = sims["sims"].array
        let hasData = analysis["has_data"].bool ?? !simRows.isEmpty
        var out = PFHyroxSims(hasData: hasData)
        out.count = analysis["count"].int ?? simRows.count
        let unmapped = analysis["unmapped"]
        out.unmappedCount = unmapped.raw is [Any] ? unmapped.array.count : (unmapped.int ?? 0)
        out.note = analysis["note"].text

        let goal = analysis["goal"]
        if goal.exists {
            out.goal = PFHyroxSims.Goal(event: goal["event"].text, date: goal["date"].text,
                                        goalSeconds: goal["goal_seconds"].double, goalDisplay: goal["goal_display"].text,
                                        basis: goal["basis"].text)
        }
        let fresh = analysis["fresh_run"]
        if fresh.exists {
            out.freshRun = PFHyroxSims.FreshRun(paceSec: fresh["pace_sec"].double, display: fresh["display"].text,
                                                nRuns: fresh["n_runs"].int, basis: fresh["basis"].text)
        }
        let latest = analysis["latest"]
        if latest.exists {
            var l = PFHyroxSims.Latest()
            l.id = latest["id"].idString
            l.date = latest["date"].text
            l.complete = latest["complete"].bool ?? true
            l.totalSeconds = latest["total_seconds"].double
            l.totalDisplay = latest["total_display"].text
            l.notes = latest["notes"].text
            l.runFadePct = latest["run_fade_pct"].double
            l.compromisedPct = latest["compromised_pct"].double
            l.compromisedRuns = latest["compromised_runs"].array.compactMap { r in
                guard let run = r["run"].int else { return nil }
                return PFHyroxSims.CompromisedRun(run: run, seconds: r["seconds"].double, pctSlower: r["pct_slower"].double)
            }
            l.maxDevPct = latest["max_dev_pct"].double
            l.withinBand = latest["within_band"].bool
            l.pacingNote = latest["pacing_note"].text
            out.latest = l
        }
        out.segments = analysis["segments"].array.enumerated().compactMap { index, s in
            guard let name = s["name"].text else { return nil }
            return PFHyroxSims.Segment(index: index, name: name, kind: s["kind"].text ?? "station",
                                       display: s["display"].text, simSeconds: s["sim_seconds"].double,
                                       goalSeconds: s["goal_seconds"].double, deltaGoalS: s["delta_goal_s"].double,
                                       prevSeconds: s["prev_seconds"].double, deltaPrevS: s["delta_prev_s"].double)
        }
        out.weakest = analysis["weakest"].array.compactMap { w in
            guard let station = w["station"].text else { return nil }
            return PFHyroxSims.Weak(station: station, display: w["display"].text, simSeconds: w["sim_seconds"].double,
                                    goalSeconds: w["goal_seconds"].double, overS: w["over_s"].double,
                                    overPct: w["over_pct"].double, suggestion: w["suggestion"].text)
        }

        // The sims list stands in for what the analysis lacks: the newest simulation's total and splits.
        if let newest = simRows.max(by: { ($0["date"].text ?? "") < ($1["date"].text ?? "") }) {
            if out.latest == nil {
                var l = PFHyroxSims.Latest()
                l.id = newest["id"].idString
                l.date = newest["date"].text
                l.complete = newest["complete"].bool ?? true
                l.totalSeconds = newest["total_seconds"].double
                l.totalDisplay = newest["total_display"].text
                l.notes = newest["notes"].text
                out.latest = l
            }
            if out.segments.isEmpty {
                out.segments = newest["segments"].array.enumerated().compactMap { index, s in
                    guard let name = s["name"].text else { return nil }
                    return PFHyroxSims.Segment(index: index, name: name, kind: s["kind"].text ?? "station",
                                               display: s["display"].text, simSeconds: s["seconds"].double)
                }
            }
        }
        return out
    }

    // MARK: muscle-check.json

    static func muscleCheck(_ j: PFJ) -> PFMuscleCheck? {
        guard j.exists else { return nil }
        var out = PFMuscleCheck(hasData: j["has_data"].bool ?? false)
        out.stale = j["stale"].bool ?? false
        let lean = j["lean"]
        if lean.exists {
            out.lean = PFMuscleCheck.Lean(
                currentTrendKg: lean["current_trend_kg"].double, noiseKg: lean["noise_kg"].double,
                noiseBasis: lean["noise_basis"].text, perWeekKg: lean["per_week_kg"].double,
                perWeekPct: lean["per_week_pct"].double, change14dKg: lean["change_14d_kg"].double,
                change28dKg: lean["change_28d_kg"].double, readings: lean["readings"].int)
        }
        let weight = j["weight"]
        if weight.exists {
            out.weight = PFMuscleCheck.WeightTrend(currentTrendKg: weight["current_trend_kg"].double,
                                                   perWeekKg: weight["per_week_kg"].double,
                                                   perWeekPct: weight["per_week_pct"].double)
        }
        out.splits = ["14d", "28d"].compactMap { window in
            let s = j["split"][window]
            guard s.exists else { return nil }
            return PFMuscleCheck.Split(window: window, days: s["days"].int, weightKg: s["weight_kg"].double,
                                       leanKg: s["lean_kg"].double, fatKg: s["fat_kg"].double,
                                       leanSharePct: s["lean_share_pct"].double, quality: s["quality"].text)
        }
        let flag = j["flag"]
        if flag.exists {
            out.flagRaised = flag["raised"].bool ?? false
            out.flagStatus = flag["status"].text
            out.flagRule = flag["rule"].text
        }
        let strength = j["strength"]
        if strength.exists {
            out.strength = PFMuscleCheck.Strength(
                hasData: strength["has_data"].bool ?? false, basis: strength["basis"].text,
                measure: strength["trend"]["measure"].text, pct: strength["trend"]["pct"].double,
                direction: strength["trend"]["direction"].text,
                patterns: strength["trend"]["patterns"].array.compactMap { $0.text })
        }
        out.tapeHasData = j["tape"]["has_data"].bool ?? false
        out.tapeWaistChange28dCm = j["tape"]["waist_change_28d_cm"].double
        out.advice = j["advice"].array.enumerated().compactMap { index, a in
            guard let text = a["text"].text else { return nil }
            return PFMuscleCheck.Advice(id: a["id"].idString ?? "advice-\(index)", severity: a["severity"].text, text: text)
        }
        let protein = j["protein_g"]
        if let single = protein.double {
            out.proteinText = "\(Int(single.rounded())) g"
        } else if let low = protein["low"].double, let high = protein["high"].double {
            out.proteinText = "\(Int(low.rounded()))\u{2013}\(Int(high.rounded())) g"
        } else if let low = protein[0].double, let high = protein[1].double {
            out.proteinText = "\(Int(low.rounded()))\u{2013}\(Int(high.rounded())) g"
        }
        return out
    }

    // MARK: tape.json

    static func tape(_ j: PFJ) -> PFTape? {
        guard j.exists else { return nil }
        var out = PFTape()
        out.readings = j["readings"].array.compactMap { r in
            guard let date = r["date"].text else { return nil }
            var values: [String: Double] = [:]
            for site in PFTape.siteOrder { if let v = r[site].double { values[site] = v } }
            return PFTape.Reading(date: date, values: values)
        }
        let trend = j["trend"].dict
        let keys = PFTape.siteOrder.filter { trend[$0] != nil } + trend.keys.filter { !PFTape.siteOrder.contains($0) }.sorted()
        out.sites = keys.compactMap { key in
            guard let t = trend[key] else { return nil }
            return PFTape.Site(key: key, latest: t["latest"].double, latestDate: t["latest_date"].text,
                               readings: t["readings"].int, perWeekCm: t["per_week_cm"].double,
                               change28dCm: t["change_28d_cm"].double, direction: t["direction"].text,
                               enough: t["enough"].bool ?? false)
        }
        let wth = j["waist_to_hip"]
        if wth.exists {
            out.waistToHip = PFTape.WaistToHip(ratio: wth["ratio"].double, waist: wth["waist"].double,
                                               hips: wth["hips"].double, date: wth["date"].text)
        }
        out.note = j["note"].text
        return out
    }

    // MARK: Heat, segmental meta, privacy

    static func heat(_ j: PFJ) -> PFHeat? {
        guard j.exists else { return nil }
        let out = PFHeat(tempC: j["temp_c"].double, feelsC: j["feels_c"].double, humidity: j["humidity"].double,
                         level: j["level"].text, paceCostPct: j["pace_cost_pct"].double, source: j["source"].text)
        return out.hasContent ? out : nil
    }

    static func segmentalMeta(_ j: PFJ) -> PFSegmentalMeta? {
        guard j.exists, let estimate = j["estimate"].bool else { return nil }
        return PFSegmentalMeta(estimate: estimate, method: j["method"].text, clampPct: j["clamp_pct"].double,
                               note: j["note"].text, shareRight: j["share_right"].double)
    }

    /// `state.settings.privacy.hide_body_on_lock_screen`, or nil when the server does not send it.
    static func hidesBodyOnLockScreen(_ state: PFJ) -> Bool? {
        state["settings"]["privacy"]["hide_body_on_lock_screen"].bool
    }

    // MARK: intraday

    /// `intraday/<date>.json` and `intraday-today.json`. Timestamps are epoch milliseconds. A negative
    /// stress value is Garmin's "no reading" marker and is dropped.
    static func intraday(_ j: PFJ) -> PFIntraday? {
        guard j.exists else { return nil }
        var out = PFIntraday()
        out.date = j["date"].text
        out.isFinal = j["final"].bool ?? false
        out.energy = points(j["body_battery"], minimum: 0)
        out.stress = points(j["stress"], minimum: 0)
        let recharge = j["last_recharge"]
        if recharge.exists {
            let start = recharge["start"].double.map { Int($0 / 1000) }
            let end = recharge["time"].double.map { Int($0 / 1000) }
            let r = PFRecharge(startTs: start, endTs: end, from: recharge["from"].double, to: recharge["to"].double,
                               minutes: recharge["minutes"].int)
            if r.startTs != nil || r.endTs != nil || r.to != nil { out.lastRecharge = r }
        }
        return out.isEmpty ? nil : out
    }

    private static func points(_ list: PFJ, minimum: Double) -> [PFIntradayPoint] {
        list.array.compactMap { pair in
            guard let ms = pair[0].double, let value = pair[1].double, value >= minimum else { return nil }
            return PFIntradayPoint(ts: Int(ms / 1000), value: value)
        }.sorted { $0.ts < $1.ts }
    }

    // MARK: day-events.json

    static func dayEvents(_ j: PFJ) -> [PFDayEvent] {
        j["events"].array.compactMap { e in
            guard let kind = e["kind"].text, let date = e["date"].text else { return nil }
            let start = PFStamp.parse(e["start"].text)
            let end = PFStamp.parse(e["end"].text)
            // An all-day entry may still carry a time-of-day in `start`; it is not a slot.
            let timed = !(e["all_day"].bool ?? false)
            var out = PFDayEvent(kind: kind, date: date)
            out.id = e["id"].idString
            out.startTs = timed ? start.map { Int($0.timeIntervalSince1970) } : nil
            out.endTs = timed ? end.map { Int($0.timeIntervalSince1970) } : nil
            out.title = e["title"].text
            out.state = e["state"].text
            out.sessionId = e["session_id"].idString
            out.matchedActivityId = e["matched_activity_id"].idString
            out.workoutType = e["workout_type"].text
            out.durationMin = e["duration_min"].double
            out.weightKg = e["weight_kg"].double
            let niggle = e["niggle"]
            if niggle.exists {
                out.niggleId = niggle["id"].idString
                out.niggleSite = niggle["site"].text
                out.niggleSide = niggle["side"].text
                out.niggleSeverity = niggle["severity"].double
                out.niggleMovements = niggle["movements"].array.compactMap { $0.text }
                out.niggleResolved = niggle["resolved"].bool ?? false
            }
            return out
        }
    }
}
