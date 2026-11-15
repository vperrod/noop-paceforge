import SwiftUI
import StrandDesign

// Blocks Today adds from the PaceForge snapshot, each its own host so Today's body does not observe the model: Weight vs goal (My Dashboard).
// Every block draws nothing when the data behind it is missing.

// MARK: - Weight vs goal

/// Today's "Weight vs goal": the scale's latest reading (dated, with its source) against the weight goal, the gap and the weekly trend.
/// One tap opens Health on the Body chip. Draws nothing without a weight goal, or while Hide numbers hides body weight.
struct PFTodayWeightGoalHost: View {
    var body: some View {
        PFSnapshotHost(drawsChrome: false, content: { snapshot in AnyView(PFTodayWeightGoalCard(progress: snapshot.bodyProgress)) })
    }
}

private struct PFTodayWeightGoalCard: View {
    let progress: PFBodyProgress?
    private let hiding = PFHiding()

    private var goal: PFProgressGoal? {
        guard let goal = progress?.goals.first(where: { $0.metric == "weight_kg" }), goal.target != nil else { return nil }
        return goal
    }

    var body: some View {
        if let goal, let target = goal.target, !hiding.hides(.body) {
            let reading = goal.lastReading ?? goal.current7d
            Button { PFDeepLink.open(.body) } label: {
                PFCard("Weight vs goal", icon: "scalemass") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(reading.map { value($0, goal.unit) } ?? "\u{2014}")
                                .font(LookFont.text(28, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                                .accessibilityIdentifier("today-weight-goal-current")
                            Text("goal \(value(target, goal.unit))")
                                .font(LookFont.text(13, weight: .medium))
                                .foregroundStyle(NoopLook.textSecondary)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NoopLook.textTertiary)
                                .accessibilityHidden(true)
                        }
                        if let reading { line(gapText(reading: reading, target: target, goal: goal)) }
                        if let trend = trendText(goal) { line(trend) }
                        Text(sourceText(goal))
                            .font(LookFont.text(11.5, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-weight-goal")
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(LookFont.text(13, weight: .medium))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func value(_ v: Double, _ unit: String) -> String {
        PFFormat.oneDecimal(v) + (unit.isEmpty ? "" : " \(unit)")
    }

    /// Distance to the target, in the direction the goal runs (down when the start was above it).
    private func gapText(reading: Double, target: Double, goal: PFProgressGoal) -> String {
        let goesDown = (goal.startValue ?? reading) >= target
        let toGo = goesDown ? reading - target : target - reading
        if toGo <= 0 { return "Target reached" }
        let by = goal.targetDate.map { " \u{00B7} by \(PFFormat.shortDate($0))" } ?? ""
        return "\(value(toGo, goal.unit)) to go\(by)"
    }

    /// "Trend 0.3 kg a week down (on track)", from PaceForge's own weekly rate.
    private func trendText(_ goal: PFProgressGoal) -> String? {
        guard let rate = goal.actualPerWeek, rate != 0 else { return nil }
        let word = rate < 0 ? "down" : "up"
        let status = goal.status == "insufficient_data" ? "" : " (\(PFFormat.words(goal.status)))"
        return "Trend \(value(abs(rate), goal.unit)) a week \(word)\(status)"
    }

    private func sourceText(_ goal: PFProgressGoal) -> String {
        let kind = goal.lastReading != nil ? "Last reading" : "7-day average"
        let date = progress?.latestReadingDate.map { " \(PFFormat.shortDate($0))" } ?? ""
        return "\(kind)\(date) \u{00B7} Hume scale, via PaceForge"
    }
}
