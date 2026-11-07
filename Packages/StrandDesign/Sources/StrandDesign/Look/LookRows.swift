#if !os(watchOS)
import SwiftUI

// MARK: - Today vs. 30 days rows, three-step rows
//
// The rows under a detail dial. Each row is an icon, a caps name and a value; a comparison row adds the
// triangle and the 30-day baseline, a three-step row adds the Poor / Sufficient / Optimal bar.

/// One "today vs. last 30 days" row.
public struct LookCompareRow: Identifiable, Equatable {
    public let id: String
    public var icon: String
    public var label: String
    public var valueText: String
    public var baselineText: String?
    public var mark: LookTodayMark?

    public init(id: String, icon: String, label: String, valueText: String, baselineText: String? = nil,
                mark: LookTodayMark? = nil) {
        self.id = id
        self.icon = icon
        self.label = label
        self.valueText = valueText
        self.baselineText = baselineText
        self.mark = mark
    }
}

/// The notched card of comparison rows with the legend strip at its foot.
public struct TodayVs30Rows: View {
    public var rows: [LookCompareRow]
    public var showsLegend: Bool

    public init(rows: [LookCompareRow], showsLegend: Bool = true) {
        self.rows = rows
        self.showsLegend = showsLegend
    }

    public var body: some View {
        LookNotchCard {
            ForEach(rows) { row in
                LookRowFrame(icon: row.icon, label: row.label) { value(row) }
                if row.id != rows.last?.id {
                    Rectangle().fill(NoopLook.divider).frame(height: 1)
                }
            }
            if showsLegend { LookLegend() }
        }
    }

    private func value(_ row: LookCompareRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(row.valueText)
                .font(LookFont.numeral(25))
                .foregroundStyle(NoopLook.textPrimary)
            if let mark = row.mark {
                LookTriangleMark(mark).alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 3 }
            }
            if let baseline = row.baselineText {
                Text(baseline)
                    .font(LookFont.numeralRegular(13))
                    .foregroundStyle(NoopLook.textTertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(row))
    }

    private func accessibilityText(_ row: LookCompareRow) -> String {
        var text = "\(row.label) \(row.valueText)"
        if let baseline = row.baselineText { text += ", last 30 days \(baseline)" }
        if let mark = row.mark {
            let direction = mark.pointsUp ? "higher" : "lower"
            let tone = mark.tone == .favourable ? "better" : (mark.tone == .unfavourable ? "worse" : "different")
            text += ", \(direction) than usual, \(tone)"
        }
        return text
    }
}

/// A Poor / Sufficient / Optimal row: three short segments with the active one lit in its step colour.
public struct ThreeStepRow: View {
    public var icon: String
    public var label: String
    public var step: LookStep
    public var valueText: String

    public init(icon: String, label: String, step: LookStep, valueText: String) {
        self.icon = icon
        self.label = label
        self.step = step
        self.valueText = valueText
    }

    public var body: some View {
        LookRowFrame(icon: icon, label: label) {
            HStack(spacing: 14) {
                HStack(spacing: 3) {
                    ForEach(LookStep.allCases, id: \.rawValue) { s in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(s == step ? NoopLook.color(for: step) : NoopLook.track)
                            .frame(height: 4)
                    }
                }
                .frame(width: 62)
                Text(valueText)
                    .font(LookFont.numeral(25))
                    .foregroundStyle(NoopLook.textPrimary)
                    .frame(minWidth: 58, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(valueText), \(stepName)")
    }

    private var stepName: String {
        switch step {
        case .poor: return "poor"
        case .sufficient: return "sufficient"
        case .optimal: return "optimal"
        }
    }
}

/// The notched card for a list of three-step rows with the Poor / Sufficient / Optimal legend under it.
public struct ThreeStepRows: View {
    public var rows: [ThreeStepItem]

    public struct ThreeStepItem: Identifiable, Equatable {
        public let id: String
        public var icon: String
        public var label: String
        public var step: LookStep
        public var valueText: String

        public init(id: String, icon: String, label: String, step: LookStep, valueText: String) {
            self.id = id
            self.icon = icon
            self.label = label
            self.step = step
            self.valueText = valueText
        }
    }

    public init(rows: [ThreeStepItem]) { self.rows = rows }

    public var body: some View {
        LookNotchCard {
            ForEach(rows) { item in
                ThreeStepRow(icon: item.icon, label: item.label, step: item.step, valueText: item.valueText)
                if item.id != rows.last?.id {
                    Rectangle().fill(NoopLook.divider).frame(height: 1)
                }
            }
            LookStepLegend()
        }
    }
}

/// "Poor  Sufficient  Optimal" with a coloured dash before each.
public struct LookStepLegend: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 14) {
            ForEach(LookStep.allCases, id: \.rawValue) { s in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(NoopLook.color(for: s))
                        .frame(width: 12, height: 3)
                    Text(name(s))
                        .font(LookFont.text(13, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(NoopLook.cardDeep))
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func name(_ s: LookStep) -> String {
        switch s {
        case .poor: return "Poor"
        case .sufficient: return "Sufficient"
        case .optimal: return "Optimal"
        }
    }
}

#if DEBUG
#Preview("TodayVs30Rows / ThreeStepRows") {
    VStack(spacing: 22) {
        TodayVs30Rows(rows: [
            LookCompareRow(id: "hrv", icon: "waveform.path.ecg", label: "Heart rate variability", valueText: "43",
                           baselineText: "46", mark: LookCompare.mark(today: 43, baseline: 46, higherIsBetter: true)),
            LookCompareRow(id: "rhr", icon: "heart", label: "Resting heart rate", valueText: "59", baselineText: "60",
                           mark: LookCompare.mark(today: 59, baseline: 60, higherIsBetter: false)),
            LookCompareRow(id: "resp", icon: "lungs", label: "Respiratory rate", valueText: "16.1", baselineText: "15.7",
                           mark: LookCompare.mark(today: 16.1, baseline: 15.7, decimals: 1, higherIsBetter: false)),
            LookCompareRow(id: "rest", icon: "moon", label: "Rest", valueText: "92%", baselineText: "87%",
                           mark: LookCompare.mark(today: 92, baseline: 87, higherIsBetter: true)),
        ])
        ThreeStepRows(rows: [
            .init(id: "hours", icon: "moon", label: "Hours vs. needed", step: .optimal, valueText: "100%"),
            .init(id: "cons", icon: "calendar", label: "Sleep consistency", step: .sufficient, valueText: "80%"),
            .init(id: "eff", icon: "bed.double", label: "Sleep efficiency", step: .poor, valueText: "71%"),
        ])
    }
    .padding(16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
