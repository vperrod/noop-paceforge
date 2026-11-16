import SwiftUI
import StrandDesign

/// Screen 1c, "What your body showed": WHOOP recovery and Garmin readiness each on its own chart with the device's usual, Garmin sleep
/// against the need, and HRV with resting heart rate. Garmin and WHOOP are never averaged or merged; every chart names its device.
struct PFReviewBody530: View {
    let doc: PFPlanWeekDoc
    let review: PFWeekReviewDoc530
    private let hiding = PFHiding()

    private var dayLetters: [String] {
        let letters = (review.trainingDays ?? []).map { ($0.dow ?? "").prefix(1).uppercased() }
        return letters.count == 7 ? letters : ["M", "T", "W", "T", "F", "S", "S"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach((doc.report?.nights?.series ?? []).indices, id: \.self) { index in
                nights((doc.report?.nights?.series ?? [])[index], labels: doc.report?.nights?.labels ?? dayLetters)
            }
            if let sleep = review.sleep, (sleep.hours ?? []).contains(where: { $0 != nil }) { sleepCard(sleep) }
            if let entries = review.hrvRhr, !entries.isEmpty { hrvCard(entries) }
        }
    }

    // MARK: Recovery and readiness, one device each

    private func nights(_ series: PFPlanWeekDoc.Series, labels: [String]) -> some View {
        let source = series.source ?? ""
        let key = source.lowercased().isEmpty ? "device" : source.lowercased()
        let values = series.values ?? []
        let bands = series.bands ?? []
        let bars = values.indices.map { index -> PFDayBar530 in
            let day = index < labels.count ? String(labels[index].prefix(1)) : ""
            let text = values[index].map { hiding.shown(String(Int($0.rounded())), .scores) } ?? "\u{00B7}"
            return PFDayBar530(id: index, value: values[index], color: PFWeekColor529.band(index < bands.count ? bands[index] : nil),
                               label: "\(day) \(text)")
        }
        let title = source == "WHOOP" ? "Recovery each morning \u{00B7} WHOOP" : source == "Garmin" ? "Readiness each morning \u{00B7} Garmin"
            : (series.title ?? source)
        let reading = source == "WHOOP" ? review.readings?.whoop : source == "Garmin" ? review.readings?.garmin : nil
        return VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: title)
            PFDayBars530(bars: bars, top: series.max ?? 100, usual: series.usual, height: 56,
                         summary: "\(title). " + bars.map { $0.label }.joined(separator: ", "))
                .accessibilityIdentifier("review530-bars-\(key)")
            PFReviewReading530(key: key, text: reading)
        }
        .pfReviewCard530(key)
    }

    // MARK: Sleep

    private func sleepCard(_ sleep: PFWeekReviewDoc530.Sleep) -> some View {
        let hours = sleep.hours ?? []
        let labels = sleep.labels ?? []
        let need = sleep.needH
        let bars = hours.indices.map { index -> PFDayBar530 in
            let met = (hours[index] ?? 0) >= (need ?? 0)
            let text = (index < labels.count ? labels[index] : nil).map { hiding.shown($0, .body) } ?? "\u{00B7}"
            return PFDayBar530(id: index, value: hours[index], color: met ? PFWeekColor529.blue : PFReviewColor530.violet, label: text)
        }
        let top = max(hours.compactMap { $0 }.max() ?? 0, need ?? 0, 1) * 1.05
        let title = "Sleep each night \u{00B7} \(sleep.source ?? "Garmin") \u{00B7} hours"
        return VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: title)
            PFDayBars530(bars: bars, top: top, usual: need, height: 60, summary: "\(title). " + bars.map { $0.label }.joined(separator: ", "))
                .accessibilityIdentifier("review530-bars-sleep")
            PFReviewReading530(key: "sleep", text: review.readings?.sleep)
        }
        .pfReviewCard530("sleep")
    }

    // MARK: HRV and resting heart rate

    private func hrvCard(_ entries: [PFWeekReviewDoc530.HrvRhr]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                let title = "HRV and resting heart rate \u{00B7} \(entry.source ?? "")"
                VStack(alignment: .leading, spacing: 8) {
                    PFWeekOverline529(text: title)
                    PFTwoLineChart530(
                        upper: PFLineSeries530(name: "HRV", values: entry.hrv ?? [], usual: entry.hrvUsual, color: PFWeekColor529.teal),
                        lower: PFLineSeries530(name: "RHR", values: entry.rhr ?? [], usual: entry.rhrUsual, color: PFWeekColor529.amber, labelsAbove: false),
                        days: dayLetters,
                        summary: "\(title), seven days",
                        format: { hiding.shown(String(Int($0.rounded())), .body) })
                    .accessibilityIdentifier("review530-lines-\((entry.source ?? "device").lowercased())")
                }
            }
            PFReviewReading530(key: "hrvrhr", text: review.readings?.hrvRhr)
        }
        .pfReviewCard530("hrvrhr")
    }
}
