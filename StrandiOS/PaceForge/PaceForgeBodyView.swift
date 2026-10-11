import SwiftUI
import Charts
import StrandDesign

/// PaceForge "Body": the latest Hume readings, the weight trend and the goals.
struct PFBodyView: View {
    let snapshot: PFSnapshot

    private var body_: PFBody { snapshot.body }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            readingsCard
            trendCard
            goalsCard
        }
    }

    // MARK: Latest readings

    private var readingsCard: some View {
        let l = body_.latest
        return PFCard(title: "Latest reading", icon: "scalemass", trailing: {
            Text(PFFormat.dayTitle(body_.date)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 16) {
                tile("Weight", l.weightKg, "kg", 1)
                tile("Body fat", l.bodyFatPct, "%", 1)
                tile("Muscle mass", l.muscleMassKg, "kg", 1)
                tile("Body water", l.totalBodyWaterPct, "%", 1)
                tile("Visceral fat", l.visceralFatIndex, nil, 0)
                tile("Metabolic age", l.metabolicAge, "yrs", 0)
            }
        }
    }

    @ViewBuilder private func tile(_ label: String, _ value: Double?, _ unit: String?, _ decimals: Int) -> some View {
        if let value {
            PFFigure(value: String(format: "%.\(decimals)f", value), unit: unit, label: label)
        }
    }

    // MARK: Weight trend

    private var trendCard: some View {
        let points = body_.series
        let weights = points.map(\.weightKg)
        let lo = (weights.min() ?? 0) - 1, hi = (weights.max() ?? 1) + 1
        return PFCard("Weight trend", icon: "chart.line.uptrend.xyaxis") {
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("Date", PFFormat.date(p.date)), y: .value("Weight", p.weightKg))
                        .foregroundStyle(StrandPalette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.6))
                    PointMark(x: .value("Date", PFFormat.date(p.date)), y: .value("Weight", p.weightKg))
                        .foregroundStyle(StrandPalette.accent)
                        .symbolSize(60)
                }
                if let goal = weightGoal {
                    RuleMark(y: .value("Goal", goal.target))
                        .foregroundStyle(PFColor.positive.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYScale(domain: min(lo, weightGoal?.target ?? lo)...hi)
            .chartXAxis {
                AxisMarks(values: points.map { PFFormat.date($0.date) }) { _ in
                    AxisGridLine().foregroundStyle(StrandPalette.hairline)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(StrandPalette.hairline)
                    AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(height: 200)
            .accessibilityIdentifier("pf-weight-chart")
        }
    }

    private var weightGoal: PFBodyGoal? { body_.goals?.first { $0.unit == "kg" } }

    // MARK: Goals

    @ViewBuilder private var goalsCard: some View {
        if let goals = body_.goals, !goals.isEmpty {
            PFCard("Goals", icon: "target") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(goals) { PFGoalRow(goal: $0) }
                }
            }
        }
    }
}

private struct PFGoalRow: View {
    let goal: PFBodyGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.label)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text("target \(format(goal.target)) \(goal.unit)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    Capsule()
                        .fill(PFColor.positive)
                        .frame(width: max(8, proxy.size.width * CGFloat(min(max(goal.progress, 0), 1))))
                }
            }
            .frame(height: 8)
            Text("Now \(format(goal.current)) \(goal.unit) \u{00B7} \(format(abs(goal.remaining))) \(goal.unit) to go")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func format(_ v: Double) -> String { String(format: "%.\(goal.dp > 1 ? 1 : goal.dp)f", v) }
}
