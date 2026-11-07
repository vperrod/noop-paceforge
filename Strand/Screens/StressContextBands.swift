import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - Context under the stress curve
//
// A thin row of workouts, naps and caffeine drawn under the day's stress line, from the same `DayTimeline`
// My Day is built from, so a spike next to a workout or a coffee explains itself. It spans exactly the time
// the line spans: `DaytimeLoadLine` places its i-th point at i / (n - 1) of the width, first point to last.

struct StressContextBands: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var caffeineLog = CaffeineLogStore.shared

    let hours: [DaytimeStress.HourPoint]

    @State private var events: [DayTimeline.Event] = []

    private static let kinds: [DayTimeline.Kind] = [.workout, .nap, .caffeine]

    /// The span the stress line covers, in unix seconds.
    private var window: (lo: Int, hi: Int)? {
        guard hours.count >= 2, let first = hours.first, let last = hours.last, last.startTs > first.startTs else { return nil }
        return (first.startTs, last.startTs)
    }

    private var shown: [DayTimeline.Event] {
        guard let window else { return [] }
        return events.filter { e in
            guard Self.kinds.contains(e.kind) else { return false }
            let end = Int((e.end ?? e.start).timeIntervalSince1970)
            return end >= window.lo && Int(e.start.timeIntervalSince1970) <= window.hi
        }
    }

    var body: some View {
        Group {
            if let window, !shown.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Canvas { context, size in
                        draw(context, size: size, lo: window.lo, hi: window.hi)
                    }
                    .frame(height: 14)
                    legend
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityIdentifier("stress-context-bands")
            }
        }
        .task(id: loadKey) { await load() }
    }

    private var loadKey: String {
        "\(window?.lo ?? 0)|\(repo.refreshSeq)|\(caffeineLog.intakes.count)"
    }

    private func load() async {
        guard let window else { events = []; return }
        let day = Date(timeIntervalSince1970: TimeInterval(window.lo))
        let loaded = await DayTimelineLoader.load(repo: repo, day: day,
                                                  options: DayTimelineLoader.Options(includeHeartRate: false,
                                                                                         includeContext: false))
        guard !Task.isCancelled else { return }
        events = loaded.timeline.events
    }

    private func draw(_ context: GraphicsContext, size: CGSize, lo: Int, hi: Int) {
        let span = Double(hi - lo)
        func x(_ date: Date) -> CGFloat {
            CGFloat(min(max((date.timeIntervalSince1970 - Double(lo)) / span, 0), 1)) * size.width
        }
        for e in shown {
            let color = MyDayStyle.color(e.kind)
            if e.kind == .caffeine {
                let cx = x(e.start)
                context.fill(Path(ellipseIn: CGRect(x: cx - 4, y: size.height / 2 - 4, width: 8, height: 8)),
                             with: .color(color))
            } else {
                let x0 = x(e.start)
                let x1 = max(x(e.end ?? e.start), x0 + 3)
                context.fill(Path(roundedRect: CGRect(x: x0, y: 2, width: x1 - x0, height: size.height - 4), cornerRadius: 4),
                             with: .color(color.opacity(0.85)))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space3) {
            ForEach(Self.kinds, id: \.self) { kind in
                if shown.contains(where: { $0.kind == kind }) {
                    HStack(spacing: 4) {
                        Circle().fill(MyDayStyle.color(kind)).frame(width: 7, height: 7)
                        Text(Self.name(kind)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private static func name(_ kind: DayTimeline.Kind) -> LocalizedStringKey {
        switch kind {
        case .workout: return "Workout"
        case .nap: return "Nap"
        default: return "Caffeine"
        }
    }

    private var accessibilitySummary: String {
        let clock = AppClock.hourMinuteFormatter()
        let parts = shown.map { "\($0.title) \(clock.string(from: $0.start))" }
        return String(localized: "Workouts, naps and caffeine today: \(parts.joined(separator: ", "))")
    }
}
