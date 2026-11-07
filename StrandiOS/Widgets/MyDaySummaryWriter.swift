import Foundation
import WidgetKit
import StrandAnalytics

/// Builds the My Day widget's summary from the same `DayTimeline` the My Day screen shows, writes it into
/// the App Group, and asks WidgetKit to reload the widget.
@MainActor
enum MyDaySummaryWriter {

    /// The last full refresh, so the day load (workouts, sleep, journal and the rest) is not repeated on
    /// every widget publish, which fires on each foreground and Health sync.
    private static var lastRefresh: Date?
    private static var isRefreshing = false
    private static let minimumGap: TimeInterval = 5 * 60

    /// Loads today (and yesterday, in the first six hours of a day, so the six-hour line is whole) and
    /// publishes. Called from the widget publish path; throttled.
    static func refresh(repo: Repository, now: Date = Date()) async {
        if let last = lastRefresh, now.timeIntervalSince(last) < minimumGap { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let today = await DayTimelineLoader.load(repo: repo, day: now, now: now).timeline
        var earlier: DayTimeline?
        if now.timeIntervalSince(today.dayStart) < TimeInterval(MyDaySummary.windowSec) {
            let before = today.dayStart.addingTimeInterval(-3600)
            earlier = await DayTimelineLoader.load(repo: repo, day: before, now: now).timeline
        }
        // Throttle only after a good write, so a failed one is retried on the next publish.
        if write(make(today: today, earlier: earlier, now: now)) { lastRefresh = now }
    }

    /// Publishes a timeline My Day has just loaded, when it alone covers the six hours.
    static func publish(_ timeline: DayTimeline, now: Date = Date()) {
        guard timeline.nowFraction != nil,
              now.timeIntervalSince(timeline.dayStart) >= TimeInterval(MyDaySummary.windowSec) else { return }
        write(make(today: timeline, earlier: nil, now: now))
    }

    // MARK: Build

    static func make(today: DayTimeline, earlier: DayTimeline?, now: Date) -> MyDaySummary {
        var out = MyDaySummary(updated: now, date: MyDaySummary.dayString(now))
        let end = Int64(now.timeIntervalSince1970)
        let start = end - MyDaySummary.windowSec

        let points = (earlier?.hr ?? []) + today.hr
        out.hr = fiveMinuteMeans(points, from: start, to: end)
        if let last = points.last, end - Int64(last.ts) <= HrTrace.gapSec { out.latestBpm = Int(last.bpm.rounded()) }

        let plans = today.events.filter { $0.kind == .planned }
        // A plan that was done as a workout is folded into that workout; it still counts as a plan.
        let folded = today.events.filter { $0.kind == .workout && $0.sources.contains(.plan) }
        out.plannedCount = plans.count + folded.count
        out.doneCount = plans.filter { $0.status == .done }.count + folded.count
        out.next = nextSession(in: plans) ?? nextPaceForgeSession()
        return out
    }

    /// Five-minute means of the curve inside the window, each stamped at the middle of its slot.
    static func fiveMinuteMeans(_ points: [DayTimeline.HRPoint], from: Int64, to: Int64) -> [HrPoint] {
        var slots: [Int64: (sum: Double, n: Int)] = [:]
        for p in points where Int64(p.ts) >= from && Int64(p.ts) <= to {
            let slot = Int64(p.ts) / 300
            var acc = slots[slot] ?? (sum: 0, n: 0)
            acc.sum += p.bpm; acc.n += 1
            slots[slot] = acc
        }
        return slots.keys.sorted().compactMap { slot in
            slots[slot].map { HrPoint(ts: slot * 300 + 150, bpm: Int(($0.sum / Double($0.n)).rounded())) }
        }
    }

    /// The first plan still to do today: timed ones in order, then those with no slot.
    private static func nextSession(in plans: [DayTimeline.Event]) -> MyDaySummary.Next? {
        let open = plans.filter { $0.status == .planned }
        let ordered = open.filter { !$0.isUntimed }.sorted { $0.start < $1.start } + open.filter(\.isUntimed)
        guard let plan = ordered.first else { return nil }
        let when = plan.isUntimed ? nil : AppClock.hourMinuteFormatter().string(from: plan.start)
        // The subtitle is "Planned · 8.0 km · 55 min"; the widget wants only the figures.
        let detail = plan.subtitle.components(separatedBy: " \u{00B7} ").dropFirst().joined(separator: " \u{00B7} ")
        return MyDaySummary.Next(name: plan.title, detail: detail.isEmpty ? nil : detail, when: when)
    }

    /// Nothing left today: the next PaceForge day's session, from the summary PaceForge already wrote.
    private static func nextPaceForgeSession() -> MyDaySummary.Next? {
        guard let summary = PFSummary.load(), let next = summary.nextSession else { return nil }
        return MyDaySummary.Next(name: next.name, detail: next.detail,
                                 when: summary.nextSessionDate.map(PFWidgetFormat.dayLine))
    }

    // MARK: Write

    @discardableResult
    private static func write(_ summary: MyDaySummary) -> Bool {
        // The same content within ten minutes needs no rewrite and no widget reload.
        if let old = MyDaySummary.load(), old.date == summary.date,
           summary.updated.timeIntervalSince(old.updated) < 600 {
            var comparable = summary
            comparable.updated = old.updated
            if comparable == old { return true }
        }
        guard summary.save() else { return false }
        WidgetCenter.shared.reloadTimelines(ofKind: MyDaySummary.widgetKind)
        return true
    }
}
