#if os(iOS)
import SwiftUI
import StrandDesign

/// The small triangle on a Key Metrics tile: today's value against the 30-day usual, read from the same series and decided by the same
/// rule as the "Today vs 30 days" rows (`LookBaseline.comparison`), so a tile and a row never disagree. Green when the move is the good
/// way for that metric, red when it is the other way, grey when the metric has no good direction. Draws nothing without a baseline, or
/// when the two read the same.
/// The 120-day series the marks read, kept per data refresh so the tiles of one Today (and a day change, which only moves the cut-off)
/// do not each ask the repository again; tiles that ask for the same series at once share one read.
@MainActor
private final class KeyTileSeriesCache {
    static let shared = KeyTileSeriesCache()

    private var seq = -1
    private var series: [String: [(day: String, value: Double)]] = [:]
    private var inFlight: [String: Task<[(day: String, value: Double)], Never>] = [:]

    func series(key: String, source: String, seq current: Int, repo: Repository) async -> [(day: String, value: Double)] {
        if current != seq {
            seq = current
            series = [:]
            inFlight = [:]
        }
        let id = "\(source)|\(key)"
        if let known = series[id] { return known }
        if let running = inFlight[id] { return await running.value }
        let task = Task { await repo.exploreSeries(key: key, source: source, days: 120) }
        inFlight[id] = task
        let loaded = await task.value
        if seq == current {
            series[id] = loaded
            inFlight[id] = nil
        }
        return loaded
    }
}

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
        let series = await KeyTileSeriesCache.shared.series(key: metric.key, source: metric.source, seq: repo.refreshSeq, repo: repo)
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
