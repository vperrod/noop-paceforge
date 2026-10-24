import SwiftUI
import StrandDesign

// MARK: - PaceForge series in the look's trend view
//
// PaceForge serves its history as dated rows ("yyyy-MM-dd"). This turns a row list into a `LookTrendMetric` so the
// Insights detail screens and the Body trend use the same trend template as NOOP Trends: metric dropdown, average
// with change against the period before, W / M / 6M / Y, a date stepper, a typical band and the 7-day average.
// The numbers are the server's, drawn as served; nothing is re-derived.

enum PFLook {
    static func points(_ rows: [(date: String, value: Double)]) -> [LookPoint] {
        let calendar = Calendar.current
        return rows.compactMap { row -> LookPoint? in
            guard row.value.isFinite else { return nil }
            return LookPoint(date: calendar.startOfDay(for: PFFormat.date(row.date)), value: row.value)
        }
    }

    static func metric(id: String, title: String, icon: String, unit: String = "", decimals: Int = 0,
                       higherIsBetter: Bool? = true, style: LookTrendStyle = .line,
                       rows: [(date: String, value: Double)], caption: String? = nil,
                       what: String? = nil) -> LookTrendMetric {
        LookTrendMetric(id: id, title: title, icon: icon, unit: unit, decimals: decimals,
                        higherIsBetter: higherIsBetter, style: style, points: points(rows), caption: caption,
                        info: what.map { LookTrendInfo(title: "What is \(title.lowercased())?", message: $0) })
    }
}

/// Fitness, fatigue and form over the history PaceForge keeps, as one trend with a dropdown.
struct PFLoadTrend: View {
    let history: [PFLoadPoint]

    var body: some View {
        LookTrendHost(metrics: [
            PFLook.metric(id: "ctl", title: "Fitness (CTL)", icon: "figure.run", decimals: 0, higherIsBetter: true,
                          rows: history.map { (date: $0.date, value: $0.ctl) },
                          what: "Your chronic training load: a smoothed view of roughly the past six weeks. It helps track how your training has built over time; a higher value is not automatically better."),
            PFLook.metric(id: "atl", title: "Fatigue (ATL)", icon: "bolt.heart", decimals: 0, higherIsBetter: nil,
                          rows: history.map { (date: $0.date, value: $0.atl) },
                          what: "Your acute training load: a faster-moving summary of recent training, roughly the past week. Read it with your recovery signals, completed sessions and how you feel; it is not a direct fatigue measurement."),
            PFLook.metric(id: "tsb", title: "Form (TSB)", icon: "gauge.medium", decimals: 0, higherIsBetter: nil,
                          rows: history.map { (date: $0.date, value: $0.tsb) },
                          what: "Fitness (CTL) minus recent load (ATL), used as a training-form estimate. It is one modelled view of load balance, not a direct measure of freshness or a universal race-day target."),
        ])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pf-load-trend")
    }
}
