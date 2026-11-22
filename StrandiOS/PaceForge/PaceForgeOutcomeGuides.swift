import Foundation

// Outcome review (`GET outcome-review`) and the contextual guides (`GET guides`): how each document reads, which accepted proposals belong
// to a week, and where a guide step's target is on the iPhone. Foundation only, so it is compiled into the macOS unit-test bundle. Field
// names are docs/app-job-contract.md's "Strength imports, PR history, outcome review and guides" section.

// MARK: Outcome review

/// One reading recorded for a morning. The server's labels say whose it is: `recovery` is the NOOP score, the rest are Garmin's own. They
/// are listed one by one and never combined.
struct PFOutcomeReading: Equatable, Identifiable {
    var key: String
    var label: String
    var text: String
    var id: String { key }
}

/// One accepted proposal and what was recorded the next morning. The values are what was filed, never a claim that the change caused them.
struct PFOutcomeRow: Equatable, Identifiable {
    struct Rating: Equatable {
        var verdict: String
        var reason: String?
    }

    var id: String
    var title: String
    var acceptedAt: String
    var changes: [String]
    /// recorded | pending | none
    var state: String
    var nextDay: String?
    var nextReadings: [PFOutcomeReading]
    var answeredReadings: [PFOutcomeReading]
    var ratings: [Rating]

    /// The day the proposal was accepted ("2026-11-20").
    var acceptedDay: String { String(acceptedAt.prefix(10)) }

    /// What the state means, in words.
    var stateLine: String {
        switch state {
        case "recorded":
            let when = nextDay.map { " (\(PFFormat.shortDate($0)))" } ?? ""
            return nextReadings.isEmpty ? "The next morning\(when) was filed with no reading to show."
                : "Recorded the next morning\(when)."
        case "pending": return "The next morning has not been filed yet."
        default: return "No next-morning reading is tied to this change."
        }
    }
}

enum PFOutcomeReview {
    /// The proposal log keeps this many days.
    static let logDays = 30

    /// The server's own words for what it recorded, with the source each belongs to.
    private static func reading(_ key: String, _ value: Double) -> PFOutcomeReading? {
        func whole(_ number: Double) -> String { String(Int(number.rounded())) }
        switch key {
        case "recovery": return PFOutcomeReading(key: key, label: "Charge (NOOP)", text: "\(whole(value))%")
        case "hrv_last_night": return PFOutcomeReading(key: key, label: "HRV last night (Garmin)", text: "\(whole(value)) ms")
        case "hrv_weekly_avg": return PFOutcomeReading(key: key, label: "HRV weekly average (Garmin)", text: "\(whole(value)) ms")
        case "resting_hr": return PFOutcomeReading(key: key, label: "Resting heart rate (Garmin)", text: "\(whole(value)) bpm")
        case "sleep_duration_seconds":
            let minutes = Int((value / 60).rounded())
            return PFOutcomeReading(key: key, label: "Sleep (Garmin)", text: String(format: "%d:%02d h", minutes / 60, minutes % 60))
        case "training_readiness": return PFOutcomeReading(key: key, label: "Training readiness (Garmin)", text: whole(value))
        default: return nil
        }
    }

    private static let order = ["recovery", "resting_hr", "hrv_last_night", "hrv_weekly_avg", "sleep_duration_seconds", "training_readiness"]

    private static func readings(_ node: PFJ) -> [PFOutcomeReading] {
        order.compactMap { key in node[key].double.flatMap { reading(key, $0) } }
    }

    static func parse(_ doc: PFJ) -> [PFOutcomeRow] {
        doc["accepted"].array.compactMap { row in
            guard let id = row["id"].text, let title = row["title"].text, let accepted = row["accepted_at"].text else { return nil }
            let result = row["result"]
            let ratings: [PFOutcomeRow.Rating] = row["feedback"].array.compactMap { item in
                item["verdict"].text.map { PFOutcomeRow.Rating(verdict: $0, reason: item["reason"].text) }
            }
            return PFOutcomeRow(id: id, title: title, acceptedAt: accepted, changes: row["changes"].strings,
                                state: result["state"].text ?? "none", nextDay: result["next_day"]["date"].text,
                                nextReadings: readings(result["next_day"]), answeredReadings: readings(result["state_when_answered"]),
                                ratings: ratings)
        }
    }

    /// The `days` of the request that reaches back to a week's first day (1 to 30; the server's own range), at least a week.
    static func days(weekStart: String, today: String) -> Int {
        min(logDays, max(7, PFFormat.daysBetween(weekStart, today) + 1))
    }

    /// Whether the proposal log still reaches that week's first day; older weeks have nothing to ask for.
    static func isInLog(weekStart: String, today: String) -> Bool {
        PFFormat.daysBetween(weekStart, today) < logDays
    }

    /// The rows accepted on the week's days, oldest first as the server sent them.
    static func rows(_ rows: [PFOutcomeRow], from start: String, to end: String) -> [PFOutcomeRow] {
        rows.filter { $0.acceptedDay >= start && $0.acceptedDay <= end }
    }
}

// MARK: Guides

/// One guide: a short list of steps to get one common thing done.
struct PFGuide: Equatable, Identifiable {
    struct Step: Equatable, Identifiable {
        var index: Int
        var text: String
        /// A web address (`#/plan/week`), a job name, a read route, or a control only the iPhone app has ("Lab Book > markers CSV").
        var web: String?
        var anchor: String?
        var job: String?
        var route: String?
        var native: String?
        var id: Int { index }
    }

    var id: String
    var title: String
    var summary: String
    var steps: [Step]
}

enum PFGuides {
    static func parse(_ doc: PFJ) -> [PFGuide] {
        doc["guides"].array.compactMap { guide in
            guard let id = guide["id"].text, let title = guide["title"].text else { return nil }
            let steps: [PFGuide.Step] = guide["steps"].array.enumerated().compactMap { index, step in
                guard let text = step["text"].text else { return nil }
                return PFGuide.Step(index: index, text: text, web: step["web"].text, anchor: step["anchor"].text, job: step["job"].text,
                                    route: step["route"].text, native: step["native"].text)
            }
            return PFGuide(id: id, title: title, summary: guide["summary"].text ?? "", steps: steps)
        }
    }
}

/// Where on the iPhone a guide step's control is.
enum PFGuideTarget: String, Equatable {
    case planWeek, planSeason, planReports, planSettings, coach, healthSleep, trainWorkouts, trainStrength, labBook

    /// The button's words.
    var title: String {
        switch self {
        case .planWeek: return "Open Plan, Week"
        case .planSeason: return "Open Plan, Season"
        case .planReports: return "Open Plan, Reports"
        case .planSettings: return "Open how your plan is built"
        case .coach: return "Open the Coach"
        case .healthSleep: return "Open Health, Sleep"
        case .trainWorkouts: return "Open Train, Workouts"
        case .trainStrength: return "Open Train, Strength"
        case .labBook: return "Open the Lab Book"
        }
    }

    /// The target of a step, from what the server names: a control only the iPhone has first, then the job it runs, then the web page it
    /// sits on, then the route it reads. A step that names nothing the app has gets no button.
    static func resolve(_ step: PFGuide.Step) -> PFGuideTarget? {
        if let native = step.native, native.lowercased().contains("lab book") { return .labBook }
        switch step.job ?? "" {
        case "strength-import-preview", "strength-import": return .trainStrength
        case "calendar-edit", "session-swap": return .planWeek
        case "plan-hours": return .planSettings
        case "event-update": return .planSeason
        case "save-rpe": return .trainWorkouts
        case "coach": return .coach
        default: break
        }
        switch step.web ?? "" {
        case "#/health/sleep": return .healthSleep
        case "#/coach": return .coach
        case "#/plan/week": return .planWeek
        case "#/plan/events": return .planSeason
        case "#/plan/reports", "#/health/weekly": return .planReports
        case "#/train/activities": return .trainWorkouts
        case "#/health/labbook": return .labBook
        default: break
        }
        switch step.route ?? "" {
        case "/strength-history": return .trainStrength
        case "/data/reports/list.json": return .planReports
        default: return nil
        }
    }
}
