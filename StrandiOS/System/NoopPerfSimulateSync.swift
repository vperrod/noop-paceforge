#if DEBUG && os(iOS)
import Foundation

/// DEBUG `-NoopPerfSimulateSync`: what a phone does when its strap sync starts, without a strap. Five seconds after launch
/// `LiveState` goes to "connected, backfilling" and, for forty seconds, publishes 10-14 times a second the way the BLE
/// objects do (heart rate, battery, sync chunk counters). Nothing here writes data: the repository is whatever the demo
/// seed and fixture supplied.
///
/// `-NoopPerfStallLog <name>` also starts a stall meter that is independent of the app's own watchdog (so the profiled
/// build does not need `-NoopPerf`, whose accessibility probe is itself work on the main thread): a background timer pings the
/// main queue every 10 ms; an unanswered ping older than 100 ms is a stall. The log is JSON in the temporary directory,
/// rewritten every second, with seconds-since-launch for every stall so the window after the sync start can be summed.
enum NoopPerfSimulateSync {
    private static let args = ProcessInfo.processInfo.arguments

    static var isRequested: Bool { args.contains("-NoopPerfSimulateSync") }

    /// Seconds after launch at which the simulated sync starts, and how long it lasts.
    static let startAfter: Double = 5
    static let duration: Double = 40

    @MainActor
    static func startIfRequested(live: LiveState) {
        startStallMeterIfRequested()
        guard isRequested else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(startAfter * 1_000_000_000))
            live.connected = true
            live.bonded = true
            live.batteryPct = 68
            live.charging = false
            // `-NoopPerfPublishOnly`: the 10-14 Hz publishes without the backfilling flag; `-NoopPerfSyncOnly`: the flag without them.
            if !args.contains("-NoopPerfPublishOnly") { live.backfilling = true }
            NoopDiag.crumb("perf.sync.started")
            let end = Date().addingTimeInterval(duration)
            var tick = 0
            while Date() < end {
                tick += 1
                if !args.contains("-NoopPerfSyncOnly") {
                    live.heartRate = 58 + (tick * 7) % 41
                    live.syncChunksThisSession += 1
                    live.decodedChunksThisSession += 1
                    if tick % 6 == 0 { live.batteryPct = 68 - Double(tick % 3) * 0.5 }
                }
                // 10-14 Hz, jittered like a radio.
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1 / 14 ... 1 / 10) * 1_000_000_000))
            }
            live.backfilling = false
            live.lastSyncedAt = Date().timeIntervalSince1970
            NoopDiag.crumb("perf.sync.ended")
        }
    }

    // MARK: Identity counters

    private static let countLock = NSLock()
    private static var counters: [String: Int] = [:]

    /// Counts a view appearing or disappearing (or a body running), so identity churn shows as a rate per second.
    static func count(_ name: String) {
        countLock.lock(); counters[name, default: 0] += 1; countLock.unlock()
    }

    private static func countersSnapshot() -> [String: Int] {
        countLock.lock(); defer { countLock.unlock() }
        return counters
    }

    // MARK: Stall meter

    private static let queue = DispatchQueue(label: "noop.perf.stallmeter")
    private static var timer: DispatchSourceTimer?
    private static var outstandingSince: Double?
    private static var events: [[Double]] = []        // [startSeconds, durationSeconds]
    private static var counterSeries: [[String: Int]] = []   // one snapshot a second, with "t"
    private static let launch = ProcessInfo.processInfo.systemUptime

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime - launch }

    private static func startStallMeterIfRequested() {
        guard let index = args.firstIndex(of: "-NoopPerfStallLog"), args.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(args[index + 1])
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.01, repeating: 0.01)
        var lastWrite = 0.0
        timer.setEventHandler {
            let t = now()
            if outstandingSince == nil {               // else a ping is still in flight; its age is read when it returns, and below
                outstandingSince = t
                let sent = t
                DispatchQueue.main.async {
                    queue.async {
                        let done = now()
                        if done - sent > 0.1 { events.append([sent, done - sent]) }
                        outstandingSince = nil
                    }
                }
            }
            guard t - lastWrite >= 1 else { return }
            lastWrite = t
            var all = events
            if let since = outstandingSince, t - since > 0.1 { all.append([since, t - since]) }   // a stall still going
            let total = all.reduce(0) { $0 + $1[1] }
            let after = all.filter { $0[0] >= startAfter }.reduce(0) { $0 + $1[1] }
            var snapshot = countersSnapshot()
            snapshot["t"] = Int(t)
            counterSeries.append(snapshot)
            let object: [String: Any] = ["uptime_s": t, "counters": Array(counterSeries.suffix(80)), "stall_events": all.count, "stalled_s_total": total,
                                         "stalled_s_after_sync_start": after, "longest_s": all.map { $0[1] }.max() ?? 0,
                                         "events": Array(all.suffix(400))]
            if let data = try? JSONSerialization.data(withJSONObject: object) { try? data.write(to: url, options: .atomic) }
        }
        timer.resume()
        Self.timer = timer
    }
}

/// DEBUG launch switches that remove one suspect at a time from Today, for the bisect in .github/workflows/profile-today.yml.
/// Motion is removed with the app's own `-noop.quietMotion YES`, not here.
enum NoopPerfSwitches {
    private static let args = ProcessInfo.processInfo.arguments
    static let noViewThatFits = args.contains("-NoopPerfNoViewThatFits")
    static let noBatteryButton = args.contains("-NoopPerfNoBattery")
    /// The battery button keeps its battery reading but is never told a sync is running.
    static let noSyncMorph = args.contains("-NoopPerfNoSyncMorph")
    /// The candidate fix: the top bar is decided without ViewThatFits.
    static let staticTopBar = args.contains("-NoopPerfStaticTopBar")
    /// `-NoopPerfMountCap N`.
    static let mountCap: Int? = args.firstIndex(of: "-NoopPerfMountCap").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
}
#endif
