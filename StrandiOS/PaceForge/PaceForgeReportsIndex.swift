import SwiftUI
import StrandDesign

// The Reports index and the week plan page. A report belongs to one scope (daily, weekly, monthly) and lives on its own page; this
// index lists the three with their latest headline, and a fourth row for the races (pack and debrief), and the week plan is a page of its own instead of the top of the Coach.

/// The index as a screen (the `noop://` and Coach links that push it); the Reports tab embeds `PFReportsIndexContent` directly.
struct PFReportsIndexScreen: View {
    var body: some View {
        ScrollView {
            PFReportsIndexContent()
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The four kinds, Day, Week, Month and Race, each a row that opens its page.
struct PFReportsIndexContent: View {
    @ObservedObject private var store = PFReportsStore.shared
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PFReportIndexKind.allCases) { kind in
                if let report = kind.reportKind { row(kind, report) } else { raceRow(kind) }
            }
            Text("The weekly report is written on Sunday evening and the monthly one at the start of each month. Earlier reports are listed by date inside each one. Race lists the races that have a race pack or a debrief.")
                .font(LookFont.text(12.5))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .containerIdentifier("pf-reports-index")
        .task { await store.loadIndex() }
    }

    private func row(_ kind: PFReportIndexKind, _ report: PFReportKind) -> some View {
        let latest = store.rows[report]?.first
        let line = latest?.headline.map { hiding.text($0) } ?? (latest == nil ? report.whenWritten : "Open the latest \(report.title.lowercased()) report.")
        return NavigationLink(value: TabRoute.reports(report.rawValue)) {
            card(kind.title, trailing: latest?.label ?? "", line: line)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-reports-index-\(report.rawValue)")
    }

    private func raceRow(_ kind: PFReportIndexKind) -> some View {
        NavigationLink(value: TabRoute.reports("race")) {
            card(kind.title, trailing: "", line: "The races with a race pack or a debrief, newest first.")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-reports-index-race")
    }

    private func card(_ title: String, trailing: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(LookFont.text(17, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                Text(trailing)
                    .font(LookFont.text(12))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            Text(line)
                .font(LookFont.text(14))
                .foregroundStyle(NoopLook.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .contentShape(Rectangle())
    }
}

/// The week plan on a page of its own. "Ask the coach about this" puts the question in the Coach's chat box and goes back to it.
struct PFWeekPlanScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PFWeekPlanCard(onAsk: ask)
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("pf-week-plan-screen")
        .task { await PFWeekPlanStore.shared.refreshIfStale() }
    }

    private func ask(_ prompt: String) {
        PFChatPrefill.shared.text = prompt
        dismiss()
    }
}
