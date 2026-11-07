#if !os(watchOS)
import SwiftUI

// MARK: - TypicalRangeBars
//
// Sleep stage rows: a caps name, the share of the night and the duration, over a hatched track with the
// stage's fill and a dashed box marking where this athlete's typical share sits.

public struct LookStageRow: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var color: Color
    /// Share of the night, 0...1.
    public var fraction: Double
    public var percentText: String
    public var durationText: String
    /// This athlete's typical share, 0...1.
    public var typical: ClosedRange<Double>?

    public init(id: String, title: String, color: Color, fraction: Double, percentText: String,
                durationText: String, typical: ClosedRange<Double>? = nil) {
        self.id = id
        self.title = title
        self.color = color
        self.fraction = fraction
        self.percentText = percentText
        self.durationText = durationText
        self.typical = typical
    }
}

/// Diagonal hatching on a rounded track.
struct LookHatchedTrack: View {
    var cornerRadius: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            context.stroke(path, with: .color(NoopLook.hatch), lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public struct TypicalRangeBars: View {
    public var rows: [LookStageRow]
    /// Total duration shown beside the legend ("6:51"), or nil.
    public var totalText: String?
    public var typicalLegend: String

    public init(rows: [LookStageRow], totalText: String? = nil, typicalLegend: String = "Typical range") {
        self.rows = rows
        self.totalText = totalText
        self.typicalLegend = typicalLegend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(NoopLook.textSecondary, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                        .frame(width: 8, height: 12)
                    Text(typicalLegend).lookCaps(12).foregroundStyle(NoopLook.textPrimary)
                }
                Spacer(minLength: 8)
                if let totalText {
                    HStack(spacing: 6) {
                        Text("Duration").lookCaps(12).foregroundStyle(NoopLook.textPrimary)
                        Text(totalText).font(LookFont.numeral(18)).foregroundStyle(NoopLook.textPrimary)
                    }
                }
            }
            .padding(.bottom, 4)
            ForEach(rows) { row in stage(row) }
        }
    }

    private func stage(_ row: LookStageRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(NoopLook.textPrimary.opacity(0.9), lineWidth: 1.6)
                    .frame(width: 22, height: 22)
                Text(row.title).lookCaps(12).foregroundStyle(NoopLook.textPrimary)
                Text(row.percentText).font(LookFont.text(12, weight: .bold)).foregroundStyle(row.color)
                Spacer(minLength: 8)
                Text(row.durationText).font(LookFont.numeral(17)).foregroundStyle(NoopLook.textPrimary)
            }
            track(row)
        }
        .padding(.top, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(row))
    }

    private func track(_ row: LookStageRow) -> some View {
        ZStack(alignment: .leading) {
            LookHatchedTrack()
                .frame(height: 14)
            GeometryReader { geo in
                let w = geo.size.width
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(row.color)
                    .frame(width: max(w * CGFloat(min(max(row.fraction, 0), 1)), 2), height: 14)
                if let typical = row.typical {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(NoopLook.textPrimary.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .background(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.white.opacity(0.12)))
                        .frame(width: max(w * CGFloat(typical.upperBound - typical.lowerBound), 12), height: 20)
                        .offset(x: w * CGFloat(typical.lowerBound), y: -3)
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }

    private func accessibilityText(_ row: LookStageRow) -> String {
        var text = "\(row.title) \(row.percentText), \(row.durationText)"
        if let typical = row.typical {
            if row.fraction < typical.lowerBound { text += ", below typical" }
            else if row.fraction > typical.upperBound { text += ", above typical" }
            else { text += ", within typical" }
        }
        return text
    }
}

#if DEBUG
#Preview("TypicalRangeBars") {
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
    .frame(width: 402)
    .background(NoopLook.card)
    .preferredColorScheme(.dark)
}
#endif
#endif
