import SwiftUI
import UserNotifications
import StrandDesign
import StrandAnalytics

// MARK: - "Wake me when I've slept enough"
//
// The honest version. A sideloaded iPhone app cannot watch sleep live while it is closed, and the strap's
// firmware alarm has to be set in advance, so this is an ESTIMATE, not detection: the strap alarm goes at the
// moment lights-out plus the usual time to fall asleep plus the sleep goal would be reached, and never later
// than the wake time the planner plans for (the latest wake). The screen says so in plain words. It arms a
// one-off alarm through the same call the regular strap alarm uses and leaves the regular alarm's settings
// alone (it is paused while this one is armed); cancelling, or the alarm going off, hands the strap back.

struct SleepPlannerAlarmCard: View {
    let data: SleepPlannerData
    let preset: SleepPlanner.Preset

    @EnvironmentObject private var model: AppModel
    // The stored alarm is the truth (it also lapses on its own once it has passed); the counter only makes
    // the card re-read it after arming, cancelling or reappearing.
    @State private var storeRevision = 0
    @State private var note: String?

    private static let backupId = "sleep-planner-alarm"

    private var plan: SleepPlanner.Plan { data.plan(for: preset) }

    private var armed: Date? {
        _ = storeRevision
        return SleepPlannerStore.armedAlarm
    }

    private func time(_ date: Date) -> String { AppClock.hourMinuteFormatter().string(from: date) }

    private func goalAlarm(lightsOut: Date) -> (alarm: Date, isCappedByLatestWake: Bool) {
        SleepPlanner.goalAlarm(lightsOut: lightsOut, latencyMin: data.latencyMin,
                               goalSleepMin: plan.targetSleepMin, latestWake: data.wake)
    }

    var body: some View {
        let atBedtime = goalAlarm(lightsOut: plan.bedtime)
        let fromNow = goalAlarm(lightsOut: Date())
        return NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ALARM MODE").strandOverline()
                    Text("Wake me when I've slept enough")
                        .font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                Text(verbatim: "NOOP cannot watch your sleep live while the app is closed, and the strap's alarm has to be set before you sleep. So this is an estimate: it sets the strap alarm for when your \(SleepPlanner.durationText(plan.targetSleepMin)) would be reached if you fall asleep about \(data.latencyMin) min after lights out, and never later than \(time(data.wake)). Fall asleep later or wake in the night and you will have slept less than the goal when it buzzes.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleep-planner-alarm-copy")

                if let armed {
                    HStack {
                        Image(systemName: "alarm.fill").foregroundStyle(StrandPalette.accent)
                            .accessibilityHidden(true)
                        Text(verbatim: "Armed for \(dayName(armed)) \(time(armed))")
                            .font(StrandFont.body.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    .accessibilityIdentifier("sleep-planner-alarm-armed")
                    Button { cancel() } label: { Text("Cancel and use my regular alarm") }
                        .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                        .accessibilityIdentifier("sleep-planner-alarm-cancel")
                } else {
                    Button { arm(atBedtime) } label: {
                        Text(verbatim: "Set for \(time(atBedtime.alarm)) (bed at \(time(plan.bedtime)))")
                    }
                    .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                    .accessibilityIdentifier("sleep-planner-alarm-set")
                    Button { arm(fromNow) } label: {
                        Text(verbatim: "I'm going to bed now: \(time(fromNow.alarm))")
                    }
                    .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                    .accessibilityIdentifier("sleep-planner-alarm-now")
                }
                if let note {
                    Text(verbatim: note).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("The strap buzz is silent. While this alarm is armed it holds the strap: your regular alarm is paused, and comes back after this one goes off or when you cancel it. Keep a backup alarm for anything you cannot miss.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("sleep-planner-alarm")
        .onAppear { storeRevision += 1 }
    }

    private func dayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func arm(_ result: (alarm: Date, isCappedByLatestWake: Bool)) {
        guard result.alarm > Date() else {
            note = "That time has already passed."
            return
        }
        model.ble.armStrapAlarm(at: result.alarm)
        scheduleBackup(at: result.alarm)
        SleepPlannerStore.armedAlarm = result.alarm
        storeRevision += 1
        note = result.isCappedByLatestWake
            ? "Capped at your wake time of \(time(data.wake)): at this bedtime the goal would not be reached before it."
            : nil
    }

    private func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.backupId])
        SleepPlannerStore.armedAlarm = nil
        storeRevision += 1
        note = nil
        // Hands the strap back to the regular alarm settings: re-armed from them, or disarmed if it is off.
        model.applySmartAlarm()
    }

    /// A one-off phone notification at the same moment, so a strap that is out of range does not leave the
    /// morning with no signal at all. Silent and Focus modes can still mute it.
    private func scheduleBackup(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.backupId])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Sleep goal reached")
        content.body = String(localized: "Your planned sleep is done. Time to wake up.")
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let id = Self.backupId
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}

/// The same card inside the Alarms screen, which is where the strap alarm and the wind-down reminder live.
/// Loads the plan itself, so the Alarms screen carries no planner state.
struct SleepPlannerAlarmEntry: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var behavior: BehaviorStore
    @State private var data: SleepPlannerData?

    private var alarmMinutes: Int? { behavior.smartAlarmEnabled ? behavior.smartAlarmMinutes : nil }
    private var loadKey: String { "\(repo.refreshSeq)|\(alarmMinutes ?? -1)" }

    var body: some View {
        Group {
            if let data { SleepPlannerAlarmCard(data: data, preset: SleepPlannerStore.preset) }
        }
        .task(id: loadKey) {
            let loaded = await SleepPlannerLoader.load(repo: repo, alarmMinutes: alarmMinutes)
            guard !Task.isCancelled else { return }
            data = loaded
        }
    }
}
