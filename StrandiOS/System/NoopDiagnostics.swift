#if os(iOS)
import Foundation
import UIKit
import os
import Darwin

// MARK: - On-device evidence for crashes, hangs and memory kills
//
// A watchdog kill (0x8badf00d, about 10 s of blocked main thread), a memory kill (jetsam) or a hang leaves nothing
// in NOOP's own logs, so a field report used to arrive with no stack and no numbers. This keeps, on the phone:
// - a ring of the last 200 breadcrumbs (screen opened, document loaded with its size, scoring start/end, a stall of
//   the main thread with the section it was in, the memory footprint), written to Application Support;
// - a "did not finish" marker, so a run that ended in the foreground without going to the background first (a crash,
//   a watchdog or memory kill, a force quit of a frozen app) is found on the next launch, with that run's breadcrumbs;
// - the MetricKit payloads iOS delivers (crash, hang, CPU and disk-write diagnostics, the daily metrics), as JSON.
// Breadcrumbs carry labels, durations, byte counts and megabytes only: no health value, no token, no document text.
// `NoopDiagReport` turns them into a compact report (64 KB at most) that the phone sends to PaceForge on the next
// launch after an unclean exit or a new diagnostic, and from Settings > Tools > Send diagnostics now.

enum NoopDiag {
    /// Points of Interest intervals around the sections below, so Instruments and XCTOSSignpostMetric see them.
    static let signposter = OSSignposter(subsystem: "app.noop.perf", category: .pointsOfInterest)

    /// DEBUG `-NoopPerf`: a finer watchdog, a footprint sample every second and the per-screen summary the perf UI
    /// tests read. Off on every real run.
    static let isPerfMode: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-NoopPerf")
        #else
        return false
        #endif
    }()

    /// A stall shorter than this is not recorded. 250 ms on a phone; 33 ms in perf mode, where a simulator on a fast Mac
    /// stands in for a slower iPhone (the perf tests apply a x4 factor to what they read).
    static var stallThreshold: TimeInterval { isPerfMode ? 0.033 : 0.25 }

    private static var started = false

    /// Called once, first thing at launch.
    @MainActor
    static func start() {
        guard !started else { return }
        started = true
        // A process iOS starts in the background (Bluetooth, a background task) is not on screen; the scene marks the
        // foreground when it becomes active. A launch on screen counts from here, so a watchdog kill during launch is
        // still found.
        NoopDiagStore.shared.beginRun(launchedOnScreen: UIApplication.shared.applicationState != .background)
        MainThreadSampler.captureMainThread()
        MainThreadWatchdog.shared.start(tick: isPerfMode ? 0.008 : 0.05, threshold: stallThreshold)
        NoopDiagSampler.shared.start(interval: isPerfMode ? 1 : 5)
        crumb("launch", ["footprint_mb": NoopDiagSampler.footprintMB()])
        recordAssistiveFeatures()
    }

    /// The assistive features on when the app was last active. With one of them running, iOS asks SwiftUI for the whole
    /// accessibility tree (every Text resolved, on the main thread), which costs as much as the screen itself.
    private(set) static var assistive: [String: Double] = [:]

    @MainActor
    static func recordAssistiveFeatures() {
        let flags: [String: Bool] = [
            "voiceover": UIAccessibility.isVoiceOverRunning, "switch_control": UIAccessibility.isSwitchControlRunning,
            "assistive_touch": UIAccessibility.isAssistiveTouchRunning, "speak_screen": UIAccessibility.isSpeakScreenEnabled,
            "speak_selection": UIAccessibility.isSpeakSelectionEnabled, "guided_access": UIAccessibility.isGuidedAccessEnabled,
            "reduce_motion": UIAccessibility.isReduceMotionEnabled, "bold_text": UIAccessibility.isBoldTextEnabled,
        ]
        let numbers = flags.mapValues { $0 ? 1.0 : 0.0 }
        guard numbers != assistive else { return }
        assistive = numbers
        crumb("assistive", numbers)
    }

    /// One breadcrumb. `event` is a fixed label from the code; `fields` are numbers only.
    static func crumb(_ event: String, _ fields: [String: Double] = [:]) {
        NoopDiagStore.shared.append(event: event, fields: fields)
    }

    // MARK: Screens and sections

    private static let labels = OSAllocatedUnfairLock(uncheckedState: Labels())
    private struct Labels {
        var screen = "launch"
        var section: String?
    }

    /// What the watchdog attributes a stall to: the innermost section running on the main thread, else the screen.
    static var currentLabels: (screen: String, section: String?) {
        labels.withLockUnchecked { ($0.screen, $0.section) }
    }

    /// The screen on show (a tab, a PaceForge segment). Stalls and CPU time are counted per screen.
    static func screen(_ name: String) {
        let previous = labels.withLockUnchecked { state -> String in
            let old = state.screen
            state.screen = name
            return old
        }
        guard previous != name else { return }
        NoopPerfStats.shared.enter(screen: name)
        crumb("screen \(name)", ["footprint_mb": NoopDiagSampler.footprintMB()])
    }

    /// Runs a synchronous section on the caller's thread, inside a signpost interval, and records its time. A stall
    /// while it runs is attributed to `label`.
    @discardableResult
    static func measure<T>(_ label: StaticString, _ body: () throws -> T) rethrows -> T {
        let name = "\(label)"
        let isMain = Thread.isMainThread
        var outer: String?
        if isMain {
            outer = labels.withLockUnchecked { state -> String? in
                let old = state.section
                state.section = name
                return old
            }
        }
        let state = signposter.beginInterval(label)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            signposter.endInterval(label, state)
            if isMain { labels.withLockUnchecked { $0.section = outer } }
            NoopPerfStats.shared.section(name, ms: ms, onMain: isMain)
            if ms >= (isPerfMode ? 16 : 100) { crumb(name, ["ms": ms.rounded(), "main": isMain ? 1 : 0]) }
        }
        return try body()
    }

    /// The start and end of a long asynchronous job (a refresh, a scoring pass), as two breadcrumbs and a signpost.
    static func begin(_ label: StaticString, _ fields: [String: Double] = [:]) -> NoopDiagInterval {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(label, id: id)
        crumb("\(label) start", fields)
        return NoopDiagInterval(label: label, state: state, start: DispatchTime.now().uptimeNanoseconds)
    }

    /// Perf mode only: counts one evaluation of a view's body, so an invalidation storm shows which view it hits.
    static func body(_ name: StaticString) {
        guard isPerfMode else { return }
        NoopPerfStats.shared.body("\(name)")
    }

    // MARK: Scene phase

    /// The scene is on screen: from now until it goes to the background, an exit is not a clean one.
    @MainActor
    static func sceneActive() {
        NoopDiagStore.shared.setForeground(true)
        crumb("active", ["footprint_mb": NoopDiagSampler.footprintMB()])
        recordAssistiveFeatures()
    }

    /// Going to the background ends the foreground stretch cleanly.
    static func sceneBackground() {
        crumb("background", ["footprint_mb": NoopDiagSampler.footprintMB()])
        NoopDiagStore.shared.setForeground(false)
    }
}

struct NoopDiagInterval {
    let label: StaticString
    let state: OSSignpostIntervalState
    let start: UInt64

    func end(_ fields: [String: Double] = [:]) {
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        NoopDiag.signposter.endInterval(label, state)
        var all = fields
        all["ms"] = ms.rounded()
        NoopDiag.crumb("\(label) end", all)
        NoopPerfStats.shared.section("\(label)", ms: ms, onMain: false)
    }
}

// MARK: - Store

/// The breadcrumb ring, the run marker and the saved MetricKit payloads, under Application Support/Diagnostics.
final class NoopDiagStore {
    static let shared = NoopDiagStore()
    static let ringSize = 200

    private let queue = DispatchQueue(label: "app.noop.diag", qos: .utility)
    private var ring: [[String: Any]] = []
    private var flushPending = false
    private let runId = UUID().uuidString.prefix(8).lowercased()

    let directory: URL? = {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("metrickit", isDirectory: true),
                                                 withIntermediateDirectories: true)
        return dir
    }()

    private func file(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var appBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    // MARK: Run marker

    /// Reads the previous run's marker; a run that was in the foreground when it ended becomes `previous-run.json`
    /// (its breadcrumbs and build), and the next report carries it. Then marks this run as started.
    func beginRun(launchedOnScreen: Bool) {
        queue.sync {
            let previous = readJSON("run-state.json")
            if let previous, previous["foreground"] as? Bool == true {
                var unclean = previous
                unclean["crumbs"] = readRingFile()
                unclean["detected_at"] = Self.now()
                unclean["detected_by_build"] = Self.appBuild
                writeJSON(unclean, "previous-run.json")
                setPending("unclean", true)
            }
            ring = []
            writeJSON(["run": String(runId), "build": Self.appBuild, "version": Self.appVersion,
                       "started_at": Self.now(), "foreground": launchedOnScreen], "run-state.json")
        }
    }

    func setForeground(_ on: Bool) {
        queue.async {
            var state = self.readJSON("run-state.json") ?? ["run": String(self.runId), "build": Self.appBuild]
            state["foreground"] = on
            state["updated_at"] = Self.now()
            self.writeJSON(state, "run-state.json")
            self.flushLocked()
        }
    }

    // MARK: Breadcrumbs

    func append(event: String, fields: [String: Double]) {
        let crumb = Self.crumb(event, fields)
        queue.async {
            self.ring.append(crumb)
            if self.ring.count > Self.ringSize { self.ring.removeFirst(self.ring.count - Self.ringSize) }
            self.scheduleFlush()
        }
    }

    /// From the watchdog thread while the main thread is still blocked: written at once, since the process may be
    /// killed before the next flush.
    func appendNow(event: String, fields: [String: Double]) {
        let crumb = Self.crumb(event, fields)
        queue.sync {
            ring.append(crumb)
            if ring.count > Self.ringSize { ring.removeFirst(ring.count - Self.ringSize) }
            flushLocked()
        }
    }

    private static func crumb(_ event: String, _ fields: [String: Double]) -> [String: Any] {
        var crumb: [String: Any] = ["t": (now() * 10).rounded() / 10, "e": event]
        for (k, v) in fields where v.isFinite { crumb[k] = v }
        return crumb
    }

    private func scheduleFlush() {
        guard !flushPending else { return }
        flushPending = true
        queue.asyncAfter(deadline: .now() + 1) { self.flushLocked() }
    }

    private func flushLocked() {
        flushPending = false
        guard let url = file("breadcrumbs.jsonl") else { return }
        let lines = ring.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            .compactMap { String(data: $0, encoding: .utf8) }
        try? Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
    }

    private func readRingFile() -> [[String: Any]] {
        guard let url = file("breadcrumbs.jsonl"), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
    }

    /// This run's breadcrumbs, oldest first.
    func currentCrumbs() -> [[String: Any]] { queue.sync { ring } }

    func previousRun() -> [String: Any]? { queue.sync { readJSON("previous-run.json") } }

    // MARK: MetricKit

    /// Keeps a MetricKit payload's JSON: the newest eight diagnostic payloads and the newest three metric payloads.
    func saveMetricKit(_ json: Data, diagnostic: Bool) {
        queue.async {
            guard let dir = self.directory?.appendingPathComponent("metrickit", isDirectory: true) else { return }
            let prefix = diagnostic ? "diagnostic" : "metric"
            let name = "\(prefix)-\(Int(Self.now() * 1000)).json"
            try? json.write(to: dir.appendingPathComponent(name), options: .atomic)
            let kept = diagnostic ? 8 : 3
            let files = self.metricKitFiles(prefix: prefix)
            for old in files.dropLast(kept) { try? FileManager.default.removeItem(at: old) }
            if diagnostic { self.setPending("metrickit", true) }
        }
    }

    /// Oldest first.
    func metricKitFiles(prefix: String) -> [URL] {
        guard let dir = directory?.appendingPathComponent("metrickit", isDirectory: true),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasPrefix(prefix + "-") && $0.hasSuffix(".json") }.sorted()
            .map { dir.appendingPathComponent($0) }
    }

    func metricKitPayloads(diagnostic: Bool) -> [(file: String, json: [String: Any])] {
        queue.sync {
            metricKitFiles(prefix: diagnostic ? "diagnostic" : "metric").compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
                return (url.lastPathComponent, json)
            }
        }
    }

    // MARK: Upload bookkeeping

    /// "unclean" and "metrickit": something the next report should carry that no report has delivered yet.
    func pending() -> Set<String> {
        queue.sync {
            guard let keys = readJSON("pending.json")?.keys else { return Set<String>() }
            return Set(keys)
        }
    }

    private func setPending(_ key: String, _ on: Bool) {
        var state = readJSON("pending.json") ?? [:]
        if on { state[key] = Self.now() } else { state.removeValue(forKey: key) }
        writeJSON(state, "pending.json")
    }

    func clearPending() { queue.sync { writeJSON([:], "pending.json") } }

    func recordUpload(status: Int?, message: String, trigger: String) {
        queue.sync {
            writeJSON(["at": Self.now(), "status": status ?? -1, "message": String(message.prefix(300)), "trigger": trigger],
                      "last-upload.json")
        }
    }

    func lastUpload() -> [String: Any]? { queue.sync { readJSON("last-upload.json") } }

    /// The newest report the phone built, kept so Settings can show and share it whether or not the server took it.
    func saveReport(_ data: Data) { queue.sync { if let url = file("last-report.json") { try? data.write(to: url, options: .atomic) } } }

    func lastReport() -> Data? { queue.sync { file("last-report.json").flatMap { try? Data(contentsOf: $0) } } }

    // MARK: Files

    private func readJSON(_ name: String) -> [String: Any]? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeJSON(_ object: [String: Any], _ name: String) {
        guard let url = file(name), let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func now() -> Double { Date().timeIntervalSince1970 }
}

// MARK: - Main-thread watchdog

/// A background thread that asks the main thread to answer every `tick`. A late answer is a stall: recorded with how
/// long it lasted and the section or screen it happened in. A stall still going after a second is written at once and
/// again every second, so a watchdog kill leaves its last seconds on disk.
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    private struct Pong {
        var seq = 0
        var at: UInt64 = 0
    }

    private let pong = OSAllocatedUnfairLock(uncheckedState: Pong())
    private var thread: Thread?

    func start(tick: TimeInterval, threshold: TimeInterval) {
        guard thread == nil else { return }
        let thread = Thread { [weak self] in self?.loop(tick: tick, threshold: threshold) }
        thread.name = "app.noop.watchdog"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    private func loop(tick: TimeInterval, threshold: TimeInterval) {
        var seq = 0
        while true {
            seq += 1
            let sent = DispatchTime.now().uptimeNanoseconds
            let mySeq = seq
            let lock = pong
            DispatchQueue.main.async {
                lock.withLockUnchecked { $0 = Pong(seq: mySeq, at: DispatchTime.now().uptimeNanoseconds) }
            }
            var lastOngoingReport = 0.0
            var ongoingLabels: (screen: String, section: String?)?
            var stallSamples = 0
            var lastTop: String?
            while true {
                Thread.sleep(forTimeInterval: tick)
                let answer = pong.withLockUnchecked { $0 }
                if answer.seq >= mySeq {
                    let blocked = Double(answer.at &- sent) / 1e9
                    if blocked >= threshold {
                        let labels = ongoingLabels ?? NoopDiag.currentLabels
                        NoopPerfStats.shared.stall(ms: blocked * 1000, screen: labels.screen, section: labels.section)
                        // The NOOP function the main thread was in, when a sample caught it: code names only.
                        let place = lastTop.map { " at \($0)" } ?? ""
                        NoopDiagStore.shared.append(event: "stall \(labels.section ?? labels.screen)\(place)",
                                                    fields: ["ms": (blocked * 1000).rounded(),
                                                             "footprint_mb": NoopDiagSampler.footprintMB()])
                    }
                    break
                }
                let waited = Double(DispatchTime.now().uptimeNanoseconds &- sent) / 1e9
                if waited >= threshold, ongoingLabels == nil { ongoingLabels = NoopDiag.currentLabels }
                // Where the main thread is: a sample every tick of a stall, at most 40 per stall.
                if waited >= threshold, stallSamples < 40 {
                    stallSamples += 1
                    let stack = MainThreadSampler.sample()
                    MainThreadProfile.shared.add(stack, stallMs: waited * 1000)
                    if let top = stack.lazy.map({ MainThreadSampler.frame($0) }).first(where: \.isApp) {
                        lastTop = MainThreadSampler.short(top.symbol)
                    }
                }
                if waited >= 1, waited - lastOngoingReport >= 1 {
                    lastOngoingReport = waited
                    let labels = ongoingLabels ?? NoopDiag.currentLabels
                    NoopDiagStore.shared.appendNow(event: "stall ongoing \(labels.section ?? labels.screen)",
                                                   fields: ["ms": (waited * 1000).rounded(),
                                                            "footprint_mb": NoopDiagSampler.footprintMB()])
                }
            }
            Thread.sleep(forTimeInterval: tick)
        }
    }
}

// MARK: - Footprint and CPU

final class NoopDiagSampler {
    static let shared = NoopDiagSampler()

    private let queue = DispatchQueue(label: "app.noop.diag.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private(set) var peakMB: Double = 0
    private var lastCrumbMB: Double = 0
    private var lastCrumbAt: Double = 0
    /// While the PaceForge tab is open, every sample is a breadcrumb.
    var isWatchingClosely = false

    func start(interval: TimeInterval) {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    private func sample() {
        let mb = Self.footprintMB()
        peakMB = max(peakMB, mb)
        NoopPerfStats.shared.footprint(mb)
        let now = NoopDiagStore.now()
        // Otherwise only a big change (a memory kill is preceded by one) or a quiet half-minute heartbeat.
        if isWatchingClosely || abs(mb - lastCrumbMB) >= 50 || now - lastCrumbAt >= 30 {
            lastCrumbMB = mb
            lastCrumbAt = now
            NoopDiag.crumb("mem", ["footprint_mb": mb, "peak_mb": peakMB])
        }
    }

    /// The physical footprint iOS's memory limit is judged on, in MB (one decimal).
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return (Double(info.phys_footprint) / 1_048_576 * 10).rounded() / 10
    }

    /// User plus system CPU time of the whole process, in seconds.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}

// MARK: - Per-screen numbers (the perf UI tests read these)

/// Stalls, blocked time, CPU time and section times per screen, plus the peak footprint. Kept on every run (it is a
/// few dictionaries); shown on screen only in perf mode (`NoopPerfProbe`).
final class NoopPerfStats {
    static let shared = NoopPerfStats()

    struct Screen {
        var stalls = 0
        var blockedMs = 0.0
        var maxStallMs = 0.0
        var maxStallLabel = ""
        var cpuS = 0.0
        var visits = 0
    }

    struct Section {
        var count = 0
        var totalMs = 0.0
        var maxMs = 0.0
        var mainMs = 0.0
    }

    private struct State {
        /// Keyed "screen#visit" ("tab.today#2" is the second time Today was opened), so the launch's work is not
        /// counted against a screen opened later.
        var screens: [String: Screen] = [:]
        var sections: [String: Section] = [:]
        var visits: [String: Int] = [:]
        var bodies: [String: Int] = [:]
        var current = "launch#1"
        var enteredCPU = NoopDiagSampler.cpuSeconds()
        var peakMB = 0.0
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    func enter(screen: String) {
        let cpu = NoopDiagSampler.cpuSeconds()
        state.withLockUnchecked { s in
            s.screens[s.current, default: Screen()].cpuS += cpu - s.enteredCPU
            let visit = (s.visits[screen] ?? 0) + 1
            s.visits[screen] = visit
            s.current = "\(screen)#\(visit)"
            s.enteredCPU = cpu
            s.screens[s.current, default: Screen()].visits = visit
        }
    }

    /// Counted against the screen visit on show when the stall started.
    func stall(ms: Double, screen: String, section: String?) {
        state.withLockUnchecked { s in
            var entry = s.screens[s.current, default: Screen()]
            entry.stalls += 1
            entry.blockedMs += ms
            if ms > entry.maxStallMs {
                entry.maxStallMs = ms
                entry.maxStallLabel = section ?? screen
            }
            s.screens[s.current] = entry
        }
    }

    func section(_ name: String, ms: Double, onMain: Bool) {
        state.withLockUnchecked { s in
            var entry = s.sections[name, default: Section()]
            entry.count += 1
            entry.totalMs += ms
            entry.maxMs = max(entry.maxMs, ms)
            if onMain { entry.mainMs += ms }
            s.sections[name] = entry
        }
    }

    func body(_ name: String) { state.withLockUnchecked { $0.bodies[name, default: 0] += 1 } }

    func footprint(_ mb: Double) { state.withLockUnchecked { $0.peakMB = max($0.peakMB, mb) } }

    /// Compact JSON: {"peak_mb":..., "screens":{name:{...}}, "sections":{name:{...}}}.
    func summaryJSON() -> String {
        let cpu = NoopDiagSampler.cpuSeconds()
        let snapshot = state.withLockUnchecked { s -> State in
            var copy = s
            copy.screens[s.current, default: Screen()].cpuS += cpu - s.enteredCPU
            return copy
        }
        func r(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        var screens: [String: Any] = [:]
        for (name, e) in snapshot.screens {
            screens[name] = ["stalls": e.stalls, "blocked_ms": r(e.blockedMs), "max_ms": r(e.maxStallMs),
                             "max_label": e.maxStallLabel, "cpu_s": r(e.cpuS), "visits": e.visits]
        }
        var sections: [String: Any] = [:]
        for (name, e) in snapshot.sections {
            sections[name] = ["n": e.count, "total_ms": r(e.totalMs), "max_ms": r(e.maxMs), "main_ms": r(e.mainMs)]
        }
        #if DEBUG
        let autopilot: Any = NoopPerfAutopilot.isDone ? "done" : "running"
        #else
        let autopilot: Any = "off"
        #endif
        let object: [String: Any] = ["peak_mb": r(max(snapshot.peakMB, NoopDiagSampler.footprintMB())), "autopilot": autopilot,
                                     "screens": screens, "sections": sections, "bodies": snapshot.bodies,
                                     "main_thread": MainThreadProfile.shared.summary()]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
