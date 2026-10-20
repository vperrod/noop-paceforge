#if os(iOS)
import Foundation
import UIKit

// MARK: - The diagnostics report and its upload
//
// One JSON object of 64 KB at most: the app build, the device model and iOS version, the previous run when it did not
// finish (its breadcrumbs), this run's breadcrumbs, the per-screen stall numbers, and the MetricKit diagnostics with each
// call stack flattened to its frames (binary name and offset; no symbol needs the phone). No health value, no token,
// no document content: breadcrumbs are labels and numbers only.
//
// Sent with the app's PaceForge bearer to POST api/app/log as {"kind": "diagnostics", "type": "field_test", "text": a
// one-line summary, "report": the object}. The kind is not "field_test" on purpose: the server hands a field_test's text
// to the field-test parser, which would read a report as a refused measurement (or, for a short text, as a real one). A
// server that does not know the kind answers 400 and stores nothing; the phone keeps the report (Settings > Tools > Last
// crash report shows and shares it) and tries again at most every two minutes.
//
// The automatic upload does not wait for the main thread: `NoopDiagUpload.startInBackground()` is the first line of the app's
// init and runs on its own utility thread (no Task, no main queue, no timer), so a main thread that freezes within seconds of
// launch cannot keep the previous run's evidence from leaving the phone.
//
// `freeze_stacks` carries the main thread's raw stacks from every stall of 1.5 s or more that no upload has delivered yet
// (see FreezeStacks): "Image+0xoffset" frames, the executable's UUID and the build number, for offline symbolication.

enum NoopDiagReport {
    static let maxBytes = 64 * 1024
    static let summaryMaxChars = 200

    struct Built {
        let json: Data
        let summary: String
        /// The ids of the freeze stalls the report carries.
        let stallIds: [String]
    }

    /// The report as JSON, cut to `maxBytes`. `skippingStalls`: freeze stalls an earlier upload of this run delivered.
    static func build(trigger: String, skippingStalls: Set<String> = []) -> Built {
        let store = NoopDiagStore.shared
        let previous = store.previousRun()
        let diagnostics = store.metricKitPayloads(diagnostic: true).map { compactDiagnostic($0.json, file: $0.file) }
        let latestMetrics = store.metricKitPayloads(diagnostic: false).last.map { compactMetrics($0.json) }
        var crumbs = store.currentCrumbs()
        var previousCrumbs = (previous?["crumbs"] as? [[String: Any]]) ?? []
        var frameCap = 60
        var diagnosticCap = diagnostics.count
        let freezeStalls = FreezeStacks.snapshot().filter { !skippingStalls.contains($0["id"] as? String ?? "") }
        var freezeStallCap = freezeStalls.count
        var freezeThin = false
        let summary = summaryLine(previous: previous, diagnostics: diagnostics)

        func object() -> [String: Any] {
            var report: [String: Any] = [
                "schema": "noop-diagnostics/1",
                "type": "field_test",
                "trigger": trigger,
                "generated_at": NoopDiagStore.now(),
                "app": ["version": NoopDiagStore.appVersion, "build": NoopDiagStore.appBuild],
                "device": ["model": deviceModel(), "os": ProcessInfo.processInfo.operatingSystemVersionString],
                "footprint_mb": NoopDiagSampler.footprintMB(),
                "assistive": NoopDiag.assistive,
                "peak_mb": NoopDiagSampler.shared.peakMB,
                "stats": (try? JSONSerialization.jsonObject(with: Data(NoopPerfStats.shared.summaryJSON().utf8))) ?? [String: Any](),
                "current_run": ["crumbs": crumbs],
                "metrickit": Array(diagnostics.suffix(diagnosticCap)).map { trimFrames($0, cap: frameCap) },
            ]
            if !freezeStalls.isEmpty {
                let freeze: [String: Any] = [
                    // The stall's own record (taken in the run that froze): this run's image table may not be read yet when
                    // the upload thread builds the report at process start.
                    "exe": (freezeStalls.last?["exe"] as? String) ?? MainThreadSampler.executableName,
                    "exe_uuid": (freezeStalls.last?["exe_uuid"] as? String) ?? MainThreadSampler.executableUUID,
                    "build": NoopDiagStore.appBuild, "version": NoopDiagStore.appVersion,
                    "format": "Image+0xoffset from the image's load address; frame 0 is the pc, the others return addresses (subtract 1)",
                    "stalls": freezeStalls.suffix(freezeStallCap).map { thinCaptures($0, thin: freezeThin) },
                ]
                report["freeze_stacks"] = freeze
            }
            if var previous {
                previous["crumbs"] = previousCrumbs
                report["unclean_previous_run"] = previous
            }
            if let latestMetrics { report["metrickit_latest_day"] = latestMetrics }
            return report
        }

        var data = (try? JSONSerialization.data(withJSONObject: object(), options: [.sortedKeys])) ?? Data("{}".utf8)
        // Cut the least useful parts first: this run's older crumbs, then the previous run's older ones, then stack depth,
        // then the oldest diagnostics.
        while data.count > maxBytes {
            if crumbs.count > 40 {
                crumbs.removeFirst(crumbs.count / 4)
            } else if previousCrumbs.count > 60 {
                previousCrumbs.removeFirst(previousCrumbs.count / 4)
            } else if frameCap > 15 {
                frameCap -= 15
            } else if diagnosticCap > 1 {
                diagnosticCap -= 1
            } else if freezeStallCap > 1 {
                freezeStallCap -= 1
            } else if !freezeThin, !freezeStalls.isEmpty {
                freezeThin = true
            } else if !crumbs.isEmpty || !previousCrumbs.isEmpty {
                crumbs = Array(crumbs.suffix(crumbs.count / 2))
                previousCrumbs = Array(previousCrumbs.suffix(previousCrumbs.count / 2))
            } else {
                break
            }
            data = (try? JSONSerialization.data(withJSONObject: object(), options: [.sortedKeys])) ?? Data("{}".utf8)
        }
        return Built(json: data, summary: summary, stallIds: freezeStalls.compactMap { $0["id"] as? String })
    }

    /// Keeps a stall's first and last capture only (the first shows where it started, the last where it ended up).
    static func thinCaptures(_ stall: [String: Any], thin: Bool) -> [String: Any] {
        guard thin, var captures = stall["captures"] as? [[String: Any]], captures.count > 2 else { return stall }
        var copy = stall
        captures = [captures[0], captures[captures.count - 1]]
        copy["captures"] = captures
        return copy
    }

    /// "NOOP 12.0.12 (469) diagnostics: unclean exit (last: stall ongoing pf.build 9000 ms); 1 crash, 0 hangs".
    static func summaryLine(previous: [String: Any]?, diagnostics: [[String: Any]]) -> String {
        var parts: [String] = []
        if let previous {
            let crumbs = (previous["crumbs"] as? [[String: Any]]) ?? []
            if let last = crumbs.last, let event = last["e"] as? String {
                let ms = (last["ms"] as? Double).map { " \(Int($0)) ms" } ?? ""
                parts.append("unclean exit of build \(previous["build"] as? String ?? "?") (last: \(event)\(ms))")
            } else {
                parts.append("unclean exit of build \(previous["build"] as? String ?? "?")")
            }
        }
        let kinds = diagnostics.compactMap { $0["kind"] as? String }
        let counts = ["crash", "hang", "cpu", "disk", "launch"].compactMap { kind -> String? in
            let n = kinds.filter { $0 == kind }.count
            return n > 0 ? "\(n) \(kind)" : nil
        }
        if !counts.isEmpty { parts.append(counts.joined(separator: ", ")) }
        if parts.isEmpty { parts.append("no crash or hang recorded") }
        let line = "NOOP \(NoopDiagStore.appVersion) (\(NoopDiagStore.appBuild)) diagnostics: " + parts.joined(separator: "; ")
        return String(line.prefix(summaryMaxChars))
    }

    // MARK: MetricKit

    /// One entry per diagnostic in a payload: its kind, its metadata (exception type and code, signal, termination
    /// reason, hang duration, ...) and the attributed thread's frames.
    static func compactDiagnostic(_ payload: [String: Any], file: String) -> [String: Any] {
        var entries: [[String: Any]] = []
        let kinds: [(key: String, kind: String)] = [
            ("crashDiagnostics", "crash"), ("hangDiagnostics", "hang"), ("cpuExceptionDiagnostics", "cpu"),
            ("diskWriteExceptionDiagnostics", "disk"), ("appLaunchDiagnostics", "launch"),
        ]
        for (key, kind) in kinds {
            for diagnostic in (payload[key] as? [[String: Any]]) ?? [] {
                var entry: [String: Any] = ["kind": kind]
                if let meta = diagnostic["diagnosticMetaData"] as? [String: Any] { entry["meta"] = meta }
                if let tree = diagnostic["callStackTree"] as? [String: Any] { entry["frames"] = frames(tree) }
                entries.append(entry)
            }
        }
        let begin: Any = payload["timeStampBegin"] ?? ""
        let end: Any = payload["timeStampEnd"] ?? ""
        let kind: Any = entries.first?["kind"] ?? "none"
        return ["file": file, "begin": begin, "end": end, "kind": kind, "diagnostics": entries]
    }

    /// The attributed thread's stack (the crashed one, or the main thread of a hang), first frame first, each as
    /// "binary+offset". Falls back to the first stack when none is attributed.
    static func frames(_ tree: [String: Any]) -> [String] {
        let stacks = (tree["callStacks"] as? [[String: Any]]) ?? []
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var out: [String] = []
        var frame = ((stack?["callStackRootFrames"] as? [[String: Any]]) ?? []).first
        while let current = frame, out.count < 120 {
            let binary = current["binaryName"] as? String ?? "?"
            let offset = (current["offsetIntoBinaryTextSegment"] as? NSNumber)?.int64Value
            let address = (current["address"] as? NSNumber)?.int64Value
            out.append("\(binary)+\(offset.map(String.init) ?? "?") @\(address.map { String($0, radix: 16) } ?? "?")")
            frame = ((current["subFrames"] as? [[String: Any]]) ?? []).first
        }
        return out
    }

    static func trimFrames(_ entry: [String: Any], cap: Int) -> [String: Any] {
        var copy = entry
        copy["diagnostics"] = ((entry["diagnostics"] as? [[String: Any]]) ?? []).map { diagnostic -> [String: Any] in
            var d = diagnostic
            if let frames = d["frames"] as? [String] { d["frames"] = Array(frames.prefix(cap)) }
            return d
        }
        return copy
    }

    /// The day's exit counts (watchdog, memory limit, crash), hang time and peak memory from a metric payload.
    static func compactMetrics(_ payload: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out["begin"] = payload["timeStampBegin"] ?? ""
        out["end"] = payload["timeStampEnd"] ?? ""
        for key in ["applicationExitMetrics", "applicationResponsivenessMetrics", "memoryMetrics", "cpuMetrics",
                    "applicationLaunchMetrics"] {
            if let value = payload[key] { out[key] = value }
        }
        return out
    }

    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        let machine = Mirror(reflecting: info.machine).children.compactMap { $0.value as? Int8 }
        return String(decoding: machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

// MARK: - Upload

enum NoopDiagUpload {
    /// Two minutes between automatic attempts when only an unclean exit, a stall flag or a MetricKit diagnostic is owed.
    /// Freeze stacks waiting for delivery skip the spacing: they are the evidence that is hardest to get again.
    static let retryInterval: TimeInterval = 2 * 60
    /// Seconds after process start of each pass of the background upload: now, then again after a failure (or news) at +20 s
    /// and +60 s.
    static let passOffsets: [TimeInterval] = [0, 20, 60]
    private static let lastAutoAttemptKey = "noop.diag.lastAutoUpload"
    private static let requestTimeout: TimeInterval = 15

    struct Outcome {
        let status: Int?
        let message: String
        var isDelivered: Bool { (200..<300).contains(status ?? 0) }
    }

    // MARK: Automatic, off the main thread

    /// First line of the app's init. A plain utility thread, never the main actor, a Task, the main queue or a Timer: a main
    /// thread that is frozen cannot delay it. It reads only files (Application Support/Diagnostics), UserDefaults and the
    /// keychain, and posts with its own ephemeral URLSession.
    static func startInBackground() {
        let thread = Thread { runPasses() }
        thread.name = "app.noop.diag.upload"
        thread.qualityOfService = .utility
        thread.stackSize = 1 << 20
        thread.start()
    }

    private static func runPasses() {
        let store = NoopDiagStore.shared
        // The previous run's marker and the saved freeze stacks, read here instead of waiting for the main thread to get to
        // `NoopDiag.start()`; both are idempotent, so the main thread's own call is then a no-op.
        store.detectPreviousRun()
        FreezeStacks.load()
        var delivered = Set<String>()
        var elapsed: TimeInterval = 0
        for (index, offset) in passOffsets.enumerated() {
            if offset > elapsed {
                Thread.sleep(forTimeInterval: offset - elapsed)
                elapsed = offset
            }
            let freeze = FreezeStacks.snapshot().filter { !delivered.contains($0["id"] as? String ?? "") }
            var owed = store.pending()
            if !freeze.isEmpty { owed.insert("freeze_stacks") }
            guard !owed.isEmpty, let endpoint = SelfHostedPushClient.paceForgeEndpoint() else { continue }
            let now = Date().timeIntervalSince1970
            if index == 0, freeze.isEmpty,
               now - UserDefaults.standard.double(forKey: lastAutoAttemptKey) < retryInterval { continue }
            UserDefaults.standard.set(now, forKey: lastAutoAttemptKey)
            _ = sendBlocking(trigger: owed.sorted().joined(separator: "+"), endpoint: endpoint,
                             pass: index + 1, delivered: &delivered)
        }
    }

    /// Builds the report, keeps it on the phone (last-report.json, before the post, so Settings shows it whatever happens
    /// next) and posts it from the calling thread. Nothing here touches the main actor.
    private static func sendBlocking(trigger: String, endpoint: (url: URL, token: String), pass: Int,
                                     delivered: inout Set<String>) -> Outcome {
        let cutoff = NoopDiagStore.now()
        let built = NoopDiagReport.build(trigger: trigger, skippingStalls: delivered)
        NoopDiagStore.shared.saveReport(built.json)
        NoopDiag.crumb("diag upload attempt", ["pass": Double(pass), "bytes": Double(built.json.count),
                                               "stalls": Double(built.stallIds.count)])
        guard let report = try? JSONSerialization.jsonObject(with: built.json),
              let body = try? JSONSerialization.data(withJSONObject: ["kind": "diagnostics", "type": "field_test",
                                                                      "text": built.summary, "report": report] as [String: Any])
        else { return Outcome(status: nil, message: "The report could not be built.") }
        let outcome = post(body, to: SelfHostedPushClient.paceForgeURL(from: endpoint.url, path: "api/app/log"),
                           token: endpoint.token)
        NoopDiagStore.shared.recordUpload(status: outcome.status, message: outcome.message, trigger: trigger)
        NoopDiag.crumb("diag upload result", ["pass": Double(pass), "status": Double(outcome.status ?? -1),
                                              "bytes": Double(built.json.count)])
        if outcome.isDelivered {
            NoopDiagStore.shared.clearPending()
            FreezeStacks.clear(before: cutoff)
            delivered.formUnion(built.stallIds)
        }
        return outcome
    }

    /// A bearer POST on a private ephemeral session that follows no redirect, answered on the calling (non-cooperative) thread.
    private static func post(_ body: Data, to url: URL, token: String) -> Outcome {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        let session = URLSession(configuration: configuration, delegate: DiagNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let done = DispatchSemaphore(value: 0)
        let answer = OutcomeBox()
        session.dataTask(with: request) { data, response, error in
            if let http = response as? HTTPURLResponse {
                let data = data ?? Data()
                // Without a valid token the server answers 200 with its HTML login page: not a delivery.
                if http.statusCode == 200, data.first(where: { ![0x20, 0x0A, 0x0D, 0x09].contains($0) }) == UInt8(ascii: "<") {
                    answer.outcome = Outcome(status: nil, message: "PaceForge answered with its login page: token not accepted.")
                } else {
                    let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
                    answer.outcome = Outcome(status: http.statusCode, message: message ?? "HTTP \(http.statusCode)")
                }
            } else {
                answer.outcome = Outcome(status: nil,
                                         message: "Could not reach PaceForge: \(error?.localizedDescription ?? "no answer")")
            }
            done.signal()
        }.resume()
        done.wait()
        return answer.outcome
    }

    /// The answer, handed from the URLSession callback to the waiting thread (the semaphore orders the two).
    private final class OutcomeBox: @unchecked Sendable {
        var outcome = Outcome(status: nil, message: "No answer.")
    }

    // MARK: Manual

    /// Builds the report, keeps it on the phone and posts it. Settings > Tools > Send diagnostics now calls this directly.
    @discardableResult
    static func send(trigger: String) async -> Outcome {
        let cutoff = NoopDiagStore.now()
        let built = NoopDiagReport.build(trigger: trigger)
        NoopDiagStore.shared.saveReport(built.json)
        guard SelfHostedPushClient.paceForgeIsConfigured else {
            let outcome = Outcome(status: nil, message: "PaceForge sync is not set up, so the report stays on this iPhone.")
            NoopDiagStore.shared.recordUpload(status: nil, message: outcome.message, trigger: trigger)
            return outcome
        }
        guard let report = try? JSONSerialization.jsonObject(with: built.json) else {
            return Outcome(status: nil, message: "The report could not be built.")
        }
        let body: [String: Any] = ["kind": "diagnostics", "type": "field_test", "text": built.summary, "report": report]
        let outcome: Outcome
        do {
            let answer = try await SelfHostedPushClient.paceForgePostReturningStatus("api/app/log", body: body)
            let message = ((try? JSONSerialization.jsonObject(with: answer.data)) as? [String: Any])?["message"] as? String
            outcome = Outcome(status: answer.status, message: message ?? "HTTP \(answer.status)")
        } catch {
            outcome = Outcome(status: nil, message: "Could not reach PaceForge: \(error.localizedDescription)")
        }
        NoopDiagStore.shared.recordUpload(status: outcome.status, message: outcome.message, trigger: trigger)
        NoopDiag.crumb("diagnostics sent", ["status": Double(outcome.status ?? -1), "bytes": Double(built.json.count)])
        if outcome.isDelivered {
            NoopDiagStore.shared.clearPending()
            FreezeStacks.clear(before: cutoff)
        }
        return outcome
    }
}

/// Refuses every redirect, so the bearer never follows one to another host.
private final class DiagNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
