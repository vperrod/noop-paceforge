#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Last night's sleep, in the dark look
//
// Hours of sleep against the prior 30 days, the overnight heart-rate line with bed and wake times, and the four
// stage rows (awake, light, deep, REM) over hatched tracks with this athlete's own typical share marked. Built from
// the same `SleepModel` the rest of the Sleep tab reads, so it can never disagree with the hero above it. The
// stage ranges are mean plus or minus one standard deviation of the last 30 nights; the card says so.

struct LookLastNightSleepCard: View {
    let model: SleepModel

    @EnvironmentObject private var repo: Repository
    @State private var heartRate: [LookHRPoint] = []

    private var night: Night { model.night }
    private var calendar: Calendar { Calendar.current }

    private var priorNights: [DailyMetric] {
        let wake = Date(timeIntervalSince1970: TimeInterval(night.session.endTs))
        let key = LookDayKey.key(wake, calendar: calendar)
        return Array(repo.days.filter { $0.day < key }.suffix(30))
    }

    private var typicalHours: Double? {
        LookTrendStats.average(priorNights.compactMap { $0.totalSleepMin }.filter { $0 > 0 })
    }

    private var ranges: LookStageRanges? {
        let nights = priorNights.compactMap { d -> LookNight? in
            guard let total = d.totalSleepMin, let eff = d.efficiency else { return nil }
            return LookNight(asleepMin: total, deepMin: d.deepMin ?? 0, remMin: d.remMin ?? 0,
                             lightMin: d.lightMin ?? 0, efficiency: eff <= 1 ? eff : eff / 100)
        }
        return LookStageTypical.ranges(nights)
    }

    private func clock(_ ts: Int) -> String {
        AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func minutesText(_ minutes: Double) -> String { LookFormat.hoursMinutes(minutes: Safe.int(minutes)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last night's sleep")
                    .font(LookFont.text(26, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                HStack(spacing: 4) {
                    Text("Today").foregroundStyle(NoopLook.textPrimary)
                    Text("vs. prior 30 days").foregroundStyle(NoopLook.textSecondary)
                }
                .font(LookFont.text(15, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 14) {
                hoursHeader
                LookHRLine(points: heartRate, bedText: clock(night.session.effectiveStartTs),
                           wakeText: clock(night.session.endTs))
                Rectangle().fill(NoopLook.divider).frame(height: 1)
                TypicalRangeBars(rows: stageRows, totalText: minutesText(night.stages.total),
                                 typicalLegend: "Typical range")
                Text("Typical range is your own: the average share of the night plus or minus one standard deviation over your last 30 nights.")
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-last-night")
        .task(id: night.session.startTs) { await loadHeartRate() }
    }

    private var hoursHeader: some View {
        let asleep = night.stages.asleep
        let mark = LookCompare.mark(today: asleep, baseline: typicalHours, decimals: 0, higherIsBetter: true)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Hours of sleep").lookCaps(12).foregroundStyle(NoopLook.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(minutesText(asleep)).font(LookFont.numeral(30)).foregroundStyle(NoopLook.textPrimary)
                if let mark { LookTriangleMark(mark) }
                if let typicalHours {
                    Text(minutesText(typicalHours)).font(LookFont.numeralRegular(13)).foregroundStyle(NoopLook.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("look-last-night-hours")
    }

    private var stageRows: [LookStageRow] {
        let s = night.stages
        let total = max(s.total, 1)
        let r = ranges
        func row(_ id: String, _ title: String, _ color: Color, _ minutes: Double, _ typical: ClosedRange<Double>?) -> LookStageRow {
            let share = minutes / total
            return LookStageRow(id: id, title: title, color: color, fraction: share,
                                percentText: "\(Safe.int((share * 100)))%", durationText: minutesText(minutes),
                                typical: typical)
        }
        return [
            row("awake", "Awake", NoopLook.stageAwake, s.awake, r?.awake),
            row("light", "Light", NoopLook.stageLight, s.light, r?.light),
            row("deep", "SWS (deep)", NoopLook.stageDeep, s.deep, r?.deep),
            row("rem", "REM", NoopLook.stageRem, s.rem, r?.rem),
        ]
    }

    @MainActor private func loadHeartRate() async {
        let session = night.session
        let buckets = await repo.hrBuckets(from: session.startTs, to: session.endTs, bucketSeconds: 60)
        guard !Task.isCancelled else { return }
        heartRate = LookNightHR.points(buckets.map { (ts: $0.ts, bpm: $0.bpm) },
                                       start: session.effectiveStartTs, end: session.endTs)
    }
}
#endif
