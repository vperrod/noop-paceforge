import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Sleep Planner entry (Today and Sleep)
//
// A one-line card that opens the planner and says tonight's bedtime. It pushes a `TabRoute` value (not a
// closure destination) so a re-tap of the tab pops back to the root (#198), like the My Day card. Loading it
// also tells the wind-down reminder what the plan is, so a reminder that follows the plan stays current
// without the planner screen being opened.

struct SleepPlannerEntryCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var behavior: BehaviorStore
    @State private var summary: String?

    private var alarmMinutes: Int? { behavior.smartAlarmEnabled ? behavior.smartAlarmMinutes : nil }
    private var loadKey: String { "\(repo.refreshSeq)|\(alarmMinutes ?? -1)" }

    var body: some View {
        NavigationLink(value: TabRoute.sleepPlanner) {
            HStack(spacing: 12) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StrandPalette.restColor)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SLEEP PLANNER").font(StrandFont.overlineScaled(11)).tracking(1.0)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: summary ?? "Tonight's need, a goal and a bedtime")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(NoopPanelSurface(tint: StrandPalette.restColor, cornerRadius: 20))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel("Sleep planner")
        .accessibilityHint("Opens tonight's sleep need and bedtime")
        .accessibilityIdentifier("sleep-planner-entry")
        .task(id: loadKey) { await load() }
    }

    private func load() async {
        let data = await SleepPlannerLoader.load(repo: repo, alarmMinutes: alarmMinutes)
        guard !Task.isCancelled else { return }
        let preset = SleepPlannerStore.preset
        let plan = data.plan(for: preset)
        summary = "Bed by \(AppClock.hourMinuteFormatter().string(from: plan.bedtime)) for \(SleepPlanner.durationText(plan.targetSleepMin)) of sleep"
        SleepPlannerLoader.publish(data, preset: preset)
    }
}
