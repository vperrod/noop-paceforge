import SwiftUI
import WidgetKit
import StrandDesign

/// Debug-only: draws the PaceForge widget faces at widget sizes inside the app so the simulator run can
/// screenshot them (`-PaceForgeFixture -PaceForgeWidgetGallery`). Same views the extension renders.
struct PFWidgetGallery: View {
    let snapshot: PFSnapshot

    var body: some View {
        let s = PFSummaryWriter.make(from: snapshot).fillingSampleGaps()
        VStack(alignment: .leading, spacing: 18) {
            Text("Widget gallery")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityIdentifier("pf-widget-gallery")

            caption("PaceForge Today, large")
            card(height: 372) { PFTodayWidgetFace(summary: s, stale: false, family: .systemLarge) }

            caption("PaceForge Today, large, race week")
            card(height: 372) {
                PFTodayWidgetFace(summary: changed(s) {
                    $0.raceWeek = PFSummary.RaceWeek(title: "Synthetic race-week 10K",
                                                     line: "Taper \u{00B7} 5 days to go \u{00B7} volume 60 %")
                }, stale: false, family: .systemLarge)
            }
            .accessibilityIdentifier("pf-widget-race-week")

            caption("PaceForge Today, medium")
            card(height: 160) { PFTodayWidgetFace(summary: s, stale: false, family: .systemMedium) }

            caption("PaceForge session, small and race countdown, small")
            HStack(spacing: 12) {
                card(height: 160) { PFSessionWidgetFace(summary: s, stale: false, family: .systemSmall) }
                card(height: 160) { PFRaceWidgetFace(summary: s, stale: false, family: .systemSmall) }
            }

            caption("PaceForge session, medium")
            card(height: 160) { PFSessionWidgetFace(summary: s, stale: false, family: .systemMedium) }

            caption("PaceForge week, medium")
            card(height: 160) { PFWeekWidgetFace(summary: s, stale: false) }

            caption("PaceForge sleep and HRV, medium")
            card(height: 160) { PFSleepHrvWidgetFace(summary: s, stale: false) }

            caption("PaceForge training load, small and body score, small")
            HStack(spacing: 12) {
                card(height: 160) { PFLoadWidgetFace(summary: s, stale: false, family: .systemSmall) }
                card(height: 160) { PFBodyWidgetFace(summary: s, stale: false) }
            }

            caption("PaceForge body, hidden by the privacy setting")
            HStack(spacing: 12) {
                card(height: 160) { PFBodyWidgetFace(summary: changed(s) { $0.hideBody = true }, stale: false) }
                    .accessibilityIdentifier("pf-widget-body-hidden")
                Spacer(minLength: 0)
            }

            caption("PaceForge heart recovery, small")
            HStack(spacing: 12) {
                card(height: 160) { PFHeartRecoveryWidgetFace(summary: s, family: .systemSmall) }
                Spacer(minLength: 0)
            }

            caption("My Day, medium")
            card(height: 160) { MyDayWidgetFace(summary: .sample, stale: false) }
                .accessibilityIdentifier("myday-widget-gallery")

            caption("My Day, no recent file")
            card(height: 110) { MyDayWidgetFace(summary: nil, stale: true) }

            caption("Effort target, small: in progress and stale")
            HStack(spacing: 12) {
                card(height: 160) { EffortTargetWidgetFace(snapshot: .effortTargetSample, stale: false, family: .systemSmall) }
                    .accessibilityIdentifier("effort-target-widget-gallery")
                card(height: 160) { EffortTargetWidgetFace(snapshot: nil, stale: true, family: .systemSmall) }
            }

            caption("Stale or missing file")
            card(height: 110) { PFTodayWidgetFace(summary: s, stale: true, family: .systemMedium) }

            caption("Lock Screen: inline, rectangular, recovery, strain, race, load, heart recovery, effort target")
            VStack(alignment: .leading, spacing: 12) {
                PFSessionWidgetFace(summary: s, stale: false, family: .accessoryInline)
                    .font(.footnote)
                PFSessionWidgetFace(summary: s, stale: false, family: .accessoryRectangular)
                    .frame(width: 170, height: 62, alignment: .leading)
                HStack(spacing: 14) {
                    PFGaugeWidgetFace(kind: .recovery, summary: s, stale: false).frame(width: 64, height: 64)
                    PFGaugeWidgetFace(kind: .strain, summary: s, stale: false).frame(width: 64, height: 64)
                    PFRaceWidgetFace(summary: s, stale: false, family: .accessoryCircular).frame(width: 64, height: 64)
                    PFLoadWidgetFace(summary: s, stale: false, family: .accessoryCircular).frame(width: 64, height: 64)
                    PFHeartRecoveryWidgetFace(summary: s, family: .accessoryCircular).frame(width: 64, height: 64)
                    EffortTargetWidgetFace(snapshot: .effortTargetSample, stale: false, family: .accessoryCircular)
                        .frame(width: 64, height: 64)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.82)))
            .environment(\.colorScheme, .dark)
        }
    }

    /// The summary with one change, for a face's second state.
    private func changed(_ summary: PFSummary, _ change: (inout PFSummary) -> Void) -> PFSummary {
        var copy = summary
        change(&copy)
        return copy
    }

    private func caption(_ text: String) -> some View {
        Text(text).strandOverline()
    }

    private func card<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(StrandPalette.surfaceBase))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(StrandPalette.hairline, lineWidth: 1))
    }
}

