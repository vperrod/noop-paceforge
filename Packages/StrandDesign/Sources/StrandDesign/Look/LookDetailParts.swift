#if !os(watchOS)
import SwiftUI

// MARK: - Detail-screen parts
//
// Plain-value pieces the Charge / Effort / Rest detail screens, the sleep block and the trend screens share: the
// TODAY title bar, the weekly bars card, a compact trend line, the overnight heart-rate line, the planner's
// time-in-bed bar and the sleep-need table. No environment objects, so each previews on its own.

/// "TODAY" in caps with an info button, above the ring (the screen's back button is the navigation bar's).
public struct LookDetailTitleBar: View {
    public var title: String
    public var onInfo: (() -> Void)?

    public init(_ title: String = "TODAY", onInfo: (() -> Void)? = nil) {
        self.title = title
        self.onInfo = onInfo
    }

    public var body: some View {
        HStack {
            Color.clear.frame(width: 28, height: 28)
            Spacer(minLength: 0)
            Text(title).lookCaps(14).foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 0)
            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About this score")
                .accessibilityIdentifier("look-detail-info")
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, NoopLook.Metric.screenInset)
    }
}

/// The last seven days as bars in a card, with a title; today is the bright one.
public struct LookWeekCard: View {
    public var title: String
    public var items: [WeeklyBarItem]
    public var maxValue: Double
    public var usesBands: Bool
    public var color: Color
    public var valueText: (Double) -> String

    /// `usesBands` colours by the hard Charge bands (red under 34, yellow 34-66, green 67+); otherwise every bar is `color`.
    public init(title: String, items: [WeeklyBarItem], maxValue: Double = 100, usesBands: Bool,
                color: Color = NoopLook.effort, valueText: @escaping (Double) -> String = { String(Int($0.rounded())) }) {
        self.title = title
        self.items = items
        self.maxValue = maxValue
        self.usesBands = usesBands
        self.color = color
        self.valueText = valueText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).lookCaps(12).foregroundStyle(NoopLook.textSecondary)
            WeeklyBars(items: items, maxValue: maxValue, showsBandLines: usesBands, height: 170,
                       colorFor: { usesBands ? NoopLook.chargeColor($0) : color }, valueText: valueText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-week-card")
    }
}

/// A compact trend line for one metric: title, average, a thin line over the typical band.
public struct LookTrendLineCard: View {
    public var title: String
    public var unit: String
    public var decimals: Int
    public var points: [LookPoint]
    public var identifier: String

    public init(title: String, unit: String, decimals: Int = 0, points: [LookPoint], identifier: String) {
        self.title = title
        self.unit = unit
        self.decimals = decimals
        self.points = points.sorted { $0.date < $1.date }
        self.identifier = identifier
    }

    public var body: some View {
        let values = points.map(\.value)
        let average = LookTrendStats.average(values)
        let band = LookTrendStats.typicalRange(of: values)
        let low = Swift.min(values.min() ?? 0, band?.lowerBound ?? values.min() ?? 0)
        let high = Swift.max(values.max() ?? 1, band?.upperBound ?? values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).lookCaps(12).foregroundStyle(NoopLook.textSecondary).lineLimit(2)
                Spacer(minLength: 8)
                Text(average.map { LookFormat.number($0, decimals: decimals) } ?? "\u{2013}")
                    .font(LookFont.numeral(22)).foregroundStyle(NoopLook.textPrimary)
                if !unit.isEmpty {
                    Text(unit).font(LookFont.text(13, weight: .semibold)).foregroundStyle(NoopLook.textSecondary)
                }
            }
            if points.count >= 2 {
                Canvas { context, size in
                    let lo = low
                    let hi = high
                    let span = Swift.max(hi - lo, 1e-9)
                    let firstTime = points[0].date.timeIntervalSince1970
                    let lastTime = points[points.count - 1].date.timeIntervalSince1970
                    let timeSpan = Swift.max(lastTime - firstTime, 1)
                    func point(_ p: LookPoint) -> CGPoint {
                        CGPoint(x: CGFloat((p.date.timeIntervalSince1970 - firstTime) / timeSpan) * size.width,
                                y: size.height * CGFloat(1 - (p.value - lo) / span))
                    }
                    if let band {
                        let top = size.height * CGFloat(1 - (band.upperBound - lo) / span)
                        let bottom = size.height * CGFloat(1 - (band.lowerBound - lo) / span)
                        context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: Swift.max(bottom - top, 1))),
                                     with: .color(NoopLook.textPrimary.opacity(0.07)))
                    }
                    var line = Path()
                    for (index, p) in points.enumerated() {
                        if index == 0 { line.move(to: point(p)) } else { line.addLine(to: point(p)) }
                    }
                    context.stroke(line, with: .color(NoopLook.textPrimary.opacity(0.85)),
                                   style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
                .frame(height: 70)
                .accessibilityHidden(true)
            } else {
                Text("Not enough days yet")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), average \(average.map { LookFormat.number($0, decimals: decimals) } ?? "none") \(unit), last \(points.count) days")
        .accessibilityIdentifier(identifier)
    }
}

/// Overnight heart rate: a thin line with dashed bed and wake rules and the bpm ticks on the left.
public struct LookHRLine: View {
    public var points: [LookHRPoint]
    public var bedText: String
    public var wakeText: String

    public init(points: [LookHRPoint], bedText: String, wakeText: String) {
        self.points = points
        self.bedText = bedText
        self.wakeText = wakeText
    }

    public var body: some View {
        VStack(spacing: 6) {
            if let axis = LookNightHR.axis(points) {
                Canvas { context, size in
                    let inset: CGFloat = 30
                    let plotWidth = Swift.max(size.width - inset - 4, 1)
                    let span = Swift.max(axis.range.upperBound - axis.range.lowerBound, 1e-9)
                    func y(_ bpm: Double) -> CGFloat { size.height * CGFloat(1 - (bpm - axis.range.lowerBound) / span) }
                    for tick in axis.ticks {
                        context.draw(Text(LookFormat.number(tick, decimals: 0))
                                        .font(LookFont.text(12, weight: .semibold))
                                        .foregroundColor(NoopLook.textTertiary),
                                     at: CGPoint(x: 0, y: y(tick)), anchor: .leading)
                    }
                    for x in [inset, inset + plotWidth] {
                        var rule = Path()
                        rule.move(to: CGPoint(x: x, y: 0))
                        rule.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(rule, with: .color(NoopLook.textSecondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    var line = Path()
                    var open = false
                    for p in points {
                        let pt = CGPoint(x: inset + CGFloat(p.x) * plotWidth, y: y(p.bpm))
                        if !open || p.breaksBefore { line.move(to: pt); open = true } else { line.addLine(to: pt) }
                    }
                    context.stroke(line, with: .color(NoopLook.rest), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                }
                .frame(height: 150)
                HStack {
                    Text(bedText).font(LookFont.text(12, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(wakeText).font(LookFont.text(12, weight: .semibold))
                }
                .foregroundStyle(NoopLook.textTertiary)
                .padding(.leading, 30)
            } else {
                Text("No overnight heart rate was recorded for this night.")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overnight heart rate from \(bedText) to \(wakeText)")
        .accessibilityIdentifier("look-hr-line")
    }
}

// MARK: Planner pieces

/// The hatched time-in-bed bar with its duration pill, and the dashed OPTIMAL bracket under it.
public struct LookTimeInBedBar: View {
    public var copy: LookPlannerCopy

    public init(copy: LookPlannerCopy) { self.copy = copy }

    public var body: some View {
        VStack(spacing: 8) {
            Text("TIME IN BED").lookCaps(10.5).foregroundStyle(NoopLook.textPrimary)
            GeometryReader { geo in
                let width = geo.size.width * CGFloat(copy.barFraction)
                ZStack {
                    LookHatchedTrack(cornerRadius: 5)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(NoopLook.textPrimary.opacity(0.9), lineWidth: 1.5))
                    Text(copy.timeInBedText)
                        .font(LookFont.numeral(14))
                        .foregroundStyle(NoopLook.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: "#2B3640")))
                        .overlay(Capsule().strokeBorder(NoopLook.textPrimary.opacity(0.9), lineWidth: 1.5))
                }
                .frame(width: Swift.max(width, 64), height: 28)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 28)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(NoopLook.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 14)
                .mask(Rectangle().padding(.top, 7))
            VStack(spacing: 2) {
                Text("OPTIMAL").lookCaps(10.5).foregroundStyle(NoopLook.textSecondary)
                Text(copy.optimalText).lookCaps(10.5).foregroundStyle(NoopLook.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time in bed \(copy.timeInBedText). Optimal \(copy.optimalText).")
        .accessibilityIdentifier("look-time-in-bed")
    }
}

/// One line of the sleep-need table: label, caption and a value; the last row is the total.
public struct LookNeedRow: Identifiable, Equatable {
    public let id: String
    public var label: String
    public var caption: String
    public var valueText: String
    /// What VoiceOver (and the UI tests) read for the value when the printed one is shorthand ("8:40").
    public var spokenValue: String?
    public var isTotal: Bool

    public init(id: String, label: String, caption: String = "", valueText: String, spokenValue: String? = nil,
                isTotal: Bool = false) {
        self.id = id
        self.label = label
        self.caption = caption
        self.valueText = valueText
        self.spokenValue = spokenValue
        self.isTotal = isTotal
    }
}

/// The sleep-need breakdown as a card of rows with the total last.
public struct LookNeedTable: View {
    public var title: String
    public var rows: [LookNeedRow]
    public var idPrefix: String
    /// The info button (or anything else) at the end of the title row.
    public var accessory: AnyView?

    public init(title: String, rows: [LookNeedRow], idPrefix: String = "look-need-", accessory: AnyView? = nil) {
        self.title = title
        self.rows = rows
        self.idPrefix = idPrefix
        self.accessory = accessory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).lookCaps(12).foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                if let accessory { accessory }
            }
            .padding(.bottom, 8)
            ForEach(rows) { row in
                if row.isTotal { Rectangle().fill(NoopLook.divider).frame(height: 1).padding(.top, 4) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(LookFont.text(row.isTotal ? 15.5 : 15, weight: row.isTotal ? .bold : .medium))
                            .foregroundStyle(NoopLook.textPrimary)
                        if !row.caption.isEmpty {
                            Text(row.caption)
                                .font(LookFont.text(12.5, weight: .medium))
                                .foregroundStyle(NoopLook.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(row.valueText).font(LookFont.numeral(row.isTotal ? 24 : 20)).foregroundStyle(NoopLook.textPrimary)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label) \(row.spokenValue ?? row.valueText)")
                .accessibilityIdentifier("\(idPrefix)\(row.id)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }
}

#if DEBUG
#Preview("Detail parts") {
    ScrollView {
        VStack(spacing: 14) {
            LookDetailTitleBar(onInfo: {})
            LookWeekCard(title: "Last 7 days", items: [
                WeeklyBarItem(id: "a", label: "T", value: 60), WeeklyBarItem(id: "b", label: "F", value: 22),
                WeeklyBarItem(id: "c", label: "S", value: 80), WeeklyBarItem(id: "d", label: "S", value: nil),
                WeeklyBarItem(id: "e", label: "M", value: 45), WeeklyBarItem(id: "f", label: "T", value: 70),
                WeeklyBarItem(id: "g", label: "W", value: 55, isToday: true),
            ], usesBands: true)
            LookNeedTable(title: "Tonight's need", rows: [
                LookNeedRow(id: "base", label: "Baseline", caption: "Your personal need", valueText: "8:00"),
                LookNeedRow(id: "total", label: "Tonight's need", valueText: "8:36", isTotal: true),
            ])
        }
        .padding(16)
    }
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
