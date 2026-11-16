import SwiftUI
import StrandDesign

/// One bar of `PFDayBars530`: a value (nil = no reading, 0 = nothing that day), its colour and the label under it ("M 28", "8:07").
struct PFDayBar530: Identifiable, Equatable {
    let id: Int
    var value: Double?
    var color: Color
    var label: String
}

/// Day bars, one per day, with an optional dashed "usual" line across them and a label under each bar. Plain SwiftUI shapes (the
/// Sunday review's training, recovery and sleep charts). `top` is the value a full-height bar stands for.
struct PFDayBars530: View {
    let bars: [PFDayBar530]
    let top: Double
    var usual: Double?
    var usualColor: Color = NoopLook.textSecondary
    var height: CGFloat = 56
    /// What a screen reader hears for the whole chart.
    var summary: String

    var body: some View {
        VStack(spacing: 4) {
            plot
            HStack(spacing: 4) {
                ForEach(bars) { bar in
                    Text(bar.label)
                        .font(LookFont.text(10, weight: .regular))
                        .foregroundStyle(NoopLook.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var plot: some View {
        let scale = max(top, 0.0001)
        return ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(bars) { bar in
                    column(bar, scale: scale)
                }
            }
            if let usual {
                GeometryReader { proxy in
                    let y = proxy.size.height * (1 - CGFloat(min(max(usual / scale, 0), 1)))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(usualColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
            }
        }
        .frame(height: height)
    }

    @ViewBuilder private func column(_ bar: PFDayBar530, scale: Double) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let value = bar.value {
                if value > 0 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(bar.color)
                        .frame(height: max(3, height * CGFloat(min(value / scale, 1))))
                }
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(NoopLook.track)
                    .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
