import Foundation

// The Athlete tab's data: the profile facts, the metric tiles with their change over four weeks, and the strengths /
// weaknesses / areas to work on. Foundation only (compiled into the macOS test bundle like the other PaceForge parsers).
//
// Everything is made from documents the app already fetches: standing.json, fitness.json, body.json, body-progress.json and
// hyrox_analysis.json, through the snapshot, plus the few fitness.json fields the snapshot did not keep (`PFAthleteFitness`).
// profile.json, analytics.json and benchmarks.json (build 501) are parsed in PaceForgeAthleteProfile.swift and arrive as `athleteDocs`.
// Nothing here asks the athlete for anything: a value that is missing reads as a dash.

// MARK: - Model

struct PFAthletePoint: Equatable {
    var date: String
    var value: Double
}

/// How a metric moved over the window: the arrow and the colour tone. `isFavourable` is nil when the movement is flat, or when the
/// metric has no better direction (form), so the arrow is drawn grey.
struct PFAthleteChange: Equatable {
    enum Direction: Equatable {
        case up, down, flat
    }

    var delta: Double?
    var direction: Direction
    /// "4 wk" for a change worked out from a series, "30 d" for the Standing document's own trend.
    var window: String
    var isFavourable: Bool?
}

/// One tile: a metric with its value, change and the series behind the sparkline and the chart.
struct PFAthleteMetric: Identifiable, Equatable {
    let id: String
    let label: String
    let unit: String
    var value: Double?
    /// The number alone, "\u{2014}" when missing; the unit is drawn beside it.
    var valueText: String
    var asOf: String?
    var series: [PFAthletePoint] = []
    var change: PFAthleteChange?
    var decimals = 0
    /// Which system the number comes from, shown on the tile detail so the strap's and the watch's scores stay apart.
    let source: String
    let what: String
    /// The "Where you stand" metric this tile reads, so its norms and plan open from the tile.
    var standingId: String?
    /// True when the "Body weight and body fat" Hide numbers switch covers this tile.
    var hidesWithBody = false
    /// Today, so the sparkline's window and its staleness count from today and not from the series' last point.
    var anchorDate: String?
    /// True for a figure that changes in steps when someone files a new value (FTP): it reads "since <date>", never an arrow.
    var isStep = false
    /// What the date line reads when the figure has no date of its own ("date unknown"); never a guessed day.
    var undatedText: String?
    /// One short line under a tile that has no sparkline (the lactate threshold's heart rate).
    var secondary: String?
    /// Figures from the same family as this one, shown on the detail page with their own dates and sources.
    var rows: [PFAthleteDetailRow] = []

    init(id: String, label: String, unit: String, value: Double?, valueText: String, source: String, what: String) {
        self.id = id
        self.label = label
        self.unit = unit
        self.value = value
        self.valueText = valueText
        self.source = source
        self.what = what
    }

    var hasSeries: Bool { series.count >= 2 }

    /// "since 1 Feb" for a step figure, "as of 1 Feb" otherwise; nil without a date.
    var datedText: String? {
        guard let asOf else { return undatedText }
        return (isStep ? "since " : "as of ") + PFFormat.shortDate(asOf)
    }

    /// The values of the tile's sparkline: the last four weeks before today (or before the last point when no day is known), or the
    /// last two points when fewer fall inside that. Empty when the last point is too old to say anything about now.
    var sparkValues: [Double] {
        guard let last = series.last, !PFAthleteMath.isStale(latest: last.date, today: anchorDate) else { return [] }
        let cutoff = PFFormat.addDays(anchorDate ?? last.date, -PFAthleteMath.windowDays)
        let recent = series.filter { $0.date >= cutoff }
        return (recent.count >= 2 ? recent : Array(series.suffix(2))).map { $0.value }
    }

    /// "+1.2 vs 4 wk", "Up vs 30 d" when the document gave no size, "No change vs 4 wk".
    var changeText: String? {
        guard let change else { return nil }
        switch change.direction {
        case .flat:
            return "No change vs \(change.window)"
        case .up, .down:
            if let size = change.delta { return PFNumber.signed(size, decimals: decimals) + " vs " + change.window }
            return (change.direction == .up ? "Up" : "Down") + " vs " + change.window
        }
    }
}

struct PFAthleteFact: Identifiable, Equatable {
    let label: String
    var text: String
    /// Where the figure comes from when that is not obvious ("NOOP setting", "auto").
    var note: String?
    /// True when the Hide numbers switch for body weight covers it.
    var hidesWithBody = false
    var id: String { label }
}

/// One cell of the running-times row: a best recent time from the Standing document, or the half-marathon the current shape equals.
struct PFAthleteRunTime: Identifiable, Equatable {
    let id: String
    let label: String
    var text: String
    var band: Int?
    /// The Standing metric the cell opens; nil for the shape-equivalent cell.
    var standingId: String?
}

/// A strength, a weakness or an area to work on, with the short evidence line and the collapsed "why".
struct PFAthleteFinding: Identifiable, Equatable {
    enum Group: String, Equatable {
        case strength, weakness, area
    }

    let id: String
    let group: Group
    let title: String
    let evidence: String
    var band: Int?
    /// A short tag such as the limiter's area ("endurance") or "HYROX".
    var tag: String?
    /// The computed reason: the rule's own words, labelled "Rule" in the app.
    var ruleWhy: String?
    /// The coach's model-written recommendation for the same thing, labelled "Coach" in the app, only ever inside the collapsed why.
    var coachWhy: String?
    var standingId: String?
    var planId: String?
    /// The tile whose detail the row links to.
    var tileId: String?
}

struct PFAthlete {
    var goalTitle: String?
    var goalLine: String?
    var facts: [PFAthleteFact] = []
    var tiles: [PFAthleteMetric] = []
    var runTimes: [PFAthleteRunTime] = []
    var hyroxCard: PFHyroxFinishCard?
    var hyrox: PFHyrox?
    var predictions: PFAthletePredictions?
    var zones: PFAthleteZones?
    var records: [PFAthleteRecord] = []
    var strengths: [PFAthleteFinding] = []
    var weaknesses: [PFAthleteFinding] = []
    var areas: [PFAthleteFinding] = []
    /// "31 metrics, 11 rated" for the row that opens the full scorecard; nil when there is no Standing document.
    var scorecardLine: String?

    var hasFindings: Bool { !(strengths.isEmpty && weaknesses.isEmpty && areas.isEmpty) }

    var hasHyrox: Bool { hyroxCard != nil || hyrox != nil }

    /// Nothing to draw beyond a header of dashes.
    var isEmpty: Bool {
        tiles.isEmpty && runTimes.isEmpty && !hasHyrox && !hasFindings && goalTitle == nil
            && predictions == nil && zones == nil && records.isEmpty
    }

    func tile(_ id: String) -> PFAthleteMetric? { tiles.first { $0.id == id } }
}

// MARK: - The fitness.json fields the snapshot does not keep

struct PFAthleteLimiter: Equatable {
    var name: String
    var area: String
    var evidence: String
}

struct PFAthleteFitness: Equatable {
    var ftpHistory: [PFAthletePoint] = []
    /// `bike.ftp`: the FTP on file. `autoFtp` is only the estimate from rides.
    var ftp: Double?
    var autoFtp: Double?
    var criticalPaceSecPerKm: Double?
    var restingHrLatest: Double?
    var halfMarathonEquivalentSec: Double?
    /// `coach_input.ranked_limiters`: the engine's own ranking, a rule and not a model's words.
    var limiters: [PFAthleteLimiter] = []
}

enum PFAthleteParse {
    static func fitness(_ f: PFJ) -> PFAthleteFitness? {
        guard f.exists else { return nil }
        var out = PFAthleteFitness()

        let bike = f["bike"]
        out.ftpHistory = points(bike["ftp_history"], valueKey: "ftp", fallbackKey: nil)
        out.ftp = bike["ftp"].double
        out.autoFtp = bike["auto_ftp"].double

        let critical = f["running"]["critical_speed"]
        if critical["available"].bool != false, let pace = critical["cs_pace_sec_per_km"].double, pace > 120, pace < 900 {
            out.criticalPaceSecPerKm = pace
        }

        out.restingHrLatest = f["load"]["resting_hr_trend"]["latest"].double
        out.halfMarathonEquivalentSec = f["prognosis"]["hm_equivalent"]["time_sec"].double

        out.limiters = f["coach_input"]["ranked_limiters"].array.compactMap { l in
            guard let name = l["name"].text else { return nil }
            return PFAthleteLimiter(name: name, area: l["area"].text ?? "", evidence: l["evidence"].text ?? "")
        }
        return out
    }

    private static func points(_ list: PFJ, valueKey: String, fallbackKey: String?) -> [PFAthletePoint] {
        let rows: [PFAthletePoint] = list.array.compactMap { p in
            guard let date = p["date"].text else { return nil }
            var found = p[valueKey].double
            if found == nil, let fallbackKey { found = p[fallbackKey].double }
            guard let number = found else { return nil }
            return PFAthletePoint(date: String(date.prefix(10)), value: number)
        }
        return rows.sorted { $0.date < $1.date }
    }
}

// MARK: - Change over four weeks

enum PFAthleteMath {
    static let windowDays = 28
    static let windowLabel = "4 wk"
    /// A last point older than this (counted to today) says nothing about the last four weeks.
    static let staleDays = 14

    /// True when `latest` is more than `staleDays` before `today`. With no day known nothing is stale.
    static func isStale(latest: String, today: String?) -> Bool {
        guard let today, !today.isEmpty else { return false }
        return PFFormat.daysBetween(latest, today) > staleDays
    }

    /// The last value at or before `date` in a series sorted oldest first; nil when the series starts later.
    static func value(onOrBefore date: String, in series: [PFAthletePoint]) -> Double? {
        series.last(where: { $0.date <= date })?.value
    }

    /// The newest value minus the value at or before four weeks before `today` (the newest point's day when `today` is nil). nil when
    /// the newest point is more than two weeks old, or the series does not reach back that far, so a stale or short history shows no
    /// arrow rather than a guess. A move inside `noise` (the scale's own day-to-day
    /// band) or inside 1 % of the earlier value is flat.
    static func change(series: [PFAthletePoint], today: String? = nil, higherIsBetter: Bool?, noise: Double? = nil) -> PFAthleteChange? {
        guard let latest = series.last, !isStale(latest: latest.date, today: today) else { return nil }
        let anchor = (today?.isEmpty == false ? today : nil) ?? latest.date
        let cutoff = PFFormat.addDays(anchor, -windowDays)
        guard let earlier = value(onOrBefore: cutoff, in: series) else { return nil }
        let delta = latest.value - earlier
        let band = max(noise ?? 0, abs(earlier) * 0.01)
        if abs(delta) <= band {
            return PFAthleteChange(delta: delta, direction: .flat, window: windowLabel, isFavourable: nil)
        }
        let direction: PFAthleteChange.Direction = delta > 0 ? .up : .down
        var favourable: Bool?
        if let higherIsBetter { favourable = (delta > 0) == higherIsBetter }
        return PFAthleteChange(delta: delta, direction: direction, window: windowLabel, isFavourable: favourable)
    }

    /// The Standing document's own trend (a 30-day window it works out on the server) as a change, for a metric whose history the app
    /// does not hold. The server's `improving` flag decides the colour; the window is named as it is.
    static func change(from trend: PFStandingTrend?) -> PFAthleteChange? {
        guard let trend else { return nil }
        let word = (trend.direction ?? "").lowercased()
        let up = ["up", "rising", "increasing", "increase", "higher"]
        let down = ["down", "falling", "decreasing", "decrease", "lower"]
        let window = "\(trend.windowDays ?? 30) d"
        if up.contains(word) || down.contains(word) {
            let isUp = up.contains(word)
            let size = trend.change.map { abs($0) }
            let delta: Double? = size.map { isUp ? $0 : -$0 }
            return PFAthleteChange(delta: delta, direction: isUp ? .up : .down, window: window, isFavourable: trend.improving)
        }
        if trend.direction == nil && trend.change == nil { return nil }
        return PFAthleteChange(delta: trend.change, direction: .flat, window: window, isFavourable: nil)
    }
}

// MARK: - Building the tab from the snapshot

enum PFAthleteBuild {
    static func make(_ s: PFSnapshot, maxHr: Int? = nil) -> PFAthlete {
        var out = PFAthlete()
        let fit = s.athleteFitness
        let standing = s.standing
        let docs = s.athleteDocs
        let profile = docs?.profile
        let today: String? = s.todayISO.isEmpty ? nil : s.todayISO

        let candidates: [PFAthleteMetric?] = [
            vo2maxTile(standing, profile),
            thresholdTile(profile, fit),
            ftpTile(fit, today: today),
            restingHrTile(standing, fit),
            hrvTile(standing),
            bodyTile(s, key: "weight_kg", id: "weight", label: "Weight", unit: "kg", decimals: 1,
                     what: Copy.weight, today: today),
            bodyTile(s, key: "body_fat_pct", id: "body_fat", label: "Body fat", unit: "%", decimals: 1,
                     what: Copy.bodyFat, today: today),
            loadTile(s, id: "ctl", label: "Fitness (CTL)", key: \PFLoadPoint.ctl, higherIsBetter: true, what: Copy.ctl, today: today),
            loadTile(s, id: "tsb", label: "Form (TSB)", key: \PFLoadPoint.tsb, higherIsBetter: nil, what: Copy.tsb, today: today),
            enduranceTile(profile),
            trainingStatusTile(profile),
        ]
        out.tiles = candidates.compactMap { $0 }
        // The one detail page for VO2max and the threshold: whichever of the three tiles is opened shows the same figures.
        let family = vo2AndThresholdRows(profile, fit)
        for index in out.tiles.indices where ["vo2max", "lt_pace"].contains(out.tiles[index].id) {
            out.tiles[index].rows = family
        }

        out.runTimes = runTimes(standing, fit)
        out.predictions = predictions(profile, docs?.analytics)
        out.zones = zones(profile)
        out.records = (profile?.personalRecords ?? []) + (docs?.benchmarks ?? [])
        out.hyroxCard = s.insights.hyroxFinish
        out.hyrox = s.insights.hyrox
        out.facts = facts(s, tiles: out.tiles, profile: profile, maxHr: maxHr)
        applyGoal(s, to: &out)

        out.strengths = strengths(standing)
        out.weaknesses = weaknesses(standing)
        out.areas = areas(s, fit)
        if let summary = standing?.summary, summary.total > 0 {
            out.scorecardLine = "\(summary.total) metrics, \(summary.total - summary.notRated) rated"
        }
        return out
    }

    // MARK: Header

    private static func applyGoal(_ s: PFSnapshot, to out: inout PFAthlete) {
        guard let race = s.today.nextRace else { return }
        out.goalTitle = race.name
        var line = PFFormat.shortDate(race.date)
        line += race.daysOut == 1 ? " \u{00B7} 1 day" : " \u{00B7} \(race.daysOut) days"
        if let goal = race.goalTime { line += " \u{00B7} goal \(goal)" }
        out.goalLine = line
    }

    private static func facts(_ s: PFSnapshot, tiles: [PFAthleteMetric], profile: PFAthleteProfile?, maxHr: Int?) -> [PFAthleteFact] {
        let dash = "\u{2014}"
        func tileText(_ id: String, suffix: String) -> String {
            guard let tile = tiles.first(where: { $0.id == id }), tile.value != nil else { return dash }
            return tile.valueText + suffix
        }
        let age = s.body?.age ?? s.standing?.profile?.age
        let height = s.body?.heightCm ?? s.standing?.profile?.heightCm
        let weight = s.body?.latest["weight_kg"] ?? s.standing?.profile?.weightKg
        var weightFact = PFAthleteFact(label: "Weight", text: weight.map { PFFormat.oneDecimal($0) + " kg" } ?? dash)
        weightFact.hidesWithBody = true
        var ltPace = PFAthleteFact(label: "LT pace", text: tileText("lt_pace", suffix: " /km"))
        if profile?.ltPaceSecPerKm == nil, ltPace.text != dash { ltPace.note = "critical speed" }
        return [
            PFAthleteFact(label: "Age", text: age.map { String($0) } ?? dash),
            PFAthleteFact(label: "Height", text: height.map { PFFormat.trimmed($0) + " cm" } ?? dash),
            weightFact,
            maxHrFact(profile, noopSetting: maxHr),
            PFAthleteFact(label: "Resting HR", text: tileText("resting_hr", suffix: " bpm")),
            PFAthleteFact(label: "FTP", text: tileText("ftp", suffix: " W")),
            ltPace,
            PFAthleteFact(label: "LT HR", text: profile?.ltHr.map { String(format: "%.0f", $0) + " bpm" } ?? dash),
        ]
    }

    /// NOOP's own setting when the athlete has set one (Settings > Profile); else the maximum in Garmin's running zone set, which is a
    /// setting; else the highest peak Garmin saw, which is not (the server says so), and is labelled that way.
    private static func maxHrFact(_ profile: PFAthleteProfile?, noopSetting: Int?) -> PFAthleteFact {
        if let noopSetting { return PFAthleteFact(label: "Max HR", text: "\(noopSetting) bpm", note: "NOOP setting") }
        if let zoneMax = profile?.zoneMaxHr {
            return PFAthleteFact(label: "Max HR", text: String(format: "%.0f", zoneMax) + " bpm", note: "Garmin zones")
        }
        if let seen = profile?.maxHrSeen {
            return PFAthleteFact(label: "Max HR", text: String(format: "%.0f", seen) + " bpm", note: "highest seen")
        }
        return PFAthleteFact(label: "Max HR", text: "\u{2014}", note: "auto")
    }

    // MARK: Tiles

    private static func standingMetric(_ standing: PFStanding?, _ ids: [String]) -> PFStandingMetric? {
        guard let standing else { return nil }
        for id in ids {
            if let metric = standing.metric(id) { return metric }
        }
        return nil
    }

    private static func vo2maxTile(_ standing: PFStanding?, _ profile: PFAthleteProfile?) -> PFAthleteMetric? {
        if let metric = standingMetric(standing, ["vo2max", "vo2"]), let value = metric.value {
            var tile = PFAthleteMetric(id: "vo2max", label: "VO2max", unit: metric.unit ?? "ml/kg/min", value: value,
                                       valueText: PFFormat.trimmed(value), source: "Garmin", what: Copy.vo2max)
            tile.decimals = 1
            tile.standingId = metric.id
            tile.asOf = profile?.date
            tile.change = PFAthleteMath.change(from: metric.trend)
            return tile
        }
        // No Standing document (or no rating for it): the Garmin profile's own figure, with its date and no change.
        guard let value = profile?.vo2Max else { return nil }
        var tile = PFAthleteMetric(id: "vo2max", label: "VO2max", unit: "ml/kg/min", value: value, valueText: PFFormat.trimmed(value),
                                   source: "Garmin", what: Copy.vo2max)
        tile.decimals = 1
        tile.asOf = profile?.date
        return tile
    }

    /// The Garmin lactate threshold (pace, with the heart rate under it) when the profile holds one, else the critical speed PaceForge fits
    /// from the runs. Either way the tile is "lt_pace" and has no arrow: neither figure keeps a history the app can read.
    private static func thresholdTile(_ profile: PFAthleteProfile?, _ fit: PFAthleteFitness?) -> PFAthleteMetric? {
        if let pace = profile?.ltPaceSecPerKm {
            var tile = PFAthleteMetric(id: "lt_pace", label: "Lactate threshold", unit: "/km", value: pace, valueText: PFFormat.pace(pace),
                                       source: "PaceForge \u{00B7} Garmin lactate threshold", what: Copy.lactateThreshold)
            tile.asOf = profile?.ltDate
            // The profile's own date is when it was synced, not when the threshold was measured, so it is not borrowed here.
            if profile?.ltDate == nil { tile.undatedText = "Date unknown" }
            tile.secondary = profile?.ltHr.map { "Heart rate " + String(format: "%.0f", $0) + " bpm" }
            return tile
        }
        guard let pace = fit?.criticalPaceSecPerKm else { return nil }
        return PFAthleteMetric(id: "lt_pace", label: "Threshold pace", unit: "/km", value: pace,
                               valueText: PFFormat.pace(pace), source: "PaceForge \u{00B7} critical speed", what: Copy.thresholdPace)
    }

    private static func enduranceTile(_ profile: PFAthleteProfile?) -> PFAthleteMetric? {
        guard let score = profile?.enduranceScore else { return nil }
        // Only today's value is held (no history in any document the app reads), so the tile says "as of" and draws no arrow.
        var tile = PFAthleteMetric(id: "endurance", label: "Endurance score", unit: "", value: score, valueText: String(format: "%.0f", score),
                                   source: "PaceForge \u{00B7} Garmin watch", what: Copy.endurance)
        tile.asOf = profile?.enduranceDate
        return tile
    }

    private static func trainingStatusTile(_ profile: PFAthleteProfile?) -> PFAthleteMetric? {
        guard let status = profile?.trainingStatus else { return nil }
        var tile = PFAthleteMetric(id: "training_status", label: "Training status", unit: "", value: nil, valueText: status,
                                   source: "PaceForge \u{00B7} Garmin watch", what: Copy.trainingStatus)
        tile.asOf = profile?.trainingStatusDate
        return tile
    }

    /// The figures behind the VO2max and threshold pages, each with its own source and date so the watch's and PaceForge's never blur.
    private static func vo2AndThresholdRows(_ profile: PFAthleteProfile?, _ fit: PFAthleteFitness?) -> [PFAthleteDetailRow] {
        func note(_ source: String, _ prefix: String, _ date: String?, needsDate: Bool = false) -> String {
            guard let date else { return needsDate ? source + ", date unknown" : source }
            return source + ", " + prefix + " " + PFFormat.shortDate(date)
        }
        var rows: [PFAthleteDetailRow] = []
        if let vo2 = profile?.vo2Max {
            rows.append(PFAthleteDetailRow(label: "VO2max, Garmin", text: PFFormat.oneDecimal(vo2) + " ml/kg/min",
                                           note: note("Garmin watch", "as of", profile?.date, needsDate: true)))
        }
        if let pace = profile?.ltPaceSecPerKm {
            rows.append(PFAthleteDetailRow(label: "Lactate threshold pace", text: PFFormat.pace(pace) + " /km",
                                           note: note("Garmin watch", "measured", profile?.ltDate, needsDate: true)))
        }
        if let hr = profile?.ltHr {
            rows.append(PFAthleteDetailRow(label: "Lactate threshold heart rate", text: String(format: "%.0f", hr) + " bpm",
                                           note: note("Garmin watch", "measured", profile?.ltDate, needsDate: true)))
        }
        if let critical = fit?.criticalPaceSecPerKm {
            rows.append(PFAthleteDetailRow(label: "Critical speed, from your runs", text: PFFormat.pace(critical) + " /km",
                                           note: "PaceForge, fitted from your best efforts"))
        }
        return rows
    }

    private static func ftpTile(_ fit: PFAthleteFitness?, today: String?) -> PFAthleteMetric? {
        guard let fit else { return nil }
        // The FTP on file wins; the estimate from rides is only the fallback and says so.
        let filed = fit.ftp ?? fit.ftpHistory.last?.value
        guard let current = filed ?? fit.autoFtp else { return nil }
        var tile = PFAthleteMetric(id: "ftp", label: "FTP", unit: "W", value: current, valueText: PFFormat.trimmed(current),
                                   source: filed == nil ? "PaceForge \u{00B7} from your rides" : "PaceForge \u{00B7} FTP on file",
                                   what: Copy.ftp)
        // FTP changes in steps when a new figure is filed: the tile says since when, and never draws an arrow from a step.
        tile.isStep = true
        tile.asOf = filed == nil ? nil : fit.ftpHistory.last?.date
        tile.series = fit.ftpHistory
        tile.anchorDate = today
        return tile
    }

    private static func restingHrTile(_ standing: PFStanding?, _ fit: PFAthleteFitness?) -> PFAthleteMetric? {
        let metric = standingMetric(standing, ["resting_hr"])
        guard let value = metric?.value ?? fit?.restingHrLatest else { return nil }
        var tile = PFAthleteMetric(id: "resting_hr", label: "Resting HR", unit: "bpm", value: value,
                                   valueText: String(format: "%.0f", value), source: "PaceForge \u{00B7} Garmin watch", what: Copy.restingHr)
        tile.standingId = metric?.id
        tile.change = PFAthleteMath.change(from: metric?.trend)
        return tile
    }

    private static func hrvTile(_ standing: PFStanding?) -> PFAthleteMetric? {
        guard let metric = standingMetric(standing, ["hrv"]), let value = metric.value else { return nil }
        var tile = PFAthleteMetric(id: "hrv", label: "HRV (7 nights)", unit: "ms", value: value,
                                   valueText: String(format: "%.0f", value), source: "PaceForge \u{00B7} Garmin watch", what: Copy.hrv)
        tile.standingId = metric.id
        tile.change = PFAthleteMath.change(from: metric.trend)
        return tile
    }

    private static func bodyTile(_ s: PFSnapshot, key: String, id: String, label: String, unit: String, decimals: Int,
                                 what: String, today: String?) -> PFAthleteMetric? {
        guard let body = s.body else { return nil }
        let rows: [PFAthletePoint] = body.series.compactMap { r in
            guard let v = r.values[key] else { return nil }
            return PFAthletePoint(date: String(r.date.prefix(10)), value: v)
        }
        let points = rows.sorted { $0.date < $1.date }
        guard let current = body.latest[key] ?? points.last?.value else { return nil }
        var tile = PFAthleteMetric(id: id, label: label, unit: unit, value: current,
                                   valueText: String(format: "%.\(decimals)f", current),
                                   source: "PaceForge \u{00B7} Hume scale", what: what)
        tile.decimals = decimals
        tile.asOf = points.last?.date ?? body.date
        tile.series = points
        tile.hidesWithBody = true
        tile.anchorDate = today
        tile.change = PFAthleteMath.change(series: points, today: today, higherIsBetter: bodyDirection(s, key: key),
                                           noise: bodyNoise(s, key: key))
        return tile
    }

    /// Which way is better for a body metric: the direction of the athlete's own goal when there is one, else the document's `good`.
    private static func bodyDirection(_ s: PFSnapshot, key: String) -> Bool? {
        if let goal = s.bodyProgress?.goals.first(where: { $0.metric == key }),
           let target = goal.target, let start = goal.startValue, target != start {
            return target > start
        }
        switch s.body?.metrics[key]?.good ?? "" {
        case "up": return true
        case "down": return false
        default: return nil
        }
    }

    private static func bodyNoise(_ s: PFSnapshot, key: String) -> Double? {
        switch key {
        case "weight_kg": return s.bodyProgress?.noiseWeightKg
        case "body_fat_pct": return s.bodyProgress?.noiseBodyFatPct
        default: return nil
        }
    }

    private static func loadTile(_ s: PFSnapshot, id: String, label: String, key: KeyPath<PFLoadPoint, Double>,
                                 higherIsBetter: Bool?, what: String, today: String?) -> PFAthleteMetric? {
        let history = s.insights.history
        guard let last = history.last else { return nil }
        let value = last[keyPath: key]
        let points = history.map { PFAthletePoint(date: String($0.date.prefix(10)), value: $0[keyPath: key]) }
        var tile = PFAthleteMetric(id: id, label: label, unit: "", value: value, valueText: String(format: "%.0f", value),
                                   source: "PaceForge \u{00B7} training load", what: what)
        tile.asOf = points.last?.date
        tile.series = points
        tile.anchorDate = today
        tile.change = PFAthleteMath.change(series: points, today: today, higherIsBetter: higherIsBetter)
        return tile
    }

    // MARK: Running times

    private static func runTimes(_ standing: PFStanding?, _ fit: PFAthleteFitness?) -> [PFAthleteRunTime] {
        var out: [PFAthleteRunTime] = []
        let wanted: [(String, String)] = [("run_5k", "5K"), ("run_10k", "10K"), ("run_half", "Half")]
        for (id, label) in wanted {
            guard let metric = standing?.metric(id), metric.value != nil || metric.display != nil else { continue }
            out.append(PFAthleteRunTime(id: id, label: label, text: metric.valueText, band: metric.band, standingId: id))
        }
        if let sec = fit?.halfMarathonEquivalentSec {
            out.append(PFAthleteRunTime(id: "hm_shape", label: "Half now", text: PFFormat.clock(sec), band: nil, standingId: nil))
        }
        return out
    }

    // MARK: Race predictions and heart-rate zones

    private static let distanceOrder = ["5k", "10k", "half", "marathon"]

    private static func inRaceOrder(_ list: [PFAthletePrediction]) -> [PFAthletePrediction] {
        list.sorted { (distanceOrder.firstIndex(of: $0.id) ?? 9) < (distanceOrder.firstIndex(of: $1.id) ?? 9) }
    }

    /// Garmin's forecast and PaceForge's own (VDOT) side by side, never averaged. No history of either is held in a document the app
    /// reads, so the card names the date of the forecast and draws no change.
    private static func predictions(_ profile: PFAthleteProfile?, _ analytics: PFAthleteAnalytics?) -> PFAthletePredictions? {
        let garmin = inRaceOrder(profile?.racePredictions ?? [])
        let model = inRaceOrder(analytics?.predictions ?? [])
        guard !garmin.isEmpty || !model.isEmpty else { return nil }
        return PFAthletePredictions(garmin: garmin, garminDate: profile?.racePredictionsDate, model: model, vdot: analytics?.vdot)
    }

    private static func zones(_ profile: PFAthleteProfile?) -> PFAthleteZones? {
        guard let profile, !profile.zones.isEmpty else { return nil }
        return PFAthleteZones(zones: profile.zones, sport: profile.zoneSport, maxHr: profile.zoneMaxHr, maxHrSeen: profile.maxHrSeen,
                              ltHr: profile.ltHr, restingHr: profile.restingHr, date: profile.date, sets: profile.zoneSets)
    }

    // MARK: Strengths, weaknesses, areas

    private static func strengths(_ standing: PFStanding?) -> [PFAthleteFinding] {
        guard let standing else { return [] }
        // A top-three metric that is itself only average is not called a strength.
        return standing.strongestTop
            .filter { ($0.band ?? 0) >= 3 }
            .prefix(3)
            .map { standingFinding($0, group: .strength, standing: standing) }
    }

    private static func weaknesses(_ standing: PFStanding?) -> [PFAthleteFinding] {
        guard let standing else { return [] }
        return standing.focusTop
            .prefix(3)
            .map { standingFinding($0, group: .weakness, standing: standing) }
    }

    private static func standingFinding(_ metric: PFStandingMetric, group: PFAthleteFinding.Group,
                                        standing: PFStanding) -> PFAthleteFinding {
        var evidence = metric.valueText
        if let band = metric.band, metric.isRated {
            evidence += " \u{00B7} \(metric.bandName), band \(band) of 5"
        }
        var parts: [String] = []
        if let why = metric.why { parts.append(why) }
        if let trend = metric.trend { parts.append(trend.text + ".") }
        return PFAthleteFinding(id: "standing-\(metric.id)", group: group, title: metric.label, evidence: evidence,
                                band: metric.band, tag: nil, ruleWhy: parts.isEmpty ? nil : parts.joined(separator: " "),
                                coachWhy: nil, standingId: metric.id, planId: metric.planId, tileId: nil)
    }

    private static func areas(_ s: PFSnapshot, _ fit: PFAthleteFitness?) -> [PFAthleteFinding] {
        var out: [PFAthleteFinding] = []
        let coachLimiters = s.coach.take?.limiters ?? []
        for (index, limiter) in (fit?.limiters ?? []).prefix(3).enumerated() {
            let coach = coachLimiters.first { $0.name.lowercased() == limiter.name.lowercased() }
                ?? coachLimiters.first { !limiter.area.isEmpty && $0.area.lowercased() == limiter.area.lowercased() }
            out.append(PFAthleteFinding(id: "limiter-\(index)", group: .area, title: limiter.name,
                                        evidence: limiter.evidence, band: nil,
                                        tag: limiter.area.isEmpty ? nil : PFFormat.capitalized(limiter.area),
                                        ruleWhy: limiter.evidence.isEmpty ? nil : limiter.evidence,
                                        coachWhy: coach?.recommendation, standingId: nil, planId: nil, tileId: nil))
        }
        // The HYROX stations furthest from the top three fill the rest, up to three rows.
        for station in (s.insights.hyrox?.stations ?? []) where out.count < 3 {
            let gap = PFNumber.signed(station.gapSec, decimals: 0) + " s"
            var evidence = "You \(station.athlete)"
            if !station.top3.isEmpty { evidence += " \u{00B7} top 3 average \(station.top3)" }
            evidence += " \u{00B7} \(gap)"
            out.append(PFAthleteFinding(id: "station-\(station.name)", group: .area, title: station.name, evidence: evidence,
                                        band: nil, tag: "HYROX",
                                        ruleWhy: "One of the HYROX stations furthest from the average of the top three finishers, worked out from your race results.",
                                        coachWhy: nil, standingId: nil, planId: nil, tileId: nil))
        }
        return out
    }

    // MARK: Words

    /// "What it is" for each tile detail: plain, short, and no claim beyond what the number is.
    private enum Copy {
        static let vo2max = "Garmin's wrist estimate of the most oxygen your body can use in a minute, per kilogram of body weight. A higher number is a bigger aerobic engine. It moves slowly, over weeks."
        static let thresholdPace = "Critical speed: the fastest pace you can hold through a long effort, fitted from your best efforts over several distances. A lower time per kilometre is faster."
        static let lactateThreshold = "Garmin's measure of the pace (and the heart rate) at which lactate starts to build faster than your body clears it, the edge between hard-but-steady and unsustainable. A lower time per kilometre is faster. It changes only when the watch measures it, so read the date."
        static let endurance = "Garmin's endurance score: one number for how much endurance your recent training has built, on Garmin's own scale. It moves slowly. PaceForge holds only today's value, so there is no change to show."
        static let trainingStatus = "Garmin's one-word reading of whether your recent training load is building, holding or losing fitness. It is the watch's label, not a PaceForge score."
        static let ftp = "Functional threshold power: the power you can hold for about an hour on the bike. It is the figure on file, or an estimate from your rides when none is filed."
        static let restingHr = "Your heart rate at rest, from the Garmin watch. A lower number over several weeks usually goes with better recovery and fitness."
        static let hrv = "The average of your last seven nights of heart-rate variability from the Garmin watch. It is a trend to read against your own usual, not a score."
        static let weight = "Your body weight from the scale, with the change over four weeks. Day-to-day swings smaller than the scale's own noise count as no change."
        static let bodyFat = "Body fat from the scale's impedance reading, with the change over four weeks. Day-to-day swings smaller than the scale's own noise count as no change."
        static let ctl = "Training load averaged over about six weeks: the fitness you have built. Higher means more built, not more ready today."
        static let tsb = "Fitness minus fatigue. Below zero you are carrying load, above zero you are fresher. Neither side is good or bad on its own."
    }
}
