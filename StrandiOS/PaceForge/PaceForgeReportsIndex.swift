import SwiftUI
import StrandDesign

// The Reports index and the week plan page. A report belongs to one scope (daily, weekly, monthly) and lives on its own page; this
// index only lists the three with their latest headline, and the week plan is a page of its own instead of the top of the Coach.

struct PFReportsIndexScreen: View {
    @ObservedObject private var store = PFReportsStore.shared
    private let hiding = PFHiding()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PFReportKind.allCases) { kind in
                    row(kind)
                }
                Text("The weekly report is written on Sunday evening and the monthly one at the start of each month. Earlier reports are listed by date inside each one.")
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("pf-reports-index")
        .task { await store.loadIndex() }
    }

    private func row(_ kind: PFReportKind) -> some View {
        let latest = store.rows[kind]?.first
        let line = latest?.headline.map { hiding.text($0) } ?? (latest == nil ? kind.whenWritten : "Open the latest \(kind.title.lowercased()) report.")
        return NavigationLink(value: TabRoute.reports(kind.rawValue)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.title)
                        .font(LookFont.text(17, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Spacer(minLength: 8)
                    Text(latest?.label ?? "")
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-reports-index-\(kind.rawValue)")
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
