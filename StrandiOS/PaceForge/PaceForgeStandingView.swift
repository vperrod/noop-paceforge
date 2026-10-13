import SwiftUI
import StrandDesign

// "Where you stand": the scorecard screen, its band bars, the metric and plan sheets, the test-day card and
// the compact summary cards on Insights and Today. Everything shown comes from standing.json; the app only
// reads it, and a field test is logged with the "Log a field test" button (the phrase Telegram would take).
// Wording is neutral: a band is a place on a scale, never a grade, and "Not rated" is greyed rather than flagged.

// MARK: - Colours

/// Band colours, from the same recovery-gradient tokens the other PaceForge cards use. Unrated is grey.
enum PFBandColor {
    static func color(for band: Int?) -> Color {
        switch band ?? 0 {
        case 1: return StrandPalette.recovery030
        case 2: return StrandPalette.recovery055
        case 3: return StrandPalette.recovery078
        case 4: return StrandPalette.recovery100
        case 5: return StrandPalette.restColor
        default: return StrandPalette.textTertiary
        }
    }

    /// The strip's colour for position 0...5 (poor ... elite, not rated).
    static func stripColor(at index: Int) -> Color {
        index < 5 ? color(for: index + 1) : StrandPalette.textTertiary
    }
}

// MARK: - Opening the scorecard

private struct PFOpenStandingKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Opens the "Where you stand" screen; set once by the PaceForge tab.
    var pfOpenStanding: () -> Void {
        get { self[PFOpenStandingKey.self] }
        set { self[PFOpenStandingKey.self] = newValue }
    }
}

extension Notification.Name {
    static let pfOpenStanding = Notification.Name("noop.paceforge.openStanding")
}

/// `noop://paceforge/standing`. Held as `pending` until the tab exists, so a cold launch still lands on it.
@MainActor
enum PFStandingLink {
    static var pending = false

    static func open() {
        pending = true
        NotificationCenter.default.post(name: .pfOpenStanding, object: nil)
    }

    /// True once, when a request is waiting.
    static func consume() -> Bool {
        defer { pending = false }
        return pending
    }
}

// MARK: - Band bar

/// Five segments, one per band. The metric's own band is the tall, solid one; the bands below it are filled
/// more softly and the ones above are faint. An unrated metric is five grey segments.
struct PFBandBar: View {
    let band: Int?
    var height: CGFloat = 8

    var body: some View {
        let segments = PFBand.segments(for: band)
        HStack(spacing: 3) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(fill(segment, position: index + 1))
                    .frame(height: segment == .current ? height + 4 : height)
            }
        }
        .frame(height: height + 4)
        .accessibilityHidden(true)
    }

    private func fill(_ segment: PFBand.Segment, position: Int) -> Color {
        switch segment {
        case .current: return PFBandColor.color(for: position)
        case .reached: return PFBandColor.color(for: position).opacity(0.5)
        case .ahead: return PFBandColor.color(for: position).opacity(0.16)
        case .unrated: return PFBandColor.color(for: nil).opacity(0.2)
        }
    }
}

// MARK: - Summary header

/// The counts as one segmented strip, then the three strongest and three focus metrics as chips.
struct PFStandingSummaryHeader: View {
    let standing: PFStanding
    var onSelect: ((PFStandingMetric) -> Void)? = nil

    var body: some View {
        if let summary = standing.summary, summary.total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                strip(summary)
                legend(summary)
                chips("Strongest", standing.strongestTop)
                chips("Focus", standing.focusTop)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pf-standing-summary")
        }
    }

    private func strip(_ summary: PFStandingSummary) -> some View {
        let fractions = PFBand.stripFractions(counts: summary.counts)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                    if fraction > 0 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(PFBandColor.stripColor(at: index).opacity(index == 5 ? 0.25 : 1))
                            .frame(width: max(6, geo.size.width * CGFloat(fraction)))
                    }
                }
            }
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stripAccessibility(summary))
        .accessibilityIdentifier("pf-standing-strip")
    }

    private func stripAccessibility(_ summary: PFStandingSummary) -> String {
        let names = PFBand.names + [PFBand.notRated]
        let parts = zip(names, summary.counts).filter { $0.1 > 0 }.map { "\($0.1) \($0.0.lowercased())" }
        return "Metrics by band: " + parts.joined(separator: ", ")
    }

    private func legend(_ summary: PFStandingSummary) -> some View {
        let names = PFBand.names + [PFBand.notRated]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)],
                         alignment: .leading, spacing: 6) {
            ForEach(Array(summary.counts.enumerated()), id: \.offset) { index, count in
                if count > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(PFBandColor.stripColor(at: index)).frame(width: 8, height: 8)
                        Text("\(count) \(names[index])")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func chips(_ title: String, _ metrics: [PFStandingMetric]) -> some View {
        if !metrics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).strandOverline()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(metrics) { metric in
                        Button { onSelect?(metric) } label: {
                            PFChip(text: metric.label, color: PFBandColor.color(for: metric.band))
                        }
                        .buttonStyle(.plain)
                        .disabled(onSelect == nil)
                        .accessibilityIdentifier("pf-standing-chip-\(title.lowercased())-\(metric.id)")
                    }
                }
            }
        }
    }
}

// MARK: - Metric row

struct PFStandingMetricRow: View {
    let metric: PFStandingMetric
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label)
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(metric.valueText)
                            .font(StrandFont.rounded(20))
                            .foregroundStyle(metric.isRated ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(metric.bandName)
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(metric.isRated ? PFBandColor.color(for: metric.band) : StrandPalette.textTertiary)
                        if metric.isLowConfidence {
                            PFChip(text: "low confidence", color: StrandPalette.textTertiary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                PFBandBar(band: metric.band)
            }
            .contentShape(Rectangle())
            .opacity(metric.isRated ? 1 : 0.62)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityText + (metric.isLowConfidence ? " Low confidence." : ""))
        .accessibilityHint("Opens the norms and the source")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("pf-standing-metric-\(metric.id)")
    }
}

// MARK: - The scorecard screen

struct PFStandingView: View {
    let standing: PFStanding
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetric: PFStandingMetric?
    @State private var selectedPlan: PFStandingPlan?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if standing.isApplicable {
                        content
                    } else {
                        notApplicable
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Where you stand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-standing-done")
                }
            }
        }
        .sheet(item: $selectedMetric) { metric in
            PFStandingMetricSheet(metric: metric, plan: standing.plan(metric.planId))
        }
        .sheet(item: $selectedPlan) { PFStandingPlanSheet(plan: $0) }
        .containerIdentifier("pf-standing-screen")
    }

    // MARK: Applicable

    @ViewBuilder private var content: some View {
        PFCard("Where you stand", icon: "chart.bar.xaxis", info: PFExplainerID.standing) {
            VStack(alignment: .leading, spacing: 10) {
                PFStandingSummaryHeader(standing: standing) { selectedMetric = $0 }
                if let note = standing.profile?.note { Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
            }
        }
        focusCard
        ForEach(standing.domains.filter { !$0.metrics.isEmpty }) { domain in
            domainCard(domain)
        }
        plansCard
        if let testDay = standing.testDay { PFTestDayCard(testDay: testDay) }
        PFAddMeasurementButton(kind: .fieldTest, title: "Log a field test")
    }

    @ViewBuilder private var focusCard: some View {
        let focus = standing.focusTop
        if !focus.isEmpty {
            PFCard("Focus", icon: "scope") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(focus) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            PFStandingMetricRow(metric: metric) { selectedMetric = metric }
                            if let plan = standing.plan(metric.planId) {
                                Button { selectedPlan = plan } label: {
                                    Label("Plan: \(plan.title)", systemImage: "list.bullet.clipboard")
                                        .font(StrandFont.subhead)
                                        .multilineTextAlignment(.leading)
                                }
                                .buttonStyle(.bordered)
                                .tint(StrandPalette.accent)
                                .accessibilityIdentifier("pf-standing-focus-plan-\(metric.id)")
                            }
                        }
                        if metric.id != focus.last?.id { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
            .containerIdentifier("pf-standing-focus")
        }
    }

    private func domainCard(_ domain: PFStandingDomain) -> some View {
        PFCard(domain.title, icon: "circle.grid.2x2") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(domain.metrics) { metric in
                    PFStandingMetricRow(metric: metric) { selectedMetric = metric }
                    if metric.id != domain.metrics.last?.id { Divider().overlay(StrandPalette.hairline) }
                }
            }
        }
        .containerIdentifier("pf-standing-domain-\(domain.id)")
    }

    @ViewBuilder private var plansCard: some View {
        if !standing.plans.isEmpty {
            PFCard("Plans", icon: "list.bullet.clipboard") {
                VStack(alignment: .leading, spacing: 10) {
                    if let intro = standing.plansIntro { PFParagraph(intro) }
                    ForEach(standing.plans) { plan in
                        Button { selectedPlan = plan } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.title)
                                        .font(StrandFont.subhead.weight(.semibold))
                                        .foregroundStyle(StrandPalette.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    if let timeframe = plan.timeframe {
                                        Text(timeframe)
                                            .font(StrandFont.caption)
                                            .foregroundStyle(StrandPalette.textTertiary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pf-standing-plan-\(plan.id)")
                        if plan.id != standing.plans.last?.id { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
            .containerIdentifier("pf-standing-plans")
        }
    }

    // MARK: Not applicable

    private var notApplicable: some View {
        PFCard("Where you stand", icon: "chart.bar.xaxis", info: PFExplainerID.standing) {
            VStack(alignment: .leading, spacing: 10) {
                PFParagraph(standing.profile?.note ?? "Norms need sex and age.")
                    .accessibilityIdentifier("pf-standing-note")
                PFParagraph("Nothing is rated until PaceForge has them. Your measured numbers are still kept.")
            }
        }
        .containerIdentifier("pf-standing-na")
    }
}

// MARK: - Metric sheet

struct PFStandingMetricSheet: View {
    let metric: PFStandingMetric
    let plan: PFStandingPlan?
    @Environment(\.dismiss) private var dismiss
    @State private var showPlan = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    if let norm = metric.norm { normCard(norm) }
                    if let why = metric.why { PFCard("Why it matters", icon: "questionmark.circle") { PFParagraph(why) } }
                    if let trend = metric.trend { trendCard(trend) }
                    sourceCard
                    if let note = metric.note {
                        PFCard("Note", icon: "note.text") { PFParagraph(note) }
                    }
                    if plan != nil {
                        Button { showPlan = true } label: {
                            Label("See the plan", systemImage: "list.bullet.clipboard")
                                .font(StrandFont.subhead.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StrandPalette.accent)
                        .accessibilityIdentifier("pf-standing-open-plan")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(metric.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-standing-metric-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showPlan) {
            if let plan { PFStandingPlanSheet(plan: plan) }
        }
        .containerIdentifier("pf-standing-metric-sheet")
    }

    private var headerCard: some View {
        PFCard(metric.label, icon: "gauge.with.dots.needle.33percent") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metric.valueText)
                        .font(StrandFont.rounded(30))
                        .foregroundStyle(StrandPalette.textPrimary)
                    PFChip(text: metric.bandName, color: PFBandColor.color(for: metric.band))
                    if metric.isLowConfidence {
                        PFChip(text: "low confidence", color: StrandPalette.textTertiary)
                    }
                }
                PFBandBar(band: metric.band, height: 10)
                if metric.isRated, let band = metric.band {
                    Text("Band \(band) of 5")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Text("Not rated. There is no norm to place this number against yet.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func normCard(_ norm: PFStandingNorm) -> some View {
        PFCard("What each band means", icon: "tablecells", info: PFExplainerID.standingBands) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(norm.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(PFBandColor.color(for: row.band))
                            .frame(width: 4, height: 18)
                        Text(row.name)
                            .font(StrandFont.subhead.weight(row.band == metric.band ? .bold : .regular))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(width: 84, alignment: .leading)
                        Text(row.text)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if row.band == metric.band {
                            Text("you")
                                .font(StrandFont.overline)
                                .foregroundStyle(PFBandColor.color(for: row.band))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pf-standing-norm-\(row.band)")
                }
            }
        }
    }

    private func trendCard(_ trend: PFStandingTrend) -> some View {
        PFCard("Trend", icon: "chart.line.uptrend.xyaxis") {
            HStack(spacing: 8) {
                Image(systemName: trend.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(trendColor(trend))
                Text(trend.text)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let improving = trend.improving {
                    Text(improving ? "toward a higher band" : "away from a higher band")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pf-standing-trend")
        }
    }

    private func trendColor(_ trend: PFStandingTrend) -> Color {
        switch trend.improving {
        case .some(true): return PFColor.positive
        case .some(false): return PFColor.warning
        case .none: return StrandPalette.textSecondary
        }
    }

    @ViewBuilder private var sourceCard: some View {
        if metric.source != nil || metric.confidence != nil {
            PFCard("Where the norms come from", icon: "books.vertical") {
                VStack(alignment: .leading, spacing: 8) {
                    if let source = metric.source {
                        HStack(spacing: 8) {
                            if let tag = source.tag { PFChip(text: tag, color: StrandPalette.accent) }
                            if let label = source.label {
                                Text(label)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .containerIdentifier("pf-standing-source")
                        if let text = source.url, let url = URL(string: text), url.scheme?.lowercased() == "https" {
                            Link(destination: url) {
                                Label("Open the source", systemImage: "arrow.up.right.square")
                                    .font(StrandFont.subhead)
                            }
                            .accessibilityIdentifier("pf-standing-source-link")
                        }
                    }
                    if let confidence = metric.confidence {
                        Text("Confidence: \(confidence)")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityIdentifier("pf-standing-confidence")
                    }
                }
            }
        }
    }
}

// MARK: - Plan sheet

struct PFStandingPlanSheet: View {
    let plan: PFStandingPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PFPlanCard(plan: plan)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-standing-plan-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .containerIdentifier("pf-standing-plan-sheet")
    }
}

/// One plan: why, the steps, how to measure it, what not to do, the evidence and the timeframe.
struct PFPlanCard: View {
    let plan: PFStandingPlan

    var body: some View {
        PFCard(title: plan.title, icon: "list.bullet.clipboard", trailing: {
            if let timeframe = plan.timeframe { PFChip(text: timeframe, color: StrandPalette.accent) }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                if let why = plan.why { PFLabeled(label: "Why", text: why) }
                if !plan.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Steps").strandOverline()
                        ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(StrandPalette.accent)
                                    .frame(width: 18, alignment: .trailing)
                                Text(step)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let measure = plan.measure { PFLabeled(label: "How to measure it", text: measure) }
                if let dont = plan.dont { PFLabeled(label: "Don't", text: dont) }
                if let evidence = plan.evidence { PFLabeled(label: "Evidence", text: evidence) }
            }
        }
        .containerIdentifier("pf-plan-\(plan.id)")
    }
}

// MARK: - Test day

struct PFTestDayCard: View {
    let testDay: PFTestDay

    var body: some View {
        PFCard("Test day", icon: "checklist") {
            VStack(alignment: .leading, spacing: 14) {
                if let intro = testDay.intro { PFParagraph(intro).accessibilityIdentifier("pf-testday-intro") }
                ForEach(testDay.tests) { test in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(test.label)
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 8)
                            Text(loggedText(test))
                                .font(StrandFont.caption)
                                .foregroundStyle(test.logged == nil ? StrandPalette.textTertiary : StrandPalette.textSecondary)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("pf-test-logged-\(test.id)")
                        }
                        if let how = test.how { PFParagraph(how) }
                        if let note = test.normNote {
                            Text(note)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let phrase = PFTestPhrase.telegram(from: test.how) {
                            Text("Log it in Telegram: \(phrase)")
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(StrandPalette.accent)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("pf-test-hint-\(test.id)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pf-test-\(test.id)")
                    if test.id != testDay.tests.last?.id { Divider().overlay(StrandPalette.hairline) }
                }
            }
        }
        .containerIdentifier("pf-testday")
    }

    /// "Last logged 35 reps, 1 Mar", or "Not logged yet".
    private func loggedText(_ test: PFTestDay.Test) -> String {
        guard let logged = test.logged else { return "Not logged yet" }
        var value = logged.display
        if value == nil, let number = logged.value { value = PFFormat.trimmed(number) }
        if let unit = test.unit, let current = value, !current.contains(unit) { value = current + " " + unit }
        var text = "Last logged " + (value ?? "")
        if let date = logged.date { text += ", " + PFFormat.shortDate(date) }
        return text
    }
}

// MARK: - Compact cards

/// The summary on Insights: the strip and chips, and a button that opens the full scorecard.
struct PFStandingInsightsCard: View {
    let standing: PFStanding
    @Environment(\.pfOpenStanding) private var openStanding

    var body: some View {
        PFCard("Where you stand", icon: "chart.bar.xaxis", info: PFExplainerID.standing) {
            VStack(alignment: .leading, spacing: 12) {
                if standing.isApplicable {
                    PFStandingSummaryHeader(standing: standing)
                } else {
                    PFParagraph(standing.profile?.note ?? "Norms need sex and age.")
                }
                Button { openStanding() } label: {
                    Label("Open the scorecard", systemImage: "chart.bar.doc.horizontal")
                        .font(StrandFont.subhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .accessibilityIdentifier("pf-standing-open")
                PFAddMeasurementButton(kind: .fieldTest, title: "Log a field test")
            }
        }
        .containerIdentifier("pf-standing-insights-card")
    }
}

/// The compact card on Today: the strongest and the focus metrics in one line each. Tapping opens the scorecard.
struct PFStandingTodayCard: View {
    let standing: PFStanding
    @Environment(\.pfOpenStanding) private var openStanding

    var body: some View {
        Button { openStanding() } label: {
            PFCard(title: "Where you stand", icon: "chart.bar.xaxis", trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    if !standing.isApplicable {
                        PFParagraph(standing.profile?.note ?? "Norms need sex and age.")
                    } else {
                        let lines = standing.summaryLines
                        if let strongest = lines.strongest { line("Strongest", strongest, StrandPalette.recovery100) }
                        if let focus = lines.focus { line("Focus", focus, StrandPalette.recovery055) }
                        if lines.strongest == nil && lines.focus == nil {
                            PFParagraph("Your measured numbers against published norms.")
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-standing-today-card")
    }

    private func line(_ title: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).strandOverline()
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
