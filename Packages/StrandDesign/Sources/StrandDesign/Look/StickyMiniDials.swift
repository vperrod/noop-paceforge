#if !os(watchOS)
import SwiftUI

// MARK: - StickyMiniDials
//
// The strip of three small dials that slides in under the status bar once the big dials have scrolled away.
// `LookSticky.isVisible` decides when; this view only draws.

public struct MiniDialItem: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var fraction: Double
    public var color: Color
    public var valueText: String

    public init(id: String, title: String, fraction: Double, color: Color, valueText: String) {
        self.id = id
        self.title = title
        self.fraction = fraction
        self.color = color
        self.valueText = valueText
    }
}

public struct StickyMiniDials: View {
    public var items: [MiniDialItem]

    public init(items: [MiniDialItem]) { self.items = items }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    RingDial(fraction: item.fraction, color: item.color, valueText: item.valueText, diameter: 34,
                             accessibilityName: item.title)
                    Text(item.title)
                        .lookCaps(11)
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, NoopLook.Metric.screenInset)
        .padding(.vertical, 8)
        .background(NoopLook.screenBottom.opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle().fill(NoopLook.divider).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-mini-dials")
    }
}

#if DEBUG
#Preview("StickyMiniDials") {
    StickyMiniDials(items: [
        MiniDialItem(id: "rest", title: "Rest", fraction: 0.73, color: NoopLook.rest, valueText: "73"),
        MiniDialItem(id: "charge", title: "Charge", fraction: 0.23, color: NoopLook.chargeColor(23), valueText: "23"),
        MiniDialItem(id: "effort", title: "Effort", fraction: 0.13, color: NoopLook.effort, valueText: "2.7"),
    ])
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
