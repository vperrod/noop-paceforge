#if !os(watchOS)
import SwiftUI
import Charts

// MARK: - LookTrendView
//
// The one trend template: a metric dropdown, the window's average with its change against the window before,
// a W / M / 6M / Y control, a date stepper, a caption, the chart and a "what is it" card. The chart is a thin
// daily line (or bars) over a typical-range band; the long views add one average line per calendar month with
// the month-on-month change under it. Everything it shows comes from `LookTrendWindow` (tested logic); the
// view only lays it out. Inputs are plain values, so it has no environment objects.

public enum LookTrendStyle: Equatable {
    case line, bars
}

public struct LookTrendInfo: Equatable {
    public var title: String
    public var message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public struct LookTrendMetric: Identifiable {
    public let id: String
    public var title: String
    public var icon: String
    public var unit: String
    public var decimals: Int
    public var higherIsBetter: Bool?
    public var style: LookTrendStyle
    /// Daily values, any order.
    public var points: [LookPoint]
    /// Our own typical band for the metric, if the caller has one; otherwise mean plus or minus one SD.
    public var typical: ClosedRange<Double>?
    public var caption: String?
    public var info: LookTrendInfo?

    public init(id: String, title: String, icon: String, unit: String, decimals: Int = 0, higherIsBetter: Bool? = true,
                style: LookTrendStyle = .line, points: [LookPoint], typical: ClosedRange<Double>? = nil,
                caption: String? = nil, info: LookTrendInfo? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.unit = unit
        self.decimals = decimals
        self.higherIsBetter = higherIsBetter
        self.style = style
        self.points = points
        self.typical = typical
        self.caption = caption
        self.info = info
    }
}

/// The W / M / 6M / Y style control (also used by Highlights): equal segments in a dark pill.
public struct LookSegmented<Option: Hashable>: View {
    public var options: [Option]
    @Binding public var selection: Option
    public var title: (Option) -> String
    public var identifier: String

    public init(options: [Option], selection: Binding<Option>, identifier: String = "look-segmented",
                title: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.identifier = identifier
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .lookCaps(12)
                        .foregroundStyle(isOn ? NoopLook.textPrimary : NoopLook.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isOn ? NoopLook.segmentOn : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(identifier)-\(title(option))")
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(NoopLook.segmentOff))
    }
}

public struct LookTrendView: View {
    public var metrics: [LookTrendMetric]
    @Binding public var metricID: String
    @Binding public var range: LookRange
    @Binding public var endDate: Date
    public var today: Date
    public var calendar: Calendar
    /// Drawn under the "What is it?" card for the metric on show (the iPhone puts "What moved it" here). nil draws nothing.
    public var footer: ((LookTrendMetric) -> AnyView)?
    /// The 7-day average line over the daily one; a per-viewer view setting, so it lives here.
    @State private var showsSevenDay = false

    public init(metrics: [LookTrendMetric], metricID: Binding<String>, range: Binding<LookRange>,
                endDate: Binding<Date>, today: Date, calendar: Calendar = .current,
                footer: ((LookTrendMetric) -> AnyView)? = nil) {
        self.metrics = metrics
        self._metricID = metricID
        self._range = range
        self._endDate = endDate
        self.today = today
        self.calendar = calendar
        self.footer = footer
    }

    private var metric: LookTrendMetric? { metrics.first { $0.id == metricID } ?? metrics.first }

    public var body: some View {
        if let selected = metric {
            content(selected)
        } else {
            Text("No data yet")
                .font(LookFont.text(15, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func content(_ metric: LookTrendMetric) -> some View {
        let window = LookTrendWindow.make(points: metric.points, range: range, endingOn: endDate, calendar: calendar,
                                          typicalOverride: metric.typical)
        return VStack(alignment: .leading, spacing: 0) {
            dropdown(metric)
            header(metric, window)
            averageToggle
            if let caption = metric.caption {
                Text(caption)
                    .font(LookFont.text(15.5, weight: .medium))
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoopLook.Metric.screenInset)
                    .padding(.top, 20)
            }
            LookTrendChart(window: window, metric: metric, calendar: calendar,
                           sevenDay: showsSevenDay ? sevenDayLine(metric, window) : [])
                .frame(height: 300)
                .padding(.top, 18)
            if let info = metric.info {
                LookInfoCard(title: info.title, message: info.message)
                    .padding(.horizontal, NoopLook.Metric.screenInset)
                    .padding(.top, 14)
            }
            if let footer {
                footer(metric)
                    .padding(.horizontal, NoopLook.Metric.screenInset)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder private func dropdown(_ metric: LookTrendMetric) -> some View {
        if metrics.count > 1 {
            Menu {
                ForEach(metrics) { m in
                    Button(m.title) { metricID = m.id }
                }
            } label: { dropdownLabel(metric, showsChevron: true) }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 10)
                .accessibilityLabel("Metric: \(metric.title)")
                .accessibilityIdentifier("look-trend-metric-menu")
        } else {
            dropdownLabel(metric, showsChevron: false)
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("look-trend-metric-title")
        }
    }

    private func dropdownLabel(_ metric: LookTrendMetric, showsChevron: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: metric.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(NoopLook.textTertiary)
            Text(metric.title)
                .lookCaps(13.5)
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }

    /// "7-DAY AVERAGE" switch under the header: draws the smoothed line over the daily one.
    private var averageToggle: some View {
        Button { showsSevenDay.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: showsSevenDay ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(showsSevenDay ? NoopLook.textPrimary : NoopLook.textTertiary)
                Text("7-day average")
                    .lookCaps(12)
                    .foregroundStyle(showsSevenDay ? NoopLook.textPrimary : NoopLook.textSecondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, NoopLook.Metric.screenInset)
        .padding(.top, 14)
        .accessibilityAddTraits(showsSevenDay ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("look-trend-seven-day")
    }

    /// Trailing seven-day mean over the whole series (so the first days of the window are not cut short), clipped
    /// to the window.
    private func sevenDayLine(_ metric: LookTrendMetric, _ window: LookTrendWindow) -> [LookPoint] {
        let all = LookTrendStats.trailingAverage(metric.points, days: 7, calendar: calendar)
        return LookSeries.within(all, from: window.start, to: window.end)
    }

    private func header(_ metric: LookTrendMetric, _ window: LookTrendWindow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Average").lookCaps(12).foregroundStyle(NoopLook.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(window.average.map { LookFormat.number($0, decimals: metric.decimals) } ?? "\u{2013}")
                        .font(LookFont.numeral(40))
                        .foregroundStyle(NoopLook.textPrimary)
                        .accessibilityIdentifier("look-trend-average")
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .font(LookFont.text(17, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                    }
                }
                if let chip = LookDelta.chip(percent: window.deltaPercent, higherIsBetter: metric.higherIsBetter) {
                    chipView(chip)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 12) {
                LookSegmented(options: LookRange.allCases, selection: $range, identifier: "look-trend-range") { $0.rawValue }
                    .frame(width: 168)
                stepper(window)
            }
        }
        .padding(.horizontal, NoopLook.Metric.screenInset)
        .padding(.top, 22)
    }

    private func chipView(_ chip: LookChip) -> some View {
        let color = NoopLook.color(forTone: chip.tone)
        return Text(chip.text)
            .font(LookFont.numeral(14))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(color.opacity(0.15)))
            .accessibilityLabel("Change against the period before: \(chip.text)")
            .accessibilityIdentifier("look-trend-delta")
    }

    private func stepper(_ window: LookTrendWindow) -> some View {
        let canForward = range.canStepForward(end: endDate, today: today, calendar: calendar)
        return HStack(spacing: 12) {
            Button {
                endDate = range.stepped(end: endDate, by: -1, today: today, calendar: calendar)
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(window.hasEarlierData ? NoopLook.textPrimary : NoopLook.textMuted)
            .disabled(!window.hasEarlierData)
            .accessibilityLabel("Earlier")
            .accessibilityIdentifier("look-trend-prev")
            Text(range.label(endingOn: endDate, calendar: calendar))
                .lookCaps(12)
                .foregroundStyle(NoopLook.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("look-trend-range-label")
            Button {
                endDate = range.stepped(end: endDate, by: 1, today: today, calendar: calendar)
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canForward ? NoopLook.textPrimary : NoopLook.textMuted)
            .disabled(!canForward)
            .accessibilityLabel("Later")
            .accessibilityIdentifier("look-trend-next")
        }
    }
}

// MARK: - Chart

struct LookTrendChart: View {
    let window: LookTrendWindow
    let metric: LookTrendMetric
    let calendar: Calendar
    /// The 7-day average line, empty when the switch is off.
    var sevenDay: [LookPoint] = []

    private var xFormat: Date.FormatStyle {
        switch window.range {
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .sixMonths, .year: return .dateTime.month(.abbreviated)
        }
    }

    /// 6M labels every month; the year view has twelve segments, so only the line and the month letters stay.
    private var showsSegmentLabels: Bool { window.spans.count <= 7 }

    var body: some View {
        Chart {
            bandMarks
            seriesMarks
            averageMarks
            segmentMarks
        }
        .chartYScale(domain: window.yDomain)
        // Room for the last date label, which the chart edge cut off ("1" for "14").
        .chartXScale(range: .plotDimension(endPadding: 14))
        .chartYAxis {
            AxisMarks(position: .leading, values: window.yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(NoopLook.divider)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(LookFormat.number(v, decimals: metric.decimals))
                            .font(LookFont.text(12.5, weight: .semibold))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: window.xTickDates(calendar: calendar)) { _ in
                AxisValueLabel(format: xFormat)
                    .font(LookFont.text(13, weight: .regular))
                    .foregroundStyle(NoopLook.textTertiary)
            }
        }
        .chartLegend(.hidden)
        .padding(.horizontal, NoopLook.Metric.screenInset)
        .accessibilityIdentifier("look-trend-chart")
    }

    @ChartContentBuilder private var bandMarks: some ChartContent {
        if let band = window.typical {
            RectangleMark(xStart: .value("From", window.start), xEnd: .value("To", window.end),
                          yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                .foregroundStyle(NoopLook.textPrimary.opacity(0.07))
        }
    }

    @ChartContentBuilder private var seriesMarks: some ChartContent {
        switch metric.style {
        case .line:
            ForEach(window.points, id: \.date) { p in
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value),
                         series: .value("Series", "daily"))
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                    .foregroundStyle(NoopLook.trendLine)
            }
        case .bars:
            ForEach(window.points, id: \.date) { p in
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value))
                    .foregroundStyle(NoopLook.effort)
            }
        }
    }

    @ChartContentBuilder private var averageMarks: some ChartContent {
        ForEach(sevenDay, id: \.date) { p in
            LineMark(x: .value("Day", p.date), y: .value("7-day average", p.value),
                     series: .value("Series", "average"))
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineJoin: .round))
                .foregroundStyle(NoopLook.textPrimary)
        }
    }

    @ChartContentBuilder private var segmentMarks: some ChartContent {
        ForEach(window.spans, id: \.from) { span in
            RuleMark(xStart: .value("From", span.from), xEnd: .value("To", span.to),
                     y: .value("Average", span.segment.average))
                .lineStyle(StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .foregroundStyle(segmentColor(span))
                .annotation(position: .top, alignment: .leading, spacing: 3) {
                    if showsSegmentLabels { segmentValue(span) }
                }
                .annotation(position: .bottom, alignment: .leading, spacing: 3) {
                    if showsSegmentLabels { segmentChange(span) }
                }
        }
    }

    private func segmentChip(_ span: LookSegmentSpan) -> LookChip? {
        LookDelta.chip(percent: span.segment.percentChange, higherIsBetter: metric.higherIsBetter)
    }

    private func segmentColor(_ span: LookSegmentSpan) -> Color {
        guard let chip = segmentChip(span) else { return NoopLook.textPrimary }
        return chip.tone == .neutral ? NoopLook.textPrimary : NoopLook.color(forTone: chip.tone)
    }

    private func segmentValue(_ span: LookSegmentSpan) -> some View {
        Text(LookFormat.number(span.segment.average, decimals: metric.decimals))
            .font(LookFont.numeral(17))
            .foregroundStyle(NoopLook.textPrimary)
    }

    @ViewBuilder private func segmentChange(_ span: LookSegmentSpan) -> some View {
        if let chip = segmentChip(span) {
            Text(chip.text)
                .font(LookFont.numeral(16))
                .foregroundStyle(segmentColor(span))
        }
    }
}

#if DEBUG
private struct LookTrendPreviewHost: View {
    @State private var metricID = "hrv"
    @State private var range = LookRange.sixMonths
    @State private var endDate = LookTrendPreviewHost.today

    static let calendar = Calendar(identifier: .gregorian)
    static let today = calendar.startOfDay(for: Date())

    private static func sample(seed: Double, base: Double, spread: Double) -> [LookPoint] {
        (0..<400).compactMap { offset -> LookPoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let wave = sin(Double(offset) / 9 + seed) * spread
            let jitter = cos(Double(offset) * 1.7 + seed) * spread * 0.5
            return LookPoint(date: date, value: base + wave + jitter)
        }
    }

    var body: some View {
        ScrollView {
            LookTrendView(
                metrics: [
                    LookTrendMetric(id: "hrv", title: "Heart rate variability", icon: "waveform.path.ecg", unit: "ms",
                                    points: Self.sample(seed: 0, base: 112, spread: 22),
                                    caption: "Sample data for the preview.",
                                    info: LookTrendInfo(title: "What is heart rate variability?",
                                                        message: "The variation in time between heartbeats while you sleep. Compare it with your own normal.")),
                    LookTrendMetric(id: "rhr", title: "Resting heart rate", icon: "heart", unit: "bpm", higherIsBetter: false,
                                    points: Self.sample(seed: 2, base: 58, spread: 4)),
                    LookTrendMetric(id: "effort", title: "Effort", icon: "bolt.heart", unit: "", decimals: 1, style: .bars,
                                    points: Self.sample(seed: 4, base: 11, spread: 4)),
                ],
                metricID: $metricID, range: $range, endDate: $endDate, today: Self.today, calendar: Self.calendar)
        }
        .frame(width: 402, height: 874)
        .lookScreenBackground()
        .preferredColorScheme(.dark)
    }
}

#Preview("LookTrendView") {
    LookTrendPreviewHost()
}
#endif
#endif
