import Foundation
import Combine

/// The few `LiveState` fields the Today screen's small status views read, as one value.
///
/// `LiveState` publishes on every sync chunk, every heart-rate beat and every R-R packet, and an
/// `ObservableObject` wakes every observer on ANY of those. The Today leaves (header sync capsule, live
/// heart-rate card, battery and sync rows) read this instead, through `LiveSnapshotStore`, so they wake at
/// most once a second and only when one of these values really changed.
struct LiveSnapshot: Equatable {
    var connected = false
    var activeIsWhoop = true
    var heartRate: Int?
    var batteryPct: Double?
    var charging: Bool?
    var ouraBatteryPct: Int?
    var ringCharging = false
    var backfilling = false
    var syncChunks = 0
    var lastSyncedAt: TimeInterval?
    var pagesBehindAtConnect: Int?
    /// `LiveState.batteryEstimate`'s remaining hours, or nil before a discharge slope exists.
    var estimateHoursRemaining: Double?

    @MainActor
    init(_ live: LiveState) {
        connected = live.connected
        activeIsWhoop = live.activeIsWhoop
        heartRate = live.heartRate
        batteryPct = live.batteryPct
        charging = live.charging
        ouraBatteryPct = live.ouraBatteryPct
        ringCharging = live.ouraWearState == .charging
        backfilling = live.backfilling
        syncChunks = live.syncChunksThisSession
        lastSyncedAt = live.lastSyncedAt
        pagesBehindAtConnect = live.pagesBehindAtConnect
        estimateHoursRemaining = live.batteryEstimate?.hoursRemaining
    }

    init() {}
}

/// Republishes `LiveSnapshot` at most once a second, and only when it differs from the last one.
///
/// The first change after a quiet spell goes out at once (a connect or a battery reading is not delayed);
/// a burst is held to one update per `interval`, with the last state of the burst delivered when the
/// interval ends. The hop to the main queue comes first because `objectWillChange` fires BEFORE the value
/// lands: the snapshot is read one turn later, when it is current.
@MainActor
final class LiveSnapshotStore: ObservableObject {
    static let shared = LiveSnapshotStore()

    @Published private(set) var snapshot = LiveSnapshot()
    private var subscription: AnyCancellable?

    private init() {}

    /// Called once from `AppModel.init`, right after the `LiveState` exists.
    func attach(to live: LiveState, interval: TimeInterval = 1) {
        snapshot = LiveSnapshot(live)
        subscription = live.objectWillChange
            .receive(on: DispatchQueue.main)
            .throttle(for: .seconds(interval), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self, weak live] _ in
                guard let self, let live else { return }
                let next = LiveSnapshot(live)
                if next != self.snapshot { self.snapshot = next }
            }
    }
}
