#if !os(watchOS)
import SwiftUI

// MARK: - LookTrendHost
//
// The state holder around `LookTrendView` (metric, range, end date) for screens that just have a list of metrics:
// NOOP Trends, a metric's detail, the sleep tab, the PaceForge Insights and Body screens. The window starts on the
// 30-day view ending today, as the reference does for a fresh metric.

public struct LookTrendHost: View {
    public var metrics: [LookTrendMetric]
    public var initialMetricID: String?
    public var initialRange: LookRange
    public var calendar: Calendar
    public var today: Date

    @State private var metricID: String
    @State private var range: LookRange
    @State private var endDate: Date

    public init(metrics: [LookTrendMetric], initialMetricID: String? = nil, initialRange: LookRange = .month,
                calendar: Calendar = .current, today: Date = Date()) {
        self.metrics = metrics
        self.initialMetricID = initialMetricID
        self.initialRange = initialRange
        self.calendar = calendar
        let day = calendar.startOfDay(for: today)
        self.today = day
        self._metricID = State(initialValue: initialMetricID ?? metrics.first?.id ?? "")
        self._range = State(initialValue: initialRange)
        self._endDate = State(initialValue: day)
    }

    public var body: some View {
        LookTrendView(metrics: metrics, metricID: $metricID, range: $range, endDate: $endDate,
                      today: today, calendar: calendar)
            .padding(.horizontal, -NoopLook.Metric.screenInset)
    }
}
#endif
