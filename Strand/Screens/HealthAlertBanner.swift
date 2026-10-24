import SwiftUI
import StrandDesign
import StrandAnalytics
import Foundation

/// Overnight-pattern banner. Observes AppModel in isolation so the ~1 Hz HR stream
/// re-renders only this small view, not the whole screen. Renders nothing when there's no alert.
struct HealthAlertBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let alert = model.healthAlert {
            let copy = localizedHealthAlertCopy(alert)
            // A frosted, warning-tinted alert card (not a flat coloured bar) — prominent but on-brand.
            // The amber wash draws attention without implying a diagnosis or hard training rule.
            NoopCard(padding: 14, tint: StrandPalette.statusWarning) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.statusWarning)
                        .frame(width: 30, height: 30)
                        .background(StrandPalette.statusWarning.opacity(0.16), in: Circle())
                        .accessibilityHidden(true)
                    Text(copy)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(copy)
        }
    }
}

/// Home-facing rendering of the semantic illness result. Both Today variants share this banner,
/// so neither can accidentally expose the analytics engine's English notification copy.
func localizedHealthAlertCopy(_ alert: AppModel.HealthAlert) -> String {
    if alert.message == .raised {
        let formatter = ListFormatter()
        formatter.locale = AppLanguage.activeLocale
        let signals = formatter.string(from: alert.firedSignals) ?? alert.firedSignals.joined(separator: ", ")
        return String(localized: "Several overnight signals are outside your usual range: \(signals). No tracked confounder was logged. Check how you feel; if you also feel run-down, consider an easier session. These signals are not illness-specific and cannot identify a cause.")
    }
    if alert.message == .alreadyUnwellAgree {
        return String(localized: "You logged feeling unwell, and several overnight signals are outside your usual range. Consider rest or easy activity if that matches how you feel; these readings cannot identify a cause.")
    }
    if alert.message == .alreadyUnwell {
        return String(localized: "You logged feeling unwell. Consider rest or easy activity if that matches how you feel. The wearable estimate cannot identify a cause.")
    }
    // The publisher gates the banner to raised/already-unwell. Keep the impossible fallback localized
    // and semantic rather than leaking `Result.copy` if a future caller bypasses that gate.
    return String(localized: "Nothing notable. Your signals look like their normal range.")
}
