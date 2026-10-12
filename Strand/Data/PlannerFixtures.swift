#if DEBUG
import Foundation
import StrandAnalytics

// MARK: - Effort target and Sleep Planner synthetic readings (DEBUG only)
//
// For simulator screenshots and UI tests, so every state can be captured with no strap and no history.
// Launch with `-EffortTargetFixture toGo | inRange | above | calibrating | noTarget` and/or
// `-SleepPlannerFixture ready | calibrating`. The readings are built through the real `EffortTarget` and
// `SleepPlanner` functions, so the screens under test run the same rules as the shipped ones. Every number
// here is invented; nothing is read from or written to the store.

enum PlannerFixture {

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.index(after: i) < args.endIndex else { return nil }
        return args[args.index(after: i)]
    }

    // MARK: Effort target

    static let effortReading: EffortTargetReading? = {
        guard let variant = value(after: "-EffortTargetFixture") else { return nil }
        // Stored 0-100 Effort; the band is the OPTIMAL 14-18 of 21 a green Charge earns.
        let band = EffortTarget.Band(whoopLow: 14, whoopHigh: 18)
        let steady = Array(repeating: 50.0, count: 42)
        let stepUp = Array(repeating: 50.0, count: 7) + Array(repeating: 100.0, count: 7)
        let tenDays = Array(repeating: 50.0, count: 10)

        let effort: Double?
        let recovery: Double?
        let loads: [Double]
        switch variant {
        case "inRange": effort = 75; recovery = 80; loads = steady
        case "above": effort = 95; recovery = 80; loads = stepUp
        case "calibrating": effort = 42; recovery = 80; loads = tenDays
        case "noTarget": effort = 42; recovery = nil; loads = steady
        default: effort = 42; recovery = 80; loads = steady   // toGo
        }
        return EffortTargetReading(
            progress: EffortTarget.progress(effort: effort, band: recovery == nil ? nil : band),
            training: EffortTarget.trainingState(recovery: recovery, load: TrainingLoadEngine.evaluateDense(loads)),
            recovery: recovery,
            dayKey: "2030-03-13")
    }()

    // MARK: Sleep Planner

    static var sleepData: SleepPlannerData? {
        guard let variant = value(after: "-SleepPlannerFixture") else { return nil }
        let calibrated = variant != "calibrating"
        let breakdown = SleepPlanner.breakdown(baselineMin: 480, yesterdayEffort: 60, typicalEffort: 40,
                                               debtMin: 100, napMin: 30)
        let wake = SleepPlanner.nextWake(baseMinutes: 7 * 60, after: Date(), calendar: .current)
            ?? Date().addingTimeInterval(8 * 3_600)
        return SleepPlannerData(
            breakdown: breakdown,
            calibration: calibrated ? .ready : SleepPlanner.calibration(nights: 3),
            latencyMin: calibrated ? 18 : SleepPlanner.defaultLatencyMin,
            latencyIsPersonal: calibrated, latencyNights: calibrated ? 12 : 0,
            wake: wake, wakeSource: calibrated ? .windDown : .fallback,
            yesterdayEffort: 60, typicalEffort: 40, debtMin: 100, napMin: 30)
    }
}
#endif
