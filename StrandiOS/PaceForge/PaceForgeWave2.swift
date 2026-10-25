import Foundation

// Wave 2 documents from PaceForge: the feel check-in, what changed since yesterday, the two answers,
// the trust flags, the metric explainers and the behaviour impact list. Foundation only, so the pure
// parsing below is compiled into the macOS unit-test bundle as well. Every field is optional on the
// wire: an older server or a friend's instance may not serve a file, and the screens then hide the part.

// MARK: Calibration and trust

/// How far a metric is from having enough history ("Day 12 of 21").
struct PFCalibration: Equatable {
    var have: Double
    var need: Double
    var unit: String?
    var ready: Bool
    var line: String?

    /// 0...1 for a progress bar; 1 once the metric is ready.
    var fraction: Double {
        if ready { return 1 }
        guard need > 0 else { return 0 }
        return min(max(have / need, 0), 1)
    }
}

/// Whether a reading can be relied on this morning, with the reasons when it cannot.
struct PFTrust: Equatable {
    var level: String
    var reasons: [String] = []

    var isLow: Bool { level == "low" }

    /// "Low confidence: the watch recorded only 40% of the night", or nil when the reading is fine.
    var text: String? {
        guard isLow else { return nil }
        guard let first = reasons.first else { return "Low confidence" }
        return "Low confidence: " + first
    }
}

// MARK: Feel

struct PFFeelDay: Identifiable, Equatable {
    var date: String
    var feel: Int?
    var score: Double?
    var band: String?
    /// match, feel_lower or feel_higher; nil when there is no answer or no score that day.
    var agreement: String?
    var gap: Int?
    var id: String { date }
}

struct PFFeelSummary: Equatable {
    var date: String?
    var answered = false
    var feel: Int?
    var at: String?
    var source: String?
    var days: [PFFeelDay] = []
    var answers = 0
    var compared = 0
    var needs = 5
    var sentence: String?

    /// The summary as it reads right after the athlete taps `value`, before the server has answered.
    func answering(_ value: Int, at timestamp: String? = nil) -> PFFeelSummary {
        var out = self
        out.answered = true
        out.feel = value
        out.at = timestamp
        out.source = "ios"
        if let last = out.days.indices.last, out.days[last].date == date {
            out.days[last].feel = value
        }
        return out
    }
}

// MARK: What changed

struct PFChangeTypical: Equatable {
    var mean: Double?
    var low: Double?
    var high: Double?
    var n: Int?
    var basis: String?
}

struct PFChangeMetric: Identifiable, Equatable {
    var id: String
    var label: String
    var unit: String
    var source: String?
    var value: Double?
    var previous: Double?
    var previousLabel: String?
    var delta: Double?
    var typical: PFChangeTypical?
    var deltaVsTypical: Double?
    /// up, down, flat or unknown.
    var direction: String
    /// better, worse, neutral or unknown, as the server judges it. The app shows it in neutral colours only.
    var tone: String
    var reason: String?
    var calibrating: Bool
    var calibration: PFCalibration?
}

struct PFCalibratingLine: Identifiable, Equatable {
    var id: String
    var label: String
    var line: String
}

struct PFWhatChanged: Equatable {
    var date: String?
    var summary: String?
    var calibrating: [PFCalibratingLine] = []
    var metrics: [PFChangeMetric] = []
}

// MARK: Explainers

struct PFExplainer: Identifiable, Equatable {
    var id: String
    var title: String
    var plain: String?
    var how: String?
    var usualRange: String?
    var caveat: String?
    var unlocks: String?
    var calibration: PFCalibration?
    /// Where the metric stands against his own usual range, and his strongest personal link (PaceForge computes both).
    var forYou: String?
    /// What PaceForge does with the number.
    var effect: String?
}

// MARK: Behaviour impact

struct PFBehaviourEffect: Equatable {
    var source: String
    var what: String
    var unit: String
    var nYes: Int
    var nNo: Int
    var meanYes: Double?
    var meanNo: Double?
    var diff: Double?
    var effectSize: Double?
}

struct PFBehaviourItem: Identifiable, Equatable {
    var question: String
    var label: String
    var daysYes: Int
    var daysNo: Int
    /// Keyed by outcome id: pf_recovery, pf_sleep_score, hrv_ms, noop_recovery.
    var effects: [String: PFBehaviourEffect]
    var primary: String?
    var line: String?
    var id: String { question }

    /// PaceForge's own outcomes first, then Garmin's, then NOOP's, each kept apart.
    var orderedEffects: [(key: String, effect: PFBehaviourEffect)] {
        let order = ["pf_recovery", "pf_sleep_score", "hrv_ms", "noop_recovery"]
        return order.compactMap { key in effects[key].map { (key: key, effect: $0) } }
    }
}

struct PFBehaviourWaiting: Identifiable, Equatable {
    var question: String
    var label: String
    var yes: Int
    var no: Int
    var id: String { question }
}

struct PFBehaviourImpact: Equatable {
    var asOf: String?
    var windowDays: Int?
    var lagDays: Int?
    var label: String?
    var minEach: Int
    var questionsSeen: Int
    var qualifying: Int
    var topLines: [String] = []
    var items: [PFBehaviourItem] = []
    var insufficient: [PFBehaviourWaiting] = []
}

// MARK: The two answers

enum PFAnswerLevel: Equatable {
    case yes, careful, no

    /// The word on the chip.
    var word: String {
        switch self {
        case .yes: return "yes"
        case .careful: return "careful"
        case .no: return "not today"
        }
    }
}

struct PFAnswer: Equatable {
    var level: PFAnswerLevel
    var reason: String?
}

struct PFAnswers: Equatable {
    var train: PFAnswer?
    var trainHard: PFAnswer?
    var plannedName: String?
    var plannedType: String?
    var plannedHard = false
    var plannedOverload = false
    var flags: [String] = []

    var hasAny: Bool { train != nil || trainHard != nil }

    /// "Train: yes · Hard: careful" for the widget, or nil when the server gave no answers.
    var widgetLine: String? {
        guard hasAny else { return nil }
        var parts: [String] = []
        if let train { parts.append("Train: " + train.level.word) }
        if let trainHard { parts.append("Hard: " + trainHard.level.word) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: Parsing

enum PFWave2Parse {
    static func calibration(_ j: PFJ) -> PFCalibration? {
        guard j.exists, let have = j["have"].double, let need = j["need"].double else { return nil }
        return PFCalibration(have: have, need: need, unit: j["unit"].text, ready: j["ready"].bool ?? false,
                             line: j["line"].text)
    }

    static func trust(_ j: PFJ) -> PFTrust? {
        guard j.exists, let level = j["level"].text else { return nil }
        return PFTrust(level: level, reasons: j["reasons"].array.compactMap { $0.text })
    }

    // MARK: feel-summary.json

    static func feelSummary(_ j: PFJ) -> PFFeelSummary? {
        // The document is only useful if the server says whether today is answered; otherwise the card hides.
        guard j.exists, j["today"].exists else { return nil }
        var out = PFFeelSummary()
        out.date = j["date"].text
        out.answered = j["today"]["answered"].bool ?? (j["today"]["feel"].int != nil)
        out.feel = j["today"]["feel"].int
        out.at = j["today"]["at"].text
        out.source = j["today"]["source"].text
        out.days = j["days"].array.compactMap { d in
            guard let date = d["date"].text else { return nil }
            return PFFeelDay(date: date, feel: d["feel"].int, score: d["score"].double, band: d["band"].text,
                             agreement: d["agreement"].text, gap: d["gap"].int)
        }
        out.answers = j["answers"].int ?? out.days.filter { $0.feel != nil }.count
        out.compared = j["compared"].int ?? out.days.filter { $0.agreement != nil }.count
        out.needs = j["needs"].int ?? 5
        out.sentence = j["sentence"].text
        return out
    }

    /// The summary inside a `POST /api/feel` answer, or nil when the body is not that shape.
    static func feelSaved(_ j: PFJ) -> (feel: Int, summary: PFFeelSummary?)? {
        guard let feel = j["saved"]["feel"].int, (1...5).contains(feel) else { return nil }
        return (feel, feelSummary(j["summary"]))
    }

    // MARK: what-changed.json

    static func whatChanged(_ j: PFJ) -> PFWhatChanged? {
        guard j.exists else { return nil }
        var out = PFWhatChanged()
        out.date = j["date"].text
        out.summary = j["summary"].text
        out.calibrating = j["calibrating"].array.compactMap { c in
            guard let id = c["id"].text, let line = c["line"].text else { return nil }
            return PFCalibratingLine(id: id, label: c["label"].text ?? id, line: line)
        }
        out.metrics = j["metrics"].array.compactMap { m in
            guard let id = m["id"].text, let label = m["label"].text else { return nil }
            let typical: PFChangeTypical? = m["typical"].exists
                ? PFChangeTypical(mean: m["typical"]["mean"].double, low: m["typical"]["low"].double,
                                  high: m["typical"]["high"].double, n: m["typical"]["n"].int,
                                  basis: m["typical"]["basis"].text)
                : nil
            let cal = calibration(m["calibration"])
            return PFChangeMetric(id: id, label: label, unit: m["unit"].string ?? "", source: m["source"].text,
                                  value: m["value"].double, previous: m["previous"].double,
                                  previousLabel: m["previous_label"].text, delta: m["delta"].double,
                                  typical: typical, deltaVsTypical: m["delta_vs_typical"].double,
                                  direction: m["direction"].text ?? "unknown", tone: m["tone"].text ?? "unknown",
                                  reason: m["reason"].text,
                                  calibrating: m["calibrating"].bool ?? (cal.map { !$0.ready } ?? false),
                                  calibration: cal)
        }
        guard out.summary != nil || !out.metrics.isEmpty else { return nil }
        return out
    }

    // MARK: metric-explainers.json

    static func explainers(_ j: PFJ) -> [PFExplainer] {
        j["metrics"].array.compactMap { m in
            guard let id = m["id"].text, let title = m["title"].text else { return nil }
            return PFExplainer(id: id, title: title, plain: m["plain"].text, how: m["how"].text,
                               usualRange: m["usual_range"].text, caveat: m["caveat"].text,
                               unlocks: m["unlocks"].text, calibration: calibration(m["calibration"]),
                               forYou: m["you"].text, effect: m["effect"].text)
        }
    }

    // MARK: behaviour-impact.json

    static func behaviourImpact(_ j: PFJ) -> PFBehaviourImpact? {
        guard j.exists else { return nil }
        let items: [PFBehaviourItem] = j["items"].array.compactMap { i in
            guard let question = i["question"].text else { return nil }
            var effects: [String: PFBehaviourEffect] = [:]
            for (key, e) in i["effects"].dict {
                guard let what = e["what"].text else { continue }
                effects[key] = PFBehaviourEffect(
                    source: e["source"].text ?? "PaceForge", what: what, unit: e["unit"].string ?? "",
                    nYes: e["n_yes"].int ?? 0, nNo: e["n_no"].int ?? 0, meanYes: e["mean_yes"].double,
                    meanNo: e["mean_no"].double, diff: e["diff"].double, effectSize: e["effect_size"].double)
            }
            return PFBehaviourItem(question: question, label: i["label"].text ?? question,
                                   daysYes: i["days_yes"].int ?? i["yes"].int ?? 0,
                                   daysNo: i["days_no"].int ?? i["no"].int ?? 0,
                                   effects: effects, primary: i["primary"].text, line: i["line"].text)
        }
        let waiting: [PFBehaviourWaiting] = j["insufficient"].array.compactMap { w in
            guard let question = w["question"].text else { return nil }
            return PFBehaviourWaiting(question: question, label: w["label"].text ?? question,
                                      yes: w["yes"].int ?? 0, no: w["no"].int ?? 0)
        }
        // Nothing seen and nothing waiting: no journal answers on this instance, so the card has no story.
        guard !items.isEmpty || !waiting.isEmpty else { return nil }
        return PFBehaviourImpact(asOf: j["as_of"].text, windowDays: j["window_days"].int, lagDays: j["lag_days"].int,
                                 label: j["label"].text, minEach: j["min_each"].int ?? 5,
                                 questionsSeen: j["questions_seen"].int ?? (items.count + waiting.count),
                                 qualifying: j["qualifying"].int ?? items.count,
                                 topLines: j["top_lines"].array.compactMap { $0.text }, items: items,
                                 insufficient: waiting)
    }

    // MARK: readiness-explained.json answers

    /// `ok` is true, false or the string "caution".
    static func answerLevel(_ j: PFJ) -> PFAnswerLevel? {
        if let text = j.string { return text.lowercased() == "caution" ? .careful : nil }
        guard let ok = j.bool else { return nil }
        return ok ? .yes : .no
    }

    static func answers(_ j: PFJ) -> PFAnswers? {
        guard j.exists else { return nil }
        var out = PFAnswers()
        if let level = answerLevel(j["train"]["ok"]) { out.train = PFAnswer(level: level, reason: j["train"]["reason"].text) }
        if let level = answerLevel(j["train_hard"]["ok"]) {
            out.trainHard = PFAnswer(level: level, reason: j["train_hard"]["reason"].text)
        }
        out.plannedName = j["planned"]["name"].text
        out.plannedType = j["planned"]["type"].text
        out.plannedHard = j["planned"]["hard"].bool ?? false
        out.plannedOverload = j["planned_overload"].bool ?? false
        out.flags = j["flags"].array.compactMap { $0.text }
        return out.hasAny ? out : nil
    }
}
