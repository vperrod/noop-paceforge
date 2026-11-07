#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Verdict line, biggest driver, calibration counter (Charge, Effort and Rest detail)
//
// One plain line for where the score stands, one sentence for what moved it most, and "Calibrating, 9 of 14 nights" while the
// Charge baseline is still building (`ScoreReadout`, a pure function in StrandAnalytics). Wording is NOOP's own and names its
// source. Nothing here changes a score, a band or a driver.

struct ScoreReadoutCard: View {
    let lines: ScoreReadout.Lines

    var body: some View {
        if !lines.isEmpty {
            VStack(spacing: 6) {
                if let verdict = lines.verdict {
                    Text(LocalizedStringKey(verdict))
                        .font(LookFont.text(17, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .accessibilityIdentifier("score-readout-verdict")
                }
                if let driver = lines.driver {
                    Text(driver)
                        .font(LookFont.text(14.5, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityIdentifier("score-readout-driver")
                }
                if let have = lines.calibrationHave, let need = lines.calibrationNeed {
                    Text(ChargeBreakdownFormat.calibrationProgress(banked: have, seed: need))
                        .font(LookFont.text(13, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .accessibilityIdentifier("score-readout-calibrating")
                }
                Text("NOOP, from your WHOOP strap")
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
