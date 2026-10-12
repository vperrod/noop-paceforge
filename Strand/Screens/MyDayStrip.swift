import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - My Day strip
//
// The 24 h strip at the top of My Day: the heart-rate line over the day's length, bands for sleep, naps,
// workouts and planned sessions, hatched grey where nothing was recorded, optional stress and steps
// overlays, a marker at "now", and a scrub line the finger drags. Drawn on one Canvas from a
// `DayTimeline`; the geometry below is plain math so the mapping from a touch to a time is testable.

/// Maps x positions to times across the day, whatever its length (a DST day is 23 or 25 hours).
struct MyDayStripGeometry: Equatable {
    let dayStart: Date
    let dayEnd: Date
    let width: CGFloat

    private var length: Double { max(1, dayEnd.timeIntervalSince(dayStart)) }

    func x(for date: Date) -> CGFloat {
        let f = date.timeIntervalSince(dayStart) / length
        return CGFloat(min(max(f, 0), 1)) * width
    }

    func x(forTs ts: Int) -> CGFloat { x(for: Date(timeIntervalSince1970: TimeInterval(ts))) }

    /// The time under a horizontal touch position, clamped to the day.
    func date(forX x: CGFloat) -> Date {
        guard width > 0 else { return dayStart }
        let f = min(max(Double(x / width), 0), 1)
        return dayStart.addingTimeInterval(f * length)
    }

    /// Consecutive heart-rate points with no break between them; the pen lifts between runs.
    static func runs(of points: [DayTimeline.HRPoint]) -> [[DayTimeline.HRPoint]] {
        var out: [[DayTimeline.HRPoint]] = []
        for p in points {
            if p.startsRun || out.isEmpty { out.append([p]) } else { out[out.count - 1].append(p) }
        }
        return out
    }

    /// The point nearest `ts`, if one lies within `limit` seconds.
    static func nearest(to ts: Int, in points: [DayTimeline.HRPoint], limit: Int = 600) -> DayTimeline.HRPoint? {
        guard let best = points.min(by: { abs($0.ts - ts) < abs($1.ts - ts) }), abs(best.ts - ts) <= limit else {
            return nil
        }
        return best
    }
}

/// Colours and symbols for each kind of event, one place, tokens only.
enum MyDayStyle {
    static func color(_ kind: DayTimeline.Kind) -> Color {
        switch kind {
        case .sleep: return StrandPalette.restColor
        case .nap: return StrandPalette.sleepLight
        case .workout: return StrandPalette.effortColor
        case .detected: return StrandPalette.metricAmber
        case .planned: return StrandPalette.accent
        case .weighIn: return StrandPalette.metricPurple
        case .caffeine: return StrandPalette.metricAmber
        case .water: return StrandPalette.metricCyan
        case .stepsBurst: return StrandPalette.metricCyan
        case .noData: return StrandPalette.textTertiary
        case .dayNote: return StrandPalette.textSecondary
        }
    }

    static func symbol(_ event: DayTimeline.Event) -> String {
        switch event.kind {
        case .sleep: return "bed.double.fill"
        case .nap: return "moon.zzz.fill"
        case .workout:
            if case .ride = event.route { return "bicycle" }
            return sportSymbol(event.title)
        case .detected: return "waveform.path.ecg"
        case .planned:
            switch event.status {
            case .done: return "checkmark.circle.fill"
            case .missed: return "xmark.circle"
            default: return "calendar"
            }
        case .weighIn: return "scalemass.fill"
        case .caffeine: return "cup.and.saucer.fill"
        case .water: return "drop.fill"
        case .stepsBurst: return "figure.walk"
        case .noData: return "waveform.slash"
        case .dayNote: return "note.text"
        }
    }

    /// The kinds drawn as bands on the strip.
    static func isBand(_ event: DayTimeline.Event) -> Bool {
        guard !event.isUntimed else { return false }
        switch event.kind {
        case .sleep, .nap, .workout, .detected, .planned: return true
        default: return false
        }
    }
}

struct MyDayStrip: View {
    let timeline: DayTimeline
    var showStress: Bool
    var showSteps: Bool
    /// Garmin's Body Battery and stress, from PaceForge. Each is its own curve with its own switch.
    var showEnergy = false
    var showGarminStress = false
    /// The time the finger is on, or nil. Owned by the screen, which scrolls its list to it.
    @Binding var scrubDate: Date?

    @State private var isScrubbing = false

    private static let plotHeight: CGFloat = 104
    private static let laneHeight: CGFloat = 12
    private static let axisHeight: CGFloat = 18
    static let totalHeight: CGFloat = plotHeight + laneHeight + axisHeight + 6

    private var bands: [DayTimeline.Event] { timeline.events.filter(MyDayStyle.isBand) }

    var body: some View {
        GeometryReader { geo in
            let geometry = MyDayStripGeometry(dayStart: timeline.dayStart, dayEnd: timeline.dayEnd, width: geo.size.width)
            Canvas { context, size in
                draw(&context, size: size, geometry: geometry)
            }
            .contentShape(Rectangle())
            // Simultaneous, and engaged only by a mostly horizontal drag, so a vertical swipe that starts
            // on the strip still scrolls the page.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if !isScrubbing {
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            isScrubbing = true
                        }
                        scrubDate = geometry.date(forX: value.location.x)
                    }
                    .onEnded { _ in isScrubbing = false }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in scrubDate = geometry.date(forX: value.location.x) }
            )
        }
        .frame(height: Self.totalHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityChildren {
            ForEach(bands) { event in
                Text(bandLabel(event))
            }
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize, geometry: MyDayStripGeometry) {
        let plot = CGRect(x: 0, y: 0, width: size.width, height: Self.plotHeight)
        let lane = CGRect(x: 0, y: Self.plotHeight + 4, width: size.width, height: Self.laneHeight)

        context.fill(Path(roundedRect: plot, cornerRadius: 10), with: .color(StrandPalette.surfaceInset))

        // Hour hairlines, then the bands behind the lines.
        for tick in axisTicks() {
            let x = geometry.x(for: tick.date)
            var line = Path()
            line.move(to: CGPoint(x: x, y: plot.minY))
            line.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(line, with: .color(StrandPalette.hairline), lineWidth: 0.5)
        }
        for event in bands { drawBand(&context, event: event, plot: plot, lane: lane, geometry: geometry) }

        // No data: hatched grey over the stretch, never a line across it.
        for gap in timeline.events where gap.kind == .noData {
            drawGap(&context, event: gap, plot: plot, geometry: geometry)
        }

        if showSteps { drawSteps(&context, plot: plot, geometry: geometry) }
        if showEnergy { drawOutside(&context, timeline.energy, color: StrandPalette.chargeColor, dash: [], plot: plot, geometry: geometry) }
        if showGarminStress {
            drawOutside(&context, timeline.garminStress, color: StrandPalette.metricAmber, dash: [2, 3], plot: plot, geometry: geometry)
        }
        if showStress { drawStress(&context, plot: plot, geometry: geometry) }
        drawHeartRate(&context, plot: plot, geometry: geometry)

        for tick in axisTicks() {
            let x = geometry.x(for: tick.date)
            context.draw(Text(tick.label).font(StrandFont.caption).foregroundColor(StrandPalette.textTertiary),
                         at: CGPoint(x: min(max(x, 10), size.width - 10), y: lane.maxY + 4), anchor: .top)
        }

        if let f = timeline.nowFraction {
            let x = CGFloat(f) * size.width
            var marker = Path()
            marker.move(to: CGPoint(x: x, y: plot.minY))
            marker.addLine(to: CGPoint(x: x, y: lane.maxY))
            context.stroke(marker, with: .color(StrandPalette.accent), lineWidth: 1.5)
            context.fill(Path(ellipseIn: CGRect(x: x - 3, y: plot.minY - 1, width: 6, height: 6)),
                         with: .color(StrandPalette.accent))
        }

        if let scrubDate { drawScrub(&context, at: scrubDate, plot: plot, lane: lane, geometry: geometry) }
    }

    private func drawBand(_ context: inout GraphicsContext, event: DayTimeline.Event, plot: CGRect, lane: CGRect,
                          geometry: MyDayStripGeometry) {
        let end = event.end ?? event.start.addingTimeInterval(20 * 60)
        let x0 = geometry.x(for: max(event.start, timeline.dayStart))
        let x1 = max(geometry.x(for: min(end, timeline.dayEnd)), x0 + 3)
        let color = MyDayStyle.color(event.kind)
        let dashed = event.kind == .planned || event.kind == .detected
        let wash = CGRect(x: x0, y: plot.minY, width: x1 - x0, height: plot.height)
        context.fill(Path(wash), with: .color(color.opacity(dashed ? 0.08 : 0.18)))
        let chip = Path(roundedRect: CGRect(x: x0, y: lane.minY, width: x1 - x0, height: lane.height), cornerRadius: 4)
        if dashed {
            context.stroke(chip, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        } else {
            context.fill(chip, with: .color(color.opacity(0.9)))
        }
    }

    private func drawGap(_ context: inout GraphicsContext, event: DayTimeline.Event, plot: CGRect,
                         geometry: MyDayStripGeometry) {
        guard let end = event.end else { return }
        let x0 = geometry.x(for: event.start), x1 = geometry.x(for: end)
        guard x1 > x0 else { return }
        let rect = CGRect(x: x0, y: plot.minY, width: x1 - x0, height: plot.height)
        context.fill(Path(rect), with: .color(StrandPalette.textTertiary.opacity(0.10)))
        var layer = context
        layer.clip(to: Path(rect))
        var hatch = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            hatch.move(to: CGPoint(x: x, y: rect.maxY))
            hatch.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 7
        }
        layer.stroke(hatch, with: .color(StrandPalette.textTertiary.opacity(0.45)), lineWidth: 1)
    }

    private func drawHeartRate(_ context: inout GraphicsContext, plot: CGRect, geometry: MyDayStripGeometry) {
        let values = timeline.hr.map(\.bpm)
        guard let low = values.min(), let high = values.max() else { return }
        let lo = max(30, low - 6)
        let hi = max(lo + 30, high + 6)
        func y(_ bpm: Double) -> CGFloat { plot.maxY - CGFloat((bpm - lo) / (hi - lo)) * (plot.height - 8) - 4 }
        for run in MyDayStripGeometry.runs(of: timeline.hr) {
            if run.count == 1, let only = run.first {
                let center = CGPoint(x: geometry.x(forTs: only.ts), y: y(only.bpm))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
                             with: .color(StrandPalette.metricRose))
                continue
            }
            var path = Path()
            for (i, p) in run.enumerated() {
                let point = CGPoint(x: geometry.x(forTs: p.ts), y: y(p.bpm))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(StrandPalette.metricRose),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawStress(_ context: inout GraphicsContext, plot: CGRect, geometry: MyDayStripGeometry) {
        func y(_ level: Double) -> CGFloat { plot.maxY - CGFloat(min(max(level / 3, 0), 1)) * (plot.height - 8) - 4 }
        var path = Path()
        var open = false
        for p in timeline.stress {
            guard let level = p.level else { open = false; continue }
            let point = CGPoint(x: geometry.x(forTs: p.ts), y: y(level))
            if open { path.addLine(to: point) } else { path.move(to: point); open = true }
        }
        context.stroke(path, with: .color(StrandPalette.stressColor),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [5, 3]))
    }

    /// A 0-100 curve from outside (Garmin Body Battery or stress) on the strip's own height. A reading more than
    /// an hour after the one before it breaks the line rather than being joined across the hole.
    private func drawOutside(_ context: inout GraphicsContext, _ points: [DayTimeline.SeriesPoint], color: Color,
                             dash: [CGFloat], plot: CGRect, geometry: MyDayStripGeometry) {
        guard !points.isEmpty else { return }
        func y(_ value: Double) -> CGFloat { plot.maxY - CGFloat(min(max(value / 100, 0), 1)) * (plot.height - 8) - 4 }
        var path = Path()
        var previous: Int?
        for p in points {
            let point = CGPoint(x: geometry.x(forTs: p.ts), y: y(p.value))
            if let previous, p.ts - previous <= 3600 { path.addLine(to: point) } else { path.move(to: point) }
            previous = p.ts
        }
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: dash))
    }

    private func drawSteps(_ context: inout GraphicsContext, plot: CGRect, geometry: MyDayStripGeometry) {
        guard let top = timeline.stepsCumulative.map(\.cumulative).max(), top > 0 else { return }
        func y(_ steps: Int) -> CGFloat { plot.maxY - CGFloat(steps) / CGFloat(top) * (plot.height - 8) - 4 }
        var line = Path()
        for (i, p) in timeline.stepsCumulative.enumerated() {
            let point = CGPoint(x: geometry.x(forTs: p.ts), y: y(p.cumulative))
            if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        var area = line
        if let last = timeline.stepsCumulative.last, let first = timeline.stepsCumulative.first {
            area.addLine(to: CGPoint(x: geometry.x(forTs: last.ts), y: plot.maxY))
            area.addLine(to: CGPoint(x: geometry.x(forTs: first.ts), y: plot.maxY))
            area.closeSubpath()
        }
        context.fill(area, with: .color(StrandPalette.metricCyan.opacity(0.12)))
        context.stroke(line, with: .color(StrandPalette.metricCyan), lineWidth: 1.5)
    }

    private func drawScrub(_ context: inout GraphicsContext, at date: Date, plot: CGRect, lane: CGRect,
                           geometry: MyDayStripGeometry) {
        let x = geometry.x(for: date)
        var line = Path()
        line.move(to: CGPoint(x: x, y: plot.minY))
        line.addLine(to: CGPoint(x: x, y: lane.maxY))
        context.stroke(line, with: .color(StrandPalette.textPrimary.opacity(0.7)), lineWidth: 1)
        let values = timeline.hr.map(\.bpm)
        if let low = values.min(), let high = values.max(),
           let p = MyDayStripGeometry.nearest(to: Int(date.timeIntervalSince1970), in: timeline.hr) {
            let lo = max(30, low - 6)
            let hi = max(lo + 30, high + 6)
            let y = plot.maxY - CGFloat((p.bpm - lo) / (hi - lo)) * (plot.height - 8) - 4
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                         with: .color(StrandPalette.textPrimary))
        }
    }

    // MARK: Axis and labels

    private struct Tick {
        let date: Date
        let label: String
    }

    /// 00, 06, 12 and 18 on the local clock, so the labels stay right on a 23 or 25 hour day.
    private func axisTicks() -> [Tick] {
        let calendar = Calendar.current
        return [0, 6, 12, 18].compactMap { hour in
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: timeline.dayStart)
                .map { Tick(date: $0, label: String(format: "%02d", hour)) }
        }
    }

    private var accessibilitySummary: String {
        let count = bands.count
        return String(localized: "Day timeline: heart rate across the day, \(count) marked periods")
    }

    private func bandLabel(_ event: DayTimeline.Event) -> String {
        let fmt = AppClock.hourMinuteFormatter()
        let from = fmt.string(from: event.start)
        guard let end = event.end else { return "\(event.title), from \(from)" }
        return "\(event.title), \(from) to \(fmt.string(from: end))"
    }
}
