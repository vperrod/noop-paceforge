#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Last 7 days (My Dashboard)
//
// WHOOP's "7 day strain and recovery" card: the strap's Charge and Effort for each of the last seven days as two rows of bars. Both come
// from the same daily series the rest of the app reads (`Repository.exploreSeries`, NOOP's own strap numbers, never mixed with Garmin's);
// a day without a value is an empty track and a dash. Draws nothing until one of the two rows has a value.

struct LookLast7DaysCard: View {
    /// The last day of the seven (the day on show).
    let day: Date

    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var charge: [WeeklyBarItem] = []
    @State private var effort: [WeeklyBarItem] = []

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var hasValues: Bool { (charge + effort).contains { $0.value != nil } }
    private var loadKey: String { "\(repo.refreshSeq)|\(effortScaleRaw)|\(Int(day.timeIntervalSince1970))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasValues {
                HStack {
                    Text("LAST 7 DAYS").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
                    Spacer(minLength: 8)
                    Text("NOOP strap").font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                }
                Text("CHARGE").lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                WeeklyBars(items: charge, maxValue: 100, showsBandLines: false, height: 96,
                           valueText: { "\(Safe.int($0))%" })
                    .accessibilityIdentifier("today-last-7-days-charge")
                Text("EFFORT").lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                WeeklyBars(items: effort, maxValue: effortScale == .whoop ? 21 : 100, showsBandLines: false, height: 96,
                           colorFor: { _ in NoopLook.effort },
                           valueText: { LookFormat.number($0, decimals: effortScale == .whoop ? 1 : 0) })
                    .accessibilityIdentifier("today-last-7-days-effort")
            }
        }
        .padding(hasValues ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if hasValues { RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card) }
        }
        .hiddenWhenPrivate(.scores, name: String(localized: "Scores"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-last-7-days")
        // On a view that may draw nothing, so the load does not wait for content.
        .background(Color.clear.frame(width: 0, height: 0).task(id: loadKey) { await load() })
    }

    @MainActor private func load() async {
        let calendar = Calendar.current
        let weekday = DateFormatter()
        weekday.locale = AppLanguage.activeLocale
        weekday.setLocalizedDateFormatFromTemplate("EEEEE")
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -(6 - $0), to: day) }
        let chargeSeries = await repo.exploreSeries(key: HeroRingMetric.charge, source: "my-whoop", days: 14)
        let effortSeries = await repo.exploreSeries(key: HeroRingMetric.effort, source: "my-whoop", days: 14)
        // A day that appears twice keeps its last value, instead of trapping.
        let chargeByDay = Dictionary(chargeSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let effortByDay = Dictionary(effortSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        guard !Task.isCancelled else { return }
        let scale = effortScale
        func item(_ date: Date, _ index: Int, _ value: Double?) -> WeeklyBarItem {
            WeeklyBarItem(id: Repository.dayString(date), label: weekday.string(from: date), value: value, isToday: index == days.count - 1)
        }
        charge = days.enumerated().map { index, date in
            item(date, index, chargeByDay[Repository.dayString(date)].flatMap { $0.isFinite ? $0 : nil })
        }
        effort = days.enumerated().map { index, date in
            item(date, index, effortByDay[Repository.dayString(date)].flatMap { $0.isFinite ? UnitFormatter.effortValue($0, scale: scale) : nil })
        }
    }
}
#endif
