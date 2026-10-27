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
    /// The weekly stage the tables belong under ("The week, session by session").
    private static let detailStageID = "detail"

    private var hasDetailStage: Bool { report.stages.contains { $0.id == Self.detailStageID } }

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
                if lead.id == Self.detailStageID, report.hasWeekNumbers { PFReportWeekNumbers(report: report) }
            }
            ForEach(report.otherStages) { stage in
                PFReportStageCard(stage: stage, prominent: false)
                if stage.id == Self.detailStageID, report.hasWeekNumbers { PFReportWeekNumbers(report: report) }
            }
            if !hasDetailStage, report.hasWeekNumbers { PFReportWeekNumbers(report: report) }
            if !report.proposals.isEmpty { proposals }
            if !report.experts.isEmpty { experts }
            if !report.sources.isEmpty { PFReportSureFold(sources: report.sources) }
            if !report.glossary.isEmpty { PFReportGlossaryFold(entries: report.glossary) }
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

/// A stage's paragraphs: bold labels drawn bold, claim tags as small source chips under the paragraph they belong to.
struct PFReportBlocks: View {
    let text: String
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PFReportText.blocks(text)) { block in
                PFReportBlockRow(block: block, size: size)
            }
        }
    }
}

/// One paragraph. Its claim tags show as chips in words (Confirmed, Partly supported, Our estimate); a tap on a chip opens the
/// "how sure are we" line for it, a second tap closes it.
private struct PFReportBlockRow: View {
    let block: PFReportBlock
    let size: CGFloat
    private let hiding = PFHiding()
    @State private var shown: PFSureLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.attributed(hiding.text(block.text)))
                .font(LookFont.text(size, weight: block.isHeading ? .semibold : .medium))
                .foregroundStyle(block.isHeading ? NoopLook.textPrimary : NoopLook.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !levels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(levels, id: \.words) { level in
                        Button { shown = (shown == level) ? nil : level } label: {
                            PFChip(text: level.words, color: level.color)
                                .frame(minHeight: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(level.words)
                    }
                }
            }
            if let level = shown {
                Text(level.explain)
                    .font(LookFont.text(11.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-reports-sure-explain")
            }
        }
    }

    /// The paragraph's levels, each once, in the order its tags came.
    private var levels: [PFSureLevel] {
        var out: [PFSureLevel] = []
        for tag in block.tags {
            let level = PFReportText.sureLevel(ofTag: tag)
            if !out.contains(level) { out.append(level) }
        }
        return out
    }

    private static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private extension PFSureLevel {
    var color: Color {
        switch self {
        case .confirmed: return PFColor.positive
        case .partial: return PFColor.warning
        case .estimate: return PFColor.critical
        }
    }
}

/// A folded card in the History style: a caps title that opens a list.
private struct PFReportFold<Content: View>: View {
    let title: String
    let identifier: String
    let content: () -> Content

    init(_ title: String, identifier: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        DisclosureGroup {
            content()
                .padding(.top, 6)
        } label: {
            Text(title)
                .lookCaps(12.5)
                .foregroundStyle(NoopLook.textPrimary)
        }
        .tint(StrandPalette.accent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier(identifier)
    }
}

/// The terms the report used, each with its one-line explanation.
private struct PFReportGlossaryFold: View {
    let entries: [PFReportGlossaryEntry]
    private let hiding = PFHiding()

    var body: some View {
        PFReportFold("Glossary (\(entries.count))", identifier: "pf-reports-glossary") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.term)
                            .font(LookFont.text(14, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                        Text(hiding.text(entry.text))
                            .font(LookFont.text(13.5, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "How sure are we?": the sources the report cites, each with its level and the claim it backs.
private struct PFReportSureFold: View {
    let sources: [PFReportSource]
    private let hiding = PFHiding()

    private static let title = "How sure are we?"
    private static let intro = "Confirmed: the research behind it was opened and supports it. Partly supported: it supports part of it. Our estimate: not proven, our best reading."

    var body: some View {
        PFReportFold(Self.title, identifier: "pf-reports-sure") {
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.intro)
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    VStack(alignment: .leading, spacing: 3) {
                        PFChip(text: source.level.words, color: source.level.color)
                        if let claim = source.claim {
                            Text(hiding.text(claim))
                                .font(LookFont.text(13.5, weight: .medium))
                                .foregroundStyle(NoopLook.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The week in numbers: every session, the days with their nights, the totals, hard against easy. Drawn from the server's own
/// figures (`sessions`, `week_table`, `week_totals`), so a line here and the text above it come from the same numbers.
private struct PFReportWeekNumbers: View {
    let report: PFReport
    private let hiding = PFHiding()

    private static let title = "The week in numbers"
    private static let sessionsTitle = "Sessions"
    private static let daysTitle = "Days and nights"
    private static let totalsTitle = "Totals"
    private static let hardLabel = "hard"

    var body: some View {
        PFCard(Self.title, icon: "tablecells") {
            VStack(alignment: .leading, spacing: 14) {
                if !report.sessions.isEmpty { sessions }
                if !report.days.isEmpty { days }
                if let totals = report.totals { totalsBlock(totals) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerIdentifier("pf-reports-week-numbers")
    }

    private func heading(_ text: String) -> some View {
        Text(text).strandOverline()
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(Self.sessionsTitle)
            ForEach(report.sessions) { session in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(session.weekday)
                        .font(LookFont.text(13, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hiding.text(session.name))
                            .font(LookFont.text(14.5, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(hiding.text(PFReportWeekText.sessionLine(session)))
                            .font(LookFont.text(12.5, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    if session.isHard {
                        PFChip(text: Self.hardLabel, color: PFColor.warning)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(Self.daysTitle)
            ForEach(report.days) { day in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(day.weekday)
                        .font(LookFont.text(13, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hiding.text(PFReportWeekText.dayLine(day)))
                            .font(LookFont.text(14, weight: .medium))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let night = PFReportWeekText.nightLine(day) {
                            Text(hiding.text(night))
                                .font(LookFont.text(12.5, weight: .medium))
                                .foregroundStyle(NoopLook.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func totalsBlock(_ totals: PFReportWeekTotals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading(Self.totalsTitle)
            if let line = PFReportWeekText.totalLine(totals) { totalsText(line, strong: true) }
            ForEach(totals.byType, id: \.label) { total in
                totalsText(PFReportWeekText.typeLine(total), strong: false)
            }
            if let line = PFReportWeekText.hardEasyLine(totals) { totalsText(line, strong: false) }
            if let line = PFReportWeekText.changeLine(totals) { totalsText(line, strong: false) }
        }
    }

    private func totalsText(_ text: String, strong: Bool) -> some View {
        Text(hiding.text(text))
            .font(LookFont.text(strong ? 14.5 : 13.5, weight: strong ? .semibold : .medium))
            .foregroundStyle(strong ? NoopLook.textPrimary : NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
