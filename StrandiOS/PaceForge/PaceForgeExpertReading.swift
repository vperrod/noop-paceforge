import SwiftUI
import StrandDesign

// The Expert reading card on Today: the daily report's head-coach stages, text only, dated, with a way into the full report.

/// Today's one Expert reading card: the daily report's head-coach stages, text only, dated. Draws nothing until the reading is on the
/// phone; Today starts the load itself, because an empty view never runs its own task.
struct PFExpertReadingHost: View {
    @ObservedObject private var store = PFReportsStore.shared

    var body: some View {
        if store.showsReports, let report = store.latestDaily {
            PFExpertReadingCard(report: report)
        }
    }
}

struct PFExpertReadingCard: View {
    let report: PFReport

    private static let openTitle = "Open full daily report"

    var body: some View {
        PFCard(title: "Expert reading", icon: "text.book.closed", trailing: {
            Text(PFReportFreshness.dateLine(report))
                .lookCaps(11)
                .foregroundStyle(NoopLook.textTertiary)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                PFReportFreshnessBlock(report: report)
                ForEach(report.stages) { stage in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.title).strandOverline()
                        PFReportBlocks(text: stage.text, size: 14.5)
                    }
                }
                Text(PFReportText.wholeNote(report.wholeSource))
                    .font(LookFont.text(11.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                NavigationLink(value: TabRoute.reports(PFReportKind.daily.rawValue)) {
                    HStack(spacing: 6) {
                        Text(Self.openTitle)
                            .font(StrandFont.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(StrandPalette.accent)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pf-expert-reading-open")
            }
        }
        .containerIdentifier("pf-expert-reading")
    }
}
