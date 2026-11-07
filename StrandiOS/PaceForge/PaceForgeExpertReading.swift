import SwiftUI
import StrandDesign

// The Expert reading card in the Coach: the daily report's head-coach stages, text only, dated, with a way into the full report.

/// The Coach's one Expert reading card: the daily report's head-coach stages, text only, dated. Draws nothing until the reading is on the
/// phone; the Coach starts the load itself, because an empty view never runs its own task.
struct PFExpertReadingHost: View {
    @ObservedObject private var store = PFReportsStore.shared

    var body: some View {
        if store.showsReports, let report = store.latestDaily {
            PFExpertReadingCard(report: report)
        }
    }
}

/// One row on Today that opens the daily report, so it is not only behind the Coach. Draws nothing until the reading is on the phone.
struct PFDailyReportRow: View {
    @ObservedObject private var store = PFReportsStore.shared

    var body: some View {
        if store.showsReports, let report = store.latestDaily {
            NavigationLink(value: TabRoute.reports(PFReportKind.daily.rawValue)) {
                HStack(spacing: 12) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "DAILY REPORT").font(StrandFont.overlineScaled(11)).tracking(1.0)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(verbatim: PFReportFreshness.dateLine(report))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(NoopPanelSurface(tint: StrandPalette.accent, cornerRadius: 20))
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityIdentifier("today-daily-report-row")
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
