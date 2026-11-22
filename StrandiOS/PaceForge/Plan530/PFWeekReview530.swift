import SwiftUI
import StrandDesign

/// The Sunday review (screens 1b to 1e): the finished week in charts, one reading line each, then the week ahead against the race calendar
/// and every workout of it. Route `review` (the inbox, the Today row, the finished week's page and `-Plan529Open review:<week>` open it).
/// The week's own document carries the `review` block; the week ahead is read from the next week's document by `PFReviewAhead530`.
struct PFWeekReview530: View {
    let week: String

    @StateObject private var store: PFDocStore529<PFPlanWeekDoc>

    init(week: String) {
        self.week = week
        _store = StateObject(wrappedValue: PFDocStore529<PFPlanWeekDoc>(path: PFDocPath529.week(week)))
    }

    private var number: String { PFReviewFormat530.weekNumber(week) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch store.state {
                case .loading:
                    PFWeekState529(kind: .loading, message: "Loading the review")
                case .empty:
                    PFWeekState529(kind: .empty, message: "The review of week \(number) is not ready yet.")
                case .failed:
                    PFWeekState529(kind: .failed, message: "The review could not be loaded.", retry: { Task { await store.refresh() } })
                case .loaded(let doc):
                    loaded(doc)
                }
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .refreshable {
            await store.refresh()
            NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        }
        .lookScreenBackground()
        .navigationTitle("Week \(number) in review")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("pf530-week-review")
        .task { await store.refreshIfStale() }
    }

    @ViewBuilder private func loaded(_ doc: PFPlanWeekDoc) -> some View {
        if store.isStale { PFWeekSub529(text: "Showing the copy saved on this phone. PaceForge could not be reached.") }
        top(doc)
        if let review = doc.report?.review, !review.isEmpty {
            PFReviewDid530(doc: doc, review: review)
            PFReviewSectionTitle530(text: "Week \(number) \u{00B7} your body")
            PFReviewBody530(doc: doc, review: review)
            PFReviewOutcomes530(from: doc.from, to: doc.to)
            if let next = review.ahead?.week ?? doc.report?.nextWeek?.week, !next.isEmpty {
                PFReviewAhead530(week: next, ahead: review.ahead)
            } else {
                PFWeekState529(kind: .empty, message: "The week ahead is not ready yet.")
            }
            experts
        } else {
            PFWeekState529(kind: .empty, message: "The charts of week \(number) are not ready yet.")
            experts
        }
    }

    // MARK: Verdict

    private func top(_ doc: PFPlanWeekDoc) -> some View {
        var pills: [(text: String, color: Color)] = []
        if let pill = doc.phase?.pill { pills.append((pill, PFWeekPhase529.color(doc.phase?.key))) }
        if let range = PFReviewFormat530.range(from: doc.from, to: doc.to) { pills.append((range, NoopLook.textSecondary)) }
        return VStack(alignment: .leading, spacing: 10) {
            PFReviewPills530(pills: pills)
            if let verdict = doc.report?.verdict, !verdict.isEmpty {
                PFReviewHeadline530(text: verdict, identifier: "review530-verdict")
            }
        }
    }

    /// The long text of the week stays one tap down.
    private var experts: some View {
        NavigationLink(value: TabRoute.reports("\(PFReportKind.weekly.rawValue):\(week)")) {
            HStack {
                Text("What each expert read")
                    .font(PFPlanFont543.text(15, weight: .medium))
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .pfWeekCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review530-link-experts")
    }
}
