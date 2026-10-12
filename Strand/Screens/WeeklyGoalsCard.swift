import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Weekly goals (Today)
//
// A card under the Charge / Effort / Rest rings: the week's plan (a preset or a custom one) as two or three
// progress rings, counted Monday to Sunday from NOOP's own data. Tapping it opens the plan picker. The rules
// that turn a week into numbers are in WeeklyGoals.swift (pure, unit-tested); this file gathers the week from
// the store and draws it. The plan is kept on this device only.

// MARK: Loader

@MainActor
enum WeeklyGoalsLoader {
    struct Week {
        var days: [WeeklyGoalDay]
        var usualBedtime: Int?
    }

    private static var memo: (key: String, week: Week)?

    /// The current Monday-to-Sunday week, from the sleep sessions, daily rows and workouts already on the phone.
    /// Zone minutes read heart-rate samples per workout, so they are only worked out when the plan asks for them.
    static func load(repo: Repository, profile: ProfileStore, needsZones: Bool, now: Date = Date(),
                     calendar: Calendar = .current) async -> Week {
        let todayKey = Repository.localDayKey(now)
        let start = WeeklyGoalEngine.weekStart(containing: todayKey)
        let key = "\(repo.refreshSeq)|\(start)|\(needsZones)|\(WindDownNudge.isEnabled)|\(Int(now.timeIntervalSince1970 / 900))"
        if let memo, memo.key == key { return memo.week }

        let keys = WeeklyGoalEngine.weekDays(startingAt: start)
        let startDate = localDate(start, calendar: calendar) ?? calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate.addingTimeInterval(7 * 86_400)
        let usualFrom = startDate.addingTimeInterval(-14 * 86_400)

        let metrics = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let apple = Dictionary((await repo.appleDailyRows(days: 21)).map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })

        // Main sleeps (long enough not to be a nap), by the day they ended. Of several in one day the longest wins.
        var longest: [String: (length: Int, bedtime: Int)] = [:]
        var prior: [Int] = []
        for session in await repo.allSleepSessions(days: 40) {
            let length = session.endTs - session.effectiveStartTs
            guard length >= 3 * 3_600 else { continue }
            let bedtime = minuteOfDay(Date(timeIntervalSince1970: TimeInterval(session.effectiveStartTs)), calendar: calendar)
            let wakeKey = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(session.endTs)))
            if keys.contains(wakeKey) {
                if (longest[wakeKey]?.length ?? 0) < length { longest[wakeKey] = (length, bedtime) }
            } else if Date(timeIntervalSince1970: TimeInterval(session.endTs)) >= usualFrom,
                      Date(timeIntervalSince1970: TimeInterval(session.endTs)) < startDate {
                prior.append(bedtime)
            }
        }

        var zoneByDay: [String: Double] = [:]
        if needsZones {
            for row in await repo.workoutRows(days: 14) {
                let began = Date(timeIntervalSince1970: TimeInterval(row.startTs))
                guard began >= startDate, began < endDate else { continue }
                let minutes = await zone45Minutes(row, repo: repo, profile: profile)
                zoneByDay[Repository.localDayKey(began), default: 0] += minutes
            }
        }

        let days = keys.map { day -> WeeklyGoalDay in
            var out = WeeklyGoalDay(day: day)
            out.sleepMinutes = metrics[day]?.totalSleepMin
            out.bedtimeMinute = longest[day]?.bedtime
            out.steps = metrics[day]?.steps ?? apple[day]?.steps
            out.zone45Minutes = zoneByDay[day]
            if WindDownNudge.isEnabled, let weekday = WeeklyGoalEngine.weekday(of: day) {
                out.plannedBedtimeMinute = ((WindDownNudge.wakeMinutes(forWeekday: weekday) - WindDownNudge.sleepSpanMinutes) % 1_440 + 1_440) % 1_440
            }
            return out
        }
        // The usual bedtime comes from the fortnight before the week; a new user falls back on this week's nights.
        let usual = WeeklyGoalEngine.usualBedtime(prior.count >= 3 ? prior : days.compactMap(\.bedtimeMinute))
        let week = Week(days: days, usualBedtime: usual)
        memo = (key, week)
        return week
    }

    /// Minutes in zones 4 and 5 for one workout: the imported split when the row has one, else the strap's own
    /// heart rate, the same order the workout screen uses.
    private static func zone45Minutes(_ row: WorkoutRow, repo: Repository, profile: ProfileStore) async -> Double {
        let duration = (row.durationS ?? Double(row.endTs - row.startTs)) / 60.0
        if let percents = WorkoutZones.percents(row.zonesJSON), duration > 0 {
            return duration * (percents[3] + percents[4]) / 100.0
        }
        if let minutes = await repo.workoutZoneMinutes(from: row.startTs, to: row.endTs, zoneSet: profile.hrZoneSet,
                                                       source: row.source), minutes.count >= 5 {
            return minutes[3] + minutes[4]
        }
        return 0
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func localDate(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: Card

struct WeeklyGoalsCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var plan: WeeklyGoalPlan? = WeeklyGoalStore.load()
    @State private var progress: [WeeklyGoalProgress] = []
    @State private var windDownOn = WindDownNudge.isEnabled
    @State private var isShowingPlans = false

    private var loadKey: String {
        "\(repo.refreshSeq)|\(plan?.preset.rawValue ?? "-")|" + (plan?.targets.map { "\($0.metric.rawValue)\($0.target)" }.joined(separator: ",") ?? "")
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { isShowingPlans = true }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("weekly-goals-card")
            .task(id: loadKey) { await reload() }
            .sheet(isPresented: $isShowingPlans) {
                WeeklyGoalsSheet(current: plan) { newPlan in
                    plan = newPlan
                    WeeklyGoalStore.save(newPlan)
                }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { isShowingPlans = true } label: { header }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel(Text(verbatim: "Weekly goals"))
                .accessibilityHint(Text(verbatim: "Opens the plans for the week"))
                .accessibilityIdentifier("weekly-goals-open")
            if plan == nil {
                Text(verbatim: "Sleep deeper, Boost fitness, Feel better, or your own two or three targets.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !progress.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(progress) { item in
                        WeeklyGoalRing(progress: item, needsReminder: item.metric == .windDown && !windDownOn)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(NoopPanelSurface(tint: StrandPalette.accent, cornerRadius: 20))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "WEEKLY GOALS").font(StrandFont.overlineScaled(11)).tracking(1.0)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: plan.map { "\($0.preset.title) \u{00B7} resets Monday" } ?? "Pick a plan for the week")
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
        .contentShape(Rectangle())
    }

    private func reload() async {
        windDownOn = WindDownNudge.isEnabled
        guard let plan else { progress = []; return }
        let week = await WeeklyGoalsLoader.load(repo: repo, profile: profile,
                                                needsZones: plan.targets.contains { $0.metric == .zone45Minutes })
        guard !Task.isCancelled else { return }
        progress = WeeklyGoalEngine.progress(plan: plan, days: week.days, usualBedtime: week.usualBedtime)
    }
}

/// One target as a progress ring with its figure underneath.
struct WeeklyGoalRing: View {
    let progress: WeeklyGoalProgress
    var needsReminder = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(StrandPalette.accent.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(progress.fraction))
                    .stroke(StrandPalette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if progress.isMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StrandPalette.accent)
                } else {
                    Text(verbatim: String(Int(progress.value.rounded())))
                        .font(StrandFont.rounded(15))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
            .frame(width: 44, height: 44)
            Text(verbatim: progress.metric.title)
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(verbatim: needsReminder ? "Reminder is off" : progress.valueText)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: needsReminder ? "\(progress.metric.title): the wind-down reminder is off" : progress.accessibilityText))
        .accessibilityIdentifier("weekly-goal-ring-\(progress.metric.rawValue)")
    }
}

// MARK: Plan picker

struct WeeklyGoalsSheet: View {
    let current: WeeklyGoalPlan?
    let onSave: (WeeklyGoalPlan?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picks: [WeeklyGoalMetric: Int]
    @State private var isEditingCustom: Bool

    init(current: WeeklyGoalPlan?, onSave: @escaping (WeeklyGoalPlan?) -> Void) {
        self.current = current
        self.onSave = onSave
        let custom = current?.preset == .custom ? current?.targets ?? [] : []
        _picks = State(initialValue: Dictionary(custom.map { ($0.metric, $0.target) }, uniquingKeysWith: { first, _ in first }))
        _isEditingCustom = State(initialValue: current?.preset == .custom)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: "Pick a plan for the week. Each target is counted from your own data, Monday to Sunday, and starts again every Monday.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach([WeeklyGoalPreset.sleepDeeper, .boostFitness, .feelBetter]) { preset in
                        presetCard(preset)
                    }
                    customCard
                    if current != nil {
                        Button(role: .destructive) {
                            onSave(nil)
                            dismiss()
                        } label: {
                            Text(verbatim: "Clear weekly goals").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("weekly-goals-clear")
                    }
                }
                .padding(16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "Weekly goals"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(verbatim: "Done") }
                        .accessibilityIdentifier("weekly-goals-done")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly-goals-sheet")
    }

    private func presetCard(_ preset: WeeklyGoalPreset) -> some View {
        Button {
            onSave(.preset(preset))
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(verbatim: preset.title)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    if current?.preset == preset {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(StrandPalette.accent)
                    }
                }
                Text(verbatim: preset.summary)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(preset.targets) { target in
                    Text(verbatim: "\u{2022} \(target.target) \(target.metric.unit): \(target.metric.title.lowercased())")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(NoopPanelSurface(tint: StrandPalette.accent, cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("weekly-goals-preset-\(preset.rawValue)")
    }

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { isEditingCustom.toggle() } } label: {
                HStack {
                    Text(verbatim: WeeklyGoalPreset.custom.title)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    if current?.preset == .custom {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(StrandPalette.accent)
                    }
                    Image(systemName: isEditingCustom ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("weekly-goals-preset-custom")
            Text(verbatim: WeeklyGoalPreset.custom.summary)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if isEditingCustom {
                ForEach(WeeklyGoalMetric.allCases) { metric in
                    customRow(metric)
                }
                Button {
                    let chosen = WeeklyGoalMetric.allCases.compactMap { metric in
                        picks[metric].map { WeeklyGoalTarget(metric: metric, target: $0) }
                    }
                    onSave(.custom(chosen))
                    dismiss()
                } label: {
                    Text(verbatim: "Use this plan").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(picks.count < 2)
                .accessibilityIdentifier("weekly-goals-custom-save")
                if picks.count < 2 {
                    Text(verbatim: "Pick at least two targets, up to three.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .padding(14)
        .background(NoopPanelSurface(tint: StrandPalette.accent, cornerRadius: 18))
    }

    private func customRow(_ metric: WeeklyGoalMetric) -> some View {
        let isOn = picks[metric] != nil
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { picks[metric] != nil },
                set: { on in
                    if on { if picks.count < 3 { picks[metric] = metric.defaultTarget } } else { picks[metric] = nil }
                })) {
                Text(verbatim: metric.title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .disabled(!isOn && picks.count >= 3)
            .accessibilityIdentifier("weekly-goals-custom-\(metric.rawValue)")
            Text(verbatim: metric.detail)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let target = picks[metric] {
                Stepper(value: Binding(get: { target }, set: { picks[metric] = metric.clamped($0) }),
                        in: metric.targetRange, step: metric.targetStep) {
                    Text(verbatim: "\(target) \(metric.unit) a week")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
}
