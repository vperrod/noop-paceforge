import Foundation

// The Coach screen's three server-built panels: "Your numbers" (`api/athlete-numbers`), the readiness decision
// (`api/readiness-decision`) and the season plan (`api/season-plan`). Foundation only, so the parsing and the wording are compiled
// into the macOS unit-test bundle. Read-only. Each parser reads leniently: a missing or oddly typed field leaves its part out and
// never blanks the panel, and a payload with nothing usable parses to nil (the card then draws nothing).

// MARK: - Your numbers

/// One line of "Your numbers": a label, the figure and the small line under it (where it comes from and its date).
struct PFNumbersRow: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
    let caption: String
}

struct PFPaceBand: Equatable, Identifiable {
    let name: String
    let lowS: Double?
    let highS: Double?
    let source: String?

    var id: String { name }
    var label: String { PFFormat.capitalized(PFFormat.words(name)) }

    /// "5:20\u{2013}5:50 /km"; one end alone reads as that pace; nil when neither end was sent.
    var range: String? {
        switch (lowS, highS) {
        case let (low?, high?):
            return "\(PFFormat.pace(min(low, high)))\u{2013}\(PFFormat.pace(max(low, high))) /km"
        case let (one?, nil), let (nil, one?):
            return PFFormat.pace(one) + " /km"
        default:
            return nil
        }
    }

    var caption: String { source.map { "Source: \($0)" } ?? "Source not given" }
}

struct PFNumbersPrediction: Equatable {
    let id: String
    let seconds: Double
}

struct PFAthleteNumbers: Equatable {
    var vo2max: Double?
    var vo2maxDate: String?
    var ltPaceSecPerKm: Double?
    var ltHr: Double?
    var ltDate: String?
    /// Race predictions in seconds, shortest distance first.
    var predictions: [PFNumbersPrediction] = []
    var predictionsDate: String?
    var trainingStatus: String?
    var trainingStatusDate: String?
    /// The athlete's own setting, not a Garmin reading.
    var maxHr: Double?
    var paces: [PFPaceBand] = []

    /// Every Garmin figure and the max-HR setting as rows, in reading order; a figure the server did not send has no row.
    var rows: [PFNumbersRow] {
        var out: [PFNumbersRow] = []
        func garmin(_ date: String?) -> String { "Garmin" + (date.map { " \u{00B7} " + PFFormat.shortDate($0) } ?? "") }
        if let v = vo2max { out.append(PFNumbersRow(id: "vo2max", label: "VO2max", value: PFFormat.trimmed(v) + " ml/kg/min", caption: garmin(vo2maxDate))) }
        if let v = ltPaceSecPerKm { out.append(PFNumbersRow(id: "lt-pace", label: "Lactate threshold pace", value: PFFormat.pace(v) + " /km", caption: garmin(ltDate))) }
        if let v = ltHr { out.append(PFNumbersRow(id: "lt-hr", label: "Lactate threshold heart rate", value: PFFormat.trimmed(v) + " bpm", caption: garmin(ltDate))) }
        if let v = trainingStatus { out.append(PFNumbersRow(id: "status", label: "Training status", value: v, caption: garmin(trainingStatusDate))) }
        for p in predictions {
            out.append(PFNumbersRow(id: "pred-" + p.id, label: Self.predictionLabel(p.id) + " prediction", value: PFFormat.clock(p.seconds),
                                    caption: garmin(predictionsDate)))
        }
        if let v = maxHr { out.append(PFNumbersRow(id: "max-hr", label: "Max heart rate", value: PFFormat.trimmed(v) + " bpm", caption: "your setting")) }
        return out
    }

    static func predictionLabel(_ id: String) -> String {
        switch id {
        case "k5": return "5K"
        case "k10": return "10K"
        case "half": return "Half marathon"
        case "marathon": return "Marathon"
        default: return PFFormat.capitalized(PFFormat.words(id))
        }
    }
}

enum PFCoachNumbers {
    private static let predictionKeys = ["k5", "k10", "half", "marathon"]

    /// nil when the payload holds no figure at all.
    static func athleteNumbers(_ data: Data?) -> PFAthleteNumbers? {
        let root = PFJ(data: data)
        guard !root.dict.isEmpty else { return nil }
        let garmin = root["garmin"]
        var out = PFAthleteNumbers()
        out.vo2max = positive(garmin["vo2max"]["value"])
        out.vo2maxDate = garmin["vo2max"]["date"].text
        out.ltPaceSecPerKm = positive(garmin["lt"]["pace_s_per_km"])
        out.ltHr = positive(garmin["lt"]["hr"])
        out.ltDate = garmin["lt"]["date"].text
        let predictions = garmin["predictions"]
        out.predictions = predictionKeys.compactMap { key in positive(predictions[key]).map { PFNumbersPrediction(id: key, seconds: $0) } }
        out.predictionsDate = predictions["date"].text
        out.trainingStatus = statusText(garmin["training_status"]["value"])
        out.trainingStatusDate = garmin["training_status"]["date"].text
        out.maxHr = positive(root["max_hr"]["value"])
        out.paces = root["paces"].array.compactMap { band -> PFPaceBand? in
            guard let name = band["name"].text else { return nil }
            let low = positive(band["low_s"]), high = positive(band["high_s"])
            guard low != nil || high != nil else { return nil }
            return PFPaceBand(name: name, lowS: low, highS: high, source: band["source"].text)
        }
        let empty = out.rows.isEmpty && out.paces.isEmpty
        return empty ? nil : out
    }

    private static func positive(_ j: PFJ) -> Double? {
        guard let v = j.double, v.isFinite, v > 0 else { return nil }
        return v
    }

    private static func statusText(_ j: PFJ) -> String? {
        if let s = j.text { return PFFormat.capitalized(PFFormat.words(s)) }
        return j.double.map { PFFormat.trimmed($0) }
    }
}

// MARK: - Readiness

enum PFStatusTone: Int, Equatable {
    case unknown, good, caution, bad

    /// A status or band word as the colour it should draw in. The server's vocabulary is open, so an unknown word stays neutral.
    static func of(_ status: String?) -> PFStatusTone {
        guard let s = status?.lowercased(), !s.isEmpty else { return .unknown }
        let tokens = Set(s.split { !$0.isLetter }.map(String.init))
        func has(_ words: [String]) -> Bool { words.contains { tokens.contains($0) } }
        if s.contains("very low") || has(["red", "poor", "bad", "critical", "compromised", "depleted", "strained"]) { return .bad }
        if has(["yellow", "amber", "orange", "caution", "warn", "warning", "fair", "moderate", "low", "high", "elevated", "suppressed",
                "below", "above", "reduced", "watch"]) { return .caution }
        if has(["green", "good", "ok", "normal", "optimal", "ready", "recovered", "stable", "balanced", "within", "steady", "strong"]) {
            return .good
        }
        return .unknown
    }
}

/// One reading of one device. A reading the device did not have (`available` false) has no value and says why in `reason`.
struct PFDeviceMetric: Equatable, Identifiable {
    let id: String
    let name: String
    let value: String?
    let unit: String?
    let status: String?
    let baseline: String?
    var reason: String? = nil
    /// Deep and REM sleep: shown, never fed to the decision.
    var isNotUsedForDecisions = false

    var tone: PFStatusTone { PFStatusTone.of(status) }

    static let notUsedNote = "not used for decisions"
}

/// The device's own score (Garmin training readiness, WHOOP recovery) with the band the server put it in. Never combined across devices.
struct PFDeviceScore: Equatable {
    let label: String
    let value: String
    let band: String?

    var tone: PFStatusTone { PFStatusTone.of(band) }
}

struct PFDeviceLoad: Equatable {
    let measure: String
    let thisWeek: String?
    let lastWeek: String?
    let changePct: String?
    let ramp: Bool

    /// "Garmin training load (7-day): 699 this week, 723 last week (-3.3%)".
    var line: String {
        var parts: [String] = []
        if let thisWeek { parts.append(thisWeek + " this week") }
        if let lastWeek { parts.append(lastWeek + " last week") }
        var text = measure + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", "))
        if let changePct { text += " (" + (changePct.hasPrefix("-") ? "" : "+") + changePct + "%)" }
        return text
    }
}

struct PFDeviceBlock: Equatable {
    var label: String?
    var available = true
    /// The server's own call on whether last night was poor for this device; nil when it did not say.
    var poor: Bool?
    var poorFlags: [String] = []
    /// Poor on several recent nights.
    var trend = false
    var score: PFDeviceScore?
    var metrics: [PFDeviceMetric] = []
    var shownOnly: [PFDeviceMetric] = []
    var illnessPossible = false
    var method: String?
    var load: PFDeviceLoad?

    var isEmpty: Bool { metrics.isEmpty && shownOnly.isEmpty && score == nil && poor == nil && load == nil }
}

struct PFReadinessCall: Equatable {
    let action: String?
    let rule: String?
    let reasons: [String]
    let question: String?
    let confidence: String?
    let raceGuard: String?
    /// What to look at yourself ("resting HR", "respiration").
    let check: [String]

    /// The call as one plain sentence.
    var sentence: String {
        let key = (action ?? "").lowercased().replacingOccurrences(of: " ", with: "_")
        switch key {
        case "go", "proceed", "keep", "as_planned", "train", "hold", "maintain", "green":
            return "Train as planned today."
        case "ease", "easy", "reduce", "scale", "scale_down", "back_off", "soften", "downgrade", "yellow":
            return "Ease today's session."
        case "rest", "skip", "off", "recover", "stop", "red":
            return "Rest today."
        case "none", "no_change", "unchanged":
            return "No change to your plan today."
        case "":
            return "No call for today yet."
        default:
            return "The coach's call today: " + PFFormat.words(key) + "."
        }
    }

    var ruleLine: String? { rule.map { "Rule: " + PFFormat.words($0) } }
    var checkLine: String? { check.isEmpty ? nil : "Check: " + check.joined(separator: ", ") }
}

enum PFDeviceAgreement: Equatable { case agree, split }

struct PFDeviceReadiness: Equatable {
    var date: String?
    var garmin: PFDeviceBlock?
    var whoop: PFDeviceBlock?
    var decision: PFReadinessCall?
    /// The note under the load figures ("No ramp on either device ...").
    var loadNote: String?

    /// Agree when both devices are poor or both are not; split when only one is. No combined number: nil when either did not say.
    var agreement: PFDeviceAgreement? {
        guard let g = garmin?.poor, let w = whoop?.poor else { return nil }
        return g == w ? .agree : .split
    }
}

enum PFDeviceReadinessParse {
    /// nil when there is neither a device block with something in it nor a decision.
    static func readiness(_ data: Data?) -> PFDeviceReadiness? {
        let root = PFJ(data: data)
        guard !root.dict.isEmpty else { return nil }
        var out = PFDeviceReadiness(date: root["date"].text, garmin: device(root["devices"]["garmin"], load: root["load"]["garmin"]),
                                    whoop: device(root["devices"]["whoop"], load: root["load"]["whoop"]),
                                    decision: decision(root["decision"]), loadNote: root["load"]["note"].text)
        if out.garmin?.isEmpty == true { out.garmin = nil }
        if out.whoop?.isEmpty == true { out.whoop = nil }
        return out.garmin == nil && out.whoop == nil && out.decision == nil ? nil : out
    }

    static func decision(_ j: PFJ) -> PFReadinessCall? {
        let action = j["action"].text, rule = j["rule"].text
        guard action != nil || rule != nil else { return nil }
        let guardText: String? = j["race_guard"].text ?? (j["race_guard"].bool == true ? "On" : nil)
        return PFReadinessCall(action: action, rule: rule, reasons: cleaned(j["reasons"]), question: j["question"].text,
                               confidence: scalarText(j["confidence"]), raceGuard: guardText, check: cleaned(j["check"]))
    }

    private static func cleaned(_ j: PFJ) -> [String] {
        j.strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The order the readings are drawn in; a reading the server adds later follows, alphabetically.
    private static let order = ["hrv", "rhr", "sleep_min", "resp", "skin_temp"]

    private static func device(_ j: PFJ, load: PFJ) -> PFDeviceBlock? {
        guard j.exists || load.exists else { return nil }
        var out = PFDeviceBlock()
        out.label = j["label"].text
        out.available = j["available"].bool ?? true
        out.poor = j["poor"].bool
        out.poorFlags = cleaned(j["poor_flags"])
        out.trend = j["trend"].bool ?? false
        out.method = j["hrv_method"].text
        out.illnessPossible = j["illness"]["possible"].bool ?? false
        let score = j["score"]
        if score["available"].bool != false, let value = scalarText(score["value"]) {
            out.score = PFDeviceScore(label: PFFormat.capitalized(score["label"].text ?? "score"), value: value, band: score["band"].text)
        }
        out.metrics = j["metrics"].dict.compactMap { key, entry -> PFDeviceMetric? in metric(id: key, entry) }.sorted { a, b in
            let (ra, rb) = (order.firstIndex(of: a.id) ?? order.count, order.firstIndex(of: b.id) ?? order.count)
            return ra != rb ? ra < rb : a.id < b.id
        }
        out.shownOnly = ["deep", "rem"].compactMap { key -> PFDeviceMetric? in
            let entry = j["shown_only"][key]
            guard let value = scalarText(entry["value"]) else { return nil }
            return PFDeviceMetric(id: key, name: displayName(key) + " sleep", value: value, unit: entry["unit"].text, status: nil, baseline: nil,
                                  isNotUsedForDecisions: true)
        }
        out.load = load["available"].bool == false ? nil : loadLine(load)
        return out
    }

    private static func loadLine(_ j: PFJ) -> PFDeviceLoad? {
        guard let measure = j["measure"].text else { return nil }
        return PFDeviceLoad(measure: measure, thisWeek: scalarText(j["this_week"]), lastWeek: scalarText(j["last_week"]),
                            changePct: scalarText(j["change_pct"]), ramp: j["ramp"].bool ?? false)
    }

    private static func metric(id: String, _ entry: PFJ) -> PFDeviceMetric? {
        guard !entry.dict.isEmpty else { return nil }
        let name = displayName(entry["label"].text ?? id)
        guard entry["available"].bool != false else {
            return PFDeviceMetric(id: id, name: name, value: nil, unit: nil, status: nil, baseline: nil, reason: entry["reason"].text ?? "no reading")
        }
        guard let value = scalarText(entry["value"]) else { return nil }
        return PFDeviceMetric(id: id, name: name, value: value, unit: entry["unit"].text, status: entry["status"].text,
                              baseline: scalarText(entry["baseline"]))
    }

    /// "deep_sleep" reads "Deep sleep"; the usual abbreviations keep their capitals.
    private static func displayName(_ raw: String) -> String {
        let acronyms = ["hrv": "HRV", "rhr": "RHR", "hr": "HR", "rem": "REM", "spo2": "SpO2"]
        let words = PFFormat.words(raw).split(separator: " ").map { acronyms[$0.lowercased()] ?? String($0) }
        return PFFormat.capitalized(words.joined(separator: " "))
    }

    private static func scalarText(_ j: PFJ) -> String? {
        if let s = j.text { return s }
        if let d = j.double, d.isFinite { return PFFormat.trimmed(d) }
        return nil
    }
}

// MARK: - Season plan

struct PFSeasonRace: Equatable, Identifiable {
    let date: String
    let name: String
    let priority: String?
    /// The priority was guessed by the server, not set by the athlete.
    let assumed: Bool

    var id: String { date + "|" + name }
    var priorityLabel: String? { priority.map { "Priority " + $0 } }
    static let assumedNote = "Assumed priority \u{2013} set it in the app"
}

struct PFSeasonBlock: Equatable, Identifiable {
    let start: String
    let end: String
    let kind: String
    let aim: String?
    let race: String?

    var id: String { start + "|" + kind }
    var title: String { PFFormat.capitalized(PFFormat.words(kind)) }
    var span: String { PFFormat.span(String(start.prefix(10)), String(end.prefix(10))) }
}

struct PFSeasonPlan: Equatable {
    var races: [PFSeasonRace] = []
    var blocks: [PFSeasonBlock] = []
    /// The block the server marked as current, when it sent the block itself; a name or an index is resolved by `current(today:)`.
    var declaredCurrent: PFSeasonBlock?
    var declaredKind: String?
    var weekRules: [String] = []

    /// The block now: the one the server named, else the one whose dates hold today.
    func current(today: String) -> PFSeasonBlock? {
        if let declaredCurrent { return declaredCurrent }
        func holdsToday(_ b: PFSeasonBlock) -> Bool { String(b.start.prefix(10)) <= today && today <= String(b.end.prefix(10)) }
        if let kind = declaredKind?.lowercased() {
            let named = blocks.filter { $0.kind.lowercased() == kind }
            if let hit = named.first(where: holdsToday) ?? named.first { return hit }
        }
        return blocks.first(where: holdsToday)
    }
}

enum PFSeasonItem: Equatable, Identifiable {
    case race(PFSeasonRace)
    case block(PFSeasonBlock, isCurrent: Bool)

    var id: String {
        switch self {
        case .race(let r): return "race|" + r.id
        case .block(let b, _): return "block|" + b.id
        }
    }

    var sortDate: String {
        switch self {
        case .race(let r): return String(r.date.prefix(10))
        case .block(let b, _): return String(b.start.prefix(10))
        }
    }
}

enum PFSeasonParse {
    /// nil when the plan has no race and no block.
    static func plan(_ data: Data?) -> PFSeasonPlan? {
        let root = PFJ(data: data)
        var out = PFSeasonPlan()
        out.races = root["races"].array.compactMap { r -> PFSeasonRace? in
            guard let date = r["date"].text, let name = r["name"].text else { return nil }
            let priority = r["priority"].idString?.trimmingCharacters(in: .whitespaces)
            return PFSeasonRace(date: date, name: name, priority: (priority?.isEmpty ?? true) ? nil : priority,
                                assumed: r["assumed"].bool ?? false)
        }
        out.blocks = root["blocks"].array.compactMap(block)
        let current = root["current_block"]
        if current.string != nil {
            out.declaredKind = current.text
        } else if let index = current.int, out.blocks.indices.contains(index) {
            out.declaredCurrent = out.blocks[index]
        } else {
            out.declaredCurrent = block(current)
        }
        out.weekRules = root["week_rules"].array.compactMap { rule in
            rule.text ?? rule["why"].text ?? rule["text"].text ?? rule["rule"].text ?? rule["name"].text
        }
        return out.races.isEmpty && out.blocks.isEmpty ? nil : out
    }

    private static func block(_ j: PFJ) -> PFSeasonBlock? {
        guard let start = j["start"].text else { return nil }
        return PFSeasonBlock(start: start, end: j["end"].text ?? start, kind: j["kind"].text ?? "block", aim: j["aim"].text, race: j["race"].text)
    }

    /// Races and blocks still to come, earliest first. A block that ended before today and a race already run are left out, and so is a
    /// race-day block: its race has its own row.
    static func timeline(_ plan: PFSeasonPlan, today: String) -> [PFSeasonItem] {
        let current = plan.current(today: today)
        let blocks = plan.blocks.filter { String($0.end.prefix(10)) >= today && $0.kind.lowercased() != "race" }.map { PFSeasonItem.block($0, isCurrent: $0 == current) }
        let races = plan.races.filter { String($0.date.prefix(10)) >= today }.map { PFSeasonItem.race($0) }
        return (blocks + races).enumerated().sorted { a, b in
            a.element.sortDate != b.element.sortDate ? a.element.sortDate < b.element.sortDate : a.offset < b.offset
        }.map(\.element)
    }
}
