import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - My Day graph (Today)
//
// The day's 24 h strip (heart rate, sleep, workouts, the plan, the overlays switched on in My Day) sits on
// Today directly under the rings, so the day reads at a glance. A tap opens the full My Day screen; the strip
// itself does not scrub here because Today owns the horizontal day swipe. It reads the same timeline as My Day
// but has no side effects (no walk auto-save).

struct MyDayTodayCard: View {
    let day: Date

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    @AppStorage("noop.myday.showStress") private var showStress = false
    @AppStorage("noop.myday.showSteps") private var showSteps = false
    @AppStorage("noop.myday.showEnergy") private var showEnergy = false
    @AppStorage("noop.myday.showGarminStress") private var showGarminStress = false

    @State private var loaded: DayTimelineLoader.Loaded?

    private var loadKey: String {
        "\(Int(day.timeIntervalSince1970))|\(repo.refreshSeq)|\(showStress)"
    }

    var body: some View {
        NavigationLink(value: TabRoute.myDay) {
            NoopCard(tint: StrandPalette.metricRose) {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    HStack {
                        Text("MY DAY").font(StrandFont.overlineScaled(11)).tracking(1.0)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }
                    if let timeline = loaded?.timeline {
                        MyDayStrip(timeline: timeline, showStress: showStress, showSteps: showSteps,
                                   showEnergy: showEnergy, showGarminStress: showGarminStress,
                                   scrubDate: .constant(nil))
                            .allowsHitTesting(false)
                    } else {
                        // Same height as the strip, so the card does not jump when the day arrives.
                        Color.clear.frame(height: MyDayStrip.totalHeight)
                    }
                }
            }
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel("My Day")
        .accessibilityHint("Opens the timeline of the day")
        .accessibilityIdentifier("today-daygraph")
        .task(id: loadKey) { await reload() }
    }

    private func reload() async {
        let options = DayTimelineLoader.Options(includeStress: showStress, segmentProfile: profile.segmentProfile)
        let result = await DayTimelineLoader.load(repo: repo, day: day, options: options)
        guard !Task.isCancelled else { return }
        loaded = result
    }
}
