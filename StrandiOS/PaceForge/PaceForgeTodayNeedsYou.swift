import SwiftUI

/// NOOP Today's Needs you: it leads the page while PaceForge is waiting on an answer (treadmill pace, a proposal, effort, feel) and
/// leaves as soon as the answer is taken. Draws nothing when nothing is open. Shares the PaceForge tab's model, so an answer given
/// here or there clears both.
struct PFTodayNeedsYouHost: View {
    @ObservedObject private var model = PFUnified.model

    var body: some View {
        Group {
            if let items = model.snapshot?.needsYou, !items.isEmpty {
                PFNeedsYouCard(items: items)
                    .environmentObject(model)
            }
        }
        .task { await model.refreshIfStale() }
    }
}
