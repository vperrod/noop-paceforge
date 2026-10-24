#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Insights: the fourth tab with the unified navigation
//
// Chips at the top and ONE chip mounted below them: Overview (What moves you, Intelligence, and PaceForge's "Where you stand" and
// insight items), Trends (the Trends screen, with Compare and the Metric Explorer one tap away), Reports (the weekly review, then the
// Monthly report, Highlights and Healthspan), Journal (the journal, with Journal impact) and Deep dives (PaceForge's fitness, fatigue
// and form, load warnings, races and HYROX prognosis). Every chip is the content of a screen that already exists, unchanged.
// NOOP's and PaceForge's scores are never merged: each section says whose it is.

enum InsightsChip: String, CaseIterable, Identifiable {
    case overview, trends, reports, journal, deepDives

    /// The chip on show, shared with the shell so an old link can land on a chip. Reset to Overview at every launch.
    static let storageKey = "noop.insights.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .trends: return "Trends"
        case .reports: return "Reports"
        case .journal: return "Journal"
        case .deepDives: return "Deep dives"
        }
    }
}

/// The Insights tab's root.
struct InsightsUnifiedHost: View {
    @EnvironmentObject private var repo: Repository
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
        ScreenScaffold(title: "Insights", subtitle: "What moves you, your trends, your reports and your journal.",
                       onRefresh: { await repo.refresh() }, lazy: true, topBackground: liquidScaffoldSky()) {
            InsightsUnifiedColumn(selection: selection)
        }
    }
}

/// The chips and the chosen chip's content.
private struct InsightsUnifiedColumn: View {
    @Binding var selection: InsightsChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        case .trends: return AnyView(InsightsTrendsChip())
        case .reports: return AnyView(InsightsReportsChip())
        case .journal: return AnyView(InsightsJournalChip())
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
        }
        .containerIdentifier("insights-chip-content-overview")
    }
}

private struct InsightsOverviewPaceForge: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let standing = snapshot.standing, standing.hasContent {
                PFDismissable(.standing, text: PFCardText.standing(standing), snapshot: snapshot) {
                    PFStandingInsightsCard(standing: standing)
                }
            }
            if let insights = snapshot.insightsV2, insights.hasContent { PFInsightsV2Section(doc: insights) }
        }
    }
}

private struct InsightsOverviewMoves: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What moves you").strandOverline()
            InsightsHubView(embedded: true)
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

/// The Trends screen, under the two screens that sat beside it in More.
private struct InsightsTrendsChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Look closer") {
                IndexRow("Compare", "rectangle.split.2x1.fill", TabRoute.compare, id: "insights-trends-compare")
                IndexRow("Metric Explorer", "square.grid.2x2.fill", TabRoute.metricExplorer, id: "insights-trends-explorer")
            }
            TrendsView()
        }
        .containerIdentifier("insights-chip-content-trends")
    }
}

/// The weekly review, then the three reports that open their own screens.
private struct InsightsReportsChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            InsightsReportRows()
            PFSnapshotHost(content: { snapshot in AnyView(InsightsWeeklyReview(snapshot: snapshot)) })
        }
        .containerIdentifier("insights-chip-content-reports")
    }
}

private struct InsightsWeeklyReview: View {
    let snapshot: PFSnapshot

    var body: some View {
        if let review = snapshot.coach.weeklyReview {
            PFCoachView(snapshot: snapshot).weeklyReviewCard(review)
                .accessibilityIdentifier("insights-weekly-review")
        } else {
            PFCard("Weekly review", icon: "calendar") {
                PFParagraph("PaceForge writes the review of your week at the end of it. It shows here once it has.")
            }
        }
    }
}

private struct InsightsReportRows: View {
    var body: some View {
        IndexSection("Reports") {
            IndexRow("Monthly report", "calendar", TabRoute.monthlyReport, id: "insights-report-monthly")
            IndexRow("Highlights", "star.fill", TabRoute.highlights, id: "insights-report-highlights")
            IndexRow("Healthspan", "hourglass", TabRoute.healthspan, id: "insights-report-healthspan")
        }
    }
}

/// The journal (and the experiments in it), with Journal impact one tap away.
private struct InsightsJournalChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Journal impact") {
                IndexRow("Journal impact", "book.closed.fill", TabRoute.journalImpact, id: "insights-journal-impact")
            }
            InsightsView(embedded: true)
        }
        .containerIdentifier("insights-chip-content-journal")
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
