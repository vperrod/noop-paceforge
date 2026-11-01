import Foundation

// The band-report numbers PaceForge serves since its band-parity build: Recovery read two ways (body signals and sleep) with a plain
// verdict line per score, Garmin's Load Focus, the weekly target-load range, muscular load, the WHOOP strap's overnight HRV status
// (via NOOP), the Healthspan input panel and the graded health watch. Foundation only, so the parsing and every small rule the cards
// draw from are compiled into the macOS unit-test bundle and the Linux logic tests.
//
// Every one of these is the server's own wording and numbers, shown as served. Nothing here works out a score on the phone, merges two
// sources or changes a number; a key the server does not send reads as absent and the card leaves out. Each block says whose it is
// (`source`): the strap's numbers are NOOP's, the rest PaceForge's or Garmin's, and they are never averaged.

// MARK: - Recovery two ways, and the verdict lines (fitness.json: daily)

/// One of the two readings of Recovery on a signed -10 to +10 line, where 0 is the athlete's usual.
struct PFSignalReading: Equatable {
    var value: Double
    /// settled, behind or well_behind.
    var state: String
    var line: String
    var gloss: String?
}

/// One plain line about a score, the biggest driver in a sentence, and a counter while it is still calibrating.
struct PFVerdictLine: Equatable {
    var verdict: String?
    var driver: String?
    var calibrating: String?

    var hasContent: Bool { verdict != nil || driver != nil || calibrating != nil }
}

struct PFRecoveryReadout: Equatable {
    var bodySignals: PFSignalReading?
    var sleepSignal: PFSignalReading?
    var recovery: PFVerdictLine?
    var sleep: PFVerdictLine?
    var strain: PFVerdictLine?
    /// Whose numbers: "PaceForge (Garmin)".
    var source: String?

    /// The source the server names for these numbers, when it names none.
    static let defaultSource = "PaceForge (Garmin)"

    var hasContent: Bool {
        bodySignals != nil || sleepSignal != nil || recovery?.hasContent == true || sleep?.hasContent == true
            || strain?.hasContent == true
    }

    /// The same readout for a watch worn by day only: nothing overnight (the two signals, the Recovery and Sleep lines) is shown, the
    /// Strain line stays. Nil when nothing is left.
    func visible(overnight: Bool) -> PFRecoveryReadout? {
        guard !overnight else { return hasContent ? self : nil }
        var out = self
        out.bodySignals = nil
        out.sleepSignal = nil
        out.recovery = nil
        out.sleep = nil
        return out.hasContent ? out : nil
    }
}

// MARK: - Garmin's Load Focus (fitness.json: load.load_focus_panel)

struct PFLoadBucket: Equatable, Identifiable {
    var key: String
    var label: String
    var value: Double
    var min: Double?
    var max: Double?
    /// under, in_range or over; nil when Garmin sent no range.
    var status: String?

    var id: String { key }
}

struct PFLoadFocus: Equatable {
    var label: String?
    var note: String?
    var asOf: String?
    var buckets: [PFLoadBucket]
    var verdict: String?

    var hasContent: Bool { !buckets.isEmpty || verdict != nil }
}

// MARK: - The weekly target-load range (projection.json: week_target)

struct PFWeekTargetWeek: Equatable, Identifiable {
    var week: String
    /// current or next.
    var state: String
    /// normal, taper or recovery.
    var kind: String
    var event: String?
    var chronic: Double?
    var actual: Double?
    var expected: Double?
    var low: Double?
    var high: Double?
    /// under, in_range, over or recovery; nil for the next week.
    var status: String?
    var plannedCheck: String?
    var plannedDelta: Double?
    var line: String?

    var id: String { week }
}

struct PFWeekTarget: Equatable {
    var source: String?
    var note: String?
    var weeks: [PFWeekTargetWeek]
}

// MARK: - Muscular load (fitness.json: strength.muscular_load)

struct PFMuscleGroup: Equatable, Identifiable {
    var key: String
    var label: String
    var acuteSets: Int
    var chronicWeeklySets: Double?
    var ratio: Double?
    /// spike, above, steady or below; nil when there is too little earlier work to compare.
    var status: String?
    var line: String?

    var id: String { key }
}

struct PFMuscularWeek: Equatable, Identifiable {
    var weekEnding: String
    var sets: Int

    var id: String { weekEnding }
}

struct PFMuscularLoad: Equatable {
    var source: String?
    var note: String?
    var calibrating: Bool
    /// The three groups with the most sets in the last 7 days, most first.
    var top: [PFMuscleGroup]
    var total: PFMuscleGroup?
    /// Sets per week, oldest first.
    var weekly: [PFMuscularWeek]
}

// MARK: - The WHOOP strap's overnight HRV (data/strap-hrv.json)

struct PFStrapNight: Equatable, Identifiable {
    var date: String
    var rmssdMs: Double?
    /// ok, short or few_beats.
    var quality: String?

    var id: String { date }
}

struct PFStrapHRV: Equatable {
    var generatedAt: String?
    /// in_band, above, below or calibrating.
    var state: String
    var mean7: Double?
    var baseline60: Double?
    var bandLow: Double?
    var bandHigh: Double?
    var nightsUsed: Int
    var nights: [PFStrapNight]
}

// MARK: - Healthspan input panel (healthspan.json: metric.input_panel)

struct PFHealthInput: Equatable, Identifiable {
    var key: String
    var label: String
    var present: Bool
    var valueText: String?
    var targetText: String?
    var status: String?
    /// Years this input adds (positive) or takes off (negative) the estimate; nil when missing.
    var years: Double?
    var source: String?
    var gloss: String?
    /// What to do to get the input; only on a missing one.
    var fix: String?

    var id: String { key }
}

struct PFHealthInputPanel: Equatable {
    var present: Int
    var total: Int
    var needed: Int
    var enough: Bool
    var statusText: String?
    var inputs: [PFHealthInput]
    var holdingBack: String?

    /// The three present inputs that move the estimate most either way.
    var movers: [PFHealthInput] {
        Array(inputs.filter { $0.present && $0.years != nil }
            .sorted { abs($0.years ?? 0) > abs($1.years ?? 0) }
            .prefix(3))
    }

    var missing: [PFHealthInput] { inputs.filter { !$0.present } }
}

// MARK: - Graded health watch (daily-intel.json: health_monitor.graded)

struct PFGradedMetric: Equatable, Identifiable {
    var key: String
    var label: String
    var status: String?
    var text: String

    var id: String { key }
}

struct PFGradedWatch: Equatable {
    /// none, watch or act.
    var level: String
    var text: String?
    var metrics: [PFGradedMetric]
    var basis: String?
    var capReason: String?
}

// MARK: - Parsing

enum PFBandParse {
    static let strapHRVPath = "data/strap-hrv.json"

    private static func number(_ j: PFJ) -> Double? {
        guard let value = j.double, value.isFinite else { return nil }
        return value
    }

    private static func isObject(_ j: PFJ) -> Bool { j.raw is [String: Any] }

    // MARK: Recovery two ways

    private static func signal(_ j: PFJ) -> PFSignalReading? {
        guard isObject(j), let value = number(j["value"]), let line = j["line"].text else { return nil }
        return PFSignalReading(value: value, state: j["state"].text ?? "settled", line: line, gloss: j["gloss"].text)
    }

    private static func verdictLine(_ j: PFJ) -> PFVerdictLine? {
        guard isObject(j) else { return nil }
        let out = PFVerdictLine(verdict: j["verdict"].text, driver: j["driver"].text, calibrating: j["calibrating"].text)
        return out.hasContent ? out : nil
    }

    /// `fitness.json`'s `daily` block; nil when the server sent neither the two signals nor a verdict line.
    static func readout(daily: PFJ) -> PFRecoveryReadout? {
        let recovery = daily["recovery"]
        let lines = daily["lines"]
        var out = PFRecoveryReadout()
        out.bodySignals = signal(recovery["body_signals"])
        out.sleepSignal = signal(recovery["sleep_signal"])
        out.recovery = verdictLine(lines["recovery"])
        out.sleep = verdictLine(lines["sleep"])
        out.strain = verdictLine(lines["strain"])
        out.source = recovery["body_signals"]["source"].text ?? lines["recovery"]["source"].text ?? lines["strain"]["source"].text
        return out.hasContent ? out : nil
    }

    // MARK: Load Focus

    /// `fitness.json`'s `load` block; nil unless Garmin's panel is available and has something to show.
    static func loadFocus(load: PFJ) -> PFLoadFocus? {
        let panel = load["load_focus_panel"]
        guard isObject(panel), panel["available"].bool == true else { return nil }
        let buckets: [PFLoadBucket] = panel["buckets"].array.compactMap { b in
            guard let key = b["key"].text, let value = number(b["value"]) else { return nil }
            return PFLoadBucket(key: key, label: b["label"].text ?? PFBand.titleFromId(key), value: value,
                                min: number(b["min"]), max: number(b["max"]), status: b["status"].text)
        }
        let out = PFLoadFocus(label: panel["label"].text, note: panel["note"].text, asOf: panel["as_of"].text,
                              buckets: buckets, verdict: panel["verdict"].text)
        return out.hasContent ? out : nil
    }

    // MARK: Weekly target

    /// `projection.json`; nil unless the range is available (a calibrating or absent range leaves the card out).
    static func weekTarget(projection: PFJ) -> PFWeekTarget? {
        let t = projection["week_target"]
        guard isObject(t), t["available"].bool == true else { return nil }
        let weeks: [PFWeekTargetWeek] = t["weeks"].array.compactMap { w in
            guard let week = w["week"].text, let state = w["state"].text else { return nil }
            return PFWeekTargetWeek(week: week, state: state, kind: w["kind"].text ?? "normal", event: w["event"].text,
                                    chronic: number(w["chronic"]), actual: number(w["actual"]), expected: number(w["expected"]),
                                    low: number(w["low"]), high: number(w["high"]), status: w["status"].text,
                                    plannedCheck: w["planned_check"].text, plannedDelta: number(w["planned_delta"]),
                                    line: w["line"].text)
        }
        guard !weeks.isEmpty else { return nil }
        return PFWeekTarget(source: t["source"].text, note: t["note"].text, weeks: weeks)
    }

    // MARK: Muscular load

    private static func muscleGroup(_ key: String, _ g: PFJ) -> PFMuscleGroup? {
        guard isObject(g) else { return nil }
        return PFMuscleGroup(key: key, label: g["label"].text ?? PFBand.titleFromId(key), acuteSets: g["acute_sets"].int ?? 0,
                             chronicWeeklySets: number(g["chronic_weekly_sets"]), ratio: number(g["ratio"]),
                             status: g["status"].text, line: g["line"].text)
    }

    /// `fitness.json`'s `strength` block; nil when the server marks it unavailable (no set on file).
    static func muscularLoad(strength: PFJ) -> PFMuscularLoad? {
        let m = strength["muscular_load"]
        guard isObject(m), m["available"].bool == true else { return nil }
        let groups = m["groups"]
        let top = m["top"].strings.prefix(3).compactMap { key in muscleGroup(key, groups[key]) }
        let weekly: [PFMuscularWeek] = m["weekly"].array.compactMap { w in
            guard let day = w["week_ending"].text, let sets = w["sets"].int else { return nil }
            return PFMuscularWeek(weekEnding: day, sets: sets)
        }
        return PFMuscularLoad(source: m["source"].text, note: m["note"].text, calibrating: m["calibrating"].bool ?? false,
                              top: Array(top), total: muscleGroup("total", m["total"]), weekly: weekly)
    }

    // MARK: Strap HRV

    /// `data/strap-hrv.json`; nil when the file is not an object or lists no night (no strap, or not read yet).
    static func strapHRV(_ doc: PFJ) -> PFStrapHRV? {
        guard isObject(doc) else { return nil }
        let nights: [PFStrapNight] = doc["nights"].array.compactMap { n in
            guard let date = n["date"].text else { return nil }
            return PFStrapNight(date: date, rmssdMs: number(n["rmssd_ms"]), quality: n["quality"].text)
        }
        guard !nights.isEmpty else { return nil }
        let s = doc["status"]
        return PFStrapHRV(generatedAt: doc["generated_at"].text, state: s["state"].text ?? "calibrating", mean7: number(s["mean7"]),
                          baseline60: number(s["baseline60"]), bandLow: number(s["band_low"]), bandHigh: number(s["band_high"]),
                          nightsUsed: s["nights_used"].int ?? 0, nights: nights)
    }

    // MARK: Healthspan inputs

    /// The `input_panel` object of the Healthspan metric; nil when it is absent or lists no input.
    static func inputPanel(_ p: PFJ) -> PFHealthInputPanel? {
        guard isObject(p) else { return nil }
        let inputs: [PFHealthInput] = p["inputs"].array.compactMap { i in
            guard let key = i["key"].text else { return nil }
            return PFHealthInput(key: key, label: i["label"].text ?? PFBand.titleFromId(key), present: i["present"].bool ?? false,
                                 valueText: i["value_text"].text, targetText: i["target_text"].text, status: i["status"].text,
                                 years: number(i["years"]), source: i["source"].text, gloss: i["gloss"].text, fix: i["fix"].text)
        }
        guard !inputs.isEmpty else { return nil }
        return PFHealthInputPanel(present: p["present"].int ?? inputs.filter { $0.present }.count,
                                  total: p["total"].int ?? inputs.count, needed: p["needed"].int ?? 0,
                                  enough: p["enough"].bool ?? false, statusText: p["status_text"].text, inputs: inputs,
                                  holdingBack: p["holding_back"]["reason"].text)
    }

    // MARK: Graded health watch

    private static let gradedLevels: Set<String> = ["none", "watch", "act"]

    /// The `graded` object of the Health monitor metric; nil when absent or when its level is not one of none, watch, act.
    static func graded(_ g: PFJ) -> PFGradedWatch? {
        guard isObject(g), let level = g["level"].text, gradedLevels.contains(level) else { return nil }
        let metrics: [PFGradedMetric] = g["metrics"].array.compactMap { m in
            guard let key = m["key"].text, let text = m["text"].text else { return nil }
            return PFGradedMetric(key: key, label: m["label"].text ?? PFBand.titleFromId(key), status: m["status"].text, text: text)
        }
        return PFGradedWatch(level: level, text: g["text"].text, metrics: metrics, basis: g["basis"].text, capReason: g["cap_reason"].text)
    }
}

// MARK: - Small rules the cards draw from

enum PFBandLogic {
    /// Positions on a bar, each 0 to 1. `low` and `high` are the range (an absent end is taken as 0 or as the largest value).
    struct Bar: Equatable {
        var value: Double
        var low: Double
        var high: Double
    }

    /// A bar with room past the largest of the three numbers, so a value over the range still sits inside the track.
    static func bar(value: Double, low: Double?, high: Double?) -> Bar? {
        guard value.isFinite, value >= 0 else { return nil }
        let lo = max(0, low ?? 0)
        let hi = max(high ?? max(value, lo), lo)
        let top = max(value, hi) * 1.15
        guard top > 0 else { return nil }
        return Bar(value: min(value / top, 1), low: min(lo / top, 1), high: min(hi / top, 1))
    }

    /// "Under range", "In range" or "Above range" for a Load Focus bucket; nil for no range.
    static func bucketWord(_ status: String?) -> String? {
        switch status {
        case "under": return "Under range"
        case "in_range": return "In range"
        case "over": return "Above range"
        default: return nil
        }
    }

    static func weekStatusWord(_ status: String?) -> String? {
        switch status {
        case "under": return "Under range"
        case "in_range": return "In range"
        case "over": return "Over range"
        case "recovery": return "Recovery week"
        default: return nil
        }
    }

    static func plannedCheckWord(_ check: String?) -> String? {
        switch check {
        case "under": return "Plan lands under"
        case "in_range": return "Plan lands in range"
        case "over": return "Plan lands over"
        default: return nil
        }
    }

    static func ratioWord(_ status: String?) -> String? {
        switch status {
        case "spike": return "Spike"
        case "above": return "Above your norm"
        case "steady": return "Steady"
        case "below": return "Below your norm"
        default: return nil
        }
    }

    static func strapStateWord(_ state: String) -> String {
        switch state {
        case "in_band": return "In your range"
        case "above": return "Above your range"
        case "below": return "Below your range"
        default: return "Calibrating"
        }
    }

    /// Where the 7-night average sits against the usual band, 0 to 1 each; nil without a band and an average.
    static func strapBar(_ hrv: PFStrapHRV) -> Bar? {
        guard let mean = hrv.mean7, let low = hrv.bandLow, let high = hrv.bandHigh, high > low else { return nil }
        let floor = min(low, mean) * 0.85
        let top = max(high, mean) * 1.15
        let span = top - floor
        guard span > 0 else { return nil }
        return Bar(value: (mean - floor) / span, low: (low - floor) / span, high: (high - floor) / span)
    }

    static func gradedWord(_ level: String) -> String {
        switch level {
        case "act": return "Take it easy"
        case "watch": return "Keep an eye on it"
        default: return "All inside your range"
        }
    }

    /// The latest night the strap read in full, for the "last night" line.
    static func lastFullNight(_ hrv: PFStrapHRV) -> PFStrapNight? {
        hrv.nights.last { $0.quality == "ok" && $0.rmssdMs != nil }
    }
}
