#if os(iOS)
import Foundation
import StrandAnalytics

// MARK: - Sleep Planner on PaceForge's sleep need
//
// PaceForge's daily-intel.json carries `sleep_need_tonight`: tonight's need as baseline + today's Effort + sleep debt
// minus naps, three goal tiers (Get by 70 %, Perform 85 %, Peak 100 %) and the time in bed each one asks for. The
// planner and the "Tonight's sleep" card draw that when the file is today's. The wake time set on the planner screen
// (UserDefaults `sleepPlanner.wakeMinutes`) still comes first: bedtime is then that wake time minus the tier's time in
// bed. Without one, the server's wake time and bedtime stand. Without the file, or with a need whose rows do not add
// up, the planner keeps NOOP's own numbers.

extension SleepPlannerData {

    /// This data with the need, the wake time and the time to fall asleep of `preset`'s tier taken from `need`.
    func applying(_ need: PFSleepNeed, preset: SleepPlanner.Preset, userWake: Int?, now: Date = Date(),
                  calendar: Calendar = .current) -> SleepPlannerData {
        guard need.rows.reduce(0, { $0 + $1.minutes }) == need.needMin,
              let night = need.nightPlan(tierID: preset.rawValue, userWake: userWake),
              let dates = night.dates(after: now, calendar: calendar) else { return self }
        func minutes(_ key: String) -> Int { need.rows.first { $0.key == key }?.minutes ?? 0 }
        var out = self
        out.breakdown = SleepPlanner.Breakdown(baselineMin: minutes("baseline"), effortExtraMin: minutes("effort"),
                                               debtRepaymentMin: minutes("debt"), napCreditMin: -minutes("naps"))
        out.calibration = .ready
        // Bedtime = wake - goal sleep - this, so it lands on the server's bedtime even where NOOP's rounding of the
        // goal differs from the server's by a minute.
        out.latencyMin = max(night.tier.timeInBedMin - SleepPlanner.targetSleepMin(needMin: need.needMin, preset: preset), 0)
        out.latencyIsPersonal = true
        out.wake = dates.wake
        out.wakeSource = night.usesPhoneWake ? .user : .typical
        out.intelNeed = need
        return out
    }
}
#endif
