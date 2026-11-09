import Foundation

// The HYROX screen (Plan > HYROX, and the Open HYROX button on the Coach race plans): the two documents the server builds for it
// (`api/hyrox/race-plan`, `api/hyrox/results`), the training, advisory and season sections it draws from documents the app already
// reads, and the wording. Foundation only, so the parsing and the wording are compiled into the macOS unit-test bundle. Read-only:
// the plan is edited on the web app. His own numbers only: no predicted finish, no top-3, field or percentile figure appears here,
// and the server's fields for those (which still exist in other documents) are never read by this screen.

// MARK: - Documents

enum PFHyroxDoc {
    static let racePlanBase = "api/hyrox/race-plan"
    static let resultsPath = "api/hyrox/results"

    /// The plan of one upcoming race (`event` is its date, yyyy-MM-dd), or of the next one when `event` is nil.
    static func racePlanPath(event: String?) -> String {
        guard let event = event?.trimmingCharacters(in: .whitespacesAndNewlines), !event.isEmpty else { return racePlanBase }
        return racePlanBase + "?event=" + event
    }
}

/// The 8 laps, the 8 stations and the Roxzone in race order, as the server names them.
enum PFHyroxSegments {
    static let order = ["Running_1", "SkiErg_1000m", "Running_2", "Sled_Push_50m", "Running_3", "Sled_Pull_50m", "Running_4",
                        "Burpee_Broad_Jump_80m", "Running_5", "Row_1000m", "Running_6", "Farmers_Carry_200m", "Running_7",
                        "Sandbag_Lunges_100m", "Running_8", "Wall_Balls", "Roxzone_Time"]
}

enum PFHyroxEventKind {
    /// The server's rule for which pacing model an event is raced under: its type or its name says HYROX (or TRYKA).
    static func isHyrox(name: String, type: String?) -> Bool {
        let kind = ((type ?? "") + " " + name).lowercased()
        return kind.contains("hyrox") || kind.contains("tryka")
    }
}

// MARK: - Next race

struct PFHyroxEvent: Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let date: String
    let daysOut: Int
    let goalTime: String?
    let format: String?
    let division: String?
    let priority: String?

    /// "HYROX Testville" reads "Testville".
    var shortName: String {
        let stripped = name.replacingOccurrences(of: "^HYROX\\s+", with: "", options: [.regularExpression, .caseInsensitive])
        return stripped.isEmpty ? name : stripped
    }

    var pickerLabel: String { shortName + " \u{00B7} " + PFFormat.shortDate(date) }

    /// "12", or "Today" on the day itself.
    var countdownValue: String { daysOut <= 0 ? "Today" : String(daysOut) }
    var countdownUnit: String? { daysOut <= 0 ? nil : (daysOut == 1 ? "day" : "days") }

    /// "Wed 11 Nov", "goal 1:10:00", "singles open", "priority A".
    var facts: [String] {
        var out = [PFFormat.dayTitle(date)]
        if let goalTime { out.append("goal " + goalTime) }
        let kind = [format, division].compactMap { $0 }.joined(separator: " ")
        if !kind.isEmpty { out.append(kind) }
        if let priority { out.append("priority " + priority) }
        return out
    }
}

/// One station or the Roxzone: the three planning levels and how much it swings.
struct PFHyroxLevel: Equatable, Identifiable {
    let key: String
    let name: String
    let realisticS: Int?
    let stretchS: Int?
    let badS: Int?
    let spreadS: Int?
    let biasS: Int?
    let saveS: Int?
    let swing: Bool

    var id: String { key }
}

struct PFHyroxRun: Equatable, Identifiable {
    let key: String
    let name: String
    let targetS: Int
    /// The lap he should not go faster than; only the first three laps carry one.
    let ceilingS: Int?
    let bandLowS: Int?
    let bandHighS: Int?

    var id: String { key }

    /// "4:58\u{2013}5:20", or nil without a band.
    var bandText: String? {
        guard let bandLowS, let bandHighS else { return nil }
        return PFHyroxFormat.clock(bandLowS) + "\u{2013}" + PFHyroxFormat.clock(bandHighS)
    }
}

/// Garmin's own 10K prediction, the running-fitness cross-check beside the pacing.
struct PFHyroxGarmin10K: Equatable {
    let seconds: Double
    let date: String?

    var line: String {
        var text = "Running-fitness cross-check: Garmin's 10K prediction is \(PFFormat.clock(seconds))"
        if let date { text += " (Garmin, \(PFFormat.shortDate(date)))" }
        return text + " (= \(PFFormat.pace(seconds / 10))/km)."
    }
}

struct PFHyroxPackSection: Equatable, Identifiable {
    let title: String
    let md: String

    var id: String { title }
}

/// The written race pack without the parts the screen builds from data (pacing, history, context).
struct PFHyroxPack: Equatable {
    /// Seconds since 1970 of the last write.
    let updated: Double?
    let sections: [PFHyroxPackSection]

    /// The sections shown open, in this order: the goal and plans A and B, the warm-up, the cues, and what to do if it goes wrong.
    var main: [PFHyroxPackSection] {
        let wanted: [(String) -> Bool] = [
            { $0.hasPrefix("goal") }, { $0.hasPrefix("warm") }, { $0.hasPrefix("mental") || $0.hasPrefix("cues") },
            { $0.hasPrefix("if it goes wrong") },
        ]
        return wanted.compactMap { matches in sections.first { matches($0.title.lowercased()) } }
    }

    var rest: [PFHyroxPackSection] {
        let shown = Set(main.map(\.title))
        return sections.filter { !shown.contains($0.title) }
    }
}

/// His saved plan for the race (written on the web app); the phone only reads it.
struct PFHyroxSavedPlan: Equatable {
    let values: [String: Int]
    let locked: [String]
    let updated: String?
}

struct PFHyroxPlanRow: Equatable, Identifiable {
    let key: String
    let name: String
    let realisticS: Int
    let planS: Int
    let isLocked: Bool

    var id: String { key }
    var deltaS: Int { planS - realisticS }
}

struct PFHyroxPlan: Equatable {
    var events: [PFHyroxEvent] = []
    var event: PFHyroxEvent?
    /// False, with a reason, when no pacing can be built from his races.
    var available = false
    var reason: String?
    var venue: String?
    var racesOnFile = 0
    /// The laps are uneven at this venue, so a run is a lap time and not a pace per km.
    var lapProfile = false
    var goalS: Int?
    var runs: [PFHyroxRun] = []
    var stations: [PFHyroxLevel] = []
    var roxzone: PFHyroxLevel?
    /// The Realistic time of every segment, by the server's segment name.
    var base: [String: Int] = [:]
    var swingNames: [String] = []
    var availableS: Int?
    var garmin10K: PFHyroxGarmin10K?
    var yourPlan: PFHyroxSavedPlan?
    var pack: PFHyroxPack?

    /// A saved plan fits the pack only while it names exactly the segments the pack's Realistic does.
    var savedPlanFits: Bool {
        guard let yourPlan, !base.isEmpty else { return false }
        return Set(yourPlan.values.keys) == Set(base.keys)
    }

    var savedPlanIsStale: Bool { yourPlan != nil && !savedPlanFits }

    var stationsWithSwing: [PFHyroxLevel] { (stations + (roxzone.map { [$0] } ?? [])).filter { $0.swing } }

    /// The stations where his best is faster than his split at this venue, widest first.
    var timeToFind: [PFHyroxLevel] {
        stations.filter { ($0.saveS ?? 0) > 0 }.sorted { ($0.saveS ?? 0) > ($1.saveS ?? 0) }
    }

    /// Every segment of the saved plan beside Realistic, in race order; empty when no saved plan fits.
    var planRows: [PFHyroxPlanRow] {
        guard savedPlanFits, let yourPlan else { return [] }
        var named: [(String, String)] = runs.map { ($0.key, $0.name) }
        named += stations.map { ($0.key, $0.name) }
        if let roxzone { named.append((roxzone.key, roxzone.name)) }
        let names = Dictionary(named, uniquingKeysWith: { first, _ in first })
        return PFHyroxSegments.order.compactMap { key in
            guard let planned = yourPlan.values[key], let realistic = base[key] else { return nil }
            return PFHyroxPlanRow(key: key, name: names[key] ?? PFFormat.words(key), realisticS: realistic, planS: planned,
                                  isLocked: yourPlan.locked.contains(key))
        }
    }

    var planTotalS: Int { planRows.reduce(0) { $0 + $1.planS } }
    var realisticTotalS: Int { planRows.reduce(0) { $0 + $1.realisticS } }
}

// MARK: - Results and performance

struct PFHyroxSplit: Equatable, Identifiable {
    let key: String
    let name: String
    let seconds: Int

    var id: String { key }
}

struct PFHyroxResultRace: Equatable, Identifiable {
    let id: String
    let date: String?
    let city: String?
    let division: String?
    let totalS: Int?
    let totalDisplay: String?
    let runsS: Int?
    let stationsS: Int?
    let roxzoneS: Int?
    /// The 8 laps; a lap the timing did not record is nil.
    let laps: [Int?]
    let stations: [PFHyroxSplit]
    let flags: [String]
    let artefact: Bool

    var title: String { city ?? "Race" }

    /// "Sun 8 Mar \u{00B7} open".
    var subtitle: String {
        var parts: [String] = []
        if let date { parts.append(PFFormat.dayTitle(date)) }
        if let division { parts.append(division) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var finishText: String { totalDisplay ?? (totalS.map { PFHyroxFormat.clock($0) } ?? "\u{2013}") }

    var summaryLine: String {
        "Runs \(PFHyroxFormat.clock(runsS)) \u{00B7} Stations \(PFHyroxFormat.clock(stationsS)) \u{00B7} Roxzone \(PFHyroxFormat.clock(roxzoneS))"
    }
}

/// One station (or the Roxzone) across all his races: best, median, last, how far apart they are and the run of times.
struct PFHyroxSeries: Equatable, Identifiable {
    let key: String
    let name: String
    let bestS: Int?
    let medianS: Int?
    let lastS: Int?
    let swingS: Int?
    /// The last race against the median of the races before it; nil on a first race.
    let changeS: Int?
    let races: Int
    /// Oldest to newest.
    let points: [Double]

    var id: String { key }
}

struct PFHyroxRunRace: Equatable, Identifiable {
    let date: String
    let city: String?
    let spreadPct: Double
    let run8Pct: Double

    var id: String { date + "|" + (city ?? "") }
}

struct PFHyroxRunStats: Equatable {
    let lapCleanRaces: Int
    let of: Int
    let bandPct: Double?
    let firstThreePct: Double?
    let run8Pct: Double?
    let perRace: [PFHyroxRunRace]
}

struct PFHyroxTimeLoss: Equatable {
    struct Row: Equatable, Identifiable {
        let name: String
        let overBestS: Int
        var id: String { name }
    }

    let race: String?
    let rows: [Row]
    let totalS: Int?

    /// "In Testville 2026-03-08 you were over your own best by Sled Push 12 s, Row 8 s = 20 s."
    var line: String? {
        guard !rows.isEmpty else { return nil }
        let list = rows.map { "\($0.name) \($0.overBestS) s" }.joined(separator: ", ")
        let total = totalS.map { " = \($0) s" } ?? ""
        return "In \(race ?? "your last race") you were over your own best by \(list)\(total)."
    }
}

struct PFHyroxResults: Equatable {
    var races: [PFHyroxResultRace] = []
    var stations: [PFHyroxSeries] = []
    var roxzone: PFHyroxSeries?
    var runs: PFHyroxRunStats?
    var timeLoss: PFHyroxTimeLoss?

    /// The fastest finish on file, as the server printed it.
    var bestFinish: String? {
        races.compactMap { race in race.totalS.map { ($0, race.finishText) } }.min { $0.0 < $1.0 }?.1
    }
}

// MARK: - Wording

enum PFHyroxFormat {
    /// m:ss (h:mm:ss from an hour), an en dash when the time is missing or zero.
    static func clock(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "\u{2013}" }
        return PFFormat.clock(Double(seconds))
    }

    /// "+5 s", "\u{2212}3 s", "\u{00B1}0 s"; an en dash for a missing number.
    static func signed(_ seconds: Int?) -> String {
        guard let seconds else { return "\u{2013}" }
        if seconds > 0 { return "+\(seconds) s" }
        if seconds < 0 { return "\u{2212}\(abs(seconds)) s" }
        return "\u{00B1}0 s"
    }

    /// "+4 s vs usual" for a series' last race; nil on a first race.
    static func againstUsual(_ series: PFHyroxSeries) -> String? {
        series.changeS.map { signed($0) + " vs usual" }
    }

    /// What the run laps say across his lap-clean races.
    static func lapNote(_ runs: PFHyroxRunStats) -> String {
        guard runs.lapCleanRaces > 0 else {
            return "No race with usable lap times yet (laps cut short by the timing mats are left out)."
        }
        var clauses: [String] = []
        if let band = runs.bandPct { clauses.append("laps 2 to 7 stay within \(PFFormat.trimmed(band)) % of the median lap") }
        if let early = runs.firstThreePct {
            clauses.append("your first three laps average \(PFFormat.trimmed(abs(early))) % \(early < 0 ? "faster" : "slower") than laps 4 to 7")
        }
        if let fade = runs.run8Pct {
            clauses.append("Run 8 is \(PFFormat.trimmed(abs(fade))) % \(fade > 0 ? "slower" : "faster") than laps 4 to 7")
        }
        let head = "Across your \(runs.lapCleanRaces) lap-clean races (of \(runs.of))"
        return clauses.isEmpty ? head + "." : head + ": " + clauses.joined(separator: "; ") + "."
    }

    /// "+3.2 %" for the per-race table.
    static func percent(_ value: Double) -> String {
        (value > 0 ? "+" : "") + PFFormat.trimmed(value) + " %"
    }

    /// The pacing table's lead-in: a venue with uneven laps gives lap times, not a pace per km.
    static func runsHint(venue: String?, lapProfile: Bool) -> String {
        if lapProfile, let venue {
            return "\(venue) is this venue's profile: its laps are uneven, so a run is a lap time, not a pace per km."
        }
        return "Targets are your own times; a run is one even km."
    }

    /// What Realistic, Stretch, Bad day, Swing and Usually vs best mean.
    static func levelsHint(venue: String?, racesOnFile: Int) -> String {
        let realistic = venue.map { "your \($0) split" } ?? "the median of your last 12 months"
        return "Realistic is \(realistic), Stretch your best in any race, Bad day your median (never faster than Realistic). "
            + "Swing is the gap between your best and worst across \(racesOnFile) races; Usually vs best is how a race typically compares with your best before it."
    }

    /// "Where the time is (your best against your Testville split): A 12 s, B 8 s = 20 s."
    static func timeToFindLine(_ plan: PFHyroxPlan) -> String? {
        guard let total = plan.availableS, !plan.timeToFind.isEmpty else { return nil }
        let list = plan.timeToFind.map { "\($0.name) \($0.saveS ?? 0) s" }.joined(separator: ", ")
        let against = plan.venue.map { " (your best against your \($0) split)" } ?? ""
        return "Where the time is\(against): \(list) = \(total) s."
    }
}

// MARK: - Parsing

enum PFHyroxParse {
    /// nil when the answer is not a JSON object. A plan with no event (none upcoming) or no pacing is still a plan: it says why.
    static func plan(_ data: Data?) -> PFHyroxPlan? {
        let root = PFJ(data: data)
        guard root.raw is [String: Any] else { return nil }
        var out = PFHyroxPlan()
        out.events = root["events"].array.compactMap(event)
        out.event = event(root["event"])
        out.available = root["available"].bool ?? false
        out.reason = root["reason"].text
        out.venue = root["venue"].text
        out.racesOnFile = root["races_on_file"].int ?? 0
        out.lapProfile = root["lap_profile"].bool ?? false
        out.goalS = root["goal_s"].int
        out.runs = root["runs"].array.compactMap(run)
        out.stations = root["stations"].array.compactMap(level)
        out.roxzone = level(root["roxzone"])
        out.base = root["base"].dict.compactMapValues { $0.int }
        out.swingNames = root["swing"].strings
        out.availableS = root["available_s"].int
        if let seconds = root["garmin_10k"]["seconds"].double, seconds > 0 {
            out.garmin10K = PFHyroxGarmin10K(seconds: seconds, date: root["garmin_10k"]["date"].text)
        }
        out.yourPlan = savedPlan(root["your_plan"])
        out.pack = pack(root["pack"])
        return out
    }

    /// nil when the answer is not a JSON object.
    static func results(_ data: Data?) -> PFHyroxResults? {
        let root = PFJ(data: data)
        guard root.raw is [String: Any] else { return nil }
        var out = PFHyroxResults()
        out.races = root["races"].array.compactMap(race)
        let performance = root["performance"]
        out.stations = performance["stations"].array.compactMap { series($0, fallbackName: nil) }
        out.roxzone = series(performance["roxzone"], fallbackName: "Roxzone", fallbackKey: "Roxzone_Time")
        out.runs = runStats(performance["runs"])
        out.timeLoss = timeLoss(performance["where_the_time_is"])
        return out
    }

    // MARK: Pieces of the plan

    private static func event(_ j: PFJ) -> PFHyroxEvent? {
        guard j.raw is [String: Any], let id = j["id"].text else { return nil }
        let date = j["date"].text ?? id
        return PFHyroxEvent(id: id, name: j["name"].text ?? "HYROX", date: date, daysOut: j["days_out"].int ?? 0,
                            goalTime: j["goal_time"].text, format: j["format"].text, division: j["division"].text,
                            priority: j["priority"].idString?.trimmingCharacters(in: .whitespaces).nilIfEmpty)
    }

    private static func level(_ j: PFJ) -> PFHyroxLevel? {
        guard j.raw is [String: Any], let key = j["key"].text else { return nil }
        return PFHyroxLevel(key: key, name: j["name"].text ?? PFFormat.words(key), realisticS: j["realistic_s"].int,
                            stretchS: j["stretch_s"].int, badS: j["bad_s"].int, spreadS: j["spread_s"].int, biasS: j["bias_s"].int,
                            saveS: j["save_s"].int, swing: j["swing"].bool ?? false)
    }

    private static func run(_ j: PFJ) -> PFHyroxRun? {
        guard let key = j["key"].text, let target = j["target_s"].int else { return nil }
        let band = j["band_s"].array
        return PFHyroxRun(key: key, name: j["name"].text ?? PFFormat.words(key), targetS: target, ceilingS: j["ceiling_s"].int,
                          bandLowS: band.count == 2 ? band[0].int : nil, bandHighS: band.count == 2 ? band[1].int : nil)
    }

    private static func savedPlan(_ j: PFJ) -> PFHyroxSavedPlan? {
        guard j.raw is [String: Any] else { return nil }
        let values = j["plan"].dict.compactMapValues { $0.int }
        guard !values.isEmpty else { return nil }
        return PFHyroxSavedPlan(values: values, locked: j["locked"].strings, updated: j["updated"].text)
    }

    private static func pack(_ j: PFJ) -> PFHyroxPack? {
        guard j.raw is [String: Any] else { return nil }
        let sections = j["sections"].array.compactMap { s -> PFHyroxPackSection? in
            guard let title = s["title"].text else { return nil }
            return PFHyroxPackSection(title: title, md: s["md"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        return PFHyroxPack(updated: j["updated"].double, sections: sections)
    }

    // MARK: Pieces of the results

    private static func race(_ j: PFJ) -> PFHyroxResultRace? {
        guard j.raw is [String: Any], let id = j["id"].text else { return nil }
        let splits = j["stations"].array.compactMap { s -> PFHyroxSplit? in
            guard let key = s["key"].text, let seconds = s["s"].int else { return nil }
            return PFHyroxSplit(key: key, name: s["name"].text ?? PFFormat.words(key), seconds: seconds)
        }
        let flags = j["flags"].strings
        return PFHyroxResultRace(id: id, date: j["date"].text, city: j["city"].text, division: j["division"].text,
                                 totalS: j["total_s"].int, totalDisplay: j["total_display"].text, runsS: j["runs_s"].int,
                                 stationsS: j["stations_s"].int, roxzoneS: j["roxzone_s"].int,
                                 laps: j["laps"].array.map { $0.int }, stations: splits, flags: flags,
                                 artefact: j["artefact"].bool ?? !flags.isEmpty)
    }

    private static func series(_ j: PFJ, fallbackName: String?, fallbackKey: String? = nil) -> PFHyroxSeries? {
        guard j.raw is [String: Any], let key = j["key"].text ?? fallbackKey, let name = j["name"].text ?? fallbackName else { return nil }
        return PFHyroxSeries(key: key, name: name, bestS: j["best_s"].int, medianS: j["median_s"].int, lastS: j["last_s"].int,
                             swingS: j["swing_s"].int, changeS: j["change_s"].int, races: j["races"].int ?? 0,
                             points: j["series"].array.compactMap { $0["s"].double })
    }

    private static func runStats(_ j: PFJ) -> PFHyroxRunStats? {
        guard j.raw is [String: Any] else { return nil }
        let perRace = j["per_race"].array.compactMap { r -> PFHyroxRunRace? in
            guard let date = r["date"].text, let spread = r["spread_pct"].double, let run8 = r["run8_vs_steady_pct"].double else { return nil }
            return PFHyroxRunRace(date: date, city: r["city"].text, spreadPct: spread, run8Pct: run8)
        }
        return PFHyroxRunStats(lapCleanRaces: j["lap_clean_races"].int ?? 0, of: j["of"].int ?? 0, bandPct: j["band_pct"].double,
                               firstThreePct: j["first_three_vs_laps_4_7_pct"].double, run8Pct: j["run8_vs_laps_4_7_pct"].double,
                               perRace: perRace)
    }

    private static func timeLoss(_ j: PFJ) -> PFHyroxTimeLoss? {
        guard j.raw is [String: Any] else { return nil }
        let rows = j["rows"].array.compactMap { r -> PFHyroxTimeLoss.Row? in
            guard let name = r["name"].text, let over = r["over_best_s"].int else { return nil }
            return PFHyroxTimeLoss.Row(name: name, overBestS: over)
        }
        return PFHyroxTimeLoss(race: j["race"].text, rows: rows, totalS: j["total_s"].int)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Training for HYROX

enum PFHyroxTraining {
    /// A session that trains the race: HYROX sessions, strength, and runs after stations. Optional sessions count.
    static func isHyroxSession(_ workout: PFWorkout) -> Bool {
        let kind = workout.kind ?? ""
        if kind.hasPrefix("hyrox") || kind == "strength" { return true }
        return (workout.name ?? "").range(of: "hyrox|compromis|brick|sled|wall ?ball|sandbag|burpee",
                                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Race simulation", "Station day", "Strength", "Compromised run" or "Stations and runs".
    static func kindLabel(_ workout: PFWorkout) -> String {
        let kind = workout.kind ?? ""
        if kind == "hyrox_simulation" { return "Race simulation" }
        if kind == "hyrox_station_day" { return "Station day" }
        if kind == "strength" { return "Strength" }
        if (workout.name ?? "").range(of: "compromis|brick", options: [.regularExpression, .caseInsensitive]) != nil { return "Compromised run" }
        return "Stations and runs"
    }

    /// The HYROX sessions of this week (from `monday` to Sunday) and of next week, soonest first.
    static func sessions(weeks: [PFWeek], today: String) -> (monday: String, thisWeek: [PFWorkout], nextWeek: [PFWorkout]) {
        let monday = PFFormat.monday(of: today)
        let nextMonday = PFFormat.addDays(monday, 7)
        let end = PFFormat.addDays(monday, 14)
        var seen = Set<String>()
        let found = weeks.flatMap { $0.days }.flatMap { $0.workouts }
            .filter { $0.date >= monday && $0.date < end && isHyroxSession($0) }
            .filter { seen.insert($0.id.isEmpty ? $0.date + ($0.name ?? "") : $0.id).inserted }
            .sorted { $0.date < $1.date }
        return (monday, found.filter { $0.date < nextMonday }, found.filter { $0.date >= nextMonday })
    }
}

// MARK: - Advisory

enum PFHyroxAdvice {
    private static let pattern = "hyrox|\\brace\\b|station|sled|wall ?ball|lunge|burpee|skierg|\\brow(?:ing)?\\b|farmers|roxzone|taper|compromised"

    /// Whether a line of coach text is about the HYROX races; `extra` are more words to look for, such as the race's city.
    static func matters(_ text: String, extra: [String] = []) -> Bool {
        if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let lower = text.lowercased()
        return extra.contains { !$0.isEmpty && lower.contains($0.lowercased()) }
    }

    /// The coach's open proposals that are about the races (title and one-line description).
    static func proposals(_ all: [PFPendingProposal], extra: [String] = []) -> [PFPendingProposal] {
        all.filter { matters($0.title + " " + $0.description, extra: extra) }
    }

    /// The lines of today's briefing that are about the races.
    static func briefLines(_ brief: PFDailyBrief?, extra: [String] = []) -> [String] {
        guard let brief else { return [] }
        return ([brief.headline] + brief.outlook).filter { !$0.isEmpty && matters($0, extra: extra) }
    }

    /// Race-week notes, only while the race of race week is a HYROX race that is still to come.
    static func raceWeek(_ week: PFRaceWeek?, extra: [String] = []) -> PFRaceWeek? {
        guard let week, (week.daysTo ?? -1) >= 0, matters(week.event.name, extra: extra), !week.notes.isEmpty else { return nil }
        return week
    }
}

// MARK: - Season

struct PFHyroxSeasonRow: Equatable, Identifiable {
    let name: String
    let date: String
    let priority: String?
    let assumed: Bool
    let daysAway: Int
    let taperText: String
    let blocks: [PFSeasonBlock]

    var id: String { date + "|" + name }

    /// "priority A", "priority ?" when the server sent none.
    var priorityText: String { "priority " + (priority ?? "?") }

    var awayText: String {
        daysAway > 0 ? "\(daysAway) day\(daysAway == 1 ? "" : "s") away" : (daysAway == 0 ? "Today" : "Done")
    }
}

enum PFHyroxSeason {
    /// The HYROX races of the season with the taper window each has (or the block it falls inside), soonest first.
    static func rows(_ plan: PFSeasonPlan?, today: String) -> [PFHyroxSeasonRow] {
        guard let plan else { return [] }
        return plan.races
            .filter { $0.name.range(of: "hyrox", options: .caseInsensitive) != nil }
            .sorted { $0.date < $1.date }
            .map { race -> PFHyroxSeasonRow in
                let day = String(race.date.prefix(10))
                let mine = plan.blocks.filter { $0.race == race.name }
                let taper = mine.first(where: { $0.kind.lowercased() == "taper" })
                var inside: PFSeasonBlock?
                if taper == nil {
                    inside = plan.blocks.first(where: { block in
                        block.race != race.name && String(block.start.prefix(10)) <= day && day <= String(block.end.prefix(10))
                    })
                }
                return PFHyroxSeasonRow(name: race.name, date: race.date, priority: race.priority, assumed: race.assumed,
                                        daysAway: PFFormat.daysBetween(today, day), taperText: taperText(taper, inside),
                                        blocks: mine)
            }
    }

    private static func taperText(_ taper: PFSeasonBlock?, _ inside: PFSeasonBlock?) -> String {
        if let taper { return "Taper \(span(taper))." }
        if let inside {
            let owner = inside.race.map { " of " + $0 } ?? ""
            return "No taper of its own: it falls in the " + inside.kind.lowercased() + owner + " (" + span(inside) + ")."
        }
        return "No taper window planned."
    }

    private static func span(_ block: PFSeasonBlock) -> String {
        PFFormat.shortDate(block.start) + " to " + PFFormat.shortDate(block.end)
    }
}
