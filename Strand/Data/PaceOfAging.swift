import Foundation

// Pace of aging: how fast Body Age has been moving, from the weekly Body Age series that Vitality already
// stores. Over the last 30 days a straight line is fitted through the weekly readings; its slope is the change
// in Body Age, and "years per year" is that change added to the one year a year always brings (a pace of 1.0
// means your Body Age is keeping step with the calendar, below 1.0 it is falling behind it). It needs at least
// four weekly readings; with fewer it says so instead of guessing. Foundation only and pure, so it is unit-tested.
// It is a wellness trend taken from habits, not a clinical measure of biological aging.

enum PaceOfAging {
    /// Weekly readings needed before a number is shown.
    static let minPoints = 4
    /// The window the line is fitted over, in days ending today.
    static let windowDays = 30
    /// The displayed pace is held between these, because a month of readings stretched to a year can swing far.
    static let paceRange: ClosedRange<Double> = -3...5

    struct Reading: Equatable {
        /// Body Age change over 30 days, in years (negative = younger).
        var changeYears: Double
        /// Years of Body Age per calendar year, held to `paceRange`.
        var yearsPerYear: Double
        var isCapped: Bool
        var pointsUsed: Int
    }

    enum Outcome: Equatable {
        /// Not enough weekly readings yet: how many there are, and how many are needed.
        case calibrating(have: Int, need: Int)
        case ready(Reading)
    }

    /// `series` is (day yyyy-MM-dd, Body Age in years), any order. Readings outside the 30 days ending `today`
    /// are ignored, as are repeated days (the last one wins).
    static func compute(series: [(day: String, value: Double)], today: String) -> Outcome {
        let start = day(today, minus: windowDays)
        var byDay: [String: Double] = [:]
        for point in series where point.day >= start && point.day <= today && point.value.isFinite {
            byDay[point.day] = point.value
        }
        let points = byDay.sorted { $0.key < $1.key }
        guard points.count >= minPoints else { return .calibrating(have: points.count, need: minPoints) }
        let xs = points.compactMap { dayNumber($0.key) }
        guard xs.count == points.count else { return .calibrating(have: 0, need: minPoints) }
        let ys = points.map(\.value)
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var covariance = 0.0, variance = 0.0
        for index in xs.indices {
            covariance += (xs[index] - meanX) * (ys[index] - meanY)
            variance += (xs[index] - meanX) * (xs[index] - meanX)
        }
        guard variance > 0 else { return .calibrating(have: points.count, need: minPoints) }
        let slopePerDay = covariance / variance
        let raw = 1 + slopePerDay * 365.25
        let pace = min(max(raw, paceRange.lowerBound), paceRange.upperBound)
        return .ready(Reading(changeYears: slopePerDay * Double(windowDays), yearsPerYear: pace,
                              isCapped: pace != raw, pointsUsed: points.count))
    }

    // MARK: Words

    /// "0.6", "1.0", "-0.4": the pace on the card, one decimal.
    static func paceText(_ reading: Reading) -> String {
        let text = String(format: "%.1f", abs(reading.yearsPerYear))
        if Double(text) == 0 { return text }
        return (reading.yearsPerYear < 0 ? "\u{2212}" : "") + text
    }

    /// "Body Age down 0.4 years in 30 days", "Body Age up 0.2 years in 30 days", "Body Age steady over 30 days".
    static func changeLine(_ reading: Reading) -> String {
        let text = String(format: "%.1f", abs(reading.changeYears))
        if Double(text) == 0 { return "Body Age steady over \(windowDays) days" }
        return "Body Age \(reading.changeYears < 0 ? "down" : "up") \(text) years in \(windowDays) days"
    }

    /// "Ageing 0.6 years per year", the card's headline.
    static func headline(_ reading: Reading) -> String { "Ageing \(paceText(reading)) years per year" }

    /// What the card says before there are enough readings.
    static func calibrationLine(have: Int, need: Int) -> String {
        "Pace of aging needs at least \(need) weekly Body Age readings from the last \(windowDays) days. You have \(have)."
    }

    // MARK: Days

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private static func date(_ day: String) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Days since 1970-01-01 of a yyyy-MM-dd day.
    private static func dayNumber(_ day: String) -> Double? {
        date(day).map { ($0.timeIntervalSince1970 / 86_400).rounded() }
    }

    static func day(_ day: String, minus n: Int) -> String {
        guard let date = date(day), let earlier = calendar.date(byAdding: .day, value: -n, to: date) else { return day }
        let c = calendar.dateComponents([.year, .month, .day], from: earlier)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
