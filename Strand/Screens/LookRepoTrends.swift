#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Look trends over the repository's daily series
//
// `LookTrendView` fed from `Repository.exploreSeries` for a list of catalog metrics: the metric dropdown on NOOP
// Trends and the Sleep tab's sleep trends. Each metric is read once per data refresh; a metric with no readings is
// left out of the dropdown. Nothing is scored or stored here.

struct LookRepoTrends: View {
    /// (catalog key, source) in dropdown order.
    let specs: [(key: String, source: String)]
    var initialKey: String? = nil
    var identifier: String = "look-repo-trends"

    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var metrics: [LookTrendMetric] = []
    @State private var loaded = false

    private var loadKey: String { "\(repo.refreshSeq)|\(effortScaleRaw)" }

    var body: some View {
        // A ZStack with a zero-size anchor, not a bare Group: an empty Group has no view, so its .task never starts
        // and the metrics would never load.
        ZStack {
            Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            if !metrics.isEmpty {
                LookTrendHost(metrics: metrics, initialMetricID: initialID, initialRange: .month,
                              footer: { AnyView(PFWhatMovedSection(metricID: $0.id)) })
            } else if loaded {
                LookInfoCard(title: "No trend yet",
                             message: "Trends draw once a few days of readings are in. Import your history in Data Sources or wear the strap for a few nights.")
            }
        }
        .containerIdentifier(identifier)
        .task(id: loadKey) { await load() }
    }

    private var initialID: String? {
        guard let initialKey else { return nil }
        return metrics.first { $0.id.hasSuffix(":\(initialKey)") }?.id
    }

    @MainActor private func load() async {
        let calendar = Calendar.current
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        var built: [LookTrendMetric] = []
        for spec in specs {
            guard let descriptor = MetricCatalog.metric(key: spec.key, source: spec.source) else { continue }
            let rows = await repo.exploreSeries(key: spec.key, source: spec.source, days: 800)
            var points = LookSeries.points(rows, calendar: calendar)
            guard points.count >= 2 else { continue }
            let isEffort = spec.key == HeroRingMetric.effort
            if isEffort {
                points = points.map { LookPoint(date: $0.date, value: UnitFormatter.effortValue($0.value, scale: scale)) }
            }
            let blurb = descriptor.description
                ?? "Your daily \(descriptor.title.lowercased()) from \(descriptor.sourceLabel). Compare it with your own typical range, not with anyone else's."
            built.append(LookTrendMetric(
                id: descriptor.id, title: descriptor.title, icon: descriptor.icon,
                unit: isEffort ? "" : descriptor.unit, decimals: isEffort ? (scale == .whoop ? 1 : 0) : descriptor.decimals,
                higherIsBetter: descriptor.higherIsBetter, style: isEffort ? .bars : .line, points: points,
                caption: descriptor.description,
                info: LookTrendInfo(title: "What is \(descriptor.title.lowercased())?", message: blurb)))
        }
        guard !Task.isCancelled else { return }
        metrics = built
        loaded = true
    }
}

extension LookRepoTrends {
    /// The metrics NOOP Trends offers, Charge / Effort / Rest first.
    static let trendsSpecs: [(key: String, source: String)] = [
        ("recovery", "my-whoop"), ("strain", "my-whoop"), ("sleep_performance", "my-whoop"), ("hrv", "my-whoop"),
        ("rhr", "my-whoop"), ("resp_rate", "my-whoop"), ("spo2", "my-whoop"), ("sleep_total_min", "my-whoop"),
        ("sleep_efficiency", "my-whoop"), ("sleep_consistency", "my-whoop"), ("hours_vs_needed_pct", "my-whoop"),
        ("sleep_debt_min", "my-whoop"), ("hr_zones13_min", "my-whoop"), ("hr_zones45_min", "my-whoop"),
        ("strength_min", "my-whoop"), ("avg_hr", "my-whoop"), ("energy_kcal", "my-whoop"), ("stress", "my-whoop"),
    ]

    /// The sleep metrics the Sleep tab offers.
    static let sleepSpecs: [(key: String, source: String)] = [
        ("sleep_total_min", "my-whoop"), ("sleep_performance", "my-whoop"), ("hours_vs_needed_pct", "my-whoop"),
        ("sleep_efficiency", "my-whoop"), ("sleep_consistency", "my-whoop"), ("sleep_deep_min", "my-whoop"),
        ("sleep_rem_min", "my-whoop"), ("sleep_light_min", "my-whoop"), ("sleep_debt_min", "my-whoop"),
        ("resp_rate", "my-whoop"),
    ]
}
#endif
