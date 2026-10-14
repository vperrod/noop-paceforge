#if !os(watchOS)
import SwiftUI

// MARK: - WeeklyBars
//
// Seven bars for the week, each coloured by its own value. For Charge the colour comes from the hard bands
// (67 and 34) and the two band lines are drawn behind the bars; for any other score the caller passes the
// colour. A day without a value is an empty track and a dash.

public struct WeeklyBarItem: Identifiable, Equatable {
    public let id: String
    public var label: String
    public var value: Double?
    public var isToday: Bool

    public init(id: String, label: String, value: Double?, isToday: Bool = false) {
        self.id = id
        self.label = label
        self.value = value
        self.isToday = isToday
    }
}

public struct WeeklyBars: View {
    public var items: [WeeklyBarItem]
    public var maxValue: Double
    public var showsBandLines: Bool
    public var height: CGFloat
    public var colorFor: (Double) -> Color
    public var valueText: (Double) -> String

    public init(items: [WeeklyBarItem], maxValue: Double = 100, showsBandLines: Bool = true, height: CGFloat = 150,
                colorFor: @escaping (Double) -> Color = { NoopLook.chargeColor($0) },
                valueText: @escaping (Double) -> String = { String(Int($0.rounded())) }) {
        self.items = items
        self.maxValue = maxValue
        self.showsBandLines = showsBandLines
        self.height = height
        self.colorFor = colorFor
        self.valueText = valueText
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if showsBandLines { bandLines }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(items) { item in column(item) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func column(_ item: WeeklyBarItem) -> some View {
        let barArea = height - 40
        let fraction = item.value.map { LookDial.fraction($0, max: maxValue) } ?? 0
        return VStack(spacing: 6) {
            Text(item.value.map(valueText) ?? "\u{2013}")
                .font(LookFont.numeral(13))
                .foregroundStyle(item.isToday ? NoopLook.textPrimary : NoopLook.textSecondary)
                .frame(height: 16)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(NoopLook.track.opacity(0.6))
                    .frame(height: barArea)
                if let value = item.value {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(colorFor(value))
                        .frame(height: max(barArea * CGFloat(fraction), 3))
                }
            }
            Text(item.label)
                .lookCaps(11)
                .foregroundStyle(item.isToday ? NoopLook.textPrimary : NoopLook.textTertiary)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.value.map { "\(item.label) \(valueText($0))" } ?? "\(item.label) no value")
    }

    /// Dashed lines at the 34 and 67 band edges, in the bar area's coordinates (labels and value rows excluded).
    private var bandLines: some View {
        let barArea = height - 40
        let top = barArea * CGFloat(1 - Double(LookBand.highFloor) / maxValue)
        let mid = barArea * CGFloat(Double(LookBand.highFloor - LookBand.mediumFloor) / maxValue)
        return VStack(spacing: 0) {
            Color.clear.frame(height: 22 + top)
            dash
            Color.clear.frame(height: mid)
            dash
            Spacer(minLength: 0)
            Color.clear.frame(height: 20)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var dash: some View {
        Rectangle()
            .fill(NoopLook.divider)
            .frame(height: 1)
    }
}

#if DEBUG
#Preview("WeeklyBars") {
    WeeklyBars(items: [
        WeeklyBarItem(id: "m", label: "M", value: 82),
        WeeklyBarItem(id: "t", label: "T", value: 55),
        WeeklyBarItem(id: "w", label: "W", value: 23),
        WeeklyBarItem(id: "th", label: "T", value: 67),
        WeeklyBarItem(id: "f", label: "F", value: 34),
        WeeklyBarItem(id: "s", label: "S", value: nil),
        WeeklyBarItem(id: "su", label: "S", value: 71, isToday: true),
    ])
    .padding(16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
