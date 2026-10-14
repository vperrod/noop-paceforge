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
                          what: "Your chronic training load: the long-run average of your daily training, about six weeks. Higher means more built-up fitness."),
            PFLook.metric(id: "atl", title: "Fatigue (ATL)", icon: "bolt.heart", decimals: 0, higherIsBetter: nil,
                          rows: history.map { (date: $0.date, value: $0.atl) },
                          what: "Your acute training load: the last week or so of training. It rises fast after a hard block and falls fast with rest."),
            PFLook.metric(id: "tsb", title: "Form (TSB)", icon: "gauge.medium", decimals: 0, higherIsBetter: nil,
                          rows: history.map { (date: $0.date, value: $0.tsb) },
                          what: "Fitness minus fatigue. Below zero you are carrying fatigue; a little above zero is fresh, which is where race day should land."),
        ])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pf-load-trend")
    }
}
