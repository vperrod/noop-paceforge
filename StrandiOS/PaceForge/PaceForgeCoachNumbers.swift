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

    /// A status word as the colour it should draw in. The server's vocabulary is open, so an unknown word stays neutral.
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

struct PFDeviceMetric: Equatable, Identifiable {
    let id: String
    let name: String
    let value: String?
    let unit: String?
    let status: String?
    let baseline: String?

    var tone: PFStatusTone { PFStatusTone.of(status) }

    /// Deep and REM sleep are shown but never feed the decision.
    var isNotUsedForDecisions: Bool {
        let tokens = id.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return tokens.contains("deep") || tokens.contains("rem")
    }

    static let notUsedNote = "not used for decisions"
}

struct PFDeviceBlock: Equatable {
    var metrics: [PFDeviceMetric] = []
    var load: [PFDeviceMetric] = []
    var method: String?
    var status: String?

    var isEmpty: Bool { metrics.isEmpty && load.isEmpty && status == nil }

    /// The device's own status word when it sent one, else the worst tone among the metrics that feed the decision.
    var tone: PFStatusTone {
        let own = PFStatusTone.of(status)
        if own != .unknown { return own }
        return metrics.filter { !$0.isNotUsedForDecisions }.map(\.tone).max { $0.rawValue < $1.rawValue } ?? .unknown
    }
}

struct PFReadinessCall: Equatable {
    let action: String?
    let rule: String?
    let reasons: [String]
    let question: String?
    let confidence: String?
    let raceGuard: String?

    /// The call as one plain sentence; the first reason rides along when the server gave one.
    var sentence: String {
        let key = (action ?? "").lowercased().replacingOccurrences(of: " ", with: "_")
        var base: String
        switch key {
        case "go", "proceed", "keep", "as_planned", "train", "hold", "maintain", "green":
            base = "Train as planned today"
        case "ease", "easy", "reduce", "scale", "scale_down", "back_off", "soften", "downgrade", "yellow":
            base = "Ease today's session"
        case "rest", "skip", "off", "recover", "stop", "red":
            base = "Rest today"
        case "":
            base = "No call for today yet"
        default:
            base = "The coach's call today: " + PFFormat.words(key)
        }
        if let reason = reasons.first {
            let trimmed = reason.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            if !trimmed.isEmpty { base += ": " + trimmed }
        }
        return base + "."
    }

    var ruleLine: String? { rule.map { "Rule: " + PFFormat.words($0) } }
}

enum PFDeviceAgreement: Equatable { case agree, split }

struct PFDeviceReadiness: Equatable {
    var date: String?
    var garmin: PFDeviceBlock?
    var whoop: PFDeviceBlock?
    var decision: PFReadinessCall?

    /// Whether the two devices read the same colour. There is no combined number: this is a mark, nil when either has no reading.
    var agreement: PFDeviceAgreement? {
        guard let g = garmin?.tone, let w = whoop?.tone, g != .unknown, w != .unknown else { return nil }
        return g == w ? .agree : .split
    }
}

enum PFDeviceReadinessParse {
    /// nil when there is neither a device block with something in it nor a decision.
    static func readiness(_ data: Data?) -> PFDeviceReadiness? {
        let root = PFJ(data: data)
        guard !root.dict.isEmpty else { return nil }
        let rootMethod = root["method"].text
        var out = PFDeviceReadiness(date: root["date"].text,
                              garmin: device(root["devices"]["garmin"], load: root["load"]["garmin"], rootMethod: rootMethod),
                              whoop: device(root["devices"]["whoop"], load: root["load"]["whoop"], rootMethod: rootMethod),
                              decision: decision(root["decision"]))
        if out.garmin?.isEmpty == true { out.garmin = nil }
        if out.whoop?.isEmpty == true { out.whoop = nil }
        return out.garmin == nil && out.whoop == nil && out.decision == nil ? nil : out
    }

    static func decision(_ j: PFJ) -> PFReadinessCall? {
        let action = j["action"].text, rule = j["rule"].text
        guard action != nil || rule != nil else { return nil }
        let guardText: String? = j["race_guard"].text ?? (j["race_guard"].bool == true ? "On" : nil)
        return PFReadinessCall(action: action, rule: rule, reasons: j["reasons"].strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                                   question: j["question"].text, confidence: scalarText(j["confidence"]), raceGuard: guardText)
    }

    private static func device(_ j: PFJ, load: PFJ, rootMethod: String?) -> PFDeviceBlock? {
        guard j.exists || load.exists else { return nil }
        return PFDeviceBlock(metrics: metrics(j), load: metrics(load), method: j["method"].text ?? load["method"].text ?? rootMethod,
                                 status: j["status"].text)
    }

    /// Keys of a device block that describe the block, not a metric.
    private static let reserved: Set<String> = ["method", "status", "date", "source", "name", "note", "notes", "available", "updated_at",
                                                "as_of", "load", "metrics"]
    private static let order = ["recovery", "readiness", "hrv", "rhr", "resting", "sleep", "strain", "load", "respiratory", "temp", "spo2"]

    /// Per-metric entries from a block that is either a list of metric objects, a map of name to metric (or bare value), or either of
    /// those under `metrics`. Whatever entries exist are returned; one that has neither a value nor a status is skipped.
    static func metrics(_ block: PFJ) -> [PFDeviceMetric] {
        let inner = block["metrics"]
        let container = inner.exists ? inner : block
        if container.raw is [Any] {
            return container.array.enumerated().compactMap { index, entry -> PFDeviceMetric? in
                let name = entry["name"].text ?? entry["metric"].text ?? entry["key"].text
                return metric(id: name ?? "metric-\(index)", name: name, entry)
            }
        }
        let useReserved = !inner.exists
        return container.dict.compactMap { key, entry -> PFDeviceMetric? in
            if useReserved && reserved.contains(key) { return nil }
            return metric(id: key, name: entry["name"].text, entry)
        }.sorted { a, b in
            let (ra, rb) = (rank(a.id), rank(b.id))
            return ra != rb ? ra < rb : a.id < b.id
        }
    }

    private static func rank(_ key: String) -> Int {
        let k = key.lowercased()
        return order.firstIndex { k.contains($0) } ?? order.count
    }

    private static func metric(id: String, name: String?, _ entry: PFJ) -> PFDeviceMetric? {
        let isObject = !entry.dict.isEmpty
        let value = isObject ? (scalarText(entry["value"]) ?? entry["value_text"].text) : scalarText(entry)
        let status = isObject ? entry["status"].text : nil
        guard value != nil || status != nil else { return nil }
        let baseline = isObject ? (scalarText(entry["baseline"]) ?? scalarText(entry["baseline"]["value"]) ?? scalarText(entry["baseline"]["mean"])
                                    ?? scalarText(entry["baseline"]["median"])) : nil
        return PFDeviceMetric(id: id, name: displayName(name ?? id), value: value,
                                 unit: isObject ? entry["unit"].text : nil, status: status, baseline: baseline)
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
            rule.text ?? rule["text"].text ?? rule["rule"].text ?? rule["name"].text
        }
        return out.races.isEmpty && out.blocks.isEmpty ? nil : out
    }

    private static func block(_ j: PFJ) -> PFSeasonBlock? {
        guard let start = j["start"].text else { return nil }
        return PFSeasonBlock(start: start, end: j["end"].text ?? start, kind: j["kind"].text ?? "block", aim: j["aim"].text, race: j["race"].text)
    }

    /// Races and blocks still to come, earliest first (a block that ended before today and a race already run are left out).
    static func timeline(_ plan: PFSeasonPlan, today: String) -> [PFSeasonItem] {
        let current = plan.current(today: today)
        let blocks = plan.blocks.filter { String($0.end.prefix(10)) >= today }.map { PFSeasonItem.block($0, isCurrent: $0 == current) }
        let races = plan.races.filter { String($0.date.prefix(10)) >= today }.map { PFSeasonItem.race($0) }
        return (blocks + races).enumerated().sorted { a, b in
            a.element.sortDate != b.element.sortDate ? a.element.sortDate < b.element.sortDate : a.offset < b.offset
        }.map(\.element)
    }
}
