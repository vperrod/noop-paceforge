import Foundation

// "Daily movement": PaceForge's movement.json, one item with the day's Garmin steps against the athlete's own typical range,
// Garmin intensity minutes, and the last seven days. Foundation only, so the parsing and every small rule the card draws from
// (status chip, range-bar positions, week bars, the "what counts" line) are compiled into the macOS unit-test bundle and the
// Linux logic tests.
//
// Steps are a separate, labelled signal: they never feed Effort, Strain, load or readiness on the server, and nothing here
// works out a score on the phone. Every field is optional on the wire; a missing file leaves the card out and an item with
// `available: false` shows the server's own reason.

struct PFMovementDay: Equatable, Identifiable {
    var date: String
    var steps: Int?
    var intensityMin: Double?
    var walkingLoad: Double?

    var id: String { date }

    /// "M", "T", "W" ... for the bar under the day; empty when the date does not parse.
    var weekdayLetter: String {
        guard let weekday = PFMovementLogic.weekday(of: date) else { return "" }
        return ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }

    /// "Monday" for VoiceOver.
    var weekdayName: String {
        guard let weekday = PFMovementLogic.weekday(of: date) else { return date }
        return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday - 1]
    }
}

struct PFMovement: Equatable {
    var asOf: String?
    /// Today is not over yet (the server's rule: before 21:00 local), so its count is still growing.
    var inProgress = false
    var stepsToday: Int
    var median30d: Int?
    var rangeLow: Int?
    var rangeHigh: Int?
    var daysUsed: Int?
    /// low, typical or high; nil while the server withholds a "low" for a day that is not over.
    var position: String?
    var intensityToday: Double?
    var intensityWeek: Double?
    var walkingLoad: Double?
    var strainToday: Double?
    var countedIn: [String] = []
    var notCountedIn: [String] = []
    var series: [PFMovementDay] = []

    var hasRange: Bool {
        guard let rangeLow, let rangeHigh else { return false }
        return rangeHigh > rangeLow
    }
}

// MARK: - Logic

enum PFMovementLogic {
    /// The line the card ends on, and the Effort info text: one rule, worded once.
    static let whatCounts = "Steps do not raise Effort; all-day heart rate above your resting level now does (Effort v2)"

    /// "9,482": a count with the thousands grouped, the same everywhere on the card.
    static func countText(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "Usual 7,200\u{2013}10,400" under the big number; nil without a range.
    static func usualText(_ movement: PFMovement) -> String? {
        guard movement.hasRange, let low = movement.rangeLow, let high = movement.rangeHigh else { return nil }
        return "Usual \(countText(low))\u{2013}\(countText(high))"
    }

    /// The big number's caption: "so far today" while the day is open, else "today".
    static func whenText(_ movement: PFMovement) -> String {
        movement.inProgress ? "so far today" : "today"
    }

    /// The chip: LOW / TYPICAL / HIGH, "DAY NOT OVER" while the server withholds a low label, else NOT RATED.
    static func chipText(_ movement: PFMovement) -> String {
        switch movement.position {
        case "low": return "LOW"
        case "typical": return "TYPICAL"
        case "high": return "HIGH"
        default: return movement.inProgress ? "DAY NOT OVER" : "NOT RATED"
        }
    }

    /// The scale of the range bar: 0 to the larger of 1.4 x the range's top and 1.1 x today's count, so both always fit.
    static func barMax(_ movement: PFMovement) -> Double {
        let high = Double(movement.rangeHigh ?? 0)
        return max(1, max(high * 1.4, Double(movement.stepsToday) * 1.1))
    }

    /// (start, end, today) as fractions of the bar, each clamped to 0...1; nil without a usable range.
    static func rangeBar(_ movement: PFMovement) -> (low: Double, high: Double, today: Double)? {
        guard movement.hasRange, let low = movement.rangeLow, let high = movement.rangeHigh else { return nil }
        let top = barMax(movement)
        func fraction(_ v: Int) -> Double { min(max(Double(v) / top, 0), 1) }
        return (fraction(low), fraction(high), fraction(movement.stepsToday))
    }

    /// Bar heights of the week as fractions of its tallest day; a day with no count is nil (drawn as a dot, not a zero).
    static func weekFractions(_ series: [PFMovementDay]) -> [Double?] {
        let top = Double(series.compactMap { $0.steps }.max() ?? 0)
        guard top > 0 else { return series.map { _ in nil } }
        return series.map { day in day.steps.map { min(max(Double($0) / top, 0.03), 1) } }
    }

    /// "42 min today \u{00B7} 118 min in 7 days"; nil when Garmin sent no intensity minutes at all.
    static func intensityText(_ movement: PFMovement) -> String? {
        func minutes(_ v: Double) -> String { String(Safe.int(v)) }
        switch (movement.intensityToday, movement.intensityWeek) {
        case let (today?, week?): return "\(minutes(today)) min today \u{00B7} \(minutes(week)) min in 7 days"
        case let (today?, nil): return "\(minutes(today)) min today"
        case let (nil, week?): return "\(minutes(week)) min in 7 days"
        default: return nil
        }
    }

    /// 1 = Sunday ... 7 = Saturday for a `yyyy-MM-dd` date, on a UTC calendar so the time zone cannot move the day.
    static func weekday(of iso: String) -> Int? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return nil }
        return calendar.component(.weekday, from: date)
    }
}

// MARK: - Parse

enum PFMovementParse {
    static let id = "movement"
    static let path = "data/movement.json"

    /// The document's one item, typed, or why it cannot be.
    static func document(_ j: PFJ) -> PFDocState<PFMovement> {
        PFIntelDocsParse.state(j, id: id, Self.metric)
    }

    static func metric(_ m: PFJ) -> PFMovement? {
        let steps = m["steps"]
        guard let today = steps["today"].int, today >= 0 else { return nil }
        var out = PFMovement(stepsToday: today)
        out.asOf = m["as_of"].text
        out.inProgress = m["in_progress"].bool ?? false
        out.median30d = steps["median_30d"].int
        out.rangeLow = steps["range_low"].int
        out.rangeHigh = steps["range_high"].int
        out.daysUsed = steps["days_used"].int
        out.position = ["low", "typical", "high"].contains(steps["position"].text ?? "") ? steps["position"].text : nil
        out.intensityToday = m["intensity"]["today"].double.flatMap { $0.isFinite ? $0 : nil }
        out.intensityWeek = m["intensity"]["week_total"].double.flatMap { $0.isFinite ? $0 : nil }
        out.walkingLoad = m["walking_load"]["value"].double.flatMap { $0.isFinite ? $0 : nil }
        out.strainToday = m["strain_today"].double.flatMap { $0.isFinite ? $0 : nil }
        out.countedIn = m["counted_in"].strings
        out.notCountedIn = m["not_counted_in"].strings
        out.series = m["series_7d"].array.compactMap { d in
            guard let date = d["date"].text else { return nil }
            return PFMovementDay(date: date, steps: d["steps"].int, intensityMin: d["intensity_min"].double,
                                 walkingLoad: d["walking_load"].double)
        }
        return out
    }

    /// The item's single suggested action, in the server's words ("a 20-minute walk lifts it"), when it has one.
    static func action(_ item: PFIntelItem) -> PFInsightAction? { item.base.actions.first }
}
