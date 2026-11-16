import SwiftUI
import StrandDesign

/// Screen 1b, "What you did": training by day against the hours of a usual week, the races against their goals, and the stations that
/// cost the most. Each block draws only what the server sent; a missing reading line leaves its chart without one.
struct PFReviewDid530: View {
    let doc: PFPlanWeekDoc
    let review: PFWeekReviewDoc530

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let days = review.trainingDays, !days.isEmpty { training(days) }
            if let races = doc.report?.races, !races.isEmpty { racesCard(races) }
            if let lost = review.raceLosses?.filter({ !($0.losses ?? []).isEmpty }), !lost.isEmpty { stations(lost) }
        }
    }

    // MARK: Training

    private func training(_ days: [PFWeekReviewDoc530.TrainingDay]) -> some View {
        let top = Double(max(days.compactMap { $0.minutes }.max() ?? 1, 1))
        let bars = days.indices.map { index -> PFDayBar530 in
            let minutes = days[index].minutes ?? 0
            return PFDayBar530(id: index, value: Double(minutes), color: PFWeekColor529.effort(days[index].effort),
                               label: "\(days[index].dow ?? "") \(minutes > 0 ? String(minutes) : "\u{00B7}")")
        }
        let summary = "Training minutes by day. " + bars.map { $0.label }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "Training, day by day \u{00B7} minutes")
            PFDayBars530(bars: bars, top: top, height: 58, summary: summary)
                .accessibilityIdentifier("review530-bars-training")
            legend(days)
            if let hours = review.hours { hoursBars(hours) }
            PFReviewReading530(key: "training", text: review.readings?.training)
        }
        .pfReviewCard530("training")
    }

    /// The efforts that appear this week, in the order easy, moderate, hard, race.
    private func legend(_ days: [PFWeekReviewDoc530.TrainingDay]) -> some View {
        let present = ["easy", "moderate", "hard", "race"].filter { effort in days.contains { $0.effort == effort && ($0.minutes ?? 0) > 0 } }
        return LookFlowLayout(spacing: 12, lineSpacing: 4) {
            ForEach(present, id: \.self) { effort in
                HStack(spacing: 5) {
                    Circle().fill(PFWeekColor529.effort(effort)).frame(width: 8, height: 8)
                    Text(effort).font(LookFont.text(11.5, weight: .regular)).foregroundStyle(NoopLook.textTertiary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func hoursBars(_ hours: PFWeekReviewDoc530.Hours) -> some View {
        if let rows = hourRows(hours) {
            PFHBars530(rows: rows, scale: rows.map { $0.value }.max(), labelWidth: 120)
                .accessibilityIdentifier("review530-bars-hours")
        }
    }

    /// This week against the mean of the last finished weeks (absent while there are too few).
    private func hourRows(_ hours: PFWeekReviewDoc530.Hours) -> [PFHBar530]? {
        guard let this = hours.thisH else { return nil }
        var rows = [PFHBar530(id: 0, label: "This week", value: this, valueText: hours.thisLabel ?? "", color: PFWeekColor529.blue)]
        if let usual = hours.usualH {
            rows.append(PFHBar530(id: 1, label: "Your last \(hours.usualWeeks ?? 4) weeks", value: usual, valueText: hours.usualLabel ?? "",
                                  color: PFReviewColor530.violet))
        }
        return rows
    }

    // MARK: Races

    private func racesCard(_ races: [PFPlanWeekDoc.Race]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: races.count == 1 ? "The race" : "The \(races.count) races")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), spacing: 8, alignment: .top)],
                      alignment: .leading, spacing: 8) {
                ForEach(races.indices, id: \.self) { index in
                    raceTile(races[index], index: index)
                }
            }
            PFReviewReading530(key: "races", text: review.readings?.races)
        }
        .pfReviewCard530("races")
    }

    private func raceTile(_ race: PFPlanWeekDoc.Race, index: Int) -> some View {
        let sub = race.sub ?? ""
        let tone: Color = sub.contains("over") ? PFWeekColor529.red : sub.contains("inside") ? PFWeekColor529.teal : NoopLook.textTertiary
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(race.day ?? "") \u{00B7} \(race.name ?? "")")
                .font(LookFont.text(11.5, weight: .regular))
                .foregroundStyle(NoopLook.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(race.time ?? "")
                .font(LookFont.text(22, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
            Text(sub)
                .font(LookFont.text(11.5, weight: .semibold))
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NoopLook.row))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review530-race-\(index)")
    }

    // MARK: Stations

    private func stations(_ races: [PFWeekReviewDoc530.RaceLoss]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(races.indices, id: \.self) { index in
                let race = races[index]
                let losses = race.losses ?? []
                let top = losses.compactMap { $0.seconds }.max() ?? 1
                VStack(alignment: .leading, spacing: 8) {
                    PFWeekOverline529(text: "\(race.name ?? "Race") \u{00B7} where the time went, against \(race.against ?? "plan")")
                    PFHBars530(rows: losses.indices.map { row in
                        PFHBar530(id: row, label: losses[row].station ?? "", value: losses[row].seconds ?? 0,
                                  valueText: PFReviewFormat530.lost(seconds: losses[row].seconds ?? 0), color: PFWeekColor529.red)
                    }, scale: top, labelWidth: 120)
                    .accessibilityIdentifier("review530-bars-stations-\(index)")
                }
            }
            PFReviewReading530(key: "stations", text: review.readings?.stations)
        }
        .pfReviewCard530("stations")
    }
}
