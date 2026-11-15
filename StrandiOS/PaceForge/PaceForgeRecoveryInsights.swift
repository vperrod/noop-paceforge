#if os(iOS)
import SwiftUI
import StrandDesign

/// Journal > "Recovery insights": the existing "What affects your recovery" card (behaviour-impact.json: how the habits logged in the
/// journal line up with the next morning's scores, each source named and never merged) on a screen of its own. It builds no analysis
/// of its own; the card and its explainer are the ones Insights already shows.
struct PFRecoveryInsightsScreen: View {
    var body: some View {
        ScrollView {
            PFSnapshotHost(content: { snapshot in
                AnyView(Group {
                    if let impact = snapshot.behaviour {
                        PFBehaviourCard(impact: impact)
                    } else {
                        PFParagraph("PaceForge has not published what affects your recovery yet. It needs a few weeks of logged journal days.")
                            .accessibilityIdentifier("pf-recovery-insights-empty")
                    }
                })
            })
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Recovery insights")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pf-recovery-insights")
    }
}
#endif
