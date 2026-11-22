import SwiftUI
import StrandDesign

/// One row of `PFHBars530`: a label, a value and the text at the end of the bar ("+45 s", "180").
struct PFHBar530: Identifiable, Equatable {
    let id: Int
    var label: String
    var value: Double
    var valueText: String
    var color: Color
}

/// Horizontal bars, each as long as its value against the largest one (or `scale`). Plain SwiftUI shapes: the hours this week against
/// the usual, the stations that cost the most, the mix of work.
struct PFHBars530: View {
    let rows: [PFHBar530]
    var scale: Double?
    var labelWidth: CGFloat = 112

    private var top: Double { max(scale ?? rows.map(\.value).max() ?? 1, 0.0001) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.label)
                        .font(PFPlanFont543.text(12, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: labelWidth, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NoopLook.row)
                            Capsule()
                                .fill(row.color)
                                .frame(width: max(4, proxy.size.width * CGFloat(min(max(row.value / top, 0), 1))))
                        }
                    }
                    .frame(height: 10)
                    Text(row.valueText)
                        .font(PFPlanFont543.text(12, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label), \(row.valueText)")
            }
        }
    }
}
