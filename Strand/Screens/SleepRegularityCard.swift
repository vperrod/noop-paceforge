import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Sleep regularity (Sleep tab)
//
// How steady the sleep/wake pattern has been over the last 14 nights, from NOOP's own sleep sessions
// (`SleepRegularity`, a pure function in StrandAnalytics). A reading is shown only when enough nights exist, and
// the "steadier / about as steady / less steady than usual" line only when earlier fortnights give an own baseline.
// Display only: it feeds no score.

/// The Sleep tab's planner entry with the regularity tile under it. The Sleep screen's section column is already at
/// the ten-child limit of a SwiftUI builder, so the new tile rides with a sibling instead of becoming an 11th child.
/// The read is started from the always-present planner card, never from the tile that may not exist yet.
struct SleepPlannerWithRegularity: View {
    @EnvironmentObject private var repo: Repository
    @State private var assessment: SleepRegularity.Assessment?

    /// A reading from sessions that all ended long ago would describe a fortnight that is over.
    private static let staleAfterSeconds = 3 * 86_400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SleepPlannerEntryCard()
            if let assessment {
                SleepRegularityTile(assessment: assessment)
                    .padding(.top, NoopMetrics.sectionSpacing)
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    @MainActor private func load() async {
        let sessions = await repo.allSleepSessions(days: 120)
        guard !Task.isCancelled else { return }
        let spans = sessions.map { SleepRegularity.Span(start: $0.effectiveStartTs, end: $0.endTs) }
        guard let last = sessions.map({ $0.endTs }).max(),
              Int(Date().timeIntervalSince1970) - last <= Self.staleAfterSeconds else {
            assessment = nil
            return
        }
        let offset = TimeZone.current.secondsFromGMT(for: Date())
        assessment = SleepRegularity.assess(spans: spans, endingAt: last, tzOffsetSeconds: offset)
    }
}

private struct SleepRegularityTile: View {
    let assessment: SleepRegularity.Assessment

    private var percentText: String { "\(Int(assessment.reading.matchPercent.rounded()))%" }

    private var trendLine: LocalizedStringKey? {
        switch assessment.trend {
        case .some(.steadier): return "Steadier than usual"
        case .some(.usual): return "About as steady as usual"
        case .some(.lessSteady): return "Less steady than usual"
        case .none: return nil
        }
    }

    var body: some View {
        NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("Sleep regularity").strandOverline()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(percentText)
                        .font(StrandFont.number(26))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let trendLine {
                        Text(trendLine)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Text("How closely you are asleep and awake at the same times from one day to the next, over your last 14 nights. 100% would be exactly the same every day. This is the Sleep Regularity Index.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Based on \(assessment.reading.nights) nights")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
