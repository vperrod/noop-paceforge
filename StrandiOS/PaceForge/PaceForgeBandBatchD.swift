import Foundation

// The second set of band-report documents PaceForge serves (batch D): when in the night the strap's heart rate settled, four plain sleep
// tiles per night, Garmin's stage shares against the athlete's own, the weekly stress load, and active hours. Foundation only, so the
// parsing and the small rules the cards draw from are compiled into the macOS unit-test bundle and the Linux logic tests.
//
// Every sentence and number is the server's, shown as served; each document names its source (the strap via NOOP, or Garmin) and none is
// merged with another or with NOOP's own numbers. A key the server does not send reads as absent and its card leaves out.
// `recovery-shadow-sleep3.jsonl` is shadow on the server and is deliberately not read.

// MARK: - Sleep settle (data/sleep-settle.json, strap, overnight)

struct PFSettleNight: Equatable {
    var date: String
    var lowestBpm: Double?
    var lowestAfterOnsetMin: Int?
    var settleAfterOnsetMin: Int?
    /// ok, short or few_samples.
    var quality: String?
    var line: String?
}

struct PFSettleStatus: Equatable {
    /// later, in_band, earlier or calibrating.
    var state: String
    var settleMin: Double?
    var baselineMin: Double?
    var line: String?
    var gloss: String?
    /// `baseline_includes`: the families of set-aside nights put back because too few were left; empty on an older document.
    var baselineIncludes: [String] = []
}

struct PFSleepSettle: Equatable {
    var source: String?
    var latest: PFSettleNight?
    var status: PFSettleStatus?

    /// The server's own sentence about the newest night: the status line once it can compare, else the night's line.
    var sentence: String? { status?.line ?? latest?.line }
}

// MARK: - Sleep tiles (data/sleep-tiles.json, Garmin via PaceForge, overnight)

struct PFSleepTile: Equatable, Identifiable {
    var key: String
    var value: Double?
    var unit: String?
    var text: String?
    var usual: Double?
    var bandLow: Double?
    var bandHigh: Double?
    /// better, usual, worse, calibrating or unavailable.
    var standing: String
    var gloss: String?

    var id: String { key }
}

struct PFSleepTiles: Equatable {
    var source: String?
    var date: String
    var tiles: [PFSleepTile]
}

// MARK: - Stage shares (data/stage-shares.json, Garmin, overnight)

struct PFStageShare: Equatable, Identifiable {
    /// deep, rem or light.
    var key: String
    var pct: Double
    var usualPct: Double?
    var deviationPts: Double?
    var large: Bool
    /// higher or lower; only when large.
    var direction: String?

    var id: String { key }
}

struct PFStageShares: Equatable {
    var source: String?
    var caveat: String?
    var gloss: String?
    var date: String
    var shares: [PFStageShare]
    var line: String?
}

// MARK: - Weekly stress load (data/stress-load.json, Garmin)

struct PFStressWeek: Equatable, Identifiable {
    var weekStart: String
    var days: Int
    var complete: Bool
    var highHoursPerDay: Double
    var restfulMinPerDay: Double

    var id: String { weekStart }
}

struct PFStressLoad: Equatable {
    var source: String?
    var gloss: String?
    var normHighHoursPerDay: Double?
    var normRestfulMinPerDay: Double?
    var weeks: [PFStressWeek]
    /// rising, steady, falling or unknown, for the high hours and the restful minutes.
    var highTrend: String?
    var restfulTrend: String?
    var line: String?
}

// MARK: - Active hours (data/active-hours.json, Garmin)

struct PFActiveHours: Equatable {
    var source: String?
    var gloss: String?
    var hourSteps: Int?
    var asOf: String?
    var activeHours: Int
    var median: Double?
    /// low, typical, high or calibrating.
    var status: String?
    var line: String?
}

// MARK: - Parsing

enum PFBatchDParse {
    static let settlePath = "data/sleep-settle.json"
    static let tilesPath = "data/sleep-tiles.json"
    static let sharesPath = "data/stage-shares.json"
    static let stressLoadPath = "data/stress-load.json"
    static let activeHoursPath = "data/active-hours.json"
    static let all = [settlePath, tilesPath, sharesPath, stressLoadPath, activeHoursPath]

    /// The four tiles, in the order the card draws them.
    static let tileOrder = ["duration", "efficiency", "restorative", "consistency"]
    static let stageOrder = ["deep", "rem", "light"]

    private static func number(_ j: PFJ) -> Double? {
        guard let value = j.double, value.isFinite else { return nil }
        return value
    }

    private static func isObject(_ j: PFJ) -> Bool { j.raw is [String: Any] }

    /// The newest night of a document's `nights` list (the lists run oldest first); nil without a dated one.
    private static func newest(_ doc: PFJ) -> PFJ? {
        doc["nights"].array.last { $0["date"].text != nil }
    }

    static func sleepSettle(_ doc: PFJ) -> PFSleepSettle? {
        guard isObject(doc), let night = newest(doc), let date = night["date"].text else { return nil }
        let latest = PFSettleNight(date: date, lowestBpm: number(night["lowest_bpm"]),
                                   lowestAfterOnsetMin: night["lowest_after_onset_min"].int,
                                   settleAfterOnsetMin: night["settle_after_onset_min"].int,
                                   quality: night["quality"].text, line: night["line"].text)
        let s = doc["status"]
        let status: PFSettleStatus? = isObject(s)
            ? PFSettleStatus(state: s["state"].text ?? "calibrating", settleMin: number(s["settle_min"]),
                             baselineMin: number(s["baseline_min"]), line: s["line"].text, gloss: s["gloss"].text,
                             baselineIncludes: s["baseline_includes"].array.compactMap { $0.text })
            : nil
        let out = PFSleepSettle(source: doc["source"].text ?? s["source"].text, latest: latest, status: status)
        return out.sentence == nil ? nil : out
    }

    static func sleepTiles(_ doc: PFJ) -> PFSleepTiles? {
        guard isObject(doc), let night = newest(doc), let date = night["date"].text else { return nil }
        let glosses = doc["gloss"]
        let tiles: [PFSleepTile] = tileOrder.compactMap { key in
            let t = night["tiles"][key]
            guard isObject(t), let standing = t["standing"].text, standing != "unavailable", let value = number(t["value"]) else { return nil }
            return PFSleepTile(key: key, value: value, unit: t["unit"].text, text: t["text"].text, usual: number(t["usual"]),
                               bandLow: number(t["band_low"]), bandHigh: number(t["band_high"]), standing: standing,
                               gloss: glosses[key].text)
        }
        guard !tiles.isEmpty else { return nil }
        return PFSleepTiles(source: doc["source"].text, date: date, tiles: tiles)
    }

    static func stageShares(_ doc: PFJ) -> PFStageShares? {
        guard isObject(doc), let night = newest(doc), let date = night["date"].text else { return nil }
        let shares: [PFStageShare] = stageOrder.compactMap { key in
            let s = night["shares"][key]
            guard isObject(s), let pct = number(s["pct"]) else { return nil }
            return PFStageShare(key: key, pct: pct, usualPct: number(s["usual_pct"]), deviationPts: number(s["deviation_pts"]),
                                large: s["large"].bool ?? false, direction: s["direction"].text)
        }
        guard !shares.isEmpty else { return nil }
        return PFStageShares(source: doc["source"].text, caveat: doc["caveat"].text, gloss: doc["gloss"].text, date: date,
                             shares: shares, line: night["line"].text)
    }

    static func stressLoad(_ doc: PFJ) -> PFStressLoad? {
        guard isObject(doc), doc["available"].bool == true else { return nil }
        let weeks: [PFStressWeek] = doc["weeks"].array.compactMap { w in
            guard let start = w["week_start"].text, let high = number(w["high_hours_per_day"]),
                  let restful = number(w["restful_min_per_day"]) else { return nil }
            return PFStressWeek(weekStart: start, days: w["days"].int ?? 0, complete: w["complete"].bool ?? false,
                                highHoursPerDay: high, restfulMinPerDay: restful)
        }
        guard !weeks.isEmpty else { return nil }
        return PFStressLoad(source: doc["source"].text, gloss: doc["gloss"].text,
                            normHighHoursPerDay: number(doc["norm"]["high_hours_per_day"]),
                            normRestfulMinPerDay: number(doc["norm"]["restful_min_per_day"]), weeks: weeks,
                            highTrend: doc["trend"]["high_hours"].text, restfulTrend: doc["trend"]["restful_min"].text,
                            line: doc["line"].text)
    }

    static func activeHours(_ doc: PFJ) -> PFActiveHours? {
        guard isObject(doc), doc["available"].bool == true, isObject(doc["metric"]), let hours = doc["metric"]["active_hours"].int else {
            return nil
        }
        let m = doc["metric"]
        return PFActiveHours(source: doc["source"].text, gloss: doc["gloss"].text, hourSteps: doc["hour_steps"].int,
                             asOf: m["as_of"].text, activeHours: hours, median: number(m["median_30d"]),
                             status: m["status"].text, line: doc["line"].text)
    }
}

// MARK: - Small rules the cards draw from

enum PFBatchDLogic {
    static func standingWord(_ standing: String) -> String? {
        switch standing {
        case "better": return "Better than usual"
        case "usual": return "About your usual"
        case "worse": return "Worse than usual"
        case "calibrating": return "Calibrating"
        default: return nil
        }
    }

    static func tileTitle(_ key: String) -> String {
        switch key {
        case "duration": return "Hours asleep"
        case "efficiency": return "Time asleep in bed"
        case "restorative": return "Deep and REM"
        case "consistency": return "Bedtime steadiness"
        default: return PFBand.titleFromId(key)
        }
    }

    static func stageTitle(_ key: String) -> String {
        switch key {
        case "deep": return "Deep sleep"
        case "rem": return "REM sleep"
        default: return "Light sleep"
        }
    }

    static func stageWord(_ share: PFStageShare) -> String? {
        guard share.large, let direction = share.direction else { return nil }
        return direction == "higher" ? "Higher than usual" : "Lower than usual"
    }

    static func trendWord(_ trend: String?) -> String? {
        switch trend {
        case "rising": return "Rising"
        case "falling": return "Falling"
        case "steady": return "Steady"
        default: return nil
        }
    }

    static func activeStatusWord(_ status: String?) -> String? {
        switch status {
        case "low": return "Fewer than usual"
        case "high": return "More than usual"
        case "typical": return "About your usual"
        case "calibrating": return "Calibrating"
        default: return nil
        }
    }

    /// 0 to 1 positions for a value, the largest value being drawn at full width; nil without a positive maximum.
    static func fraction(_ value: Double, of maximum: Double) -> Double? {
        guard value.isFinite, maximum.isFinite, maximum > 0 else { return nil }
        return min(max(value / maximum, 0), 1)
    }
}
