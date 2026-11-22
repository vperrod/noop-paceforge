import SwiftUI
import Charts
import StrandDesign

// A chart the Coach asked to show with one of its replies (`query_chart` on the turn). The rows come from the `query-chart` job, run when the
// athlete taps "Show the chart" (30 an hour, so not for every turn the transcript scrolls past). Every point is a stored reading from one
// source; a day with no reading is a gap in the line and is listed, never filled in. A split by a journal question colours the days by the
// answer about the day before and names the two groups with their counts; it describes two groups of days and is not a finding. The Coach
// thread about the chart is the scoped conversation `chart:<id>` (`POST api/app/chat` with `session_id`).

@MainActor struct PFCoachChartCard: View {
    let chart: PFChartRef

    @ObservedObject private var model = PFUnified.model
    @StateObject private var tracker = PFJobTracker()
    @State private var result: PFChartResult?
    @State private var message: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var status: String?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    /// The turns of the Coach thread about this chart.
    private var thread: [PFChatTurn] {
        (model.snapshot?.coach.workoutChat ?? []).filter { $0.sessionID == chart.scope }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            if let result {
                chartView(result)
                details(result)
                conversation
            } else {
                Button {
                    Task { await load() }
                } label: {
                    if isBusy { ProgressView() } else { Label("Show the chart", systemImage: "chart.xyaxis.line") }
                }
                .buttonStyle(NoopButtonStyle(.secondary))
                .disabled(isBusy)
                .accessibilityIdentifier("pf-chart-show")
            }
            if let message {
                Text(message).font(StrandFont.caption).foregroundStyle(PFColor.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
        .containerIdentifier("pf-chart-\(chart.id)")
    }

    private var title: String {
        let name = result?.metric.label ?? PFChartMetric.title(for: chart.spec.metric)
        return "\(name), last \(chart.spec.days) days"
    }

    // MARK: Chart

    private func color(_ group: String?) -> Color {
        switch group {
        case "yes": return StrandPalette.accent
        case "no": return PFColor.violet
        default: return StrandPalette.textTertiary
        }
    }

    @ViewBuilder private func chartView(_ result: PFChartResult) -> some View {
        let points = result.points
        if points.isEmpty {
            Text("No readings in this window.").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
        } else {
            Chart {
                ForEach(result.missingDays, id: \.self) { day in
                    RuleMark(x: .value("No reading", PFFormat.date(day)))
                        .foregroundStyle(StrandPalette.textTertiary.opacity(0.25))
                }
                ForEach(points) { point in
                    LineMark(x: .value("Day", PFFormat.date(point.date)), y: .value(result.metric.label, point.value),
                             series: .value("Stretch", point.segment))
                        .foregroundStyle(StrandPalette.textTertiary)
                    PointMark(x: .value("Day", PFFormat.date(point.date)), y: .value(result.metric.label, point.value))
                        .foregroundStyle(color(point.group))
                        .symbolSize(30)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            .accessibilityLabel("\(result.metric.label), \(result.n) of \(result.windowDays) days have a reading")
            .accessibilityIdentifier("pf-chart-plot")
        }
    }

    @ViewBuilder private func details(_ result: PFChartResult) -> some View {
        Text(result.coverageLine).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        if let missing = result.missingLine {
            Text(missing).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        if result.split != nil {
            HStack(spacing: 14) {
                legend("Yes days", color("yes"))
                legend("No days", color("no"))
                legend("No answer", color(nil))
            }
            if let yes = result.groupLine("yes") { Text(yes).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            if let no = result.groupLine("no") { Text(no).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
            if let line = result.splitLine {
                Text(line).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if let note = result.note {
            Text(note).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func legend(_ text: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(text).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    // MARK: The Coach about this chart

    @ViewBuilder private var conversation: some View {
        ForEach(thread) { turn in PFChatBubble(turn: turn) }
        TextField("Ask the Coach about this chart", text: $draft, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("pf-chart-ask-input")
        Button {
            Task { await ask() }
        } label: {
            if sending { ProgressView() } else { Label("Ask about this chart", systemImage: "bubble.left.and.bubble.right") }
        }
        .buttonStyle(NoopButtonStyle(.secondary))
        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("pf-chart-ask")
        if let status {
            Text(status).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Work

    @MainActor private func load() async {
        guard let inputs = chart.spec.inputs else {
            message = "This chart asks for something the app cannot read."
            return
        }
        message = nil
        switch await tracker.run(.queryChart, inputs: inputs) {
        case .failure(let failure):
            message = failure.message
        case .success(let reply):
            if let parsed = PFChartResult.parse(reply) {
                result = parsed
            } else {
                message = PFJobError.unreadable.message
            }
        }
    }

    @MainActor private func ask() async {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !sending else { return }
        let before = thread.filter { $0.role == "coach" }.count
        sending = true
        status = nil
        defer { sending = false }
        do {
            let reply = try await PFAPI.postCoachMessage(typed, sessionID: chart.scope)
            guard (200..<300).contains(reply.status) else {
                status = PFJ(data: reply.data)["message"].text ?? "The Coach did not take that. Your question is kept."
                return
            }
            draft = ""
            status = "Sent. The Coach is reading the chart."
            for _ in 0..<20 {
                await model.refresh()
                if thread.filter({ $0.role == "coach" }).count > before {
                    status = nil
                    return
                }
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
            status = "Still working. Pull to refresh later to see the reply."
        } catch {
            status = "Could not send that. \(PFAPI.failureDetail(error))"
        }
    }
}
