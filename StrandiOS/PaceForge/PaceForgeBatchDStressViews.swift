#if os(iOS)
import SwiftUI
import StrandDesign

// Weekly stress load on Insights > Deep dives (see PaceForgeBandBatchD.swift for the numbers): the last weeks' hours a day above the
// athlete's own high-stress level and restful minutes a day, against their own usual day. Garmin's all-day stress, worked out by Garmin
// from heart-rate variability; NOOP's own Stress screen is a different calculation and the two are never merged. A daytime signal, so a
// watch worn by day only gets it too.

/// The cards the batch D store feeds on Insights. Started from here so the load runs whether or not any card has something to draw yet.
struct PFBatchDInsightsCards: View {
    @ObservedObject private var store = PFBatchDStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let load = store.stressLoad { PFStressLoadCard(load: load) }
        }
        .task { await store.refreshIfStale() }
    }
}

struct PFStressLoadCard: View {
    let load: PFStressLoad

    private var highMax: Double { max(load.weeks.map { $0.highHoursPerDay }.max() ?? 0, load.normHighHoursPerDay ?? 0) }
    private var restfulMax: Double { max(load.weeks.map { $0.restfulMinPerDay }.max() ?? 0, load.normRestfulMinPerDay ?? 0) }

    var body: some View {
        PFCard("Weekly stress load", icon: "waveform.path") {
            VStack(alignment: .leading, spacing: 14) {
                PFSourceLabel(title: "Garmin all-day stress", source: load.source)
                PFStressMetric(title: "Hours a day above your high-stress level", unit: "h", points: load.weeks.map { PFStressPoint(week: $0, value: $0.highHoursPerDay) },
                               norm: load.normHighHoursPerDay, maximum: highMax, trend: load.highTrend, decimals: 1)
                PFStressMetric(title: "Restful minutes a day", unit: "min", points: load.weeks.map { PFStressPoint(week: $0, value: $0.restfulMinPerDay) },
                               norm: load.normRestfulMinPerDay, maximum: restfulMax, trend: load.restfulTrend, decimals: 0)
                if let line = load.line { PFParagraph(line) }
                if let gloss = load.gloss {
                    Text(gloss)
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .containerIdentifier("pf-stress-load")
    }
}

private struct PFStressPoint: Identifiable {
    let week: PFStressWeek
    let value: Double

    var id: String { week.id }
}

/// One measure over the weeks: a bar per week, the athlete's usual day marked on each, and whether the newest week is rising, steady or falling.
private struct PFStressMetric: View {
    let title: String
    let unit: String
    let points: [PFStressPoint]
    let norm: Double?
    let maximum: Double
    let trend: String?
    let decimals: Int

    private func valueText(_ value: Double) -> String {
        decimals == 0 ? "\(Safe.int(value)) \(unit)" : "\(PFFormat.oneDecimal(value)) \(unit)"
    }

    private var usualText: String? { norm.map { "Your usual day: " + valueText($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                if let word = PFBatchDLogic.trendWord(trend) { PFChip(text: word, color: PFColor.sky) }
            }
            ForEach(points) { point in
                PFStressWeekBar(label: PFFormat.shortDate(point.week.weekStart), partial: !point.week.complete, value: valueText(point.value),
                                bar: PFBatchDLogic.fraction(point.value, of: maximum), norm: norm.flatMap { PFBatchDLogic.fraction($0, of: maximum) })
            }
            if let usualText { Text(usualText).font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PFStressWeekBar: View {
    let label: String
    let partial: Bool
    let value: String
    let bar: Double?
    let norm: Double?

    private var labelText: String { partial ? label + " (part)" : label }

    var body: some View {
        HStack(spacing: 8) {
            Text(labelText)
                .font(LookFont.text(12, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .frame(width: 86, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(NoopLook.track)
                    Capsule()
                        .fill(NoopLook.rest.opacity(partial ? 0.35 : 0.6))
                        .frame(width: max(width * CGFloat(bar ?? 0), 3))
                    if let norm {
                        Rectangle()
                            .fill(NoopLook.textPrimary)
                            .frame(width: 1.5, height: 12)
                            .offset(x: min(width * CGFloat(norm), width - 1.5))
                    }
                }
            }
            .frame(height: 12)
            Text(value)
                .font(LookFont.text(13, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .frame(width: 64, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
