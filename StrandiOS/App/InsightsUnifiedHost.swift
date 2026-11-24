#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Insights: the last chip of the Coach
//
// Chips at the top and ONE chip mounted below them: Overview (PaceForge's "Where you stand" tiles, What moves you (closed until
// tapped), Intelligence, then the weekly review and the Monthly report, Highlights and Healthspan rows) and Deep dives (PaceForge's fitness,
// fatigue and form, load warnings, races and HYROX prognosis). Trends and Journal are chips of Health.
// Every chip is the content of a screen that already exists, unchanged.
// NOOP's and PaceForge's scores are never merged: each section says whose it is.

enum InsightsChip: String, CaseIterable, Identifiable {
    case overview, deepDives

    /// The chip on show, shared with the shell so an old link can land on a chip. Reset to Overview at every launch.
    static let storageKey = "noop.insights.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .deepDives: return "Deep dives"
        }
    }
}

/// Insights as the last chip of the Coach: its own chips (Overview, Deep dives) and the chosen one. A stored trends or journal raw
/// value (they moved to Health) falls back to Overview.
struct InsightsEmbedded: View {
    @AppStorage(InsightsChip.storageKey) private var chipRaw = InsightsChip.overview.rawValue

    private var chip: InsightsChip { InsightsChip(rawValue: chipRaw) ?? .overview }

    private var selection: Binding<InsightsChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip insights.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        InsightsUnifiedColumn(selection: selection)
    }
}

/// The chips and the chosen chip's content.
private struct InsightsUnifiedColumn: View {
    @Binding var selection: InsightsChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFPageNote(key: "insights")
            PFProactiveInsightsSection()
            SectionChips(options: InsightsChip.allCases, selection: $selection, idPrefix: "insights-chip",
                         id: { $0.rawValue }, title: { $0.title })
            InsightsChipBody(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("insights-host")
    }
}

/// One chip's content, with its mount time in the breadcrumbs.
private struct InsightsChipBody: View {
    let chip: InsightsChip

    var body: some View {
        UnifiedChipMount(host: "insights", name: chip.rawValue, content: content)
    }

    private var content: AnyView {
        switch chip {
        case .overview: return AnyView(InsightsOverviewChip())
        case .deepDives: return AnyView(InsightsDeepDivesChip())
        }
    }
}

// MARK: - Chips

/// PaceForge's "Where you stand" and insight items, then NOOP's What moves you and Intelligence. This host answers the PaceForge links.
private struct InsightsOverviewChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            PFSnapshotHost(isPrimary: true, content: { snapshot in AnyView(InsightsOverviewPaceForge(snapshot: snapshot)) })
            InsightsOverviewMoves()
            InsightsOverviewIntelligence()
            InsightsReportRows()
            // The second host on this chip: content only, because the first one already draws the lock, loading, failed and offline states.
            PFSnapshotHost(drawsChrome: false, content: { snapshot in AnyView(InsightsWeeklyReview(snapshot: snapshot)) })
        }
        .containerIdentifier("insights-chip-content-overview")
    }
}

private struct InsightsOverviewPaceForge: View {
    let snapshot: PFSnapshot

    private var cards: [PFInsightItem] { snapshot.insightsV2?.insightCards ?? [] }
    private var standing: PFStanding? { snapshot.standing.flatMap { $0.hasContent ? $0 : nil } }

    var body: some View {
        if !cards.isEmpty || standing != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where you stand").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(cards) { PFInsightCard(item: $0, asTile: true) }
                    if let standing {
                        PFDismissable(.standing, text: PFCardText.standing(standing), snapshot: snapshot) {
                            InsightsScorecardTile(standing: standing)
                        }
                    }
                }
                .containerIdentifier(cards.isEmpty ? "pf-where-you-stand" : "pf-insights-v2")
            }
        }
    }
}

/// The scorecard as the last tile of Where you stand: it opens the scorecard (where the rating strip and the strongest and focus
/// metrics are) and carries the Log a field test button.
private struct InsightsScorecardTile: View {
    let standing: PFStanding
    @Environment(\.pfOpenStanding) private var openStanding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openStanding() } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scorecard")
                        .lookCaps(10.5)
                        .foregroundStyle(NoopLook.textSecondary)
                        .lineLimit(1)
                    Text("Open")
                        .font(StrandFont.rounded(20))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if !standing.isApplicable {
                        Text(standing.profile?.note ?? "Norms need sex and age.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pf-standing-open")
            PFAddMeasurementButton(kind: .fieldTest, title: "Log a field test")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.tile))
        .containerIdentifier("pf-standing-insights-card")
    }
}

/// What moves you, closed until tapped; its content (the ranked movers and the dose view) loads when it opens.
private struct InsightsOverviewMoves: View {
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What moves you")
                            .font(StrandFont.body.weight(.semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                        Text("Ranked from your data")
                            .font(StrandFont.caption)
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("insights-moves-toggle")
            if isOpen { InsightsHubView(embedded: true) }
        }
    }
}

private struct InsightsOverviewIntelligence: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intelligence").strandOverline()
            IntelligenceView(embedded: true)
        }
    }
}

/// The weekly review (the end of Overview, after the three report rows).
private struct InsightsWeeklyReview: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            if let review = snapshot.coach.weeklyReview {
                PFCoachView(snapshot: snapshot).weeklyReviewCard(review)
                    .accessibilityIdentifier("insights-weekly-review")
            } else {
                PFCard("Weekly review", icon: "calendar") {
                    PFParagraph("PaceForge writes the review of your week at the end of it. It shows here once it has.")
                }
            }
            // The week report now lives in Plan > Week: last week's page, one swipe back from the plan.
            IndexSection("Week report") {
                IndexRow("Last week's report", "calendar", TabRoute.plan529(.week(PFISOWeek529.previous(PFAPI.todayISO))),
                         id: "insights-week-report")
            }
        }
    }
}

private struct InsightsReportRows: View {
    /// "2026-10" for a phone whose today is in November 2026.
    private static var lastMonthKey: String {
        let firstOfThisMonth = String(PFAPI.todayISO.prefix(8)) + "01"
        return String(PFFormat.addDays(firstOfThisMonth, -1).prefix(7))
    }

    var body: some View {
        IndexSection("Longer reports") {
            // The month in a few lines (Plan's month report, for last month); the scores for the month stay one row below it.
            IndexRow("Monthly report", "calendar", TabRoute.plan529(.monthReport(key: Self.lastMonthKey)), id: "insights-report-monthly")
            IndexRow("Monthly scores", "chart.bar", TabRoute.monthlyReport, id: "insights-report-monthly-scores")
            IndexRow("Highlights", "star.fill", TabRoute.highlights, id: "insights-report-highlights")
            IndexRow("Healthspan", "hourglass", TabRoute.healthspan, id: "insights-report-healthspan")
        }
    }
}

/// PaceForge's fitness, fatigue and form, load warnings, races and HYROX prognosis (its Insights screen without the two cards that are
/// on Overview).
private struct InsightsDeepDivesChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(PFInsightsView(snapshot: snapshot, includesOverview: false)) })
            .containerIdentifier("insights-chip-content-deepDives")
    }
}
#endif
