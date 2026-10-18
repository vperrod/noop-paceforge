import Foundation

// "Phase 4 intel": the five read-only documents PaceForge publishes next to daily-intel.json: healthspan.json (body age
// range and pace of aging), journal-impact.json (what helps and hurts the next morning's score), highlights.json (records,
// streaks, notable stats), monthly-report.json and my-plan.json (this week's plan progress). Foundation only, so the
// parsing and every small rule the screens draw from (age range wording, the pace ruler, the 10-segment driver bar,
// impact bars, the streak chip, the "5 days left" line, the saved Healthspan weeks) are compiled into the macOS
// unit-test bundle and the Linux logic tests.
//
// Every field is optional on the wire. A missing file, a missing item or an item with `available: false` is shown as
// exactly that, with the server's own reason; nothing is worked out from the athlete's data on the phone, and the app only
// reads. NOOP (strap) and Garmin-built figures are never merged: each number carries the source the server named for it.

// MARK: - Ids and paths

enum PFDocID {
    static let healthspan = "healthspan"
    static let journalImpact = "journal_impact"
    static let highlights = "highlights"
    static let monthlyReport = "monthly_report"
    static let myPlan = "my_plan"
}

enum PFDocPath {
    static let healthspan = "data/healthspan.json"
    static let journalImpact = "data/journal-impact.json"
    static let highlights = "data/highlights.json"
    static let monthlyReport = "data/monthly-report.json"
    static let myPlan = "data/my-plan.json"

    static let all = [healthspan, journalImpact, highlights, monthlyReport, myPlan]
}

// MARK: - Dates (UTC calendar, no time zone surprises)

enum PFDocDate {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    private static let isoCalendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2026-10-14" (or a longer timestamp starting with it) as noon UTC, or nil.
    static func date(_ iso: String) -> Date? {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func iso(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func addDays(_ iso: String, _ days: Int) -> String? {
        guard let base = date(iso), let moved = calendar.date(byAdding: .day, value: days, to: base) else { return nil }
        return self.iso(moved)
    }

    /// Whole days from `a` to `b`.
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let from = date(a), let to = date(b) else { return nil }
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    /// Monday is 0, Sunday is 6.
    static func weekdayIndex(_ iso: String) -> Int? {
        guard let d = date(iso) else { return nil }
        return (calendar.component(.weekday, from: d) + 5) % 7
    }

    /// "11 Oct".
    static func shortDate(_ iso: String) -> String? {
        guard let d = date(iso) else { return nil }
        let c = calendar.dateComponents([.month, .day], from: d)
        guard let month = c.month, let day = c.day, (1...12).contains(month) else { return nil }
        return "\(day) \(months[month - 1])"
    }

    /// "1 Jun 2026".
    static func dayMonthYear(_ iso: String) -> String? {
        guard let short = shortDate(iso), let d = date(iso) else { return nil }
        return "\(short) \(calendar.component(.year, from: d))"
    }

    /// The Monday of an ISO week key as PaceForge writes it ("2026-W42"), or nil.
    static func monday(ofWeek key: String) -> String? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), parts[1].hasPrefix("W"), let week = Int(parts[1].dropFirst()) else {
            return nil
        }
        guard let d = isoCalendar.date(from: DateComponents(hour: 12, weekday: 2, weekOfYear: week, yearForWeekOfYear: year)) else {
            return nil
        }
        return iso(d)
    }

    /// "OCT 12 - OCT 18" for an ISO week key; nil when the key does not parse.
    static func weekRangeText(_ key: String) -> String? {
        guard let start = monday(ofWeek: key), let end = addDays(start, 6),
              let a = shortDate(start), let b = shortDate(end) else { return nil }
        func flip(_ s: String) -> String {
            let p = s.split(separator: " ")
            return p.count == 2 ? "\(p[1].uppercased()) \(p[0])" : s.uppercased()
        }
        return "\(flip(a)) - \(flip(b))"
    }
}

// MARK: - The state of one document

/// A document as the screens see it: not served, served but unavailable (with the server's own reason), or ready.
enum PFDocState<T: Equatable>: Equatable {
    case missing
    case unavailable(reason: String?, item: PFIntelItem)
    case ready(T, item: PFIntelItem)

    var value: T? {
        if case .ready(let value, _) = self { return value }
        return nil
    }

    var item: PFIntelItem? {
        switch self {
        case .missing: return nil
        case .unavailable(_, let item): return item
        case .ready(_, let item): return item
        }
    }

    var reason: String? {
        if case .unavailable(let reason, _) = self { return reason }
        return nil
    }

    var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }
}

// MARK: - Healthspan

struct PFYearsRange: Equatable {
    var low: Double
    var high: Double
    var mid: Double?
}

struct PFBodyAge: Equatable {
    var low: Double
    var high: Double
    var mid: Double?
    /// The server's "35 to 38".
    var text: String?
    /// Years against the athlete's own age, negative = younger.
    var yearsVsAge: PFYearsRange?
}

struct PFPaceMetric: Equatable {
    var key: String
    var label: String
    var years6m: Double?
    var years30d: Double?
}

struct PFPaceOfAging: Equatable {
    var available: Bool
    var reason: String?
    /// ISO week key, "2026-W42".
    var week: String?
    var computedOn: String?
    var carried: Bool
    var value: Double?
    var low: Double?
    var high: Double?
    /// reversing, slowing, steady or accelerated.
    var label: String?
    var rangeLow: Double
    var rangeHigh: Double
    var basis: String?
    var metrics: [PFPaceMetric] = []

    func metric(_ key: String) -> PFPaceMetric? { metrics.first { $0.key == key } }
}

struct PFHealthDriver: Equatable, Identifiable {
    var key: String
    var label: String
    var unit: String?
    var source: String?
    var targetText: String?
    var note: String?
    var value: Double?
    var valueText: String?
    var coverage: Double?
    /// meets, short or unknown.
    var status: String
    var years: Double?
    var yearsLow: Double?
    var yearsHigh: Double?
    var action: PFInsightAction?
    var id: String { key }

    var isUnknown: Bool { status == "unknown" || years == nil }
}

struct PFHealthspan: Equatable {
    var asOf: String?
    /// "Our calculation of the published WHOOP Healthspan method, not WHOOP's number."
    var label: String?
    var age: Double?
    var sex: String?
    var windowDays: Int?
    var inputsAvailable: Int?
    var inputsTotal: Int?
    var missing: [String] = []
    var bodyAge: PFBodyAge?
    var pace: PFPaceOfAging?
    var drivers: [PFHealthDriver] = []
    var assumptions: [String] = []
}

/// The three groups the drivers fall into, for the GO TO links.
enum PFDriverGroup: String, CaseIterable, Equatable {
    case sleep, activity, body

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .activity: return "Activity"
        case .body: return "Body and fitness"
        }
    }

    static func of(_ key: String) -> PFDriverGroup {
        switch key {
        case "sleep_duration", "sleep_consistency": return .sleep
        case "steps", "zones_1_3", "zones_4_5", "strength": return .activity
        default: return .body
        }
    }
}

enum PFHealthspanFormat {
    /// "35\u{2013}38": the body age as a range, never a single number. A range that rounds to one whole number is widened to the
    /// whole years around it.
    static func rangeText(low: Double, high: Double) -> String {
        let lo = min(low, high), hi = max(low, high)
        var a = Safe.int(lo), b = Safe.int(hi)
        if a >= b {
            a = Safe.int(lo, .down)
            b = Safe.int(hi, .up)
        }
        if a >= b { b = a + 1 }
        return "\(a)\u{2013}\(b)"
    }

    enum Direction: Equatable { case younger, older, aboutRight }

    struct AgeVerdict: Equatable {
        var direction: Direction
        /// "3 to 6 years younger", "1 to 3 years older", or "about your age".
        var text: String
    }

    /// The gap to the athlete's own age as a range, from `years_vs_age` (negative = younger). A range that crosses zero reads
    /// "about your age" with its edges.
    static func ageVerdict(_ range: PFYearsRange) -> AgeVerdict {
        let lo = min(range.low, range.high), hi = max(range.low, range.high)
        if lo < 0, hi > 0 {
            let edges = "\(PFNumber.signed(lo, decimals: 0)) to \(PFNumber.signed(hi, decimals: 0)) years"
            return AgeVerdict(direction: .aboutRight, text: "about your age (\(edges))")
        }
        let younger = hi <= 0
        let near = younger ? abs(hi) : lo
        let far = younger ? abs(lo) : hi
        var a = Safe.int(near), b = Safe.int(far)
        if a >= b {
            a = Safe.int(near, .down)
            b = Safe.int(far, .up)
        }
        if a >= b { b = a + 1 }
        return AgeVerdict(direction: younger ? .younger : .older,
                          text: "\(a) to \(b) years \(younger ? "younger" : "older")")
    }

    /// "\u{2212}0.6x", "1.0x", "2.2x".
    static func paceText(_ value: Double) -> String {
        let text = String(format: "%.1f", abs(value))
        if Double(text) == 0 { return "0.0x" }
        return (value < 0 ? "\u{2212}" : "") + text + "x"
    }

    /// "\u{2212}1.0x to 2.2x".
    static func paceRangeText(low: Double, high: Double) -> String {
        "\(paceText(min(low, high))) to \(paceText(max(low, high)))"
    }

    /// Where a pace sits on the ruler, 0...1 from the left edge (\u{2212}1.0x) to the right (3.0x).
    static func paceFraction(_ value: Double, low: Double = -1, high: Double = 3) -> Double {
        guard high > low, value.isFinite else { return 0 }
        return min(max((value - low) / (high - low), 0), 1)
    }

    enum PaceChip: Equatable { case slower, steady, faster }

    /// Slower than the calendar (under 0.9x), about as fast (0.9x to 1.1x) or faster.
    static func paceChip(_ value: Double) -> PaceChip {
        if value < 0.9 { return .slower }
        if value > 1.1 { return .faster }
        return .steady
    }

    static func chipText(_ chip: PaceChip) -> String {
        switch chip {
        case .slower: return "SLOWER"
        case .steady: return "STEADY"
        case .faster: return "FASTER"
        }
    }

    /// Days until the next weekly update: the pace is refreshed once an ISO week, so the next one is the Monday after `asOf`.
    static func daysToNextUpdate(asOf: String) -> Int? {
        guard let index = PFDocDate.weekdayIndex(asOf) else { return nil }
        return 7 - index
    }

    /// "NEXT UPDATE IN 4 DAYS" / "NEXT UPDATE TOMORROW".
    static func nextUpdateText(asOf: String) -> String? {
        guard let days = daysToNextUpdate(asOf: asOf) else { return nil }
        return days == 1 ? "NEXT UPDATE TOMORROW" : "NEXT UPDATE IN \(days) DAYS"
    }

    /// "\u{2212}3.6" / "+0.8", the years a driver adds (+) or takes off (\u{2212}).
    static func yearsText(_ years: Double) -> String { PFNumber.signed(years, decimals: 1) }

    /// "\u{2212}4.7 to \u{2212}2.4".
    static func yearsRangeText(low: Double, high: Double) -> String {
        "\(yearsText(min(low, high))) to \(yearsText(max(low, high)))"
    }
}

/// A driver's 10-segment bar: the segments fill from the left towards the end that takes years off, with a marker for the
/// 6-month average and one for the last 30 days. Positions are in years of impact on one scale shared by every driver, so
/// the bars can be compared.
struct PFDriverBar: Equatable {
    static let segments = 10

    var filled: Int
    /// 0...1 from the end that adds years (left) to the end that takes years off (right).
    var marker6m: Double?
    var marker30d: Double?

    /// The shared scale: the largest impact in either window across the drivers, at least one year.
    static func scale(_ metrics: [PFPaceMetric], drivers: [PFHealthDriver] = []) -> Double {
        var largest = 1.0
        for m in metrics {
            largest = max(largest, abs(m.years6m ?? 0), abs(m.years30d ?? 0))
        }
        for d in drivers {
            largest = max(largest, abs(d.years ?? 0), abs(d.yearsLow ?? 0), abs(d.yearsHigh ?? 0))
        }
        return largest
    }

    static func position(years: Double, scale: Double) -> Double {
        guard scale > 0, years.isFinite else { return 0.5 }
        return min(max(0.5 - years / (2 * scale), 0), 1)
    }

    static func make(years6m: Double?, years30d: Double?, scale: Double) -> PFDriverBar {
        let six = years6m.map { position(years: $0, scale: scale) }
        let thirty = years30d.map { position(years: $0, scale: scale) }
        let filled = six.map { min(max(Safe.int(($0 * Double(segments))), 0), segments) } ?? 0
        return PFDriverBar(filled: filled, marker6m: six, marker30d: thirty)
    }

    /// A driver's bar from its own years and the 30-day figure the pace block holds for it.
    static func make(driver: PFHealthDriver, pace: PFPaceOfAging?, scale: Double) -> PFDriverBar {
        let thirty = pace?.metric(driver.key)?.years30d
        return make(years6m: driver.years ?? pace?.metric(driver.key)?.years6m, years30d: thirty, scale: scale)
    }
}

/// The weeks of body age and pace the phone has seen. The server holds only the current week, so each week's range is kept on
/// the phone (UserDefaults) the first time it is fetched; the week stepper and the trend card read from here.
struct PFHealthspanWeek: Codable, Equatable {
    var week: String
    var asOf: String
    var ageLow: Double
    var ageHigh: Double
    var paceValue: Double?
    var paceLow: Double?
    var paceHigh: Double?
}

enum PFHealthspanHistory {
    static let storageKey = "noop.paceforge.healthspan.weeks"
    static let maxWeeks = 78

    /// `weeks` with `entry` added, or replacing the entry of the same week; oldest first, capped.
    static func upserting(_ entry: PFHealthspanWeek, into weeks: [PFHealthspanWeek]) -> [PFHealthspanWeek] {
        var out = weeks.filter { $0.week != entry.week }
        out.append(entry)
        out.sort { $0.week < $1.week }
        return out.count > maxWeeks ? Array(out.suffix(maxWeeks)) : out
    }

    /// The current week's entry from the document; nil without a week key or a body age.
    static func entry(from h: PFHealthspan) -> PFHealthspanWeek? {
        guard let week = h.pace?.week, let body = h.bodyAge else { return nil }
        return PFHealthspanWeek(week: week, asOf: h.asOf ?? "", ageLow: body.low, ageHigh: body.high,
                                paceValue: h.pace?.value, paceLow: h.pace?.low, paceHigh: h.pace?.high)
    }

    static func encode(_ weeks: [PFHealthspanWeek]) -> Data? { try? JSONEncoder().encode(weeks) }

    static func decode(_ data: Data?) -> [PFHealthspanWeek] {
        guard let data, let weeks = try? JSONDecoder().decode([PFHealthspanWeek].self, from: data) else { return [] }
        return weeks.sorted { $0.week < $1.week }
    }

    /// The week `step` places from `week` in the stored list (\u{2212}1 earlier, +1 later), or nil at either end.
    static func neighbour(of week: String, step: Int, in weeks: [PFHealthspanWeek]) -> String? {
        guard let index = weeks.firstIndex(where: { $0.week == week }) else { return nil }
        let target = index + step
        return weeks.indices.contains(target) ? weeks[target].week : nil
    }
}

// MARK: - Journal impact

struct PFImpactEntry: Equatable, Identifiable {
    var id: String
    var label: String
    var group: String?
    var nWith: Int
    var nWithout: Int
    var meanWith: Double?
    var meanWithout: Double?
    var diff: Double?
    /// The signed percentage difference in the next morning's score.
    var pct: Double?
    var t: Double?
    var clear: Bool
    var strong: Bool
    var confidence: String?
    var note: String?
    var action: PFInsightAction?
}

struct PFNotEnough: Equatable, Identifiable {
    var id: String
    var label: String
    var group: String?
    var nWith: Int
    var nWithout: Int
}

struct PFJournalImpact: Equatable {
    var asOf: String?
    var windowDays: Int?
    var minEach: Int
    var outcomeLabel: String?
    var outcomeSource: String?
    var outcomeUnit: String?
    var outcomeDays: Int?
    var hurts: [PFImpactEntry] = []
    var helps: [PFImpactEntry] = []
    var noClearEffect: [PFImpactEntry] = []
    var notEnoughData: [PFNotEnough] = []
    var tested: Int?

    /// Every behaviour with a number, for finding the longest bar.
    var scored: [PFImpactEntry] { hurts + helps + noClearEffect }

    var hasAnyEffect: Bool { !hurts.isEmpty || !helps.isEmpty }
}

enum PFImpactFormat {
    /// "\u{2212}21 %", "+8 %".
    static func pctText(_ pct: Double) -> String {
        let whole = Safe.int(pct)
        if whole == 0 { return "0 %" }
        return (whole < 0 ? "\u{2212}" : "+") + "\(abs(whole)) %"
    }

    /// The longest bar's size: the largest effect on the screen, at least 10 %, so a lone 3 % effect is not drawn full width.
    static func barScale(_ entries: [PFImpactEntry]) -> Double {
        max(10, entries.compactMap { $0.pct.map(abs) }.max() ?? 10)
    }

    /// A bar as a share of the half-width it may use, 0...1.
    static func barFraction(_ pct: Double, scale: Double) -> Double {
        guard scale > 0, pct.isFinite else { return 0 }
        return min(abs(pct) / scale, 1)
    }

    /// The worst first.
    static func sortedHurts(_ entries: [PFImpactEntry]) -> [PFImpactEntry] {
        entries.sorted { ($0.pct ?? 0) < ($1.pct ?? 0) }
    }

    /// The best first.
    static func sortedHelps(_ entries: [PFImpactEntry]) -> [PFImpactEntry] {
        entries.sorted { ($0.pct ?? 0) > ($1.pct ?? 0) }
    }

    /// What a behaviour with too few days still needs: "Needs 4 more days with it and 5 without."
    static func needText(_ item: PFNotEnough, minEach: Int) -> String {
        let withMore = max(minEach - item.nWith, 0)
        let withoutMore = max(minEach - item.nWithout, 0)
        func days(_ n: Int) -> String { "\(n) more day\(n == 1 ? "" : "s")" }
        switch (withMore > 0, withoutMore > 0) {
        case (true, true): return "Needs \(days(withMore)) with it and \(days(withoutMore)) without."
        case (true, false): return "Needs \(days(withMore)) with it."
        case (false, true): return "Needs \(days(withoutMore)) without it."
        case (false, false): return "Has enough days; it is not clear yet."
        }
    }

    /// "66 days with it, 22 without".
    static func countsText(with nWith: Int, without nWithout: Int) -> String {
        "\(nWith) day\(nWith == 1 ? "" : "s") with it, \(nWithout) without"
    }
}

/// Which behaviours were already on screen the last time the Journal impact screen was opened, so a new one carries a NEW chip.
enum PFSeenIDs {
    static let storageKey = "noop.paceforge.journalImpact.seen"

    static func decode(_ raw: String?) -> Set<String>? {
        guard let raw else { return nil }
        return Set(raw.split(separator: ",").map(String.init))
    }

    static func encode(_ ids: Set<String>) -> String { ids.sorted().joined(separator: ",") }

    /// The ids in `current` the screen has not shown before. The very first visit marks nothing new (everything would be).
    static func newIDs(current: [String], seen: Set<String>?) -> Set<String> {
        guard let seen else { return [] }
        return Set(current).subtracting(seen)
    }

    static func updated(seen: Set<String>?, current: [String]) -> Set<String> {
        (seen ?? []).union(current)
    }
}

// MARK: - Highlights

struct PFRecordValue: Equatable {
    var value: Double
    var display: String?
    var date: String?
    var daysAgo: Int?
    var source: String?
    var label: String?
}

struct PFRecordPeriod: Equatable, Identifiable {
    /// 1M, 3M or all.
    var id: String
    var label: String
    var noop: PFRecordValue?
    var garmin: PFRecordValue?
}

struct PFRecord: Equatable, Identifiable {
    /// rest, charge or effort.
    var id: String
    var label: String
    var periods: [PFRecordPeriod] = []

    func period(_ id: String) -> PFRecordPeriod? { periods.first { $0.id == id } }
}

struct PFStreak: Equatable, Identifiable {
    var id: String
    var label: String
    var source: String?
    /// days or weeks.
    var unit: String
    var rule: String?
    var current: Int
    var best: Int
    var since: String?
    var alive: Bool
    var line: String?

    /// "6 Days", "1 Day", "2 Weeks".
    var countText: String {
        let noun = unit == "weeks" ? "Week" : "Day"
        return "\(current) \(noun)\(current == 1 ? "" : "s")"
    }

    /// "Best 7 weeks".
    var bestText: String {
        let noun = unit == "weeks" ? "week" : "day"
        return "Best \(best) \(noun)\(best == 1 ? "" : "s")"
    }
}

struct PFNotable: Equatable, Identifiable {
    var id: String
    var label: String
    var value: Double?
    var display: String
    var date: String?
    var daysAgo: Int?
    var source: String?
    var scope: String?
    var detail: String?
}

struct PFHighlights: Equatable {
    var asOf: String?
    var records: [PFRecord] = []
    var streaks: [PFStreak] = []
    var notable: [PFNotable] = []
    var noopSince: String?
    var garminSince: String?

    func record(_ id: String) -> PFRecord? { records.first { $0.id == id } }
    var hasContent: Bool { !records.isEmpty || !streaks.isEmpty || !notable.isEmpty }
}

enum PFHighlightPeriod: String, CaseIterable, Equatable {
    case month = "1M"
    case quarter = "3M"
    case allTime = "all"

    var title: String { self == .allTime ? "ALL TIME" : rawValue }
}

enum PFHighlightsLogic {
    /// The streak the Home chip and the insight card lead with: the longest alive streak counted in days, ties to the first
    /// listed. A weeks streak never wins over a days one; nil when nothing is alive.
    static func leadStreak(_ streaks: [PFStreak]) -> PFStreak? {
        var best: PFStreak?
        for s in streaks where s.alive && s.unit == "days" && s.current > 0 {
            if best == nil || s.current > (best?.current ?? 0) { best = s }
        }
        return best
    }

    /// The chip on the Home top bar: the count and what is being counted.
    struct Chip: Equatable {
        var count: Int
        var text: String
        var spoken: String
    }

    static func chip(_ h: PFHighlights?) -> Chip? {
        guard let h, let lead = leadStreak(h.streaks) else { return nil }
        let days = lead.current
        return Chip(count: days, text: "\(days)",
                    spoken: "\(days) day streak: \(lead.label)")
    }

    /// A dial's fraction on its 0-100 axis for the record's value in a period (NOOP side only), nil without a value.
    static func dialFraction(_ record: PFRecord, period: PFHighlightPeriod) -> Double? {
        guard let v = record.period(period.rawValue)?.noop?.value, v.isFinite else { return nil }
        return min(max(v / 100, 0), 1)
    }

    /// A value and unit from the server's display text: "39 bpm" gives ("39", "bpm"), "8 h 59" gives ("8:59", "hr"),
    /// "282 W" gives ("282", "W"), "1185" gives ("1185", "").
    static func valueParts(_ display: String) -> (number: String, unit: String) {
        let text = display.trimmingCharacters(in: .whitespaces)
        let words = text.split(separator: " ").map(String.init)
        if words.count == 3, words[1] == "h", Int(words[0]) != nil, let minutes = Int(words[2]) {
            return ("\(words[0]):" + String(format: "%02d", minutes), "hr")
        }
        guard let first = words.first else { return ("", "") }
        return (first, words.dropFirst().joined(separator: " "))
    }

    /// "1 Jun 2026" and, when the server says how long ago, "135 days ago".
    static func dateCaption(date: String?, daysAgo: Int?) -> String? {
        guard let date, let when = PFDocDate.dayMonthYear(date) else { return nil }
        guard let daysAgo else { return when }
        switch daysAgo {
        case 0: return "\(when) \u{00B7} today"
        case 1: return "\(when) \u{00B7} yesterday"
        default: return "\(when) \u{00B7} \(daysAgo) days ago"
        }
    }

    /// The SF Symbol of a notable stat.
    static func notableSymbol(_ id: String) -> String {
        switch id {
        case "rhr_low": return "heart"
        case "rhr_high": return "heart.fill"
        case "hrv_low", "hrv_high": return "waveform.path.ecg"
        case "sleep_longest": return "moon.zzz"
        case "max_hr": return "bolt.heart"
        case "longest_run": return "figure.run"
        case "power_20min": return "bolt"
        case "weekly_load": return "chart.bar"
        default: return "star"
        }
    }
}

// MARK: - Monthly report

struct PFMonthMeasure: Equatable {
    var value: Double
    var n: Int?
}

struct PFMonthRow: Equatable, Identifiable {
    /// charge, effort, rest, weight or fitness.
    var key: String
    var label: String
    var unit: String?
    var source: String?
    var seriesLabel: String?
    /// ok or not enough data.
    var state: String?
    var reason: String?
    var current: PFMonthMeasure?
    var previous: PFMonthMeasure?
    var delta: Double?
    var pct: Double?
    /// up, down or flat.
    var direction: String?
    /// better, worse, neutral or nil.
    var assessment: String?
    var id: String { key }

    var hasData: Bool { (state == nil || state == "ok") && current != nil }

    /// The triangle beside the figure: up or down, green when the change is the right way and amber when it is not, neutral
    /// when the server did not judge it. A flat month has none.
    var mark: (pointsUp: Bool, tone: PFMonthTone)? {
        guard hasData, direction == "up" || direction == "down" else { return nil }
        let tone: PFMonthTone
        switch assessment {
        case "better": tone = .good
        case "worse": tone = .bad
        default: tone = .neutral
        }
        return (direction == "up", tone)
    }
}

enum PFMonthTone: Equatable { case good, bad, neutral }

struct PFMonthMover: Equatable, Identifiable {
    var key: String
    var label: String
    var unit: String?
    var source: String?
    var previous: Double?
    var current: Double?
    var delta: Double?
    var pct: Double?
    var assessment: String?
    var whatMoved: [PFMoveLink] = []
    var action: PFInsightAction?
    var id: String { key }
}

struct PFMonthPeriod: Equatable, Identifiable {
    /// last_full or month_to_date.
    var id: String
    var label: String
    var from: String?
    var to: String?
    var days: Int?
    var comparedWith: String?
    var rows: [PFMonthRow] = []
    var movers: [PFMonthMover] = []
}

struct PFMonthGoal: Equatable, Identifiable {
    /// weight or race.
    var id: String
    var title: String
    var headline: String?
    var text: String?
    var status: String?
    var source: String?
}

struct PFMonthFocus: Equatable, Identifiable {
    var index: Int
    var text: String
    var why: String?
    var effortText: String?
    var topic: String?
    var id: Int { index }
}

struct PFMonthlyReport: Equatable {
    var asOf: String?
    var periods: [PFMonthPeriod] = []
    var goals: [PFMonthGoal] = []
    var focus: [PFMonthFocus] = []

    func period(_ id: String) -> PFMonthPeriod? { periods.first { $0.id == id } }
}

enum PFMonthlyFormat {
    /// A row's figure with its unit: "43.6 %", "7.2 of 21", "90.9 kg", "53.6 ml/kg/min".
    static func valueText(_ row: PFMonthRow, _ value: Double) -> String {
        let decimals = (row.unit == "%" && row.key != "weight") ? 0 : 1
        let number = String(format: "%.\(decimals)f", value)
        switch row.unit ?? "" {
        case "": return number
        case "%": return "\(number) %"
        default: return "\(number) \(row.unit ?? "")"
        }
    }

    /// "\u{2212}17.4 on August 2026" / "+8.9 on September 2026".
    static func deltaText(_ row: PFMonthRow, comparedWith: String?) -> String? {
        guard row.hasData, let delta = row.delta else { return nil }
        let size = PFNumber.signed(delta, decimals: abs(delta) >= 10 ? 0 : 1)
        guard let comparedWith, !comparedWith.isEmpty else { return size }
        return "\(size) on \(comparedWith)"
    }

    /// "Steady" for a flat month, else "Better" / "Worse" / "Up" / "Down".
    static func chipText(_ row: PFMonthRow) -> String? {
        guard row.hasData else { return nil }
        if row.direction == "flat" { return "STEADY" }
        switch row.assessment {
        case "better": return "BETTER"
        case "worse": return "WORSE"
        default:
            switch row.direction {
            case "up": return "UP"
            case "down": return "DOWN"
            default: return nil
            }
        }
    }
}

// MARK: - My plan

struct PFPlanItem: Equatable, Identifiable {
    var index: Int
    var label: String
    var done: Bool
    var date: String?
    var weekday: String?
    /// done, partial, missed, today or upcoming.
    var status: String
    var minutes: Int?
    var hard: Bool
    var sport: String?
    var id: Int { index }

    /// "Mon \u{00B7} 30 min".
    var detailText: String {
        var parts: [String] = []
        if let weekday { parts.append(weekday) }
        if let minutes { parts.append("\(minutes) min") }
        if hard { parts.append("hard") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

struct PFPlanNext: Equatable {
    var label: String
    var date: String?
    var weekday: String?
    var minutes: Int?
    var hard: Bool
    var sport: String?

    /// "Thu \u{00B7} 45 min".
    var detailText: String {
        var parts: [String] = []
        if let weekday { parts.append(weekday) }
        if let minutes { parts.append("\(minutes) min") }
        if hard { parts.append("hard") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

struct PFMyPlan: Equatable {
    var asOf: String?
    var weekFrom: String?
    var weekTo: String?
    var weekISO: String?
    var planName: String?
    var planPhase: String?
    var planned: Int
    var done: Int
    var partial: Int
    var missed: Int
    var pctAccomplished: Int?
    var daysLeft: Int?
    var next: PFPlanNext?
    var items: [PFPlanItem] = []
    /// on track, behind or done, in the server's words.
    var statusLabel: String?

    /// 0...1 for the progress bar.
    var progress: Double {
        guard let pct = pctAccomplished else { return planned > 0 ? Double(done) / Double(planned) : 0 }
        return min(max(Double(pct) / 100, 0), 1)
    }

    /// "5 DAYS LEFT \u{00B7} 62 % ACCOMPLISHED".
    var headerText: String {
        var parts: [String] = []
        if let daysLeft {
            switch daysLeft {
            case ...0: parts.append("WEEK COMPLETE")
            case 1: parts.append("1 DAY LEFT")
            default: parts.append("\(daysLeft) DAYS LEFT")
            }
        }
        if let pct = pctAccomplished { parts.append("\(pct) % ACCOMPLISHED") }
        return parts.joined(separator: " \u{00B7} ")
    }

    var hasContent: Bool { planned > 0 || !items.isEmpty }
}

// MARK: - The five documents together

struct PFIntelDocs: Equatable {
    var healthspan: PFDocState<PFHealthspan> = .missing
    var journalImpact: PFDocState<PFJournalImpact> = .missing
    var highlights: PFDocState<PFHighlights> = .missing
    var monthlyReport: PFDocState<PFMonthlyReport> = .missing
    var myPlan: PFDocState<PFMyPlan> = .missing

    /// True when none of the five was served (an old server, or offline with nothing cached).
    var isEmpty: Bool {
        healthspan.isMissing && journalImpact.isMissing && highlights.isMissing
            && monthlyReport.isMissing && myPlan.isMissing
    }
}

// MARK: - Parsing

enum PFIntelDocsParse {

    /// One item of a document, typed, or why it cannot be. `j` is the document root.
    static func state<T: Equatable>(_ j: PFJ, id: String, _ typed: (PFJ) -> T?) -> PFDocState<T> {
        guard j.exists, j.raw is [String: Any] else { return .missing }
        let order = j["order"].array.compactMap { $0.idString }
        var itemJSON = j["items"][id]
        var key = id
        if !itemJSON.exists, let first = order.first ?? j["items"].dict.keys.sorted().first {
            itemJSON = j["items"][first]
            key = first
        }
        guard itemJSON.exists, let base = PFInsightsV2Parse.item(itemJSON, key: key) else { return .missing }
        let item = PFIntelItem(base: base, sources: itemJSON["source"].strings)
        guard base.available else {
            return .unavailable(reason: base.meaning ?? base.status.reason ?? base.dataNote, item: item)
        }
        let metric = itemJSON["metric"]
        guard metric.exists, let value = typed(metric) else {
            return .unavailable(reason: "The document has no usable figures yet.", item: item)
        }
        return .ready(value, item: item)
    }

    static func docs(healthspan: PFJ, journalImpact: PFJ, highlights: PFJ, monthlyReport: PFJ, myPlan: PFJ) -> PFIntelDocs {
        PFIntelDocs(
            healthspan: state(healthspan, id: PFDocID.healthspan, Self.healthspan),
            journalImpact: state(journalImpact, id: PFDocID.journalImpact, Self.journalImpact),
            highlights: state(highlights, id: PFDocID.highlights, Self.highlights),
            monthlyReport: state(monthlyReport, id: PFDocID.monthlyReport, Self.monthlyReport),
            myPlan: state(myPlan, id: PFDocID.myPlan, Self.myPlan))
    }

    // MARK: healthspan

    static func healthspan(_ m: PFJ) -> PFHealthspan? {
        var out = PFHealthspan()
        out.asOf = m["as_of"].text
        out.label = m["label"].text
        out.age = m["age"].double
        out.sex = m["sex"].text
        out.windowDays = m["window_days"].int
        out.inputsAvailable = m["inputs_available"].int
        out.inputsTotal = m["inputs_total"].int
        out.missing = m["missing"].strings
        let b = m["body_age"]
        if let low = b["low"].double, let high = b["high"].double {
            var vs: PFYearsRange?
            if let a = b["years_vs_age"]["low"].double, let c = b["years_vs_age"]["high"].double {
                vs = PFYearsRange(low: a, high: c, mid: b["years_vs_age"]["mid"].double)
            }
            out.bodyAge = PFBodyAge(low: low, high: high, mid: b["mid"].double, text: b["text"].text, yearsVsAge: vs)
        }
        let p = m["pace"]
        if p.exists, p.raw is [String: Any] {
            // The ruler draws a tick every 0.1x, so a reversed, infinite or enormous range falls back to the usual -1x to 3x.
            let served = p["range"].array.compactMap { $0.double }
            let range = served.count == 2 && served[0].isFinite && served[1].isFinite && served[0] < served[1]
                && served[1] - served[0] <= 20 ? served : []
            out.pace = PFPaceOfAging(
                available: p["available"].bool ?? (p["value"].double != nil), reason: p["reason"].text,
                week: p["week"].text, computedOn: p["computed_on"].text, carried: p["carried"].bool ?? false,
                value: p["value"].double, low: p["low"].double, high: p["high"].double, label: p["label"].text,
                rangeLow: range.count == 2 ? range[0] : -1, rangeHigh: range.count == 2 ? range[1] : 3,
                basis: p["basis"].text,
                metrics: p["metrics"].array.compactMap { x in
                    guard let key = x["key"].text else { return nil }
                    return PFPaceMetric(key: key, label: x["label"].text ?? PFBand.titleFromId(key),
                                        years6m: x["years_6m"].double, years30d: x["years_30d"].double)
                })
        }
        out.drivers = m["drivers"].array.compactMap { d in
            guard let key = d["key"].text else { return nil }
            return PFHealthDriver(
                key: key, label: d["label"].text ?? PFBand.titleFromId(key), unit: d["unit"].text, source: d["source"].text,
                targetText: d["target_text"].text, note: d["note"].text, value: d["value"].double,
                valueText: d["value_text"].text, coverage: d["coverage"].double, status: d["status"].text ?? "unknown",
                years: d["years"].double, yearsLow: d["years_low"].double, yearsHigh: d["years_high"].double,
                action: PFInsightsV2Parse.action(d["action"]))
        }
        out.assumptions = m["assumptions"].strings
        return out.bodyAge != nil || out.pace != nil || !out.drivers.isEmpty ? out : nil
    }

    // MARK: journal_impact

    private static func impact(_ e: PFJ) -> PFImpactEntry? {
        guard let id = e["id"].text, let label = e["label"].text else { return nil }
        return PFImpactEntry(
            id: id, label: label, group: e["group"].text, nWith: e["n_with"].int ?? 0, nWithout: e["n_without"].int ?? 0,
            meanWith: e["mean_with"].double, meanWithout: e["mean_without"].double, diff: e["diff"].double,
            pct: e["pct"].double, t: e["t"].double, clear: e["clear"].bool ?? false, strong: e["strong"].bool ?? false,
            confidence: e["confidence"].text, note: e["note"].text, action: PFInsightsV2Parse.action(e["action"]))
    }

    static func journalImpact(_ m: PFJ) -> PFJournalImpact? {
        var out = PFJournalImpact(minEach: m["min_each"].int ?? 5)
        out.asOf = m["as_of"].text
        out.windowDays = m["window_days"].int
        out.outcomeLabel = m["outcome"]["label"].text
        out.outcomeSource = m["outcome"]["source"].text
        out.outcomeUnit = m["outcome"]["unit"].text
        out.outcomeDays = m["outcome"]["days"].int
        out.hurts = m["hurts"].array.compactMap(impact)
        out.helps = m["helps"].array.compactMap(impact)
        out.noClearEffect = m["no_clear_effect"].array.compactMap(impact)
        out.notEnoughData = m["not_enough_data"].array.compactMap { e in
            guard let id = e["id"].text, let label = e["label"].text else { return nil }
            return PFNotEnough(id: id, label: label, group: e["group"].text, nWith: e["n_with"].int ?? 0,
                               nWithout: e["n_without"].int ?? 0)
        }
        out.tested = m["tested"].int
        let any = !out.hurts.isEmpty || !out.helps.isEmpty || !out.noClearEffect.isEmpty || !out.notEnoughData.isEmpty
        return any ? out : nil
    }

    // MARK: highlights

    private static func recordValue(_ v: PFJ) -> PFRecordValue? {
        guard v.exists, v.raw is [String: Any], let value = v["value"].double else { return nil }
        return PFRecordValue(value: value, display: v["display"].text, date: v["date"].text, daysAgo: v["days_ago"].int,
                             source: v["source"].text, label: v["label"].text)
    }

    static func highlights(_ m: PFJ) -> PFHighlights? {
        var out = PFHighlights()
        out.asOf = m["as_of"].text
        out.noopSince = m["noop_since"].text
        out.garminSince = m["garmin_since"].text
        out.records = m["records"].array.compactMap { r in
            guard let id = r["id"].text else { return nil }
            let periods: [PFRecordPeriod] = r["periods"].array.compactMap { p in
                guard let pid = p["id"].text else { return nil }
                return PFRecordPeriod(id: pid, label: p["label"].text ?? pid, noop: recordValue(p["noop"]),
                                      garmin: recordValue(p["garmin"]))
            }
            return PFRecord(id: id, label: r["label"].text ?? PFBand.titleFromId(id), periods: periods)
        }
        out.streaks = m["streaks"].array.compactMap { s in
            guard let id = s["id"].text, let current = s["current"].int else { return nil }
            return PFStreak(id: id, label: s["label"].text ?? PFBand.titleFromId(id), source: s["source"].text,
                            unit: s["unit"].text ?? "days", rule: s["rule"].text, current: current,
                            best: s["best"].int ?? current, since: s["since"].text, alive: s["alive"].bool ?? false,
                            line: s["line"].text)
        }
        out.notable = m["notable"].array.compactMap { n in
            guard let id = n["id"].text, let display = n["display"].text else { return nil }
            return PFNotable(id: id, label: n["label"].text ?? PFBand.titleFromId(id), value: n["value"].double,
                             display: display, date: n["date"].text, daysAgo: n["days_ago"].int, source: n["source"].text,
                             scope: n["scope"].text, detail: n["detail"].text)
        }
        return out.hasContent ? out : nil
    }

    // MARK: monthly_report

    private static func measure(_ v: PFJ) -> PFMonthMeasure? {
        guard let value = v["value"].double else { return nil }
        return PFMonthMeasure(value: value, n: v["n"].int)
    }

    private static func moveLinks(_ list: PFJ) -> [PFMoveLink] {
        list.array.compactMap { l in
            guard let sentence = l["sentence"].text else { return nil }
            return PFMoveLink(behaviour: l["behaviour"].text, label: l["label"].text, sentence: sentence,
                              strength: l["strength"].text)
        }
    }

    private static func goal(_ id: String, title: String, _ g: PFJ, headline: String?) -> PFMonthGoal? {
        guard g.exists, g.raw is [String: Any], g["text"].text != nil || headline != nil else { return nil }
        return PFMonthGoal(id: id, title: title, headline: headline, text: g["text"].text, status: g["status"].text,
                           source: g["source"].text)
    }

    static func monthlyReport(_ m: PFJ) -> PFMonthlyReport? {
        var out = PFMonthlyReport()
        out.asOf = m["as_of"].text
        out.periods = m["periods"].array.compactMap { p in
            guard let id = p["id"].text else { return nil }
            var period = PFMonthPeriod(id: id, label: p["label"].text ?? PFBand.titleFromId(id), from: p["from"].text,
                                       to: p["to"].text, days: p["days"].int, comparedWith: p["compared_with"].text)
            period.rows = p["metrics"].array.compactMap { r in
                guard let key = r["key"].text else { return nil }
                return PFMonthRow(
                    key: key, label: r["label"].text ?? PFBand.titleFromId(key), unit: r["unit"].text,
                    source: r["source"].text, seriesLabel: r["series_label"].text, state: r["state"].text,
                    reason: r["reason"].text, current: measure(r["current"]), previous: measure(r["previous"]),
                    delta: r["delta"].double, pct: r["pct"].double, direction: r["direction"].text,
                    assessment: r["assessment"].text)
            }
            period.movers = p["movers"].array.compactMap { x in
                guard let key = x["key"].text else { return nil }
                return PFMonthMover(
                    key: key, label: x["label"].text ?? PFBand.titleFromId(key), unit: x["unit"].text,
                    source: x["source"].text, previous: x["previous"].double, current: x["current"].double,
                    delta: x["delta"].double, pct: x["pct"].double, assessment: x["assessment"].text,
                    whatMoved: moveLinks(x["what_moved"]), action: PFInsightsV2Parse.action(x["action"]))
            }
            return period
        }
        let g = m["goals"]
        var goals: [PFMonthGoal] = []
        let w = g["weight"]
        if let target = w["target_kg"].double {
            let headline = "\(PFNumber.trimmed(target)) kg" + (w["kg_to_go"].double.map { " \u{00B7} \(String(format: "%.1f", $0)) kg to go" } ?? "")
            if let item = goal("weight", title: "Weight goal", w, headline: headline) { goals.append(item) }
        }
        let r = g["race"]
        if let name = r["name"].text {
            let headline = name + (r["days_to"].int.map { " \u{00B7} in \($0) days" } ?? "")
            if let item = goal("race", title: "Race", r, headline: headline) { goals.append(item) }
        }
        out.goals = goals
        out.focus = m["focus"].array.enumerated().compactMap { index, f in
            guard let text = f["text"].text else { return nil }
            // `effort` is a plain sentence here ("no extra time"), an object in the item's `actions`.
            let effort = f["effort"].text ?? PFInsightsV2Parse.effort(f["effort"])?.text
            return PFMonthFocus(index: index, text: text, why: f["why"].text, effortText: effort, topic: f["topic"].text)
        }
        return out.periods.isEmpty ? nil : out
    }

    // MARK: my_plan

    static func myPlan(_ m: PFJ) -> PFMyPlan? {
        guard let planned = m["planned_sessions"].int else { return nil }
        var out = PFMyPlan(planned: planned, done: m["done"].int ?? 0, partial: m["partial"].int ?? 0,
                           missed: m["missed"].int ?? 0)
        out.asOf = m["as_of"].text
        out.weekFrom = m["week"]["from"].text
        out.weekTo = m["week"]["to"].text
        out.weekISO = m["week"]["iso"].text
        out.planName = m["plan"]["name"].text
        out.planPhase = m["plan"]["phase"].text
        out.pctAccomplished = m["pct_accomplished"].int
        out.daysLeft = m["days_left"].int
        let n = m["next_item"]
        if n.exists, n.raw is [String: Any], let label = n["label"].text {
            out.next = PFPlanNext(label: label, date: n["date"].text, weekday: n["weekday"].text,
                                  minutes: n["minutes"].int, hard: n["hard"].bool ?? false, sport: n["sport"].text)
        }
        out.items = m["items"].array.enumerated().compactMap { index, i in
            guard let label = i["label"].text else { return nil }
            let done = i["done"].bool ?? false
            return PFPlanItem(index: index, label: label, done: done, date: i["date"].text, weekday: i["weekday"].text,
                              status: i["status"].text ?? (done ? "done" : "upcoming"), minutes: i["minutes"].int,
                              hard: i["hard"].bool ?? false, sport: i["sport"].text)
        }
        return out.hasContent ? out : nil
    }
}
