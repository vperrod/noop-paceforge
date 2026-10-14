#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Stress monitor (the look)
//
// The Stress monitor tile opens here: the latest reading on the 0 to 3 scale with its word (LOW, MEDIUM, HIGH), a line through the
// day's scored hours, the day's average, the peak and the time in the high band, and a link to the full Stress screen that
// still holds everything it had. The readings are NOOP's own daytime stress (heart rate and beat-to-beat intervals from the
// strap); an hour with no signal, or taken out because you were moving, is a gap in the line and never a value. With nothing
// scored the screen says so and what it needs, instead of drawing a made-up day.

struct LookStressMonitorScreen: View {
    @EnvironmentObject private var repo: Repository

    @State private var result: DaytimeStress.Result?
    @State private var loaded = false
    @State private var dayStart = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)

    private var loadKey: String { "\(repo.refreshSeq)" }

    private var hours: [StressMonitorLogic.Hour] {
        (result?.timeline ?? []).map { StressMonitorLogic.Hour(startTs: $0.startTs, level: $0.level, masked: $0.maskedForActivity) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if StressMonitorLogic.hasData(hours) {
                    reading
                    chart
                    summary
                } else if loaded {
                    empty
                } else {
                    Text("Reading the day")
                        .font(LookFont.text(15, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                NavigationLink(value: TabRoute.stress) {
                    InsightLink("Open the full Stress screen")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("look-stress-full")
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .lookScreenBackground()
        .navigationTitle("Stress monitor")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("look-stress-monitor")
        .task(id: loadKey) { await load() }
    }

    @MainActor private func load() async {
        dayStart = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let scored = await StressDayCurve.today(repo: repo, personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled)?.result
        guard !Task.isCancelled else { return }
        result = scored
        loaded = true
    }

    // MARK: Reading

    private var reading: some View {
        let latest = StressMonitorLogic.latest(hours)
        let level = latest.map { LookStressLevel.forScore($0.level) } ?? .low
        let color = NoopLook.color(for: level)
        let updated = StressMonitorLogic.lastUpdated(hours, now: Int(Date().timeIntervalSince1970))
        return VStack(alignment: .leading, spacing: 6) {
            if let updated {
                Text("Last updated \(AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(updated))))")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(latest.map { StressMonitorLogic.levelText($0.level) } ?? "\u{2013}")
                    .font(LookFont.numeral(56))
                    .foregroundStyle(NoopLook.textPrimary)
                Text(level.label)
                    .font(LookFont.text(18, weight: .bold))
                    .tracking(18 * 0.07)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            Text("On a scale of 0 to 3. Under 1 is low, under 2 is medium, 2 and over is high.")
                .font(LookFont.text(12.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.tile))
        .hiddenWhenPrivate(.scores, name: String(localized: "Stress"))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("look-stress-reading")
    }

    // MARK: The day line

    private var chart: some View {
        let runs = StressMonitorLogic.runs(hours)
        let masked = StressMonitorLogic.maskedStarts(hours)
        let dayStart = self.dayStart
        return VStack(alignment: .leading, spacing: 8) {
            Text("THROUGH THE DAY")
                .lookCaps(11.5)
                .foregroundStyle(NoopLook.textSecondary)
            Canvas { context, size in
                let left: CGFloat = 26
                let bottom: CGFloat = 20
                let plotWidth = max(size.width - left - 4, 1)
                let plotHeight = max(size.height - bottom - 6, 1)
                func point(_ r: StressMonitorLogic.Reading) -> CGPoint {
                    CGPoint(x: left + CGFloat(StressMonitorLogic.xFraction(ts: r.startTs, dayStart: dayStart)) * plotWidth,
                            y: 3 + plotHeight * CGFloat(1 - StressMonitorLogic.yFraction(level: r.level)))
                }
                for tick in [0.0, 1.0, 2.0, 3.0] {
                    let y = 3 + plotHeight * CGFloat(1 - StressMonitorLogic.yFraction(level: tick))
                    var rule = Path()
                    rule.move(to: CGPoint(x: left, y: y))
                    rule.addLine(to: CGPoint(x: left + plotWidth, y: y))
                    context.stroke(rule, with: .color(NoopLook.divider), style: StrokeStyle(lineWidth: 1, dash: tick == 0 ? [] : [3, 3]))
                    context.draw(Text(StressMonitorLogic.levelText(tick)).font(LookFont.text(11, weight: .semibold)).foregroundColor(NoopLook.textTertiary),
                                 at: CGPoint(x: 0, y: y), anchor: .leading)
                }
                for (index, label) in ["00:00", "06:00", "12:00", "18:00"].enumerated() {
                    context.draw(Text(label).font(LookFont.text(11, weight: .semibold)).foregroundColor(NoopLook.textTertiary),
                                 at: CGPoint(x: left + plotWidth * CGFloat(index) / 4, y: size.height - 8),
                                 anchor: index == 0 ? .leading : .center)
                }
                // Exercise hours: a mark on the base, because they are taken out of the score rather than read as stress.
                for start in masked {
                    let x = left + CGFloat(StressMonitorLogic.xFraction(ts: start, dayStart: dayStart)) * plotWidth
                    let width = plotWidth / 24
                    context.fill(Path(roundedRect: CGRect(x: x, y: 3 + plotHeight - 3, width: width, height: 3), cornerRadius: 1.5),
                                 with: .color(NoopLook.effort.opacity(0.7)))
                }
                for run in runs {
                    if run.count == 1, let only = run.first {
                        let p = point(only)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                                     with: .color(NoopLook.color(for: LookStressLevel.forScore(only.level))))
                        continue
                    }
                    for pair in zip(run, run.dropFirst()) {
                        var segment = Path()
                        segment.move(to: point(pair.0))
                        segment.addLine(to: point(pair.1))
                        context.stroke(segment, with: .color(NoopLook.color(for: LookStressLevel.forScore(pair.1.level))),
                                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(height: 190)
            .accessibilityHidden(true)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(NoopLook.effort.opacity(0.7)).frame(width: 14, height: 3)
                Text("Hours you were moving are left out, not scored as stress.")
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .hiddenWhenPrivate(.scores, name: String(localized: "Stress"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stress through the day, \(runs.reduce(0) { $0 + $1.count }) scored hours")
        .accessibilityIdentifier("look-stress-chart")
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: 10) {
            stat("TODAY'S AVERAGE", result?.dayMean.map(StressMonitorLogic.levelText) ?? "\u{2013}")
            stat("PEAK", result?.peak?.level.map(StressMonitorLogic.levelText) ?? "\u{2013}")
            stat("TIME IN HIGH", LookFormat.hoursMinutes(minutes: result?.highStressMinutes ?? 0))
        }
        .hiddenWhenPrivate(.scores, name: String(localized: "Stress"))
        .accessibilityIdentifier("look-stress-summary")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).lookCaps(10).foregroundStyle(NoopLook.textTertiary).lineLimit(2).minimumScaleFactor(0.8)
            Text(value).font(LookFont.numeral(24)).foregroundStyle(NoopLook.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: No data

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            LookInfoCard(title: "No stress data from the strap yet",
                         message: "Stress is read from the strap's heart rate and beat-to-beat intervals, so nothing is shown until an hour has been scored. No value is made up in the meantime.")
            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT IT NEEDS").lookCaps(11).foregroundStyle(NoopLook.textTertiary)
                need("Wear the strap through the day, not only at night.")
                need("An hour needs enough clean heartbeats before it is scored.")
                need("Hours of exercise are left out, because exercise raises heart rate on its own.")
                need("The first scores also need a few worn nights to learn your own baseline.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        }
        .accessibilityIdentifier("look-stress-empty")
    }

    private func need(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}").foregroundStyle(NoopLook.textTertiary)
            Text(text)
                .font(LookFont.text(14, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Stress monitor") {
    NavigationStack {
        LookStressMonitorScreen()
            .environmentObject(Repository(deviceId: "preview"))
    }
    .preferredColorScheme(.dark)
}
#endif
#endif
