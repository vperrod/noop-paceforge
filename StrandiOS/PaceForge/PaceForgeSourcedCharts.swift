import Foundation

// The Coach's sourced charts and the athlete's own experiments: the inputs of `query-chart` and `experiment`, how their results read, the
// rule that breaks a line where a day has no reading, and the experiment list in `GET data/experiments.json`. Foundation only, so it is
// compiled into the macOS unit-test bundle. Field names are docs/app-job-contract.md's `query-chart`, `experiment` and "Scoped Coach
// conversations" sections. Nothing here fills a gap: a day with no reading has no row, and the server's caveat is carried verbatim.

/// The readings a chart or an experiment can ask for (the contract's closed list). The id is what is sent; the title is the phone's word
/// for it, used before the server has answered (the answer names its own label, unit and source).
enum PFChartMetric: String, CaseIterable, Identifiable {
    case hrv
    case restingHR = "resting_hr"
    case resp
    case skinTemp = "skin_temp"
    case spo2
    case sleepHours = "sleep_hours"
    case noopRecovery = "noop_recovery"
    case pfRecovery = "pf_recovery"
    case pfSleepScore = "pf_sleep_score"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: return "HRV"
        case .restingHR: return "Resting heart rate"
        case .resp: return "Respiration"
        case .skinTemp: return "Skin temperature"
        case .spo2: return "Blood oxygen"
        case .sleepHours: return "Sleep hours"
        case .noopRecovery: return "Charge (NOOP)"
        case .pfRecovery: return "Readiness (PaceForge)"
        case .pfSleepScore: return "Sleep score (PaceForge)"
        }
    }

    static func title(for id: String) -> String { PFChartMetric(rawValue: id)?.title ?? PFFormat.capitalized(PFFormat.words(id)) }
}

// MARK: Chart request

/// A chart's spec: `{metric, days 7 to 180, split}`. The same three fields come on the Coach's turn and go to `query-chart`.
struct PFChartSpec: Equatable {
    static let minDays = 7
    static let maxDays = 180

    var metric: String
    var days: Int
    /// A journal question; each morning is then grouped by the answer about the day before.
    var split: String?

    static func parse(_ node: PFJ) -> PFChartSpec? {
        guard let metric = node["metric"].text, let days = node["days"].int else { return nil }
        return PFChartSpec(metric: metric, days: days, split: node["split"].text)
    }

    /// The `query-chart` inputs, or nil when the server would refuse them (an unknown metric, days outside 7 to 180, a split over 200 characters).
    var inputs: [String: Any]? { PFJobInputs.queryChart(metric: metric, days: days, split: split) }
}

extension PFJobInputs {
    /// `query-chart`: `{metric, days, split?}`. The schema is closed: nothing else is sent.
    static func queryChart(metric: String, days: Int, split: String? = nil) -> [String: Any]? {
        guard PFChartMetric(rawValue: metric) != nil, (PFChartSpec.minDays...PFChartSpec.maxDays).contains(days) else { return nil }
        var inputs: [String: Any] = ["metric": metric, "days": days]
        if let split {
            let question = split.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty, question.unicodeScalars.count <= 200 else { return nil }
            inputs["split"] = question
        }
        return inputs
    }
}

/// The chart a Coach turn asks for: the turn's `query_chart` block, `{id, scope, spec}`. The app runs `query-chart` with the spec to get
/// the rows; the scope is the key of the Coach thread about this chart.
struct PFChartRef: Equatable {
    var id: String
    var scope: String
    var spec: PFChartSpec

    static func parse(_ node: PFJ) -> PFChartRef? {
        guard let id = node["id"].text, let scope = node["scope"].text, let spec = PFChartSpec.parse(node["spec"]) else { return nil }
        return PFChartRef(id: id, scope: scope, spec: spec)
    }
}

// MARK: Chart answer

/// The rows `query-chart` answers: one per day that has a reading, from one source for the whole window.
struct PFChartResult: Equatable {
    struct MetricInfo: Equatable {
        var id: String
        var label: String
        var unit: String
        var source: String
    }

    /// One stored reading. `group` is "yes", "no" or nil (no journal answer about the day before) when the chart was split.
    struct Row: Equatable, Identifiable {
        var date: String
        var value: Double
        var source: String
        var group: String?
        var id: String { date }
    }

    struct Side: Equatable {
        var n: Int
        /// Nil below the minimum days a side: no average is shown for a handful of days.
        var mean: Double?
    }

    struct Split: Equatable {
        var question: String
        var lagDays: Int
        var source: String
        var minEach: Int
        var unansweredDays: Int
        var yes: Side
        var no: Side
    }

    var id: String
    var scope: String
    var spec: PFChartSpec
    var metric: MetricInfo
    var start: String
    var end: String
    var windowDays: Int
    var rows: [Row]
    var n: Int
    var missingDays: [String]
    var note: String?
    var split: Split?

    static func parse(_ result: PFJ) -> PFChartResult? {
        guard let id = result["id"].text, let spec = PFChartSpec.parse(result["spec"]), let metricID = result["metric"]["id"].text else { return nil }
        let metric = MetricInfo(id: metricID, label: result["metric"]["label"].text ?? PFChartMetric.title(for: metricID),
                                unit: result["metric"]["unit"].text ?? "", source: result["metric"]["source"].text ?? "")
        let rows: [Row] = result["rows"].array.compactMap { row in
            guard let date = row["date"].text, let value = row["value"].double, value.isFinite else { return nil }
            return Row(date: date, value: value, source: row["source"].text ?? metric.source, group: row["group"].text)
        }
        var split: Split?
        let node = result["split"]
        if let question = node["question"].text {
            func group(_ name: String) -> Side { Side(n: node["groups"][name]["n"].int ?? 0, mean: node["groups"][name]["mean"].double) }
            split = Split(question: question, lagDays: node["lag_days"].int ?? 1, source: node["source"].text ?? "NOOP journal",
                          minEach: node["min_each"].int ?? 5, unansweredDays: node["unanswered_days"].int ?? 0,
                          yes: group("yes"), no: group("no"))
        }
        return PFChartResult(id: id, scope: result["scope"].text ?? "chart:\(id)", spec: spec, metric: metric,
                             start: result["window"]["start"].text ?? "", end: result["window"]["end"].text ?? "",
                             windowDays: result["window"]["days"].int ?? spec.days, rows: rows, n: result["n"].int ?? rows.count,
                             missingDays: result["missing_days"].strings, note: result["note"].text, split: split)
    }

    /// One reading to draw: its calendar day and the stretch of consecutive days it belongs to. A line is drawn within a stretch and
    /// never across a day with no reading.
    struct Point: Equatable, Identifiable {
        var date: String
        var value: Double
        var segment: Int
        var group: String?
        var id: String { date }
    }

    /// The rows oldest first, each with the number of its stretch of consecutive days. A day with no reading ends a stretch.
    var points: [Point] {
        let ordered = rows.sorted { $0.date < $1.date }
        var out: [Point] = []
        var segment = 0
        var previous: String?
        for row in ordered {
            if let previous, PFFormat.daysBetween(previous, row.date) != 1 { segment += 1 }
            out.append(Point(date: row.date, value: row.value, segment: segment, group: row.group))
            previous = row.date
        }
        return out
    }

    /// "61 ms", "7.4 h".
    func valueText(_ value: Double) -> String {
        let number = PFFormat.trimmed((value * 10).rounded() / 10)
        return metric.unit.isEmpty ? number : (metric.unit == "%" ? "\(number)%" : "\(number) \(metric.unit)")
    }

    /// The line under the chart: how many days have a reading out of the days asked for, and where the readings come from.
    var coverageLine: String {
        let source = metric.source.isEmpty ? "" : " from \(metric.source)"
        return "\(n) of \(windowDays) days have a reading\(source)."
    }

    /// The days with no reading, so a gap in the line is explained. Nothing was filled in.
    var missingLine: String? {
        guard !missingDays.isEmpty else { return nil }
        let shown = missingDays.prefix(6).map { PFFormat.shortDate($0) }.joined(separator: ", ")
        let more = missingDays.count > 6 ? " and \(missingDays.count - 6) more" : ""
        return "No reading on \(shown)\(more). These days are left as gaps, not filled in."
    }

    /// "Yes days: 12, average 61 ms" or "No days: 4, too few for an average".
    func groupLine(_ name: String) -> String? {
        guard let split else { return nil }
        let group = name == "yes" ? split.yes : split.no
        let label = name == "yes" ? "Yes days" : "No days"
        guard let mean = group.mean else { return "\(label): \(group.n), under \(split.minEach) days so no average is shown." }
        return "\(label): \(group.n), average \(valueText(mean))."
    }

    /// What a split means, in the server's own terms: two groups of days, not a finding.
    var splitLine: String? {
        guard let split else { return nil }
        var text = "Each morning is grouped by your \u{201C}\(split.question)\u{201D} answer about the day before"
        if split.unansweredDays > 0 { text += "; \(split.unansweredDays) days had no answer" }
        return text + ". This describes two groups of days. It is not a finding."
    }
}

// MARK: Experiments

/// One experiment as `GET data/experiments.json` lists it (definitions only, no results).
struct PFExperiment: Equatable, Identifiable {
    var id: String
    var title: String
    var question: String
    var outcome: String
    var start: String
    var end: String
    var status: String?

    static func parseList(_ data: Data?) -> [PFExperiment] {
        PFJ(data: data)["experiments"].array.compactMap { row in
            guard let id = row["id"].text, let title = row["title"].text, let question = row["question"].text,
                  let outcome = row["outcome"].text, let start = row["start"].text, let end = row["end"].text else { return nil }
            return PFExperiment(id: id, title: title, question: question, outcome: outcome, start: start, end: end, status: row["status"].text)
        }
        .sorted { $0.start != $1.start ? $0.start > $1.start : $0.title < $1.title }
    }

    /// "9 Nov to 23 Nov".
    var windowLine: String { "\(PFFormat.shortDate(start)) to \(PFFormat.shortDate(end))" }
}

/// What the form of a new experiment may hold: the server's own limits.
enum PFExperimentRules {
    static let minWindow = 7
    static let maxWindow = 90
    static let maxDaysBack = 180
    static let maxDaysAhead = 60
    static let maxTitle = 80

    /// Days from start to end, both included.
    static func windowDays(start: String, end: String) -> Int { PFFormat.daysBetween(start, end) + 1 }

    /// What is wrong with a definition, or nil when it can be sent.
    static func problem(title: String, question: String?, outcome: String?, start: String, end: String, today: String) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the experiment a name." }
        if name.unicodeScalars.count > maxTitle { return "The name can be \(maxTitle) characters at most." }
        if question == nil { return "Choose the habit it is about." }
        guard let outcome, PFChartMetric(rawValue: outcome) != nil else { return "Choose what to look at the next morning." }
        let days = windowDays(start: start, end: end)
        if days < minWindow || days > maxWindow { return "The window must be \(minWindow) to \(maxWindow) days; this one is \(days)." }
        if PFFormat.daysBetween(today, start) < -maxDaysBack { return "The window cannot start more than \(maxDaysBack) days ago." }
        if PFFormat.daysBetween(today, end) > maxDaysAhead { return "The window cannot end more than \(maxDaysAhead) days from now." }
        return nil
    }
}

extension PFJobInputs {
    /// `experiment` with `define`. The question must be one of the active journal questions; the server checks that.
    static func experimentDefine(title: String, question: String, outcome: String, start: String, end: String, today: String) -> [String: Any]? {
        guard PFExperimentRules.problem(title: title, question: question, outcome: outcome, start: start, end: end, today: today) == nil else { return nil }
        let habit = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !habit.isEmpty, habit.unicodeScalars.count <= 200 else { return nil }
        return ["action": "define", "title": title.trimmingCharacters(in: .whitespacesAndNewlines), "question": habit,
                "outcome": outcome, "start": start, "end": end]
    }

    /// `experiment` with `review` or `retire`: the id is 16 lowercase hex digits.
    static func experimentAction(_ action: String, id: String) -> [String: Any]? {
        guard action == "review" || action == "retire", id.count == 16, id.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return ["action": action, "id": id]
    }
}

/// The reading of one experiment, computed by the server on every call.
struct PFExperimentReview: Equatable {
    struct Effect: Equatable {
        var meanYes: Double?
        var meanNo: Double?
        var diff: Double?
        var pct: Double?
        var t: Double?
        var effectSize: Double?
        var confidence: String?
    }

    var id: String
    var scope: String
    var title: String
    var question: String
    var outcomeLabel: String
    var outcomeUnit: String
    var outcomeSource: String
    var start: String
    var end: String
    var evaluatedThrough: String?
    var lagDays: Int
    var nYes: Int
    var nNo: Int
    var minEach: Int
    var answeredWithoutReading: Int
    /// not_enough_data | too_early | no_clear_difference | lined_up
    var status: String
    var statement: String
    /// Nil while a side has under `minEach` days: no number is shown then.
    var effect: Effect?
    /// The server's caveat, shown with every review, word for word.
    var caveat: String

    static func parse(_ result: PFJ) -> PFExperimentReview? {
        guard let id = result["id"].text, let status = result["status"].text, let statement = result["statement"].text,
              let caveat = result["caveat"].text else { return nil }
        var effect: Effect?
        if result["effect"].exists, result["effect"].dict.isEmpty == false {
            let node = result["effect"]
            let confidence = node["confidence"].text ?? node["confidence"].double.map { PFFormat.trimmed($0) }
            effect = Effect(meanYes: node["mean_yes"].double, meanNo: node["mean_no"].double, diff: node["diff"].double, pct: node["pct"].double,
                            t: node["t"].double, effectSize: node["effect_size"].double, confidence: confidence)
        }
        let outcome = result["outcome"]
        return PFExperimentReview(
            id: id, scope: result["scope"].text ?? "experiment:\(id)", title: result["title"].text ?? "", question: result["question"].text ?? "",
            outcomeLabel: outcome["label"].text ?? PFChartMetric.title(for: outcome["id"].text ?? ""), outcomeUnit: outcome["unit"].text ?? "",
            outcomeSource: outcome["source"].text ?? "", start: result["window"]["start"].text ?? "", end: result["window"]["end"].text ?? "",
            evaluatedThrough: result["window"]["evaluated_through"].text, lagDays: result["lag_days"].int ?? 1,
            nYes: result["n_yes"].int ?? 0, nNo: result["n_no"].int ?? 0, minEach: result["min_each"].int ?? 5,
            answeredWithoutReading: result["answered_without_reading"].int ?? 0, status: status, statement: statement, effect: effect,
            caveat: caveat)
    }

    /// The status in plain words.
    var statusTitle: String {
        switch status {
        case "not_enough_data": return "Not enough days yet"
        case "too_early": return "Too early to act on"
        case "no_clear_difference": return "No clear difference"
        case "lined_up": return "Lined up with the habit"
        default: return PFFormat.capitalized(PFFormat.words(status))
        }
    }

    /// "12 yes days and 9 no days."
    var countsLine: String { "\(nYes) yes \(nYes == 1 ? "day" : "days") and \(nNo) no \(nNo == 1 ? "day" : "days")." }

    /// The numbers behind a review that has them, one line each: the two averages and the gap. Empty when the server sent no effect.
    func effectLines(valueText: (Double) -> String) -> [String] {
        guard let effect else { return [] }
        var out: [String] = []
        if let yes = effect.meanYes, let no = effect.meanNo {
            out.append("Next-morning average after a yes: \(valueText(yes)). After a no: \(valueText(no)).")
        }
        if let diff = effect.diff {
            var text = "Difference: \(diff > 0 ? "+" : "")\(valueText(diff))"
            if let pct = effect.pct { text += " (\(pct > 0 ? "+" : "")\(PFFormat.trimmed((pct * 10).rounded() / 10)) %)" }
            out.append(text + ".")
        }
        if let size = effect.effectSize { out.append("Effect size (Cohen's d): \(PFFormat.trimmed((size * 100).rounded() / 100)).") }
        return out
    }

    /// "2 answered days had no reading the next morning and are left out."
    var gapLine: String? {
        answeredWithoutReading > 0 ? "\(answeredWithoutReading) answered \(answeredWithoutReading == 1 ? "day" : "days") had no reading the next morning and are left out." : nil
    }
}
