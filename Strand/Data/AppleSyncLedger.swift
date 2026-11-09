import Foundation

/// What each Apple Health aggregate read of one sync pass did, so a failed read costs only its own metric.
///
/// The upserts write whole rows (`column = excluded.column`), so a read that failed and stood in as nil would
/// erase the stored value. Most metrics therefore still hold the whole pass back when one fails. Steps do not:
/// they are the one metric another source (the Garmin watch PaceForge mirrors in) can cover, so a failed
/// steps read is carried as its own state. The pass goes on, the stored step counts are written back
/// unchanged, and the next sync reads steps again. Foundation-only so Linux can run its tests.
struct AppleSyncLedger: Equatable {
    /// The label the bridge records the steps read under.
    static let stepsLabel = "stepCount"

    private(set) var failedLabels: [String] = []

    mutating func record(_ label: String, failed: Bool) {
        if failed { failedLabels.append(label) }
    }

    var stepsFailed: Bool { failedLabels.contains(Self.stepsLabel) }

    /// Failed reads that hold the whole write back: everything except steps.
    var blockingFailures: [String] { failedLabels.filter { $0 != Self.stepsLabel } }

    /// Every failed read, steps included, for the per-metric error record.
    var allFailures: [String] { failedLabels }

    /// The step count a day's row is written with. A failed read keeps the stored count; a good read
    /// replaces it with what Health says, including nothing.
    static func stepsForWrite(stepsFailed: Bool, fresh: Int?, stored: Int?) -> Int? {
        stepsFailed ? stored : fresh
    }
}
