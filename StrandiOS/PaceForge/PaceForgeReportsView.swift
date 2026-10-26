import SwiftUI
import StrandDesign

// The Reports screen (Daily | Weekly | Monthly, latest first, a dated history). It draws what
// PaceForge wrote: text checked on the server, laid out here. Fixed words are plain strings, like the rest of the PaceForge screens.

// MARK: - Reports screen

struct PFReportsScreen: View {
    @ObservedObject private var store = PFReportsStore.shared
    @State private var kind: PFReportKind
    @State private var selectedKey: String?
    private let hiding = PFHiding()

    private static let screenTitle = "Reports"

    init(kind: PFReportKind = .daily) {
        _kind = State(initialValue: kind)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LookSegmented(options: PFReportKind.allCases, selection: kindBinding, identifier: "pf-reports-kind",
                              title: { $0.title })
                    .frame(height: 44)
                stateContent
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .lookScreenBackground()
        .navigationTitle(Self.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("pf-reports")
        .task { await store.loadIndex() }
    }

    private var kindBinding: Binding<PFReportKind> {
        Binding(get: { kind }, set: { kind = $0; selectedKey = nil })
    }

    @ViewBuilder private var stateContent: some View {
        let list = store.rows[kind] ?? []
        switch store.indexState {
        case .notSetUp:
            message("PaceForge is not set up on this phone. Add it under Data, PaceForge sync, and the reports show here.")
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                message("The reports could not be loaded. Check the connection and try again.")
                Button { Task { await store.loadIndex() } } label: {
                    Text(Self.retryTitle)
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pf-reports-retry")
            }
        case .notLoaded, .loading:
            message("Loading the reports.")
        case .ready:
            if let first = list.first {
                readyContent(list, first: first)
            } else {
                PFCard("No \(kind.title.lowercased()) report yet") {
                    PFParagraph(kind.whenWritten)
                }
                .containerIdentifier("pf-reports-empty")
            }
        }
    }

    private static let retryTitle = "Try again"

    private func message(_ text: String) -> some View {
        Text(text)
            .font(LookFont.text(14.5))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("pf-reports-message")
    }

    @ViewBuilder private func readyContent(_ list: [PFReportRow], first: PFReportRow) -> some View {
        let key = list.contains(where: { $0.key == selectedKey }) ? (selectedKey ?? first.key) : first.key
        historyGroup(list, current: key)
        PFReportBody(kind: kind, key: key)
    }

    private func historyTitle(_ count: Int) -> String { "History (\(count))" }

    private func historyGroup(_ list: [PFReportRow], current: String) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(list) { row in
                    Button { selectedKey = row.key } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(LookFont.text(14.5, weight: .semibold))
                                    .foregroundStyle(row.key == current ? StrandPalette.accent : NoopLook.textPrimary)
                                if let headline = row.headline {
                                    Text(hiding.text(headline))
                                        .font(LookFont.text(12.5))
                                        .foregroundStyle(NoopLook.textTertiary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 8)
                            if row.isStale {
                                Text(Self.staleWord)
                                    .font(LookFont.text(11.5, weight: .semibold))
                                    .foregroundStyle(PFColor.warning)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf-reports-row-\(row.key)")
                }
            }
            .padding(.top, 6)
        } label: {
            Text(historyTitle(list.count))
                .lookCaps(12.5)
                .foregroundStyle(NoopLook.textPrimary)
        }
        .tint(StrandPalette.accent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-reports-history")
    }

    private static let staleWord = "stale"
}

// MARK: - One report

private struct PFReportBody: View {
    let kind: PFReportKind
    let key: String
    @ObservedObject private var store = PFReportsStore.shared

    private var reportID: String { PFReportsStore.reportID(kind, key) }

    var body: some View {
        Group {
            if let report = store.reports[reportID] {
                PFReportContent(report: report)
            } else if store.failedReports.contains(reportID) {
                PFCard("Report not loaded") {
                    PFParagraph("This report could not be loaded. Check the connection and open it again.")
                }
            } else {
                Text(Self.loadingText)
                    .font(LookFont.text(14.5))
                    .foregroundStyle(NoopLook.textSecondary)
            }
        }
        .task(id: reportID) { await store.loadReport(kind, key: key) }
    }

    private static let loadingText = "Loading the report."
}

private struct PFReportContent: View {
    let report: PFReport
    private let hiding = PFHiding()

    private static let notCheckedTitle = "What was not checked"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let note = PFReportFreshness.note(report, today: PFAPI.todayISO) {
                Text(note)
                    .font(LookFont.text(13, weight: .semibold))
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-reports-note")
            }
            if let lead = report.lead {
                PFReportStageCard(stage: lead, prominent: true)
            }
            ForEach(report.otherStages) { stage in
                PFReportStageCard(stage: stage, prominent: false)
            }
            if !report.proposals.isEmpty { proposals }
            if !report.experts.isEmpty { experts }
            if !report.notChecked.isEmpty { footnote }
        }
        .containerIdentifier("pf-reports-body")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(PFReportFreshness.dateLine(report))
                .font(LookFont.text(22, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Text(PFReportText.wholeNote(report.wholeSource))
                .font(LookFont.text(12.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var proposals: some View {
        PFCard("Proposed changes", icon: "checklist") {
            VStack(alignment: .leading, spacing: 10) {
                PFParagraph("Accept or Dismiss lives in the Needs you card on Today. Nothing in your plan changes until you accept one.")
                ForEach(report.proposals) { proposal in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hiding.text(proposal.title))
                            .font(LookFont.text(15, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !proposal.detail.isEmpty {
                            Text(hiding.text(proposal.detail))
                                .font(LookFont.text(14, weight: .medium))
                                .foregroundStyle(NoopLook.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .containerIdentifier("pf-reports-proposals")
    }

    private var experts: some View {
        PFCard("Domain experts (\(report.experts.count))", icon: "person.2") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(report.experts) { expert in
                    DisclosureGroup {
                        PFReportBlocks(text: expert.text, size: 14.5)
                            .padding(.top, 6)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(expert.title)
                                .font(LookFont.text(15, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                            Text(PFReportText.sourceNote(expert.source))
                                .font(LookFont.text(11.5, weight: .medium))
                                .foregroundStyle(NoopLook.textTertiary)
                        }
                    }
                    .tint(StrandPalette.accent)
                    .containerIdentifier("pf-reports-expert-\(expert.id)")
                }
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.notCheckedTitle)
                .font(LookFont.text(11.5, weight: .semibold))
                .foregroundStyle(NoopLook.textTertiary)
            ForEach(Array(report.notChecked.enumerated()), id: \.offset) { _, line in
                Text(hiding.text(line))
                    .font(LookFont.text(11.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .containerIdentifier("pf-reports-not-checked")
    }
}

private struct PFReportStageCard: View {
    let stage: PFReportStage
    let prominent: Bool

    var body: some View {
        PFCard(stage.title) {
            VStack(alignment: .leading, spacing: 10) {
                PFReportBlocks(text: stage.text, size: prominent ? 16 : 15)
                Text(PFReportText.sourceNote(stage.source))
                    .font(LookFont.text(11.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
        }
        .overlay {
            if prominent {
                RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous)
                    .stroke(StrandPalette.accent.opacity(0.4), lineWidth: 1)
            }
        }
        .containerIdentifier("pf-reports-stage-\(stage.id)")
    }
}

/// A stage's paragraphs: bold labels drawn bold, claim tags as one small line under the paragraph they belong to.
struct PFReportBlocks: View {
    let text: String
    let size: CGFloat
    private let hiding = PFHiding()

    private static let sourcePrefix = "Source: "

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PFReportText.blocks(text)) { block in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.attributed(hiding.text(block.text)))
                        .font(LookFont.text(size, weight: block.isHeading ? .semibold : .medium))
                        .foregroundStyle(block.isHeading ? NoopLook.textPrimary : NoopLook.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !block.tags.isEmpty {
                        Text(Self.sourcePrefix + block.tags.joined(separator: "; "))
                            .font(LookFont.text(11, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
