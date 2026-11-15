#if os(iOS)
import SwiftUI
import StrandDesign

/// The small triangle on a Key Metrics tile: today's value against the 30-day usual, read from the same series and decided by the same
/// rule as the "Today vs 30 days" rows (`LookBaseline.comparison`), so a tile and a row never disagree. Green when the move is the good
/// way for that metric, red when it is the other way, grey when the metric has no good direction. Draws nothing without a baseline, or
/// when the two read the same.
struct KeyTileMark: View {
    let metric: MetricDescriptor
    let day: Date
    let effortScale: EffortScale

    @EnvironmentObject private var repo: Repository
    @State private var mark: LookTodayMark?

    private var loadKey: String {
        "\(repo.refreshSeq)|\(metric.key)|\(metric.source)|\(Int(day.timeIntervalSince1970))|\(effortScale == .whoop)"
    }

    var body: some View {
        Group {
            if let mark { LookTriangleMark(mark) }
        }
        .task(id: loadKey) { await load() }
    }

    @MainActor private func load() async {
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        let series = await repo.exploreSeries(key: metric.key, source: metric.source, days: 120)
        let points = LookSeries.points(series, calendar: calendar).filter { $0.date < endOfDay }
        let isEffort = metric.key == HeroRingMetric.effort
        let scaled = isEffort
            ? points.map { LookPoint(date: $0.date, value: UnitFormatter.effortValue($0.value, scale: effortScale)) }
            : points
        let decimals = isEffort ? (effortScale == .whoop ? 1 : 0) : metric.decimals
        let result = LookBaseline.comparison(scaled, decimals: decimals, higherIsBetter: metric.higherIsBetter, calendar: calendar)?.mark
        guard !Task.isCancelled else { return }
        mark = result
    }
}
#endif
