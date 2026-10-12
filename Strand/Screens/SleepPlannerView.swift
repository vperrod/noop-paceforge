import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Sleep Planner
//
// Tonight's sleep need broken into parts, a goal (Get by / Perform / Peak), and the bedtime that reaches it.
// NOOP's own: the baseline is the personal need the Rest score already uses, the debt is the 14-night ledger
// the Sleep tab shows, and the wake time is the one the wind-down reminder or the strap alarm already holds.
// The maths is `SleepPlanner` in StrandAnalytics; this file reads the repository and draws.

struct SleepPlannerView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    @State private var data: SleepPlannerData?
    @State private var preset = SleepPlannerStore.preset
    @State private var followsPlan = SleepPlannerStore.useForReminder

    private var alarmMinutes: Int? { behavior.smartAlarmEnabled ? behavior.smartAlarmMinutes : nil }
    private var loadKey: String { "\(repo.refreshSeq)|\(alarmMinutes ?? -1)" }

    var body: some View {
        ScreenScaffold(title: "Sleep planner",
                       subtitle: "Tonight's need, a goal, and the bedtime that reaches it.") {
            if let data {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    hero(data)
                    goalCard(data)
                    needCard(data)
                    bedtimeCard(data)
                    SleepPlannerAlarmCard(data: data, preset: preset)
                    reminderCard
                }
            } else {
                Text("Working out tonight").font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityIdentifier("sleep-planner-loading")
            }
        }
        .accessibilityIdentifier("sleep-planner")
        .task(id: loadKey) { await reload() }
    }

    private func reload() async {
        let loaded = await SleepPlannerLoader.load(repo: repo, alarmMinutes: alarmMinutes)
        guard !Task.isCancelled else { return }
        data = loaded
        SleepPlannerLoader.publish(loaded, preset: preset)
    }

    // MARK: Text helpers

    private func time(_ date: Date) -> String { AppClock.hourMinuteFormatter().string(from: date) }

    private func wakeSourceText(_ data: SleepPlannerData) -> String {
        switch data.wakeSource {
        case .windDown: return "the wake time of your wind-down reminder"
        case .alarm: return "your strap alarm's time"
        case .typical: return "your typical wake-up"
        case .fallback: return "a default of 07:00, since no wake time is set yet"
        }
    }

    private func latencyText(_ data: SleepPlannerData) -> String {
        data.latencyIsPersonal
            ? "about \(data.latencyMin) min to fall asleep, the median of your last \(data.latencyNights) nights"
            : "a default \(data.latencyMin) min to fall asleep, until \(SleepPlanner.minimumNights) nights show your own"
    }

    // MARK: Hero

    private func hero(_ data: SleepPlannerData) -> some View {
        let plan = data.plan(for: preset)
        return NoopCard(tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TONIGHT").strandOverline()
                Text(verbatim: "Bed by \(time(plan.bedtime))")
                    .font(StrandFont.number(34))
                    .foregroundStyle(StrandPalette.restColor)
                    .accessibilityIdentifier("sleep-planner-bedtime")
                Text(verbatim: "Asleep by \(time(plan.asleepBy)), up at \(time(data.wake))")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: "\(SleepPlanner.durationText(plan.targetSleepMin)) of sleep: \(preset.title), \(preset.percentText) of tonight's \(SleepPlanner.durationText(data.needMin))")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = data.calibration.note {
                    Text(verbatim: "\(note). Until then the plan runs on defaults where your own data is missing.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sleep-planner-calibration")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Goal presets

    private func goalCard(_ data: SleepPlannerData) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Sleep goal", overline: "How much of tonight's need")
            HStack(spacing: 8) {
                ForEach(SleepPlanner.Preset.allCases, id: \.self) { p in presetButton(p, data) }
            }
        }
    }

    private func presetButton(_ p: SleepPlanner.Preset, _ data: SleepPlannerData) -> some View {
        let selected = p == preset
        let target = SleepPlanner.targetSleepMin(needMin: data.needMin, preset: p)
        return Button {
            preset = p
            SleepPlannerStore.preset = p
            SleepPlannerLoader.publish(data, preset: p)
        } label: {
            VStack(spacing: 3) {
                Text(verbatim: p.title).font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: p.percentText).font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(verbatim: SleepPlanner.durationText(target)).font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? StrandPalette.accent.opacity(0.16) : StrandPalette.hairline.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? StrandPalette.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(p.title), \(p.percentText), \(SleepPlanner.durationText(target))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sleep-planner-preset-\(p.rawValue)")
    }

    // MARK: Need breakdown

    private func needCard(_ data: SleepPlannerData) -> some View {
        let b = data.breakdown
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack {
                SectionHeader("Tonight's need", overline: "Where it comes from")
                PlannerInfoButton(title: "Sleep need", tint: StrandPalette.restColor, sections: needInfo,
                                  calibration: data.calibration.note, identifier: "sleep-planner-need-info")
            }
            NoopCard(tint: StrandPalette.restColor) {
                VStack(alignment: .leading, spacing: 12) {
                    needRow("Your baseline", SleepPlanner.durationText(b.baselineMin),
                            "The personal need your Rest score uses", id: "baseline")
                    needRow("Yesterday's effort", SleepPlanner.signedDurationText(b.effortExtraMin),
                            effortCaption(data, scale: scale), id: "effort")
                    needRow("Sleep debt repayment", SleepPlanner.signedDurationText(b.debtRepaymentMin),
                            debtCaption(data), id: "debt")
                    needRow("Naps today", SleepPlanner.signedDurationText(-b.napCreditMin),
                            napCaption(data), id: "naps")
                    Divider().overlay(StrandPalette.hairline)
                    HStack {
                        Text("Tonight's need").font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Text(verbatim: SleepPlanner.durationText(b.tonightMin))
                            .font(StrandFont.number(22))
                            .foregroundStyle(StrandPalette.restColor)
                            .accessibilityIdentifier("sleep-planner-need-total")
                    }
                }
            }
        }
    }

    private func needRow(_ title: String, _ value: String, _ caption: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: caption).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(verbatim: value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleep-planner-need-\(id)")
    }

    private func effortCaption(_ data: SleepPlannerData, scale: EffortScale) -> String {
        guard let y = data.yesterdayEffort else { return "No Effort scored yesterday, so nothing is added" }
        guard let t = data.typicalEffort else {
            return "Needs \(SleepPlanner.minimumNights) days of Effort to compare yesterday with your usual"
        }
        return "Yesterday \(UnitFormatter.effortDisplay(y, scale: scale)) against your usual \(UnitFormatter.effortDisplay(t, scale: scale))"
    }

    private func debtCaption(_ data: SleepPlannerData) -> String {
        data.debtMin < 1
            ? "No debt over the last 14 nights"
            : "A quarter of your \(SleepPlanner.durationText(Int(data.debtMin.rounded()))) debt, at most 1 h a night"
    }

    private func napCaption(_ data: SleepPlannerData) -> String {
        data.napMin < 1
            ? "No nap today"
            : "\(SleepPlanner.durationText(Int(data.napMin.rounded()))) asleep in naps, at most 1 h counted"
    }

    private var needInfo: [PlannerInfoSection] {
        [
            PlannerInfoSection(
                heading: "The sum",
                body: "Tonight's need = your baseline + extra for yesterday's effort + debt repayment \u{2212} naps today. Each part is shown in minutes so you can see what moved it."),
            PlannerInfoSection(
                heading: "Your baseline",
                body: "The personal need the Rest score already measures against: your upper-quartile night over the recent weeks, never below 8 h and never above 9.5 h. Under \(SleepPlanner.minimumNights) nights of data it is 8 h."),
            PlannerInfoSection(
                heading: "Yesterday's effort",
                body: "Up to +\(Int(SleepPlanner.effortExtraMaxMin)) min. Nothing is added at or below your usual daily Effort (the mean of the 28 days before yesterday). The full \(Int(SleepPlanner.effortExtraMaxMin)) min applies once yesterday ran \(Int((SleepPlanner.effortFullAtRatio - 1) * 100)) % above your usual, scaled evenly in between: \(Int(SleepPlanner.effortExtraMaxMin)) \u{00D7} (yesterday \u{00F7} usual \u{2212} 1) \u{00F7} \(String(format: "%.1f", SleepPlanner.effortFullAtRatio - 1)). Yesterday is used, not today, so the figure stays steady through the evening. It needs \(SleepPlanner.minimumNights) days of Effort to have a usual to compare with."),
            PlannerInfoSection(
                heading: "Sleep debt repayment",
                body: "A quarter of your 14-night sleep debt (the ledger on the Sleep tab), at most \(Int(SleepPlanner.debtRepaymentMaxMin)) min a night, so a debt is paid down over several nights rather than in one."),
            PlannerInfoSection(
                heading: "Naps today",
                body: "Minutes actually asleep in today's naps come off, at most \(Int(SleepPlanner.napCreditMaxMin)) min. They are taken out of the debt above, so a nap is never counted twice."),
        ]
    }

    // MARK: Bedtime

    private func bedtimeCard(_ data: SleepPlannerData) -> some View {
        let rows = data.presetRows(selected: preset)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack {
                SectionHeader("Bedtime", overline: "What each goal costs")
                PlannerInfoButton(title: "Bedtime", tint: StrandPalette.restColor, sections: bedtimeInfo(data),
                                  calibration: data.calibration.note, identifier: "sleep-planner-bedtime-info")
            }
            NoopCard(tint: StrandPalette.restColor) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows, id: \.preset) { row in presetRow(row) }
                    Divider().overlay(StrandPalette.hairline)
                    Text(verbatim: "Up at \(time(data.wake)), from \(wakeSourceText(data)). Plans on \(latencyText(data)).")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func presetRow(_ row: SleepPlanner.PresetRow) -> some View {
        let selected = row.preset == preset
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.preset.title).font(StrandFont.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: shiftText(row, selected: selected)).font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "Bed \(time(row.plan.bedtime))").font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: SleepPlanner.durationText(row.plan.targetSleepMin)).font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleep-planner-row-\(row.preset.rawValue)")
    }

    /// What this goal costs or gains against the selected one.
    private func shiftText(_ row: SleepPlanner.PresetRow, selected: Bool) -> String {
        if selected { return "Your goal" }
        let sleep = SleepPlanner.signedDurationText(row.sleepShiftMin)
        let bed = SleepPlanner.durationText(abs(row.bedtimeShiftMin))
        return "\(sleep) sleep, bed \(bed) \(row.bedtimeShiftMin > 0 ? "later" : "earlier")"
    }

    private func bedtimeInfo(_ data: SleepPlannerData) -> [PlannerInfoSection] {
        let plan = data.plan(for: preset)
        return [
            PlannerInfoSection(
                heading: "The formula",
                body: "Bedtime = wake time \u{2212} sleep goal \u{2212} time to fall asleep. Tonight: \(time(data.wake)) \u{2212} \(SleepPlanner.durationText(plan.targetSleepMin)) \u{2212} \(data.latencyMin) min = \(time(plan.bedtime)). It counts real elapsed hours, so a night with a clock change still holds the sleep you planned."),
            PlannerInfoSection(
                heading: "Wake time",
                body: "Taken from \(wakeSourceText(data)). Your wind-down reminder's wake time comes first, then the strap alarm's, then your typical wake-up (the median of the last four weeks, from \(SleepPlanner.minimumNights) nights). Per-weekday wake times you set in Alarms are honoured."),
            PlannerInfoSection(
                heading: "Time to fall asleep",
                body: "The median gap between getting into bed and the first stretch of sleep in your last four weeks of main sleeps, kept between \(SleepPlanner.latencyFloorMin) and \(SleepPlanner.latencyCeilingMin) min. The strap cannot see the first few minutes of lying down, so treat it as a floor. Until \(SleepPlanner.minimumNights) nights show your own it is \(SleepPlanner.defaultLatencyMin) min. Now: \(latencyText(data))."),
            PlannerInfoSection(
                heading: "The three goals",
                body: "Get by is 70 % of tonight's need, Perform 85 % (the default) and Peak 100 %. The list shows what each costs or gains against your choice, in sleep and in bedtime."),
        ]
    }

    // MARK: Reminder

    private var reminderCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use the plan for my wind-down reminder").font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(WindDownNudge.isEnabled
                             ? "The reminder then lands before the planned bedtime instead of counting back over a fixed sleep need. It follows the plan as of the last time NOOP worked it out."
                             : "Turn on the wind-down reminder under Alarms first; this then sets when it fires.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $followsPlan)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Use the plan for my wind-down reminder")
                        .accessibilityIdentifier("sleep-planner-follow")
                }
            }
        }
        .onChangeCompat(of: followsPlan) { on in
            SleepPlannerStore.useForReminder = on
            if let data { SleepPlannerLoader.publish(data, preset: preset) }
            WindDownNudge.refreshSchedule()
        }
    }
}
