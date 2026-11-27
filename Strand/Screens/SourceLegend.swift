import SwiftUI
import StrandDesign

/// One line saying which device a screen's or card's figures come from.
struct SourceNote: View {
    var source = SourceSplit.whoop
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            PFSourceTag(source: source)
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The key under a chart that carries both devices: WHOOP solid, Garmin dashed. Only the devices on the chart are named.
struct SourceLegend: View {
    var showsWhoop = true
    var showsGarmin = true
    var whoopColor: Color

    var body: some View {
        HStack(spacing: 14) {
            if showsWhoop { entry(SourceSplit.whoop, color: whoopColor, dash: []) }
            if showsGarmin { entry(SourceSplit.garmin, color: NoopLook.trendDown, dash: [4, 3]) }
        }
        .accessibilityElement(children: .combine)
    }

    private func entry(_ source: String, color: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 18, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dash))
            .frame(width: 18, height: 2)
            PFSourceTag(source: source)
        }
    }
}
