import SwiftUI
import StrandDesign

// MARK: - Pace of aging (Health > Vitality)
//
// How fast Body Age has moved over the last 30 days, from the weekly Body Age series. The arithmetic is in
// PaceOfAging.swift (pure, unit-tested). With fewer than four weekly readings the card says how many it has
// instead of showing a number. A wellness trend from habits, not a clinical measure.

struct PaceOfAgingCard: View {
    /// The weekly Body Age series: (day, years).
    let series: [(day: String, value: Double)]
    let today: String

    private var outcome: PaceOfAging.Outcome { PaceOfAging.compute(series: series, today: today) }

    private var calibrationText: String? {
        if case .calibrating(let have, let need) = outcome { return PaceOfAging.calibrationLine(have: have, need: need) }
        return nil
    }

    var body: some View {
        NoopCard(tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Pace of aging").strandOverline()
                    Spacer()
                    PlannerInfoButton(title: "Pace of aging", tint: StrandPalette.chargeColor, sections: Self.info,
                                      calibration: calibrationText, identifier: "pace-of-aging-info")
                }
                switch outcome {
                case .ready(let reading):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: PaceOfAging.paceText(reading))
                            .font(StrandFont.number(34))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(verbatim: "years per year")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(verbatim: PaceOfAging.headline(reading)))
                    .accessibilityIdentifier("pace-of-aging-value")
                    Text(verbatim: PaceOfAging.changeLine(reading))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .accessibilityIdentifier("pace-of-aging-change")
                    if reading.isCapped {
                        Text(verbatim: "Shown at the edge of its range. A month of readings stretched to a year can swing a long way.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .calibrating:
                    Text(verbatim: calibrationText ?? "")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pace-of-aging-calibrating")
                }
                Text(verbatim: "A wellness trend from your habits, not a clinical measure of aging.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pace-of-aging-card")
    }

    private static let info: [PlannerInfoSection] = [
        PlannerInfoSection(heading: "What it is",
                           body: "How fast your Body Age has moved over the last 30 days, written as years of Body Age per calendar year. 1.0 means your Body Age is keeping step with the calendar. Under 1.0 it is falling behind it, so you are aging more slowly. Over 1.0 it is running ahead."),
        PlannerInfoSection(heading: "How it is worked out",
                           body: "A straight line is fitted through your weekly Body Age readings from the last 30 days. Its slope is the change in Body Age, shown over 30 days, and the pace is that slope for a year plus the one year a year always brings. It needs at least 4 weekly readings; with fewer it waits."),
        PlannerInfoSection(heading: "Good to know",
                           body: "A month of readings stretched to a year can swing a long way, so read the direction rather than the decimal. Body Age comes from your resting heart rate, HRV, sleep and steps against published population figures. It is a wellness estimate, not a clinical biological age."),
    ]
}
