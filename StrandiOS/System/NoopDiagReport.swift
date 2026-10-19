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
// crash report shows and shares it) and tries again at most every six hours.

enum NoopDiagReport {
    static let maxBytes = 64 * 1024
    static let summaryMaxChars = 200

    struct Built {
        let json: Data
        let summary: String
    }

    /// The report as JSON, cut to `maxBytes`.
    static func build(trigger: String) -> Built {
        let store = NoopDiagStore.shared
        let previous = store.previousRun()
        let diagnostics = store.metricKitPayloads(diagnostic: true).map { compactDiagnostic($0.json, file: $0.file) }
        let latestMetrics = store.metricKitPayloads(diagnostic: false).last.map { compactMetrics($0.json) }
        var crumbs = store.currentCrumbs()
        var previousCrumbs = (previous?["crumbs"] as? [[String: Any]]) ?? []
        var frameCap = 60
        var diagnosticCap = diagnostics.count
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
                "peak_mb": NoopDiagSampler.shared.peakMB,
                "stats": (try? JSONSerialization.jsonObject(with: Data(NoopPerfStats.shared.summaryJSON().utf8))) ?? [String: Any](),
                "current_run": ["crumbs": crumbs],
                "metrickit": Array(diagnostics.suffix(diagnosticCap)).map { trimFrames($0, cap: frameCap) },
            ]
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
            } else if !crumbs.isEmpty || !previousCrumbs.isEmpty {
                crumbs = Array(crumbs.suffix(crumbs.count / 2))
                previousCrumbs = Array(previousCrumbs.suffix(previousCrumbs.count / 2))
            } else {
                break
            }
            data = (try? JSONSerialization.data(withJSONObject: object(), options: [.sortedKeys])) ?? Data("{}".utf8)
        }
        return Built(json: data, summary: summary)
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
    /// Six hours between automatic attempts, so a server that refuses the report does not spend the app-log allowance.
    static let retryInterval: TimeInterval = 6 * 3600
    private static let lastAutoAttemptKey = "noop.diag.lastAutoUpload"

    struct Outcome {
        let status: Int?
        let message: String
        var isDelivered: Bool { (200..<300).contains(status ?? 0) }
    }

    /// At launch: when the previous run did not finish or MetricKit delivered a diagnostic, and none was sent in the last
    /// six hours, send the report once.
    static func sendIfOwed() async {
        let pending = NoopDiagStore.shared.pending()
        guard !pending.isEmpty, SelfHostedPushClient.paceForgeIsConfigured else { return }
        let last = UserDefaults.standard.double(forKey: lastAutoAttemptKey)
        guard Date().timeIntervalSince1970 - last >= retryInterval else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAutoAttemptKey)
        _ = await send(trigger: pending.sorted().joined(separator: "+"))
    }

    /// Builds the report, keeps it on the phone and posts it. Settings > Tools > Send diagnostics now calls this directly.
    @discardableResult
    static func send(trigger: String) async -> Outcome {
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
        if outcome.isDelivered { NoopDiagStore.shared.clearPending() }
        return outcome
    }
}
#endif
