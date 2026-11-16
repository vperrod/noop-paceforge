import SwiftUI
import StrandDesign

/// One line of `PFTwoLineChart530`: a name ("HRV"), a value per day (nil = no reading) and the device's own usual, drawn dashed.
struct PFLineSeries530: Equatable {
    var name: String
    var values: [Double?]
    var usual: Double?
    var color: Color
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

    private let height: CGFloat = 124

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    plot(upper, other: lower, in: proxy.size, band: 20...46, otherBand: 62...80)
                    plot(lower, other: upper, in: proxy.size, band: 62...80, otherBand: 20...46)
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

    /// The points of a line (nil = no reading), each on the line's own scale inside its band.
    private func dots(_ series: PFLineSeries530, in size: CGSize, band: ClosedRange<CGFloat>) -> [Dot?] {
        let known: [Double] = series.values.compactMap { $0 }
        let spread: [Double] = known + (series.usual.map { [$0] } ?? [])
        guard let low = spread.min(), let high = spread.max() else { return [] }
        let count = series.values.count
        return series.values.enumerated().map { index, value in
            value.map { Dot(index: index, point: CGPoint(x: x(index, count: count, size: size), y: y($0, low: low, high: high, band: band, size: size))) }
        }
    }

    /// True when `series` has its first (or last) reading higher on screen than `other`'s: its label then goes above the point and the
    /// other's below, so the two labels never meet and neither lies across a line.
    private func isHigher(_ series: PFLineSeries530, than other: PFLineSeries530, last: Bool, in size: CGSize,
                          band: ClosedRange<CGFloat>, otherBand: ClosedRange<CGFloat>) -> Bool {
        func edge(_ list: [Dot?]) -> CGFloat? { (last ? list.compactMap { $0 }.last : list.compactMap { $0 }.first)?.point.y }
        guard let mine = edge(dots(series, in: size, band: band)) else { return true }
        guard let theirs = edge(dots(other, in: size, band: otherBand)) else { return true }
        return mine <= theirs
    }

    @ViewBuilder private func plot(_ series: PFLineSeries530, other: PFLineSeries530, in size: CGSize, band: ClosedRange<CGFloat>,
                                   otherBand: ClosedRange<CGFloat>) -> some View {
        let known: [Double] = series.values.compactMap { $0 }
        let spread: [Double] = known + (series.usual.map { [$0] } ?? [])
        if let low = spread.min(), let high = spread.max() {
            let points = dots(series, in: size, band: band)
            let startAbove = isHigher(series, than: other, last: false, in: size, band: band, otherBand: otherBand)
            let endAbove = isHigher(series, than: other, last: true, in: size, band: band, otherBand: otherBand)
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
                    label("\(series.name) \(format(series.values[first.index] ?? 0))", at: first.point, leading: true, above: startAbove,
                          color: series.color, size: size)
                    label("\(series.name) \(format(series.values[last.index] ?? 0))", at: last.point, leading: false, above: endAbove,
                          color: series.color, size: size)
                } else if let only = points.compactMap({ $0 }).first {
                    label("\(series.name) \(format(series.values[only.index] ?? 0))", at: only.point, leading: true, above: startAbove,
                          color: series.color, size: size)
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

    /// A value label at an end of a line, clear of both lines: above its point for the series that is higher on screen there, below for the
    /// other. The first label is left-aligned and the last right-aligned inside the chart, a few points in from the edge.
    private func label(_ text: String, at point: CGPoint, leading: Bool, above: Bool, color: Color, size: CGSize) -> some View {
        let y = above ? max(8, point.y - 14) : min(size.height - 8, point.y + 14)
        return Text(text)
            .font(LookFont.text(10.5, weight: .semibold))
            .foregroundStyle(color)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            .padding(.horizontal, 4)
            .frame(width: size.width, height: 14)
            .position(x: size.width / 2, y: y)
    }
}
