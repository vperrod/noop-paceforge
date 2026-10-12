import Foundation

// Health report: the last 30 nights of the Health Monitor vitals (HRV, resting heart rate, respiratory rate,
// blood oxygen, skin temperature against your baseline) as plain figures for a shareable one-page PDF.
// Foundation only and pure: it takes nights already read from the daily rows and returns each vital's latest
// reading, average, range and a series to draw. The page that draws it is in HealthReportPage.swift. These are
// the numbers your strap recorded, shown without judgement: the report says so, and it is not medical advice.

/// One night's vitals, as read from the daily row. Any of them may be missing.
struct HealthReportNight: Equatable {
    var day: String
    var hrv: Double?
    var restingHr: Double?
    var respRate: Double?
    var spo2: Double?
    /// Skin temperature against the person's own baseline, in °C.
    var skinTempDev: Double?

    init(day: String, hrv: Double? = nil, restingHr: Double? = nil, respRate: Double? = nil, spo2: Double? = nil,
         skinTempDev: Double? = nil) {
        self.day = day
        self.hrv = hrv
        self.restingHr = restingHr
        self.respRate = respRate
        self.spo2 = spo2
        self.skinTempDev = skinTempDev
    }
}

enum HealthReportVitalKind: String, CaseIterable, Identifiable {
    case hrv, restingHr, respRate, spo2, skinTemp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: return "HRV"
        case .restingHr: return "Resting heart rate"
        case .respRate: return "Respiratory rate"
        case .spo2: return "Blood oxygen"
        case .skinTemp: return "Skin temperature"
        }
    }

    /// A line on what the figure is, for the page.
    var caption: String {
        switch self {
        case .hrv: return "Overnight heart-rate variability (RMSSD)."
        case .restingHr: return "Lowest steady heart rate of the night."
        case .respRate: return "Breaths per minute while asleep."
        case .spo2: return "Average blood-oxygen saturation while asleep."
        case .skinTemp: return "Skin temperature against your own baseline."
        }
    }

    func unit(fahrenheit: Bool) -> String {
        switch self {
        case .hrv: return "ms"
        case .restingHr: return "bpm"
        case .respRate: return "breaths/min"
        case .spo2: return "%"
        case .skinTemp: return fahrenheit ? "\u{00B0}F vs baseline" : "\u{00B0}C vs baseline"
        }
    }

    var decimals: Int {
        switch self {
        case .hrv, .restingHr: return 0
        case .respRate, .spo2: return 1
        case .skinTemp: return 2
        }
    }

    /// Skin temperature is a deviation, so it is shown with its sign.
    var isSigned: Bool { self == .skinTemp }
}

struct HealthReportVital: Identifiable, Equatable {
    var kind: HealthReportVitalKind
    var fahrenheit = false
    /// The most recent night with a reading, and its day.
    var latest: Double?
    var latestDay: String?
    var mean: Double?
    var minimum: Double?
    var maximum: Double?
    /// How many of the nights carried a reading.
    var nights = 0
    /// The readings, oldest first, for a small chart.
    var series: [Double] = []
    /// The latest reading minus the average of the other nights; nil with fewer than two readings.
    var deltaVsAverage: Double?

    var id: String { kind.rawValue }
    var hasData: Bool { nights > 0 }

    /// "58", "14.2", "+0.30": the number as the page prints it.
    func text(_ value: Double) -> String {
        let shown = fahrenheit && kind == .skinTemp ? value * 1.8 : value
        let body = String(format: "%.\(kind.decimals)f", abs(shown))
        if kind.isSigned {
            if Double(body) == 0 { return body }
            return (shown < 0 ? "\u{2212}" : "+") + body
        }
        return shown < 0 ? "\u{2212}" + body : body
    }

    var unit: String { kind.unit(fahrenheit: fahrenheit) }

    /// "+3 on your 30-night average", "\u{2212}0.20 on your 30-night average", or nil.
    func deltaText(nightsInReport: Int) -> String? {
        guard let deltaVsAverage else { return nil }
        let shown = fahrenheit && kind == .skinTemp ? deltaVsAverage * 1.8 : deltaVsAverage
        let body = String(format: "%.\(kind.decimals)f", abs(shown))
        let sign = Double(body) == 0 ? "" : (shown < 0 ? "\u{2212}" : "+")
        return "\(sign)\(body) on your \(nightsInReport)-night average"
    }
}

struct HealthReport: Equatable {
    var start: String
    var end: String
    /// The window the report covers, in nights.
    var windowNights: Int
    var vitals: [HealthReportVital]

    /// True when no vital has a single reading in the window.
    var isEmpty: Bool { vitals.allSatisfy { !$0.hasData } }
}

enum HealthReportData {
    static let windowNights = 30

    /// The report for the `nights` days ending `today` (yyyy-MM-dd): every vital in a fixed order, each with
    /// its latest reading, average, range and series. A vital with no reading in the window is kept, with
    /// `nights == 0`, so the page can say so.
    static func build(nights list: [HealthReportNight], today: String, nights count: Int = windowNights,
                      fahrenheit: Bool = false) -> HealthReport {
        let start = day(today, minus: count - 1)
        let window = list.filter { $0.day >= start && $0.day <= today }.sorted { $0.day < $1.day }
        let vitals = HealthReportVitalKind.allCases.map { kind in
            vital(kind, in: window, fahrenheit: fahrenheit)
        }
        return HealthReport(start: start, end: today, windowNights: count, vitals: vitals)
    }

    private static func reading(_ kind: HealthReportVitalKind, _ night: HealthReportNight) -> Double? {
        let value: Double?
        switch kind {
        case .hrv: value = night.hrv
        case .restingHr: value = night.restingHr
        case .respRate: value = night.respRate
        case .spo2: value = night.spo2
        case .skinTemp: return night.skinTempDev
        }
        // A zero or negative figure for these is a missing reading, not a measurement.
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func vital(_ kind: HealthReportVitalKind, in window: [HealthReportNight], fahrenheit: Bool) -> HealthReportVital {
        var out = HealthReportVital(kind: kind, fahrenheit: fahrenheit)
        let readings = window.compactMap { night in reading(kind, night).map { (day: night.day, value: $0) } }
        guard let last = readings.last else { return out }
        let values = readings.map(\.value)
        out.nights = values.count
        out.series = values
        out.latest = last.value
        out.latestDay = last.day
        out.mean = values.reduce(0, +) / Double(values.count)
        out.minimum = values.min()
        out.maximum = values.max()
        if values.count >= 2 {
            let others = values.dropLast()
            out.deltaVsAverage = last.value - others.reduce(0, +) / Double(others.count)
        }
        return out
    }

    /// The day `n` days before `day` (yyyy-MM-dd), by calendar days. An unreadable day is returned unchanged.
    static func day(_ day: String, minus n: Int) -> String {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let earlier = calendar.date(byAdding: .day, value: -n, to: date) else { return day }
        let c = calendar.dateComponents([.year, .month, .day], from: earlier)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
