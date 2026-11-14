#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Insights: the last chip of the Coach
//
// Chips at the top and ONE chip mounted below them: Overview (What moves you, Intelligence, PaceForge's "Where you stand" and
// insight items, then the weekly review and the Monthly report, Highlights and Healthspan rows) and Deep dives (PaceForge's fitness,
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

/// The weekly review (the end of Overview, after the three report rows).
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
        IndexSection("Longer reports") {
            IndexRow("Monthly report", "calendar", TabRoute.monthlyReport, id: "insights-report-monthly")
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
