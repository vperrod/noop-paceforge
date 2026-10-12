import SwiftUI
import WidgetKit
import StrandDesign

// The My Day widget face. It lives in the shared folder so the extension draws it and the app's debug
// widget gallery renders the very same view. It reads a MyDaySummary only.

/// The last six hours of heart rate over a FIXED window, so missing time stays empty. The pen lifts across
/// any stretch longer than the trace's gap rule.
private struct MyDayHRShape: Shape {
    let series: [HrPoint]
    let windowStart: Int64
    let windowEnd: Int64
    let low: Int
    let high: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let span = CGFloat(windowEnd - windowStart)
        guard span > 0, rect.width > 0, rect.height > 0 else { return path }
        let range = CGFloat(max(high - low, 1))
        func point(_ p: HrPoint) -> CGPoint {
            let x = CGFloat(p.ts - windowStart) / span * rect.width
            let y = rect.height - CGFloat(p.bpm - low) / range * rect.height
            return CGPoint(x: min(max(x, 0), rect.width), y: y)
        }
        var run: [CGPoint] = []
        func flush() {
            defer { run.removeAll() }
            guard let first = run.first else { return }
            if run.count == 1 {
                path.addEllipse(in: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4))
                return
            }
            path.move(to: first)
            for p in run.dropFirst() { path.addLine(to: p) }
        }
        var previous: HrPoint?
        for p in series where p.ts >= windowStart && p.ts <= windowEnd {
            if let previous, p.ts - previous.ts > HrTrace.gapSec { flush() }
            run.append(point(p))
            previous = p
        }
        flush()
        return path
    }
}

struct MyDayWidgetFace: View {
    let summary: MyDaySummary?
    let stale: Bool

    private var accent: Color { StrandPalette.zone5 }

    var body: some View {
        if let s = summary, !stale {
            HStack(alignment: .top, spacing: 14) {
                heartRate(s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                next(s)
                    .frame(width: 118, alignment: .leading)
            }
        } else {
            PFWidgetStale()
        }
    }

    // MARK: Heart rate

    private func heartRate(_ s: MyDaySummary) -> some View {
        let bpms = s.hr.map(\.bpm)
        let low = (bpms.min() ?? 50) - 3
        let high = (bpms.max() ?? 120) + 3
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("LAST 6 H")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                Spacer(minLength: 4)
                if let latest = s.latestBpm {
                    Text("\(latest)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("bpm")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            if s.hr.isEmpty {
                Text("No heart rate in the last 6 hours")
                    .font(.system(size: 12))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                MyDayHRShape(series: s.hr, windowStart: s.windowStart, windowEnd: s.windowEnd, low: low, high: high)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(maxHeight: .infinity)
                    .background(alignment: .bottom) {
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    }
            }
            Text(asOf(s))
                .font(.system(size: 10))
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
        }
    }

    /// "to 14:05": where the line ends, so a file that stopped short is not read as live.
    private func asOf(_ s: MyDaySummary) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return "6 h to \(f.string(from: s.updated))"
    }

    // MARK: Next session

    private func next(_ s: MyDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NEXT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            if let next = s.next {
                Text(next.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let when = next.when {
                    Text(when)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(StrandPalette.accent)
                }
                if let detail = next.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("Nothing planned")
                    .font(.system(size: 13))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 0)
            if s.plannedCount > 0 {
                Text("\(s.doneCount) of \(s.plannedCount) done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
}
