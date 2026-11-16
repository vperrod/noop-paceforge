import SwiftUI
import StrandDesign

/// What the journal learned (screen 5e): one outcome and one lag at a time, the behaviours with a clear effect, those with none, and the
/// questions still collecting. Every result is read from one device's measure, WHOOP or Garmin, and the screen names it; the two are never
/// averaged. The numbers come from `insights` in data/journal-view.json, the days still needed from `list`.
struct PFJournalInsightsBody530: View {
    typealias Logic = PFJournalLogic530

    let doc: PFJournalDoc530

    @State private var outcome = "recovery"
    @State private var lag = 1
    @State private var seriesID: String?
    @State private var showsAllCollecting = false
    private let hiding = PFHiding()

    /// The first questions shown under "Still collecting"; the rest are one tap away.
    private static let collectingShown = 3

    private var series: [Logic.Series] { Logic.series(doc.insights, outcome: outcome) }

    private var selected: Logic.Series? {
        series.first { $0.id == seriesID } ?? series.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionChips(options: Logic.outcomes, selection: $outcome, idPrefix: "pf530-insight-outcome",
                         id: { $0 }, title: { Logic.outcomeTitle($0) })
            SectionChips(options: [1, 2], selection: $lag, idPrefix: "pf530-insight-lag",
                         id: { String($0) }, title: { Logic.lagTitle($0) })
            if series.count > 1 {
                SectionChips(options: series, selection: seriesBinding, idPrefix: "pf530-insight-series",
                             id: { $0.id.replacingOccurrences(of: "|", with: "-").lowercased() }, title: { $0.title })
            }
            results
            collecting
        }
        .containerIdentifier("pf530-insights-body")
        .onChange(of: outcome) { _, _ in seriesID = nil }
    }

    private var seriesBinding: Binding<Logic.Series> {
        Binding(get: { selected ?? Logic.Series(outcome: outcome, device: "", measure: "", unit: "") },
                set: { seriesID = $0.id })
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        if let selected {
            let split = Logic.split(doc.insights, series: selected, lag: lag)
            if split.clear.isEmpty && split.noEffect.isEmpty {
                noResults(for: selected)
            } else {
                ForEach(Array(split.clear.enumerated()), id: \.offset) { _, insight in clearCard(insight, series: selected) }
                if !split.noEffect.isEmpty { noEffectCard(split.noEffect, series: selected) }
            }
        } else {
            noResults(for: nil)
        }
    }

    private func noResults(for series: Logic.Series?) -> some View {
        let what = series.map { "\($0.title) " } ?? "\(Logic.outcomeTitle(outcome)) "
        return VStack(alignment: .leading, spacing: 6) {
            PFOver529(text: "No result yet")
            Text("No behaviour has \(Logic.daysNeeded) days with it and \(Logic.daysNeeded) without it against \(what)\(Logic.lagTitle(lag).lowercased()) yet.")
                .font(LookFont.text(14))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planCard529()
        .containerIdentifier("pf530-insight-empty")
    }

    private func clearCard(_ insight: Logic.Insight, series: Logic.Series) -> some View {
        let id = insight.behaviour ?? insight.label ?? "behaviour"
        let days = (insight.nWith ?? 0) + (insight.nWithout ?? 0)
        let hurts = (insight.diff ?? 0) < 0
        let withValue = insight.meanWith ?? 0
        let withoutValue = insight.meanWithout ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: "Clear effect · \(Logic.lagTitle(lag).lowercased()) \(series.title) · \(days) days")
            barRow(label: insight.label ?? id, value: shown(withValue, series.unit), fraction: Logic.barFraction(withValue, unit: series.unit),
                   color: hurts ? NoopLook.trendDown : NoopLook.trendUp, id: "pf530-insight-with-\(id)")
            barRow(label: "Without it", value: shown(withoutValue, series.unit), fraction: Logic.barFraction(withoutValue, unit: series.unit),
                   color: NoopLook.rest, id: "pf530-insight-without-\(id)")
            if let split = insight.byAmount, !split.isEmpty {
                amounts(split, series: series, id: id)
            }
            reading(Logic.verdict(insight.diff), insight.note)
        }
        .planCard529()
        .containerIdentifier("pf530-insight-clear-\(id)")
    }

    private func amounts(_ buckets: [PFJournalDoc530.Bucket], series: Logic.Series, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By amount")
                .font(LookFont.text(12.5, weight: .semibold))
                .foregroundStyle(NoopLook.textTertiary)
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                let mean = bucket.mean ?? 0
                barRow(label: "\(bucket.amount ?? "") · \(bucket.n ?? 0) days", value: shown(mean, series.unit),
                       fraction: Logic.barFraction(mean, unit: series.unit), color: NoopLook.effort, id: "pf530-insight-amount-\(id)-\(bucket.amount ?? "")")
            }
        }
    }

    private func reading(_ verdict: String, _ note: String?) -> some View {
        (Text("\(verdict). ").font(LookFont.text(13.5, weight: .bold)).foregroundColor(NoopLook.textPrimary)
            + Text(hiding.text(note ?? "")).font(LookFont.text(13.5)).foregroundColor(NoopLook.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func noEffectCard(_ insights: [Logic.Insight], series: Logic.Series) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: "No clear effect")
            ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                let id = insight.behaviour ?? insight.label ?? "behaviour"
                let withValue = insight.meanWith ?? 0
                let withoutValue = insight.meanWithout ?? 0
                let pair = hiding.shown("\(Logic.plainText(withValue, unit: series.unit)) / \(Logic.plainText(withoutValue, unit: series.unit))", .scores)
                HStack(spacing: 10) {
                    Text(insight.label ?? id)
                        .font(LookFont.text(13.5, weight: .medium))
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineLimit(2)
                        .frame(width: 112, alignment: .leading)
                    track(fraction: Logic.barFraction(withValue, unit: series.unit), color: NoopLook.rest)
                    Text(pair)
                        .font(LookFont.text(13, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                        .frame(minWidth: 62, alignment: .trailing)
                        .accessibilityIdentifier("pf530-insight-value-\(id)")
                }
                .containerIdentifier("pf530-insight-row-\(id)")
            }
            Text("\(series.measure) with it / without it, \(series.device).")
                .font(LookFont.text(12.5))
                .foregroundStyle(NoopLook.textTertiary)
        }
        .planCard529()
        .containerIdentifier("pf530-insight-noeffect")
    }

    // MARK: Still collecting

    @ViewBuilder private var collecting: some View {
        let waiting = Logic.collecting(doc.list)
        if !waiting.isEmpty {
            let shownRows = showsAllCollecting ? waiting : Array(waiting.prefix(Self.collectingShown))
            VStack(alignment: .leading, spacing: 10) {
                PFOver529(text: "Still collecting · needs \(Logic.daysNeeded) yes and \(Logic.daysNeeded) no")
                ForEach(shownRows, id: \.key) { question in
                    let key = question.key ?? ""
                    HStack(spacing: 10) {
                        Text(question.label ?? key)
                            .font(LookFont.text(13.5, weight: .medium))
                            .foregroundStyle(NoopLook.textPrimary)
                            .lineLimit(2)
                            .frame(width: 112, alignment: .leading)
                        track(fraction: Logic.progress(yes: question.nYes, no: question.nNo), color: Color(hex: NoopLook.Hex.coachBlue))
                        Text("\(question.nYes ?? 0) · \(question.nNo ?? 0)")
                            .font(LookFont.text(13, weight: .semibold))
                            .foregroundStyle(NoopLook.textSecondary)
                            .frame(minWidth: 62, alignment: .trailing)
                            .accessibilityIdentifier("pf530-insight-counts-\(key)")
                    }
                    .containerIdentifier("pf530-insight-collecting-\(key)")
                }
                Text(collectingNote(total: waiting.count))
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if waiting.count > Self.collectingShown {
                    Button { showsAllCollecting.toggle() } label: {
                        Text(showsAllCollecting ? "Show fewer" : "Show all \(waiting.count)")
                            .font(LookFont.text(13, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                            .frame(minHeight: 40, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf530-insight-collecting-all")
                }
            }
            .planCard529()
            .containerIdentifier("pf530-insight-collecting")
        }
    }

    private func collectingNote(total: Int) -> String {
        let more = total - Self.collectingShown
        guard !showsAllCollecting, more > 0 else { return "Yes days · no days so far." }
        return "Yes days · no days so far. \(more) more \(more == 1 ? "question is" : "questions are") at the same stage."
    }

    // MARK: Bars

    private func shown(_ value: Double, _ unit: String) -> String {
        hiding.shown(Logic.valueText(value, unit: unit), .scores)
    }

    private func barRow(label: String, value: String, fraction: Double, color: Color, id: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(LookFont.text(13.5, weight: .medium))
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(2)
                .frame(width: 112, alignment: .leading)
            track(fraction: fraction, color: color)
            Text(value)
                .font(LookFont.text(13, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(minWidth: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    /// A bar on its track: a plain shape, `fraction` of the width.
    private func track(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NoopLook.track)
                Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
