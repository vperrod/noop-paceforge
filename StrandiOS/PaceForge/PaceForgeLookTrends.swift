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
