import SwiftUI
import StrandDesign

/// D8: the Effort target card shows both targets, each named. The strap's band is the card's own text; this is the other one, the target
/// PaceForge works out from Garmin, read from today's daily-intel.json. Draws nothing while that document is not from today or has no target.
struct PFEffortTargetGarmin529: View {
    @ObservedObject private var intel = PFDailyIntelStore.shared
    private let hiding = PFHiding()

    var body: some View {
        if let current = intel.intel, current.isCurrent(for: PFAPI.todayISO), let target = current.call?.effortTarget {
            VStack(alignment: .leading, spacing: 4) {
                Divider().overlay(StrandPalette.hairline)
                Text("GARMIN VIA PACEFORGE")
                    .font(StrandFont.overlineScaled(11))
                    .tracking(1.0)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text(hiding.text("Effort target \(target.rangeText)"))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("effort-target-garmin")
            }
        }
    }
}
