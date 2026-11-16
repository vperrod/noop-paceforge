import SwiftUI
import StrandDesign

/// One line of `PFTwoLineChart530`: a name ("HRV"), a value per day (nil = no reading) and the device's own usual, drawn dashed.
struct PFLineSeries530: Equatable {
    var name: String
    var values: [Double?]
    var usual: Double?
    var color: Color
    /// The end labels sit above the line, or below it for the lower line so the two never cover each other.
    var labelsAbove = true
}

/// Two lines on one chart, each on its own scale (HRV is in milliseconds and resting heart rate in beats a minute, so they only share
/// the days): `upper` in the top band, `lower` in the bottom one. The first and last reading of each line are labelled. Gaps break the line.
struct PFTwoLineChart530: View {
    let upper: PFLineSeries530
    let lower: PFLineSeries530
    let days: [String]
    var summary: String
    /// Numbers shown as text; the chart passes them through the hide switches.
    var format: (Double) -> String = { String(Int($0.rounded())) }

    private let height: CGFloat = 100

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    plot(upper, in: proxy.size, band: 10...50)
                    plot(lower, in: proxy.size, band: 62...88)
                }
            }
            .frame(height: height)
            HStack(spacing: 0) {
                ForEach(days.indices, id: \.self) { index in
                    Text(days[index])
                        .font(LookFont.text(10, weight: .regular))
                        .foregroundStyle(NoopLook.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    /// The y of `value` inside the band (a fraction of the chart height in points: 0 to 100), larger values higher.
    private func y(_ value: Double, low: Double, high: Double, band: ClosedRange<CGFloat>, size: CGSize) -> CGFloat {
        let span = high - low
        let fraction = span > 0 ? CGFloat((value - low) / span) : 0.5
        let point = band.upperBound - fraction * (band.upperBound - band.lowerBound)
        return point / 100 * size.height
    }

    private func x(_ index: Int, count: Int, size: CGSize) -> CGFloat {
        // The centre of the day's column, so a point sits over its label.
        size.width * (CGFloat(index) + 0.5) / CGFloat(max(count, 1))
    }

    @ViewBuilder private func plot(_ series: PFLineSeries530, in size: CGSize, band: ClosedRange<CGFloat>) -> some View {
        let known: [Double] = series.values.compactMap { $0 }
        let spread: [Double] = known + (series.usual.map { [$0] } ?? [])
        if let low = spread.min(), let high = spread.max() {
            let count = series.values.count
            let points: [Dot?] = series.values.enumerated().map { index, value in
                value.map { Dot(index: index, point: CGPoint(x: x(index, count: count, size: size), y: y($0, low: low, high: high, band: band, size: size))) }
            }
            ZStack(alignment: .topLeading) {
                if let usual = series.usual {
                    Path { path in
                        let line = y(usual, low: low, high: high, band: band, size: size)
                        path.move(to: CGPoint(x: 4, y: line))
                        path.addLine(to: CGPoint(x: size.width - 4, y: line))
                    }
                    .stroke(series.color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                Path { path in
                    var previous: CGPoint?
                    for entry in points {
                        if let entry {
                            if previous != nil { path.addLine(to: entry.point) } else { path.move(to: entry.point) }
                            previous = entry.point
                        } else {
                            previous = nil
                        }
                    }
                }
                .stroke(series.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ForEach(endpoints(points)) { end in
                    Circle().fill(series.color).frame(width: 7, height: 7).position(end.point)
                }
                if let first = points.compactMap({ $0 }).first, let last = points.compactMap({ $0 }).last, first.index != last.index {
                    label("\(series.name) \(format(series.values[first.index] ?? 0))", at: first.point, leading: true, series: series, height: size.height)
                    label("\(series.name) \(format(series.values[last.index] ?? 0))", at: last.point, leading: false, series: series, height: size.height)
                } else if let only = points.compactMap({ $0 }).first {
                    label("\(series.name) \(format(series.values[only.index] ?? 0))", at: only.point, leading: true, series: series, height: size.height)
                }
            }
        }
    }

    private struct Dot: Identifiable {
        let index: Int
        let point: CGPoint
        var id: Int { index }
    }

    private func endpoints(_ points: [Dot?]) -> [Dot] {
        let known = points.compactMap { $0 }
        guard let first = known.first, let last = known.last else { return [] }
        return first.index == last.index ? [first] : [first, last]
    }

    /// A value label at the end of a line: to the right of the first point, to the left of the last; above the line, or below for the lower one.
    private func label(_ text: String, at point: CGPoint, leading: Bool, series: PFLineSeries530, height: CGFloat) -> some View {
        let y = series.labelsAbove ? max(8, point.y - 11) : min(height - 6, point.y + 12)
        return Text(text)
            .font(LookFont.text(10.5, weight: .semibold))
            .foregroundStyle(series.color)
            .fixedSize()
            .position(x: point.x + (leading ? 34 : -34), y: y)
    }
}
