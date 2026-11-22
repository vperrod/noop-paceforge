import SwiftUI
import StrandDesign

/// "After the changes you accepted": the proposals accepted during the reviewed week, each with what was recorded the next morning
/// (`GET outcome-review`) and the thumbs the athlete gave it. The numbers are what was filed, never a claim that the change caused them.
/// Garmin's and NOOP's readings are listed under their own names and never combined. Draws nothing when no proposal was accepted that week
/// or the proposal log no longer reaches it.
struct PFReviewOutcomes530: View {
    /// The week's first and last day ("2026-11-09", "2026-11-15").
    let from: String?
    let to: String?

    @State private var rows: [PFOutcomeRow] = []
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !rows.isEmpty {
                PFReviewSectionTitle530(text: "After the changes you accepted")
                ForEach(rows) { row in card(row) }
                PFWeekSub529(text: "These are the readings filed the morning after. They do not show that the change caused them.")
            }
        }
        .containerIdentifier("review530-outcomes")
        .task(id: "\(from ?? "")|\(to ?? "")") { await load() }
    }

    private func card(_ row: PFOutcomeRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PFWeekOverline529(text: "Accepted \(PFFormat.dayTitle(row.acceptedDay))")
            Text(hiding.text(row.title))
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(row.changes.enumerated()), id: \.offset) { _, change in PFWeekSub529(text: change) }
            PFWeekBody529(text: row.stateLine)
            if !row.nextReadings.isEmpty { readings("The next morning", row.nextReadings) }
            if !row.answeredReadings.isEmpty { readings("When you answered", row.answeredReadings) }
            ForEach(Array(row.ratings.enumerated()), id: \.offset) { _, rating in
                PFWeekSub529(text: ratingText(rating))
            }
        }
        .pfWeekCard()
        .accessibilityIdentifier("review530-outcome-\(row.id)")
    }

    private func readings(_ heading: String, _ list: [PFOutcomeReading]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            PFWeekOverline529(text: heading)
            ForEach(list) { reading in
                Text("\(reading.label): \(hiding.shown(reading.text, .scores))")
                    .font(PFPlanFont543.text(13.5, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
            }
        }
    }

    private func ratingText(_ rating: PFOutcomeRow.Rating) -> String {
        let base = rating.verdict == "up" ? "You rated this helpful." : "You rated this not helpful."
        guard let reason = rating.reason, !reason.isEmpty else { return base }
        return base + " " + reason
    }

    @MainActor private func load() async {
        guard let from, let to, from.count >= 10, PFAPI.isConfigured else { return }
        let today = PFAPI.todayISO
        guard PFOutcomeReview.isInLog(weekStart: from, today: today) else {
            rows = []
            return
        }
        let days = PFOutcomeReview.days(weekStart: from, today: today)
        guard let data = try? await PFAPI.fetch("api/outcome-review?days=\(days)") else { return }
        rows = PFOutcomeReview.rows(PFOutcomeReview.parse(PFJ(data: data)), from: from, to: to)
    }
}
