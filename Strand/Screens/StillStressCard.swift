import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - While you were still (Stress screen)
//
// The daytime stress proxy read only from five-minute windows when the wrist was still, and the minutes of those that
// were restorative (`StillStress`, a pure function in StrandAnalytics). Additive: it sits under the existing timeline
// and changes none of its numbers or the Stress score.

struct StillStressCard: View {
    let result: StillStress.Result

    private var restorativeNote: LocalizedStringKey {
        if result.restorativeMinutes != nil {
            return "Restorative minutes are still minutes when your heart rate was at or below your usual calm level of recent days."
        }
        return "Restorative minutes appear once there are 5 earlier days to compare with. Days so far: \(result.referenceDays)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("While you were still", overline: "Intraday")
            NoopCard(tint: StressRamp.calm) {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    HStack(alignment: .top, spacing: NoopMetrics.gap) {
                        StillFigure(title: "Still time", minutes: result.stillMinutes)
                        StillFigure(title: "Restorative minutes", minutes: result.restorativeMinutes)
                    }
                    DaytimeLoadLine(hours: result.hourly)
                    Text("Only moments when your wrist was still, so walking and workouts are not mistaken for stress. The line is the same 0-3 proxy as above, from heart rate only.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(restorativeNote)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct StillFigure: View {
    let title: LocalizedStringKey
    let minutes: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).strandOverline()
            if let minutes {
                Text("\(minutes) min")
                    .font(StrandFont.number(26))
                    .foregroundStyle(StrandPalette.textPrimary)
            } else {
                Text("\u{2013}")
                    .font(StrandFont.number(26))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The calm level of each earlier day, kept on the phone so restorative minutes have something personal to compare with.
/// One small dictionary, trimmed to a month by `StillStress.recordingCalm`.
enum StillStressHistory {
    static let defaultsKey = "noop.stress.stillCalmHR"

    static func read() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
    }

    static func write(_ history: [String: Double]) {
        UserDefaults.standard.set(history, forKey: defaultsKey)
    }
}
