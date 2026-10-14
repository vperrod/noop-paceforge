#if DEBUG
import SwiftUI
import StrandDesign

// MARK: - Look gallery (DEBUG)
//
// `--demo-screen looklab` renders every component of the dark look with made-up numbers, one section per
// component, so the simulator UI tests (LookComponentsUITests) can capture each one in dark and in light. The
// numbers here are synthetic samples, not anyone's data. Stripped from Release.

struct LookGalleryScreen: View {
    @State private var tab = "home"
    @State private var metricID = "hrv"
    @State private var range = LookRange.sixMonths
    @State private var endDate = Calendar.current.startOfDay(for: Date())

    private static let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                section("dials", "RingDial") { dials }
                section("monitors", "Monitor tiles, My Day, Daily Outlook") { monitors }
                section("compare", "Today vs. 30 days, insight card") { compare }
                section("steps", "Three-step rows") { steps }
                section("weekly", "Weekly bars") { weekly }
                section("stages", "Typical-range bars") { stages }
                section("trend", "Trend view") { trend }
                section("chrome", "Floating tab bar, sticky mini dials") { chrome }
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.vertical, 24)
        }
        .lookScreenBackground()
        .accessibilityIdentifier("look-gallery")
    }

    private func section<Content: View>(_ id: String, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).lookCaps(11).foregroundStyle(NoopLook.textTertiary)
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-gallery-\(id)")
    }

    private var dials: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top, spacing: 0) {
                RingDial(fraction: 0.73, color: NoopLook.rest, valueText: "73", unitText: "%", diameter: 92,
                         accessibilityName: "Rest").frame(maxWidth: .infinity)
                RingDial(fraction: 0.23, color: NoopLook.chargeColor(23), valueText: "23", unitText: "%", diameter: 92,
                         accessibilityName: "Charge").frame(maxWidth: .infinity)
                RingDial(fraction: 0.13, color: NoopLook.effort, valueText: "2.7",
                         target: LookDial.targetArc(low: 13.2, high: 16.5, max: 21), diameter: 92,
                         accessibilityName: "Effort").frame(maxWidth: .infinity)
            }
            RingDial(fraction: 0.55, color: NoopLook.chargeColor(55), valueText: "55", unitText: "%", diameter: 272,
                     style: .hero, wordmark: "NOOP", titleLines: ["CHARGE"], accessibilityName: "Charge")
            RingDial(fraction: 0.676, color: NoopLook.effort, valueText: "14.2",
                     target: LookDial.targetArc(low: 13.2, high: 16.5, max: 21), diameter: 272, style: .hero,
                     wordmark: "NOOP", titleLines: ["EFFORT"], accessibilityName: "Effort")
        }
    }

    private var monitors: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                MonitorTile(title: "Health monitor", badge: .symbol("exclamationmark"), badgeForeground: Color(hex: "#E8505A"),
                            badgeBackground: NoopLook.alertWash, status: "VERY ELEVATED", statusColor: NoopLook.alert,
                            detail: "Respiratory rate")
                MonitorTile(title: "Stress monitor", badge: .text("1.7"), badgeForeground: NoopLook.stressMedium,
                            badgeBackground: NoopLook.stressMedium.opacity(0.2), status: "MEDIUM",
                            statusColor: NoopLook.stressMedium, detail: "Scale 0 to 3")
            }
            LookSectionHeader("My Day", onAdd: {})
            OutlookBar(action: {})
            ActivitiesCard(items: [
                ActivityPillItem(id: "sleep", pillColor: NoopLook.rest, icon: "moon.fill", pillText: "6:20", title: "Sleep",
                                 startText: "23:17", endText: "05:48", barColor: NoopLook.rest),
                ActivityPillItem(id: "walk", pillColor: NoopLook.effort, icon: "figure.walk", pillText: "0:37",
                                 title: "Walking", startText: "07:05", endText: "07:42", barColor: NoopLook.effort),
            ], onAdd: {}, onStart: {})
        }
    }

    private var compare: some View {
        VStack(spacing: 18) {
            TodayVs30Rows(rows: [
                LookCompareRow(id: "hrv", icon: "waveform.path.ecg", label: "Heart rate variability", valueText: "43",
                               baselineText: "46", mark: LookCompare.mark(today: 43, baseline: 46, higherIsBetter: true)),
                LookCompareRow(id: "rhr", icon: "heart", label: "Resting heart rate", valueText: "59", baselineText: "60",
                               mark: LookCompare.mark(today: 59, baseline: 60, higherIsBetter: false)),
                LookCompareRow(id: "resp", icon: "lungs", label: "Respiratory rate", valueText: "16.1", baselineText: "15.7",
                               mark: LookCompare.mark(today: 16.1, baseline: 15.7, decimals: 1, higherIsBetter: false)),
                LookCompareRow(id: "rest", icon: "moon", label: "Rest", valueText: "92%", baselineText: "87%",
                               mark: LookCompare.mark(today: 92, baseline: 87, higherIsBetter: true)),
            ])
            LookInsightCard("Your resting heart rate is within its typical range and HRV is a little low, which gives a yellow Charge. A good day to stay active without a hard session.",
                        linkTitle: "Break down my Charge", action: {})
        }
    }

    private var steps: some View {
        ThreeStepRows(rows: [
            .init(id: "hours", icon: "moon", label: "Hours vs. needed", step: .optimal, valueText: "100%"),
            .init(id: "cons", icon: "calendar", label: "Sleep consistency", step: .sufficient, valueText: "80%"),
            .init(id: "eff", icon: "bed.double", label: "Sleep efficiency", step: .poor, valueText: "71%"),
        ])
    }

    private var weekly: some View {
        WeeklyBars(items: [
            WeeklyBarItem(id: "m", label: "M", value: 82), WeeklyBarItem(id: "t", label: "T", value: 55),
            WeeklyBarItem(id: "w", label: "W", value: 23), WeeklyBarItem(id: "th", label: "T", value: 67),
            WeeklyBarItem(id: "f", label: "F", value: 34), WeeklyBarItem(id: "s", label: "S", value: nil),
            WeeklyBarItem(id: "su", label: "S", value: 71, isToday: true),
        ])
    }

    private var stages: some View {
        TypicalRangeBars(rows: [
            LookStageRow(id: "awake", title: "Awake", color: NoopLook.stageAwake, fraction: 0.08, percentText: "8%",
                         durationText: "0:31", typical: 0.05...0.12),
            LookStageRow(id: "light", title: "Light", color: NoopLook.stageLight, fraction: 0.49, percentText: "49%",
                         durationText: "3:05", typical: 0.45...0.58),
            LookStageRow(id: "deep", title: "Deep", color: NoopLook.stageDeep, fraction: 0.21, percentText: "21%",
                         durationText: "1:20", typical: 0.15...0.24),
            LookStageRow(id: "rem", title: "REM", color: NoopLook.stageRem, fraction: 0.22, percentText: "22%",
                         durationText: "1:24", typical: 0.2...0.26),
        ], totalText: "6:51")
        .padding(16)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }

    private static func sample(seed: Double, base: Double, spread: Double) -> [LookPoint] {
        let today = calendar.startOfDay(for: Date())
        return (0..<400).compactMap { offset -> LookPoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let wave = sin(Double(offset) / 9 + seed) * spread
            let jitter = cos(Double(offset) * 1.7 + seed) * spread * 0.5
            return LookPoint(date: date, value: base + wave + jitter)
        }
    }

    private var trend: some View {
        LookTrendView(
            metrics: [
                LookTrendMetric(id: "hrv", title: "Heart rate variability", icon: "waveform.path.ecg", unit: "ms",
                                points: Self.sample(seed: 0, base: 112, spread: 22), caption: "Sample numbers for the gallery.",
                                info: LookTrendInfo(title: "What is heart rate variability?",
                                                    message: "The variation in time between heartbeats while you sleep. Compare it with your own normal.")),
                LookTrendMetric(id: "rhr", title: "Resting heart rate", icon: "heart", unit: "bpm", higherIsBetter: false,
                                points: Self.sample(seed: 2, base: 58, spread: 4)),
                LookTrendMetric(id: "effort", title: "Effort", icon: "bolt.heart", unit: "", decimals: 1, style: .bars,
                                points: Self.sample(seed: 4, base: 11, spread: 4)),
            ],
            metricID: $metricID, range: $range, endDate: $endDate, today: Self.calendar.startOfDay(for: Date()),
            calendar: Self.calendar)
        .padding(.horizontal, -NoopLook.Metric.screenInset)
    }

    private var chrome: some View {
        VStack(spacing: 18) {
            StickyMiniDials(items: [
                MiniDialItem(id: "rest", title: "Rest", fraction: 0.73, color: NoopLook.rest, valueText: "73"),
                MiniDialItem(id: "charge", title: "Charge", fraction: 0.23, color: NoopLook.chargeColor(23), valueText: "23"),
                MiniDialItem(id: "effort", title: "Effort", fraction: 0.13, color: NoopLook.effort, valueText: "2.7"),
            ])
            .padding(.horizontal, -NoopLook.Metric.screenInset)
            FloatingTabBar(items: [
                LookTabItem(id: "home", title: "Home", symbol: "house"),
                LookTabItem(id: "health", title: "Health", symbol: "heart"),
                LookTabItem(id: "paceforge", title: "PaceForge", symbol: "figure.run"),
                LookTabItem(id: "more", title: "More", symbol: "line.3.horizontal"),
            ], selection: $tab, onCoach: {})
            .padding(.horizontal, -NoopLook.Metric.screenInset)
        }
    }
}
#endif
