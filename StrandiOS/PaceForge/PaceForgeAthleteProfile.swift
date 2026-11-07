import Foundation

// The Athlete tab's second layer: what Garmin's profile holds (profile.json), what PaceForge's engine works out from it
// (analytics.json) and the benchmarks the athlete has filed (benchmarks.json). Foundation only, like PaceForgeAthlete.swift.
//
// Three documents the server already serves to the app's bearer and the app did not read until build 501. Each one is optional: a
// document the server does not have, or a field it does not hold, reads as missing and the tab shows a dash for it.
//
// profile.json keeps its old values across a failed Garmin sync (the server merges), so every figure from it carries its own date and
// the profile's `profile_date` is kept too; the tab never presents an old value as today's.

// MARK: - Model

/// One heart-rate zone: Garmin's floor and ceiling in beats per minute.
struct PFAthleteZone: Identifiable, Equatable {
    var zone: Int
    var low: Int
    var high: Int
    var id: Int { zone }
}

/// A forecast race time. `confidence` is the engine's own word ("High", "Moderate") and exists only for PaceForge's model.
struct PFAthletePrediction: Identifiable, Equatable {
    let id: String
    let label: String
    var seconds: Double
    var paceSecPerKm: Double?
    var confidence: String?

    var text: String { PFFormat.clock(seconds) }
}

/// A personal record or a filed benchmark, with where it came from.
struct PFAthleteRecord: Identifiable, Equatable {
    let id: String
    let label: String
    var text: String
    var date: String?
    var source: String
}

/// A labelled figure on a metric's detail page.
struct PFAthleteDetailRow: Identifiable, Equatable {
    let label: String
    var text: String
    var note: String?
    var id: String { label }
}

/// `profile.json`: the Garmin profile as the server last stored it.
struct PFAthleteProfile: Equatable {
    var date: String?
    var vo2Max: Double?
    var restingHr: Double?
    /// `max_hr`: the highest peak Garmin saw in recent activities. The server says it is not a setting.
    var maxHrSeen: Double?
    /// The maximum in the running zone set (else the default one): the maximum the watch is configured with.
    var zoneMaxHr: Double?
    var zoneSport: String?
    /// Every sport's zone set in `hr_zone_sets`, with the floors of zones 1 to 5 where the document has them.
    var zoneSets: [PFZoneSet] = []
    var ltHr: Double?
    var ltPaceSecPerKm: Double?
    var ltDate: String?
    var zones: [PFAthleteZone] = []
    var racePredictions: [PFAthletePrediction] = []
    var racePredictionsDate: String?
    var enduranceScore: Double?
    var enduranceDate: String?
    var trainingStatus: String?
    var trainingStatusDate: String?
    var personalRecords: [PFAthleteRecord] = []
}

/// `analytics.json`: PaceForge's own race forecast (VDOT) with the confidence of each distance.
struct PFAthleteAnalytics: Equatable {
    var vdot: Double?
    var predictions: [PFAthletePrediction] = []
}

/// The three documents together; nil from the parser when none of them exists.
struct PFAthleteDocs: Equatable {
    var profile: PFAthleteProfile?
    var analytics: PFAthleteAnalytics?
    var benchmarks: [PFAthleteRecord] = []
}

/// What the race-predictions card and its page show.
struct PFAthletePredictions: Equatable {
    var garmin: [PFAthletePrediction] = []
    var garminDate: String?
    var model: [PFAthletePrediction] = []
    var vdot: Double?
}

/// What the heart-rate-zones card and its page show.
struct PFAthleteZones: Equatable {
    var zones: [PFAthleteZone] = []
    var sport: String?
    var maxHr: Double?
    var maxHrSeen: Double?
    var ltHr: Double?
    var restingHr: Double?
    var date: String?
    var sets: [PFZoneSet] = []
}

// MARK: - Parsing

extension PFAthleteParse {
    /// The profile, analytics and benchmarks documents as one value; nil when none of the three exists.
    static func documents(profile: PFJ, analytics: PFJ, benchmarks: PFJ) -> PFAthleteDocs? {
        guard profile.exists || analytics.exists || benchmarks.exists else { return nil }
        return PFAthleteDocs(profile: profile.exists ? self.profile(profile) : nil,
                             analytics: analytics.exists ? self.analytics(analytics) : nil,
                             benchmarks: self.benchmarks(benchmarks))
    }

    static func profile(_ p: PFJ) -> PFAthleteProfile {
        var out = PFAthleteProfile()
        out.date = day(p["profile_date"])
        out.vo2Max = positive(p["vo2_max"])
        out.restingHr = positive(p["resting_hr"])
        out.maxHrSeen = positive(p["max_hr"])
        out.ltHr = positive(p["lactate_threshold_hr"])
        out.ltPaceSecPerKm = thresholdPace(rawSpeed: p["lactate_threshold_speed"].double)
        out.ltDate = day(p["lactate_threshold_date"])
        out.enduranceScore = positive(p["endurance_score"])
        out.enduranceDate = day(p["endurance_date"])
        out.trainingStatus = trainingStatus(p["training_status"].text)
        out.trainingStatusDate = day(p["training_status_date"])
        out.racePredictions = p["race_predictions"].array.compactMap { row in
            prediction(distance: row["distance"].text, seconds: row["predicted_seconds"].double, pace: nil, confidence: nil)
        }
        out.racePredictionsDate = day(p["race_predictions_date"])

        // A zone number appears once (the zone is the row's id); a later duplicate is dropped.
        var seenZones = Set<Int>()
        out.zones = p["hr_zones"].array.compactMap { row in
            guard let zone = row["zone"].int, (1...5).contains(zone),
                  let low = row["low_bpm"].int, let high = row["high_bpm"].int, low > 0, high >= low,
                  seenZones.insert(zone).inserted else { return nil }
            return PFAthleteZone(zone: zone, low: low, high: high)
        }.sorted { $0.zone < $1.zone }

        // The configured maximum lives in the sport's zone set; the running set first, then the default one.
        out.zoneSets = PFZoneSet.parseAll(p["hr_zone_sets"])
        let sets = p["hr_zone_sets"].array
        let chosen = ["RUNNING", "DEFAULT"].compactMap { sport in sets.first { $0["sport"].text?.uppercased() == sport } }.first
            ?? sets.first { positive($0["max"]) != nil }
        if let chosen, let max = positive(chosen["max"]) {
            out.zoneMaxHr = max
            out.zoneSport = chosen["sport"].text.map { PFFormat.capitalized($0.lowercased()) }
        }

        out.personalRecords = p["personal_records"].array.compactMap { row in
            guard let seconds = row["time_seconds"].double, seconds > 0, seconds.isFinite, let distance = row["distance"].text else { return nil }
            let key = predictionKey(distance)
            let label = key?.label ?? PFFormat.capitalized(PFFormat.words(distance.lowercased()))
            return PFAthleteRecord(id: "pr-\(key?.id ?? distance)", label: label, text: PFFormat.clock(seconds),
                                   date: day(row["record_date"]), source: "Garmin personal record")
        }
        return out
    }

    static func analytics(_ a: PFJ) -> PFAthleteAnalytics {
        var out = PFAthleteAnalytics()
        let race = a["race_predictions"]
        out.vdot = positive(race["vdot"]) ?? positive(a["snapshot"]["vdot"])
        out.predictions = race["predictions"].array.compactMap { row in
            prediction(distance: row["distance"].text, seconds: row["predicted_seconds"].double,
                       pace: row["pace_sec_per_km"].double, confidence: row["confidence"].text)
        }
        return out
    }

    /// The benchmarks the athlete filed (a wall-ball maximum, a 500 m row), each with the date of its latest reading. Body weight and FTP
    /// have tiles of their own; a key whose unit is not known is left out rather than shown bare.
    static func benchmarks(_ b: PFJ) -> [PFAthleteRecord] {
        let history = b["history"]
        return b.dict.keys.sorted().compactMap { key -> PFAthleteRecord? in
            guard key != "history", key != "bodyweight_kg", key != "ftp_watts",
                  let value = positive(b[key]), let shown = benchmarkText(key: key, value: value) else { return nil }
            let latest = history[key].array.last
            let source: String
            switch latest?["source"].text {
            case "manual": source = "entered by you"
            case .some: source = "from a benchmark test"
            case nil: source = "benchmark"
            }
            return PFAthleteRecord(id: "bench-\(key)", label: benchmarkLabel(key), text: shown, date: latest.flatMap { day($0["date"]) },
                                   source: source)
        }
    }

    // MARK: Helpers

    /// Garmin's lactate-threshold speed as a pace. The server cleans the unit before it uses the value (m/s, cm/s, mm/s or a tenths slip),
    /// so the same rule reads it here; a value that fits none of them is not shown.
    static func thresholdPace(rawSpeed: Double?) -> Double? {
        guard let raw = rawSpeed, raw.isFinite, raw > 0 else { return nil }
        let metresPerSecond: Double
        if raw >= 2, raw <= 7 { metresPerSecond = raw }
        else if raw >= 200, raw <= 700 { metresPerSecond = raw / 100 }
        else if raw >= 2000 { metresPerSecond = raw / 1000 }
        else if raw < 2, raw * 10 >= 2, raw * 10 <= 7 { metresPerSecond = raw * 10 }
        else { return nil }
        return 1000 / metresPerSecond
    }

    /// "Productive" from "Productive", "PRODUCTIVE" or "PRODUCTIVE_2".
    static func trainingStatus(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.lowercased().split(whereSeparator: { $0 == "_" || $0 == " " }).filter { Int($0) == nil }
        guard !words.isEmpty else { return nil }
        return PFFormat.capitalized(words.joined(separator: " "))
    }

    private static func positive(_ node: PFJ) -> Double? {
        guard let value = node.double, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func day(_ node: PFJ) -> String? {
        guard let text = node.text, text.count >= 10 else { return nil }
        return String(text.prefix(10))
    }

    private static let distancesMetres: [String: Double] = ["5k": 5000, "10k": 10000, "half": 21097.5, "marathon": 42195]

    /// The id and the short label of the four race distances; nil for anything else (the engine also lists a 1 km time).
    static func predictionKey(_ distance: String) -> (id: String, label: String)? {
        let key = distance.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        switch key {
        case "5k": return ("5k", "5K")
        case "10k": return ("10k", "10K")
        case "half marathon", "half", "hm": return ("half", "Half")
        case "marathon": return ("marathon", "Marathon")
        default: return nil
        }
    }

    private static func prediction(distance: String?, seconds: Double?, pace: Double?, confidence: String?) -> PFAthletePrediction? {
        guard let distance, let key = predictionKey(distance), let seconds, seconds.isFinite, seconds > 0 else { return nil }
        let derived = distancesMetres[key.id].map { seconds / ($0 / 1000) }
        return PFAthletePrediction(id: key.id, label: key.label, seconds: seconds, paceSecPerKm: pace ?? derived, confidence: confidence)
    }

    private static let benchmarkLabels: [String: String] = [
        "wall_balls_max": "Wall balls, most in a row", "row_500m_sec": "Row 500 m", "ski_500m_sec": "Ski 500 m",
        "run_5k_sec": "5K time trial", "cooper_12_m": "Cooper 12 minutes",
    ]

    private static func benchmarkLabel(_ key: String) -> String {
        if let known = benchmarkLabels[key] { return known }
        var base = key
        for suffix in ["_sec", "_max", "_m"] where base.hasSuffix(suffix) { base = String(base.dropLast(suffix.count)) }
        return PFFormat.capitalized(PFFormat.words(base))
    }

    private static func benchmarkText(key: String, value: Double) -> String? {
        if key.hasSuffix("_sec") { return PFFormat.clock(value) }
        if key.hasSuffix("_max") { return PFFormat.trimmed(value) + " reps" }
        if key.hasSuffix("_m") { return PFFormat.trimmed(value) + " m" }
        return nil
    }
}
