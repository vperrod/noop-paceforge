import Foundation

// Training analytics from PaceForge, read-only except two writes through doors the app already has: heart-rate zone sets per sport and
// effective date (`hr-zones-add`), and a race's course and pacing notes (`event-update`, op `set`). Foundation only, so it is compiled into the
// macOS unit-test bundle. Contract: "Training analytics" in docs/app-job-contract.md.
//
// Reads: `GET api/hr-zones`, `GET api/comparable-sessions?activity_id=`, `GET api/session-reps?session_id=`, and a race's `course_context` in
// `data/events.json`. Nothing here is guessed: a property the server does not know reads as "not known", never as a match.

// MARK: Heart-rate zones per sport

/// One stored set: the zones of a sport from an effective date. Sets are never edited; a correction is a new set.
struct PFHRZoneSet: Equatable, Identifiable {
    let id: String
    let sport: String
    let effectiveFrom: String
    let source: String
    /// The lowest bpm of zones 1 to 5.
    let floors: [Int]
    let maxHr: Int?
    let note: String?
}

struct PFZoneBand: Equatable, Identifiable {
    let zone: Int
    let low: Int
    let high: Int
    var id: Int { zone }
}

/// The definition in force for a sport on a day: a stored set (`per_sport`), Garmin's profile zones (`global`) or none.
struct PFResolvedZones: Equatable, Identifiable {
    let sport: String
    let date: String
    let resolved: String
    let definitionID: String?
    let effectiveFrom: String?
    let source: String?
    let maxHr: Int?
    let zones: [PFZoneBand]

    var id: String { sport }

    /// Which definition this is, in words.
    var line: String {
        PFHRZones.describe(resolved: resolved, sport: sport, effectiveFrom: effectiveFrom, source: source, id: definitionID)
    }
}

struct PFHRZonesDoc: Equatable {
    var sets: [PFHRZoneSet] = []
    var resolved: [PFResolvedZones] = []
    var date: String?
}

/// The definition an analysis recorded next to its zone table (`hr_zone_def` on a ride's metrics).
struct PFZoneDefinition: Equatable {
    let id: String?
    let sport: String?
    let resolved: String?
    let effectiveFrom: String?
    let source: String?

    var line: String {
        PFHRZones.describe(resolved: resolved ?? "none", sport: sport ?? "", effectiveFrom: effectiveFrom, source: source, id: id)
    }

    static func parse(_ j: PFJ) -> PFZoneDefinition? {
        guard j.exists, j["resolved"].text != nil else { return nil }
        return PFZoneDefinition(id: j["id"].text, sport: j["sport"].text, resolved: j["resolved"].text, effectiveFrom: j["effective_from"].text,
                                source: j["source"].text)
    }
}

enum PFHRZones {
    /// The sources a set can come from: the server's closed list, with the words the app shows.
    static let sources: [PFChoice] = PFChoice.list([
        ("manual", "Entered by hand"), ("garmin", "Garmin"), ("lab_test", "Lab test"), ("field_test", "Field test"), ("formula", "Formula"),
    ])

    /// The sports offered as one tap; any other short lower-case name works too.
    static let sports = ["running", "cycling", "swimming", "strength"]

    static func sourceLabel(_ key: String?) -> String {
        guard let key else { return "Unknown source" }
        if key == "garmin_profile" { return "Garmin profile" }
        return sources.first { $0.key == key }?.label ?? PFFormat.capitalized(PFFormat.words(key))
    }

    /// "Zones used: your cycling set from 1 Oct, entered by hand". For Garmin's profile zones the id is a hash of the zones, so a change in
    /// Garmin shows as a different id.
    static func describe(resolved: String, sport: String, effectiveFrom: String?, source: String?, id: String?) -> String {
        let sportName = sport.isEmpty ? "" : sport.replacingOccurrences(of: "_", with: " ") + " "
        switch resolved {
        case "per_sport":
            var text = "Your \(sportName)zone set"
            if let effectiveFrom { text += " from " + PFFormat.shortDate(effectiveFrom) }
            if let source { text += ", " + sourceLabel(source).lowercased() }
            return text
        case "global":
            let idText = id.map { " (\($0))" } ?? ""
            let forSport = sportName.isEmpty ? "this sport" : sportName.trimmingCharacters(in: .whitespaces)
            return "Garmin's profile zones" + idText + ", no set of your own for " + forSport
        default:
            return "No zone definition was recorded"
        }
    }

    static func parse(_ data: Data?) -> PFHRZonesDoc {
        let root = PFJ(data: data)
        var doc = PFHRZonesDoc()
        doc.date = root["date"].text
        doc.sets = root["sets"].array.compactMap { row in
            guard let id = row["id"].text, let sport = row["sport"].text, let from = row["effective_from"].text else { return nil }
            let floors = row["floors"].array.compactMap { $0.int }
            return PFHRZoneSet(id: id, sport: sport, effectiveFrom: from, source: row["source"].text ?? "manual",
                               floors: floors.count == 5 ? floors : [], maxHr: row["max_hr"].int, note: row["note"].text)
        }
        doc.resolved = root["resolved"].array.compactMap { row in
            guard let sport = row["sport"].text, let resolved = row["resolved"].text else { return nil }
            let zones: [PFZoneBand] = row["zones"].array.compactMap { zone in
                guard let number = zone["zone"].int, let low = zone["low_bpm"].int, let high = zone["high_bpm"].int else { return nil }
                return PFZoneBand(zone: number, low: low, high: high)
            }
            return PFResolvedZones(sport: sport, date: row["date"].text ?? "", resolved: resolved, definitionID: row["id"].text,
                                   effectiveFrom: row["effective_from"].text, source: row["source"].text, maxHr: row["max_hr"].int, zones: zones)
        }
        return doc
    }

    /// The sets of one sport, newest effective date first.
    static func sets(of sport: String, in doc: PFHRZonesDoc) -> [PFHRZoneSet] {
        doc.sets.filter { $0.sport == sport }.sorted { ($0.effectiveFrom, $0.id) > ($1.effectiveFrom, $1.id) }
    }
}

extension PFJobInputs {
    /// `hr-zones-add`: exactly `sport, effective_from, source, floors, max_hr` and `note` when given. nil when a value could not pass the
    /// server's validator.
    static func hrZonesAdd(sport: String, effectiveFrom: String, source: String, floors: [Int], maxHr: Int, note: String = "") -> [String: Any]? {
        guard PFZoneSetDraft.isSportKey(sport), isDay(effectiveFrom), PFHRZones.sources.contains(where: { $0.key == source }),
              floors.count == 5, floors.allSatisfy({ (30...230).contains($0) }), (30...230).contains(maxHr),
              zip(floors, floors.dropFirst()).allSatisfy({ $0 < $1 }), let last = floors.last, last < maxHr else { return nil }
        var inputs: [String: Any] = ["sport": sport, "effective_from": effectiveFrom, "source": source, "floors": floors, "max_hr": maxHr]
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            guard text.count <= PFZoneSetDraft.maxNoteLength else { return nil }
            inputs["note"] = text
        }
        return inputs
    }
}

/// The form for a new zone set, as typed. A failed send leaves it whole.
struct PFZoneSetDraft: Equatable {
    var sport = "running"
    var effectiveFrom: String
    var source = "manual"
    var floorTexts = ["", "", "", "", ""]
    var maxHrText = ""
    var note = ""

    static let maxNoteLength = 300
    /// The server accepts dates from here to a year ahead.
    static let earliestDay = "2000-01-01"
    static let maxDaysAhead = 366

    init(effectiveFrom: String) { self.effectiveFrom = effectiveFrom }

    /// A short lower-case name: a letter, then letters or underscores, 2 to 25 characters.
    static func isSportKey(_ text: String) -> Bool {
        guard (2...25).contains(text.count), let first = text.first, first.isASCII, first.isLowercase, first.isLetter else { return false }
        return text.allSatisfy { $0.isASCII && (($0.isLetter && $0.isLowercase) || $0 == "_") }
    }

    /// What the athlete typed for the sport, as the server's key.
    var sportKey: String { sport.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_") }

    private func bpm(_ text: String) -> Int? {
        guard let value = PFManualPlan.whole(text), (30...230).contains(value) else { return nil }
        return value
    }

    private var floors: [Int]? {
        let values = floorTexts.map { bpm($0) }
        return values.contains(where: { $0 == nil }) ? nil : values.compactMap { $0 }
    }

    func problem(today: String) -> String? {
        if !Self.isSportKey(sportKey) { return "Name the sport in one or two words, like running or cycling." }
        if !PFJobInputs.isDay(effectiveFrom) { return "Pick the day the zones start." }
        if effectiveFrom < Self.earliestDay || PFManualPlan.daysBetween(today, effectiveFrom) > Self.maxDaysAhead { return "That start day is out of range." }
        guard let floors else { return "Each zone's lowest heart rate is a whole number from 30 to 230." }
        guard let ceiling = bpm(maxHrText) else { return "The maximum heart rate is a whole number from 30 to 230." }
        if zip(floors, floors.dropFirst()).contains(where: { $0 >= $1 }) { return "The zones have to rise from zone 1 to zone 5." }
        if let last = floors.last, last >= ceiling { return "Zone 5 has to start below the maximum." }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxNoteLength { return "The note is too long (300 characters at most)." }
        return nil
    }

    /// The `hr-zones-add` inputs; nil when the form has a problem.
    func inputs(today: String) -> [String: Any]? {
        guard problem(today: today) == nil, let floors, let ceiling = bpm(maxHrText) else { return nil }
        return PFJobInputs.hrZonesAdd(sport: sportKey, effectiveFrom: effectiveFrom, source: source, floors: floors, maxHr: ceiling, note: note)
    }
}

// MARK: Comparable earlier runs

struct PFComparableRun: Equatable, Identifiable {
    let id: String
    let date: String
    let name: String
    let distanceM: Double?
    let durationS: Double?
    let paceSPerKm: Double?
    let avgHr: Int?
    let plannedClass: String?
    /// What was verified about the match, one phrase each; a property the server could not check reads as not known.
    let matchLines: [String]

    /// "10.0 km in 50:00, 5:00 /km, avg 150 bpm".
    var summary: String {
        var parts: [String] = []
        if let distanceM, distanceM > 0 { parts.append(PFFormat.oneDecimal(distanceM / 1000) + " km") }
        if let durationS { parts.append(PFFormat.clock(durationS)) }
        if let paceSPerKm { parts.append(PFFormat.pace(paceSPerKm) + " /km") } else { parts.append("pace not confirmed") }
        if let avgHr { parts.append("avg \(avgHr) bpm") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

struct PFExcludedRun: Equatable, Identifiable {
    let id: String
    let date: String
    let name: String
    /// The server's code, for example `size_differs`.
    let reason: String
    let detail: String?

    var reasonText: String { PFComparable.reasonText(reason) }
}

struct PFComparableDoc: Equatable {
    var isAvailable = false
    var reason: String?
    var windowDays = 120
    var limit = 5
    var plannedClass: String?
    var olderThanWindow = 0
    var comparable: [PFComparableRun] = []
    var excluded: [PFExcludedRun] = []
}

enum PFComparable {
    /// Why a run was left out, in words.
    static func reasonText(_ code: String) -> String {
        switch code {
        case "condition_differs": return "Treadmill against outdoor"
        case "size_differs": return "A different length"
        case "size_unknown": return "Its length is not known"
        case "no_size": return "No distance or time to compare"
        case "pace_pending": return "A belt run whose pace is not confirmed yet"
        case "route_differs": return "A different start place"
        case "terrain_differs": return "A different amount of climbing"
        case "planned_type_differs": return "A different kind of planned session"
        case "beyond_limit": return "Comparable, but not one of the newest"
        default: return PFFormat.capitalized(PFFormat.words(code))
        }
    }

    /// One phrase per property the server reports in `match`. `unknown` is "not known", never a match and never a mismatch.
    static func matchLines(_ match: PFJ) -> [String] {
        var lines: [String] = []
        if let condition = match["condition"].text { lines.append("Same conditions: " + condition) }
        if let ratio = match["size_ratio"].double {
            let basis = match["size_basis"].text ?? "size"
            lines.append("Size: \(PFFormat.oneDecimal(ratio)) times this run's \(basis)")
        }
        if let route = match["route"].text {
            if route == "same place" { lines.append("Same start place") }
            else if route == "unknown" { lines.append("Start place not known") }
            else { lines.append("Route: " + route) }
        }
        if let terrain = match["terrain"].text {
            if terrain == "similar climb" { lines.append("Similar climbing") }
            else if terrain == "unknown" { lines.append("Climbing not known") }
            else { lines.append("Terrain: " + terrain) }
        }
        if let planned = match["planned"].text {
            lines.append(planned == "unknown" ? "Planned type not known" : "Planned: " + planned)
        }
        return lines
    }

    static func parse(_ data: Data?) -> PFComparableDoc {
        let root = PFJ(data: data)
        var doc = PFComparableDoc()
        doc.isAvailable = root["available"].bool == true
        doc.reason = root["reason"].text
        doc.windowDays = root["window_days"].int ?? 120
        doc.limit = root["limit"].int ?? 5
        doc.plannedClass = root["planned_class"].text
        doc.olderThanWindow = root["older_than_window"].int ?? 0
        doc.comparable = root["comparable"].array.compactMap { row in
            guard let id = row["activity_id"].idString else { return nil }
            return PFComparableRun(id: id, date: row["date"].text ?? "", name: row["name"].text ?? "Run", distanceM: row["distance_m"].double,
                                   durationS: row["duration_s"].double, paceSPerKm: row["pace_s_per_km"].double, avgHr: row["avg_hr"].int,
                                   plannedClass: row["planned_class"].text, matchLines: matchLines(row["match"]))
        }
        doc.excluded = root["excluded"].array.compactMap { row in
            guard let id = row["activity_id"].idString, let reason = row["reason"].text else { return nil }
            return PFExcludedRun(id: id, date: row["date"].text ?? "", name: row["name"].text ?? "Run", reason: reason, detail: row["detail"].text)
        }
        return doc
    }
}

// MARK: Repetitions against the plan

struct PFRepRow: Equatable, Identifiable {
    let n: Int
    /// exact, size_mismatch, merged, combined, absorbed or unmatched.
    let alignment: String
    let lapIndexes: [Int]
    let stepType: String?
    let plannedDistanceM: Double?
    let plannedDurationS: Double?
    let targetType: String?
    let targetLow: Double?
    let targetHigh: Double?
    let actualDistanceM: Double?
    let actualDurationS: Double?
    let actualPaceSPerKm: Double?
    let actualAvgHr: Int?
    let paceOutsideBandS: Double?
    let paceInBand: Bool?
    let hrOutsideBandBpm: Double?
    let hrInBand: Bool?
    let hasActual: Bool

    var id: Int { n }

    /// "1 km, pace 3:55 to 4:05 /km".
    var plannedLine: String {
        var parts: [String] = []
        if let plannedDistanceM {
            parts.append(plannedDistanceM >= 1000 ? PFFormat.trimmed(plannedDistanceM / 1000) + " km" : PFFormat.trimmed(plannedDistanceM) + " m")
        } else if let plannedDurationS {
            parts.append(PFFormat.clock(plannedDurationS))
        }
        if let low = targetLow, let high = targetHigh {
            switch (targetType ?? "").lowercased() {
            case "pace": parts.append("pace \(PFFormat.pace(low)) to \(PFFormat.pace(high)) /km")
            case "heart_rate", "hr", "heart rate": parts.append("heart rate \(PFFormat.trimmed(low)) to \(PFFormat.trimmed(high)) bpm")
            default: parts.append((targetType.map { PFFormat.words($0) + " " } ?? "target ") + "\(PFFormat.trimmed(low)) to \(PFFormat.trimmed(high))")
            }
        }
        return parts.isEmpty ? "Planned step" : parts.joined(separator: ", ")
    }

    /// "1.00 km in 4:00 (4:00 /km), avg 168 bpm"; "No lap found" when nothing was matched.
    var actualLine: String {
        guard hasActual else { return "No lap found for this repetition" }
        var parts: [String] = []
        if let actualDistanceM, actualDistanceM > 0 { parts.append(String(format: "%.2f km", actualDistanceM / 1000)) }
        if let actualDurationS { parts.append((parts.isEmpty ? "" : "in ") + PFFormat.clock(actualDurationS)) }
        var text = parts.joined(separator: " ")
        if let actualPaceSPerKm { text += (text.isEmpty ? "" : " ") + "(\(PFFormat.pace(actualPaceSPerKm)) /km)" }
        if let actualAvgHr { text += (text.isEmpty ? "" : ", ") + "avg \(actualAvgHr) bpm" }
        return text.isEmpty ? "Lap found, no figures" : text
    }

    /// Where the pace sits against the plan's band; nil when there is no pace check.
    var paceVerdict: String? {
        guard let paceInBand else { return nil }
        if paceInBand { return "Pace inside the band" }
        guard let outside = paceOutsideBandS else { return "Pace outside the band" }
        let seconds = Int(abs(outside).rounded())
        return outside > 0 ? "Pace \(seconds) s/km slower than the band" : "Pace \(seconds) s/km faster than the band"
    }

    var heartRateVerdict: String? {
        guard let hrInBand else { return nil }
        if hrInBand { return "Heart rate inside the band" }
        guard let outside = hrOutsideBandBpm else { return "Heart rate outside the band" }
        let beats = Int(abs(outside).rounded())
        return outside > 0 ? "Heart rate \(beats) bpm above the band" : "Heart rate \(beats) bpm below the band"
    }

    /// How the lap was matched, when it is anything but one lap for one repetition.
    var alignmentNote: String? {
        switch alignment {
        case "exact": return nil
        case "size_mismatch": return "Taken by position; the lap's size differs from the plan"
        case "merged": return "Several laps add up to this repetition"
        case "combined": return "One lap holds this repetition and the next one (a missed lap press), so no pace for either"
        case "absorbed": return "Counted inside the neighbouring lap, so no pace"
        case "unmatched": return nil
        default: return PFFormat.capitalized(PFFormat.words(alignment))
        }
    }
}

struct PFRepsDoc: Equatable {
    var isAvailable = false
    var reason: String?
    var method: String?
    var plannedReps = 0
    /// False on a treadmill whose pace the athlete has not confirmed.
    var trustedPace: Bool?
    var reps: [PFRepRow] = []
    var unmatchedLaps: [Int] = []
    var note: String?
}

enum PFReps {
    static func parse(_ data: Data?) -> PFRepsDoc {
        let root = PFJ(data: data)
        var doc = PFRepsDoc()
        doc.isAvailable = root["available"].bool == true
        doc.reason = root["reason"].text
        doc.method = root["method"].text
        doc.plannedReps = root["planned_reps"].int ?? 0
        doc.trustedPace = root["trusted_pace"].bool
        doc.unmatchedLaps = root["unmatched_laps"].array.compactMap { $0.int }
        doc.note = root["note"].text
        doc.reps = root["reps"].array.compactMap { row in
            guard let n = row["n"].int else { return nil }
            let planned = row["planned"], actual = row["actual"], delta = row["delta"]
            return PFRepRow(n: n, alignment: row["alignment"].text ?? "exact", lapIndexes: row["lap_indexes"].array.compactMap { $0.int },
                            stepType: planned["step_type"].text, plannedDistanceM: planned["distance_m"].double,
                            plannedDurationS: planned["duration_s"].double, targetType: planned["target_type"].text,
                            targetLow: planned["target_low"].double, targetHigh: planned["target_high"].double,
                            actualDistanceM: actual["distance_m"].double, actualDurationS: actual["duration_s"].double,
                            actualPaceSPerKm: actual["pace_s_per_km"].double, actualAvgHr: actual["avg_hr"].int,
                            paceOutsideBandS: delta["pace_outside_band_s"].double, paceInBand: delta["pace_in_band"].bool,
                            hrOutsideBandBpm: delta["hr_outside_band_bpm"].double, hrInBand: delta["hr_in_band"].bool, hasActual: actual.exists)
        }
        return doc
    }
}

// MARK: Race course and pacing context

/// The notes an athlete wrote for a race: entered by hand, never scraped or inferred.
struct PFCourseContext: Equatable {
    var courseNote: String?
    var pacingNote: String?
    var elevationGainM: Int?
    var url: String?
    var updatedAt: String?
}

enum PFCourse {
    static let maxTextLength = 500
    static let maxElevation = 10_000

    /// The `course_context` of the race on that date (and name) in `data/events.json`, a list or an object holding it under `events`.
    static func context(in data: Data?, date: String, name: String?) -> PFCourseContext? {
        let root = PFJ(data: data)
        let rows = root.array.isEmpty ? root["events"].array : root.array
        let event = rows.first { $0["date"].text == date && (name == nil || $0["name"].text == name) }
            ?? rows.first { $0["date"].text == date }
        guard let context = event?["course_context"], context.exists else { return nil }
        return PFCourseContext(courseNote: context["course_note"].text, pacingNote: context["pacing_note"].text,
                               elevationGainM: context["elevation_gain_m"].int, url: context["url"].text, updatedAt: context["updated_at"].text)
    }

    /// A web address the server takes: http or https, one word, at most 500 characters.
    static func isURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return (lower.hasPrefix("http://") || lower.hasPrefix("https://")) && !text.contains(where: { $0.isWhitespace }) && text.count <= maxTextLength
    }
}

/// The course and pacing form of one race, as typed. Blank clears that part.
struct PFCourseDraft: Equatable {
    var courseNote = ""
    var pacingNote = ""
    var elevationText = ""
    var url = ""

    init() {}

    init(_ context: PFCourseContext?) {
        courseNote = context?.courseNote ?? ""
        pacingNote = context?.pacingNote ?? ""
        elevationText = context?.elevationGainM.map(String.init) ?? ""
        url = context?.url ?? ""
    }

    private func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var problem: String? {
        if clean(courseNote).count > PFCourse.maxTextLength { return "The course note is too long (500 characters at most)." }
        if clean(pacingNote).count > PFCourse.maxTextLength { return "The pacing note is too long (500 characters at most)." }
        if !clean(elevationText).isEmpty, !(PFManualPlan.whole(elevationText).map { (0...PFCourse.maxElevation).contains($0) } ?? false) {
            return "Climbing is a whole number of metres, 0 to 10000."
        }
        if !clean(url).isEmpty, !PFCourse.isURL(clean(url)) { return "The link has to start with http:// or https://." }
        return nil
    }

    /// The `event-update` fields that differ from `original`; a part cleared in the form goes as an empty string, which clears it on the server.
    func changes(from original: PFCourseDraft) -> [String: String] {
        var fields: [String: String] = [:]
        if clean(courseNote) != clean(original.courseNote) { fields["course_note"] = clean(courseNote) }
        if clean(pacingNote) != clean(original.pacingNote) { fields["pacing_note"] = clean(pacingNote) }
        if clean(elevationText) != clean(original.elevationText) { fields["course_elevation_gain_m"] = clean(elevationText) }
        if clean(url) != clean(original.url) { fields["course_url"] = clean(url) }
        return fields
    }
}

extension PFJobInputs {
    /// `event-update`, `op: "set"` with the course and pacing fields: the race matched by its date (and name). nil when nothing changed or
    /// the date is not a day.
    static func raceCourseSet(date: String, name: String?, fields: [String: String]) -> [String: Any]? {
        guard isDay(date), !fields.isEmpty else { return nil }
        var match: [String: Any] = ["date": date]
        if let name, !name.isEmpty { match["name"] = name }
        return ["op": "set", "match": match, "fields": fields]
    }
}
