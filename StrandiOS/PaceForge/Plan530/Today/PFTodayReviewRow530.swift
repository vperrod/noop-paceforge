import SwiftUI

/// The Sunday review row on Today (build 530): directly above the overview card on Sunday from the wind-down time and on Monday until
/// 12:00, for the most recently finished week, and only when that week's document has a `review` block. A tap opens the review.
struct PFTodayReviewRow530: View {
    @StateObject private var index = PFDocStore529<PFPlanWeekIndexDoc>(path: PFDocPath529.weekIndex)
    @StateObject private var inbox = PFDocStore529<PFInboxDoc>(path: PFDocPath529.inbox)

    var body: some View {
        // Re-read every minute, as the overview card does, so the row appears at the wind-down time without the screen being reopened.
        TimelineView(.everyMinute) { context in
            row(now: context.date)
        }
        .task {
            await index.refreshIfStale()
            await inbox.refreshIfStale()
        }
    }

    @ViewBuilder private func row(now: Date) -> some View {
        if PFTodayReviewWindow530.isOpen(now: now, windDownMinutes: PFAlertDelivery530.minutes(inbox.doc?.quiet?.windDown)),
           let week = PFTodayReviewWindow530.latestFinishedWeek(index.doc?.weeks, today: Self.todayKey(now)) {
            PFTodayReviewRowLoaded530(week: week)
        }
    }

    private static func todayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Loads the finished week's document and draws the row when it has a review.
private struct PFTodayReviewRowLoaded530: View {
    let week: String
    @StateObject private var store: PFDocStore529<PFPlanWeekDoc>

    init(week: String) {
        self.week = week
        _store = StateObject(wrappedValue: PFDocStore529<PFPlanWeekDoc>(path: PFDocPath529.week(week)))
    }

    var body: some View {
        Group {
            if store.doc?.report?.review != nil { PFReviewTodayRow530(week: week) }
        }
        .task { await store.refreshIfStale() }
    }
}
