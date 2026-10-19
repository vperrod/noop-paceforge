#if os(iOS)
import SwiftUI
import StrandDesign

/// Settings > Tools > Last crash report: whether the previous run ended without going to the background first (a crash,
/// a watchdog or memory kill, a force quit of a frozen app) and its last breadcrumbs, the crash and hang reports iOS
/// delivered, the last upload and the report itself to send or share. Nothing here is health data.
struct NoopDiagnosticsView: View {
    @State private var previous: [String: Any]?
    @State private var diagnostics: [[String: Any]] = []
    @State private var lastUpload: [String: Any]?
    @State private var reportText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Previous run") { previousRun }
                section("Crash and hang reports from iOS") { metricKit }
                section("Last upload") { upload }
                VStack(alignment: .leading, spacing: 10) {
                    NoopDiagSendButton { refresh() }
                    if !reportText.isEmpty {
                        ShareLink(item: reportText, subject: Text("NOOP diagnostics"),
                                  message: Text("NOOP \(NoopDiagStore.appVersion) (\(NoopDiagStore.appBuild)) diagnostics")) {
                            Label("Share the report", systemImage: "square.and.arrow.up")
                                .font(StrandFont.body)
                        }
                        .accessibilityIdentifier("diag-share")
                        Text("\(reportText.utf8.count / 1024) KB. Labels, timings and memory figures only: no health data, no token.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Last crash report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    private func refresh() {
        previous = NoopDiagStore.shared.previousRun()
        diagnostics = NoopDiagStore.shared.metricKitPayloads(diagnostic: true)
            .map { NoopDiagReport.compactDiagnostic($0.json, file: $0.file) }
        lastUpload = NoopDiagStore.shared.lastUpload()
        let built = NoopDiagReport.build(trigger: "view")
        reportText = String(decoding: built.json, as: UTF8.self)
    }

    @ViewBuilder private var previousRun: some View {
        if let previous {
            let crumbs = (previous["crumbs"] as? [[String: Any]]) ?? []
            VStack(alignment: .leading, spacing: 6) {
                Text("Build \(previous["build"] as? String ?? "?") ended while on screen, started \(Self.time(previous["started_at"])). Found at the next launch, \(Self.time(previous["detected_at"])).")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(crumbs.suffix(30).enumerated()), id: \.offset) { _, crumb in
                    Text(Self.line(crumb))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .accessibilityIdentifier("diag-last-run")
        } else {
            Text("Every recorded run went to the background before it ended.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityIdentifier("diag-last-run")
        }
    }

    @ViewBuilder private var metricKit: some View {
        if diagnostics.isEmpty {
            Text("None yet. iOS delivers a crash or hang report the day after it happens, at most once a day.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        } else {
            ForEach(Array(diagnostics.reversed().enumerated()), id: \.offset) { _, payload in
                ForEach(Array(((payload["diagnostics"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(d["kind"] as? String ?? "?") \u{00B7} \(payload["end"] as? String ?? "")")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        if let meta = d["meta"] as? [String: Any] {
                            Text(Self.meta(meta))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        ForEach(Array(((d["frames"] as? [String]) ?? []).prefix(8).enumerated()), id: \.offset) { _, frame in
                            Text(frame)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var upload: some View {
        if let lastUpload {
            let status = lastUpload["status"] as? Int ?? -1
            Text("\(Self.time(lastUpload["at"])): \(status > 0 ? "HTTP \(status)" : "not sent"). \(lastUpload["message"] as? String ?? "")")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("diag-status")
        } else {
            Text("Nothing sent yet.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityIdentifier("diag-status")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).strandOverline()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM HH:mm:ss"
        return f
    }()

    static func time(_ value: Any?) -> String {
        guard let seconds = value as? Double else { return "?" }
        return clock.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func line(_ crumb: [String: Any]) -> String {
        let at = (crumb["t"] as? Double).map { clock.string(from: Date(timeIntervalSince1970: $0)) } ?? "?"
        let numbers = crumb.keys.filter { $0 != "t" && $0 != "e" }.sorted()
            .compactMap { key -> String? in (crumb[key] as? Double).map { "\(key)=\($0)" } }
        return "\(at) \(crumb["e"] as? String ?? "?") \(numbers.joined(separator: " "))"
    }

    static func meta(_ meta: [String: Any]) -> String {
        ["exceptionType", "exceptionCode", "signal", "terminationReason", "hangDuration", "appBuildVersion", "osVersion"]
            .compactMap { key in meta[key].map { "\(key): \($0)" } }
            .joined(separator: "\n")
    }
}

/// "Send diagnostics now": builds the report, keeps it and posts it to PaceForge, then says what the server answered.
struct NoopDiagSendButton: View {
    var onDone: () -> Void = {}
    @State private var isSending = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isSending = true
                Task {
                    let outcome = await NoopDiagUpload.send(trigger: "manual")
                    result = outcome.isDelivered ? "Sent. PaceForge has it." : "Not delivered: \(outcome.message)"
                    isSending = false
                    onDone()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Send diagnostics now")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    if isSending { ProgressView() }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityIdentifier("diag-send-now")
            if let result {
                Text(result)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("diag-send-result")
            }
        }
    }
}
#endif

#if DEBUG
#if os(iOS)
/// `-NoopPerf` only: one invisible element whose value is `NoopPerfStats.summaryJSON()`, refreshed every second, so a UI
/// test can read the per-screen stalls, CPU time, section times and peak footprint the app measured on itself.
struct NoopPerfProbe: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("noop-perf-summary")
                .accessibilityValue(NoopPerfStats.shared.summaryJSON())
        }
        .allowsHitTesting(false)
    }
}
#endif
#endif
