import Foundation

// "Where you stand": PaceForge's standing.json, the scorecard of the athlete's measured numbers against
// published norms. Foundation only, so the parsing and the pure helpers below (band bars, the summary strip,
// trend wording, the Telegram phrase) are compiled into the macOS unit-test bundle as well.
//
// Every field is optional on the wire. A missing file, a missing section or a metric with no band simply
// leaves that part out; nothing here is ever worked out from the athlete's data on the phone. The app only
// reads: the field tests in the test-day card are logged in Telegram.

// MARK: - Bands

/// The five bands a metric is rated into, and the pure helpers the bars and the summary strip draw from.
enum PFBand {
    /// Neutral names, lowest band first. A server label wins when it sends one.
    static let names = ["Poor", "Average", "Good", "Very good", "Elite"]
    static let notRated = "Not rated"

    static func isRated(_ band: Int?) -> Bool {
        guard let band else { return false }
        return (1...5).contains(band)
    }

    /// The band's name: the server's label when it sent one, else the fixed name, else "Not rated".
    static func name(band: Int?, serverLabel: String?) -> String {
        if let label = serverLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        guard let band, isRated(band) else { return notRated }
        return names[band - 1]
    }

    /// One segment of the five-segment bar. `current` is the metric's own band; the ones below it are
    /// `reached` and the ones above it `ahead`. An unrated metric has five `unrated` segments (drawn grey).
    enum Segment: Equatable {
        case reached, current, ahead, unrated
    }

    static func segments(for band: Int?) -> [Segment] {
        guard let band, isRated(band) else { return Array(repeating: .unrated, count: 5) }
        return (1...5).map { index in
            if index < band { return .reached }
            return index == band ? .current : .ahead
        }
    }

    /// The summary strip: each band's share of the rated-and-unrated metrics, in the order poor, average,
    /// good, very good, elite, not rated. Counts below zero count as zero; an all-zero list gives all zeros.
    static func stripFractions(counts: [Int]) -> [Double] {
        let clean = counts.map { max(0, $0) }
        let total = clean.reduce(0, +)
        guard total > 0 else { return clean.map { _ in 0 } }
        return clean.map { Double($0) / Double(total) }
    }

    /// What VoiceOver reads for a metric row: "Resting heart rate, 58 bpm. Good, band 3 of 5."
    static func accessibilityText(label: String, value: String, band: Int?, serverLabel: String?) -> String {
        if isRated(band), let band {
            return "\(label), \(value). \(name(band: band, serverLabel: serverLabel)), band \(band) of 5."
        }
        return "\(label), \(value). Not rated."
    }
}

// MARK: - Model

struct PFStandingProfile: Equatable {
    var age: Int?
    var sex: String?
    var heightCm: Double?
    var weightKg: Double?
    var normsPack: String?
    /// False when the norms cannot be applied (no sex or age on file); then `note` says what is missing.
    var applicable: Bool?
    var note: String?
}

struct PFStandingNorm: Equatable {
    var poor: String?
    var average: String?
    var good: String?
    var veryGood: String?
    var elite: String?

    struct Row: Identifiable, Equatable {
        var band: Int
        var name: String
        var text: String
        var id: Int { band }
    }

    /// The norm table, one row per band, lowest first. Bands the server sent no text for are left out.
    var rows: [Row] {
        let texts = [poor, average, good, veryGood, elite]
        return texts.enumerated().compactMap { index, text in
            guard let text, !text.isEmpty else { return nil }
            return Row(band: index + 1, name: PFBand.names[index], text: text)
        }
    }

    var isEmpty: Bool { rows.isEmpty }
}

struct PFStandingSource: Equatable {
    /// The server's short tag, shown as a chip: PR, VB or RC.
    var tag: String?
    var label: String?
    var url: String?
}

struct PFStandingTrend: Equatable {
    var direction: String?
    var change: Double?
    var windowDays: Int?
    /// True when the change is toward a better band, false when away from it, nil when unknown.
    var improving: Bool?

    private var normalised: String {
        switch (direction ?? "").lowercased() {
        case "up", "rising", "increasing", "increase", "higher": return "up"
        case "down", "falling", "decreasing", "decrease", "lower": return "down"
        default: return "flat"
        }
    }

    /// SF Symbol for the arrow.
    var symbol: String {
        switch normalised {
        case "up": return "arrow.up.right"
        case "down": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    /// "Up 2.4 over 30 days", "Down 1.2 over 30 days", "Flat over 30 days". Neutral: no good or bad wording.
    var text: String {
        let window = windowDays.map { " over \($0) days" } ?? ""
        switch normalised {
        case "up", "down":
            let word = normalised == "up" ? "Up" : "Down"
            if let change {
                return "\(word) \(PFNumber.trimmedOne(abs(change)))\(window)"
            }
            return word + window
        default:
            return "Flat" + (window.isEmpty ? "" : window)
        }
    }
}

struct PFStandingMetric: Identifiable, Equatable {
    var id: String
    var label: String
    var value: Double?
    var display: String?
    var unit: String?
    /// 1 (poor) to 5 (elite); nil when the metric is not rated.
    var band: Int?
    var bandLabel: String?
    var norm: PFStandingNorm?
    var source: PFStandingSource?
    var confidence: String?
    var why: String?
    var trend: PFStandingTrend?
    var planId: String?
    var note: String?

    var isRated: Bool { PFBand.isRated(band) }
    var bandName: String { PFBand.name(band: isRated ? band : nil, serverLabel: isRated ? bandLabel : nil) }
    var isLowConfidence: Bool { (confidence ?? "").lowercased() == "low" }

    /// The value as shown: the server's own text, else the number, else a dash. The unit is added only when
    /// the server's text does not already carry it.
    var valueText: String {
        var text = display
        if text == nil, let value { text = PFNumber.trimmed(value) }
        guard var shown = text, !shown.isEmpty else { return "\u{2014}" }
        if let unit, !unit.isEmpty, !shown.contains(unit) { shown += " " + unit }
        return shown
    }

    var accessibilityText: String {
        PFBand.accessibilityText(label: label, value: valueText, band: band, serverLabel: bandLabel)
    }

    /// `valueText`, or the Hide-numbers placeholder in its place.
    func valueText(hidden: Bool) -> String { hidden ? PFRedact.placeholder : valueText }

    /// What VoiceOver reads: the placeholder instead of the number while hidden.
    func accessibilityText(hidden: Bool) -> String {
        PFBand.accessibilityText(label: label, value: valueText(hidden: hidden), band: band, serverLabel: bandLabel)
    }

    /// The Hide-numbers switch that covers this metric, if any.
    var hideKind: PFRedact.Kind? { PFRedact.kind(forStandingMetric: id) }
}

struct PFStandingDomain: Identifiable, Equatable {
    var id: String
    var title: String
    var metrics: [PFStandingMetric] = []
}

struct PFStandingSummary: Equatable {
    var poor = 0
    var average = 0
    var good = 0
    var veryGood = 0
    var elite = 0
    var notRated = 0
    var strongest: [String] = []
    var focus: [String] = []
    var unrated: [String] = []

    /// Counts in strip order: poor, average, good, very good, elite, not rated.
    var counts: [Int] { [poor, average, good, veryGood, elite, notRated] }
    var total: Int { counts.reduce(0, +) }
}

struct PFStandingPlan: Identifiable, Equatable {
    var id: String
    var title: String
    var why: String?
    var steps: [String] = []
    var measure: String?
    var dont: String?
    var evidence: String?
    var timeframe: String?
}

struct PFTestDay: Equatable {
    struct Logged: Equatable {
        var value: Double?
        var display: String?
        var date: String?
    }

    struct Test: Identifiable, Equatable {
        var id: String
        var label: String
        var unit: String?
        var how: String?
        var normNote: String?
        var logged: Logged?
    }

    var intro: String?
    var tests: [Test] = []
}

struct PFStanding: Equatable {
    var generatedAt: String?
    var profile: PFStandingProfile?
    var domains: [PFStandingDomain] = []
    var summary: PFStandingSummary?
    var plansIntro: String?
    var plans: [PFStandingPlan] = []
    var testDay: PFTestDay?

    /// False only when the server says the norms cannot be applied; an absent flag means they can.
    var isApplicable: Bool { profile?.applicable ?? true }

    var metrics: [PFStandingMetric] { domains.flatMap(\.metrics) }

    /// Whether any part of the scorecard has something to show. A not-applicable profile still shows its note.
    var hasContent: Bool {
        if !isApplicable { return profile != nil }
        return !metrics.isEmpty || testDay != nil
    }

    func metric(_ id: String) -> PFStandingMetric? { metrics.first { $0.id == id } }

    func plan(_ id: String?) -> PFStandingPlan? {
        guard let id else { return nil }
        return plans.first { $0.id == id }
    }

    /// The metrics a list of ids names, in that order; ids the document does not carry are skipped.
    func metrics(ids: [String]) -> [PFStandingMetric] { ids.compactMap { metric($0) } }

    /// The three strongest and three focus metrics for the header chips.
    var strongestTop: [PFStandingMetric] { Array(metrics(ids: summary?.strongest ?? []).prefix(3)) }
    var focusTop: [PFStandingMetric] { Array(metrics(ids: summary?.focus ?? []).prefix(3)) }

    /// "Strongest: A, B. Focus: C." for the compact Today card and the dismiss text.
    var summaryLines: (strongest: String?, focus: String?) {
        func join(_ list: [PFStandingMetric]) -> String? {
            list.isEmpty ? nil : list.map(\.label).joined(separator: ", ")
        }
        return (join(strongestTop), join(focusTop))
    }
}

// MARK: - Telegram phrase

/// The phrase a field test is logged with, taken from the test's own `how` text, never made up here.
enum PFTestPhrase {
    /// The text between the first pair of quotes in `how` (straight or curly): `Telegram e.g. "push-ups 35"`
    /// gives `push-ups 35`. With no quotes, a short `how` (60 characters or fewer) is the phrase itself; a
    /// longer one is a description, not a phrase, and gives nil.
    static func telegram(from how: String?) -> String? {
        guard let how = how?.trimmingCharacters(in: .whitespacesAndNewlines), !how.isEmpty else { return nil }
        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}")]
        var best: (offset: Int, text: String)?
        for (open, close) in pairs {
            guard let start = how.firstIndex(of: open) else { continue }
            let after = how.index(after: start)
            guard let end = how[after...].firstIndex(of: close) else { continue }
            let inner = String(how[after..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { continue }
            let offset = how.distance(from: how.startIndex, to: start)
            if best == nil || offset < best!.offset { best = (offset, inner) }
        }
        if let best { return best.text }
        return how.count <= 60 ? how : nil
    }
}

// MARK: - Parsing

enum PFStandingParse {
    static func standing(_ j: PFJ) -> PFStanding? {
        guard j.exists, j.raw is [String: Any] else { return nil }
        var out = PFStanding()
        out.generatedAt = j["generated_at"].text
        out.profile = profile(j["profile"])
        out.domains = j["domains"].array.compactMap(domain)
        out.summary = summary(j["summary"])
        out.plansIntro = j["plans_intro"].text
        out.plans = j["plans"].array.compactMap(plan)
        out.testDay = testDay(j["test_day"])
        return out.profile == nil && out.domains.isEmpty && out.plans.isEmpty && out.testDay == nil ? nil : out
    }

    private static func profile(_ p: PFJ) -> PFStandingProfile? {
        guard p.exists else { return nil }
        return PFStandingProfile(age: p["age"].int, sex: p["sex"].text, heightCm: p["height_cm"].double,
                                 weightKg: p["weight_kg"].double, normsPack: p["norms_pack"].text,
                                 applicable: p["applicable"].bool, note: p["note"].text)
    }

    private static func domain(_ d: PFJ) -> PFStandingDomain? {
        guard let id = d["id"].idString else { return nil }
        let metrics = d["metrics"].array.compactMap(metric)
        return PFStandingDomain(id: id, title: d["title"].text ?? PFBand.titleFromId(id), metrics: metrics)
    }

    private static func metric(_ m: PFJ) -> PFStandingMetric? {
        guard let id = m["id"].idString, let label = m["label"].text else { return nil }
        var out = PFStandingMetric(id: id, label: label)
        out.value = m["value"].double
        out.display = m["display"].text ?? m["display"].double.map { PFNumber.trimmed($0) }
        out.unit = m["unit"].text
        if let band = m["band"].int, PFBand.isRated(band) { out.band = band }
        out.bandLabel = m["band_label"].text
        out.norm = norm(m["norm"])
        out.source = source(m["source"])
        out.confidence = m["confidence"].text
        out.why = m["why"].text
        out.trend = trend(m["trend"])
        out.planId = m["plan_id"].idString
        out.note = m["note"].text
        return out
    }

    private static func norm(_ n: PFJ) -> PFStandingNorm? {
        guard n.exists else { return nil }
        let out = PFStandingNorm(poor: n["poor"].text, average: n["average"].text, good: n["good"].text,
                                 veryGood: n["very_good"].text, elite: n["elite"].text)
        return out.isEmpty ? nil : out
    }

    private static func source(_ s: PFJ) -> PFStandingSource? {
        guard s.exists else { return nil }
        let out = PFStandingSource(tag: s["tag"].text, label: s["label"].text, url: s["url"].text)
        return out.tag == nil && out.label == nil && out.url == nil ? nil : out
    }

    private static func trend(_ t: PFJ) -> PFStandingTrend? {
        guard t.exists else { return nil }
        let out = PFStandingTrend(direction: t["direction"].text, change: t["change"].double,
                                  windowDays: t["window_days"].int, improving: t["improving"].bool)
        return out.direction == nil && out.change == nil ? nil : out
    }

    private static func summary(_ s: PFJ) -> PFStandingSummary? {
        guard s.exists else { return nil }
        let c = s["counts"]
        var out = PFStandingSummary()
        out.poor = c["poor"].int ?? 0
        out.average = c["average"].int ?? 0
        out.good = c["good"].int ?? 0
        out.veryGood = c["very_good"].int ?? 0
        out.elite = c["elite"].int ?? 0
        out.notRated = c["not_rated"].int ?? 0
        out.strongest = s["strongest"].array.compactMap { $0.idString }
        out.focus = s["focus"].array.compactMap { $0.idString }
        out.unrated = s["unrated"].array.compactMap { $0.idString }
        return out
    }

    private static func plan(_ p: PFJ) -> PFStandingPlan? {
        guard let id = p["id"].idString, let title = p["title"].text else { return nil }
        let steps: [String] = p["steps"].array.compactMap { $0.text ?? $0["text"].text }
        return PFStandingPlan(id: id, title: title, why: p["why"].text, steps: steps, measure: p["measure"].text,
                              dont: p["dont"].text, evidence: p["evidence"].text, timeframe: p["timeframe"].text)
    }

    private static func testDay(_ t: PFJ) -> PFTestDay? {
        guard t.exists else { return nil }
        let tests: [PFTestDay.Test] = t["tests"].array.compactMap { test in
            guard let id = test["id"].idString, let label = test["label"].text else { return nil }
            var logged: PFTestDay.Logged?
            let l = test["logged"]
            if l.exists {
                let entry = PFTestDay.Logged(value: l["value"].double,
                                             display: l["display"].text,
                                             date: l["date"].text)
                if entry.value != nil || entry.display != nil { logged = entry }
            }
            return PFTestDay.Test(id: id, label: label, unit: test["unit"].text, how: test["how"].text,
                                  normNote: test["norm_note"].text, logged: logged)
        }
        let out = PFTestDay(intro: t["intro"].text, tests: tests)
        return out.intro == nil && out.tests.isEmpty ? nil : out
    }
}

extension PFBand {
    /// "heart_lungs" -> "Heart lungs": the title a domain gets when the server sent none.
    static func titleFromId(_ id: String) -> String {
        let spaced = id.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
