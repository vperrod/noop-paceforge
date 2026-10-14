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
    #if os(iOS)
    @State private var plan: SleepPlanner.Plan?
    /// PaceForge's sleep need for tonight, when its file is today's (see SleepPlannerIntel.swift).
    @ObservedObject private var intelStore = PFDailyIntelStore.shared
    #endif

    private var alarmMinutes: Int? { behavior.smartAlarmEnabled ? behavior.smartAlarmMinutes : nil }
    private var loadKey: String {
        #if os(iOS)
        return "\(repo.refreshSeq)|\(alarmMinutes ?? -1)|\(intelStore.intel?.generatedAt ?? "")"
        #else
        return "\(repo.refreshSeq)|\(alarmMinutes ?? -1)"
        #endif
    }

    @ViewBuilder var body: some View {
        #if os(iOS)
        lookBody
        #else
        classicBody
        #endif
    }

    #if os(iOS)
    /// The dark look: tonight's sleep as one activity row (sleep pill with the target hours, bedtime and wake).
    private var lookBody: some View {
        let clock = AppClock.hourMinuteFormatter()
        let item = ActivityPillItem(
            id: "tonight", pillColor: NoopLook.rest, icon: "bed.double.fill",
            pillText: plan.map { LookFormat.hoursMinutes(minutes: $0.targetSleepMin) } ?? "\u{2013}",
            title: String(localized: "Tonight's sleep"),
            startText: plan.map { clock.string(from: $0.bedtime) }, endText: plan.map { clock.string(from: $0.wake) },
            barColor: NoopLook.rest)
        return NavigationLink(value: TabRoute.sleepPlanner) {
            ActivityPillRow(item)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary ?? "Sleep planner. Tonight's need, a goal and a bedtime")
        .accessibilityHint("Opens tonight's sleep need and bedtime")
        .accessibilityIdentifier("sleep-planner-entry")
        .task(id: loadKey) { await load() }
    }
    #endif

    private var classicBody: some View {
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
        #if os(iOS)
        await intelStore.refreshIfStale()
        #endif
        var data = await SleepPlannerLoader.load(repo: repo, alarmMinutes: alarmMinutes)
        guard !Task.isCancelled else { return }
        let preset = SleepPlannerStore.preset
        #if os(iOS)
        // The same numbers the planner screen draws: PaceForge's need and bedtime when it has them.
        if let need = intelStore.current?.sleepNeed {
            data = data.applying(need, preset: preset, userWake: SleepPlannerStore.wakeMinutes)
        }
        #endif
        let plan = data.plan(for: preset)
        summary = "Bed by \(AppClock.hourMinuteFormatter().string(from: plan.bedtime)) for \(SleepPlanner.durationText(plan.targetSleepMin)) of sleep"
        #if os(iOS)
        self.plan = plan
        #endif
        SleepPlannerLoader.publish(data, preset: preset)
    }
}
