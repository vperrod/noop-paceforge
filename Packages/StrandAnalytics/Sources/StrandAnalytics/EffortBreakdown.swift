import Foundation
import WhoopProtocol

// EffortBreakdown.swift — WHY an Effort number is what it is.
//
// The ring shows one number and nothing about what built it. This returns the same inputs and
// intermediate quantities `StrainScorer.strain` works from (reserve, zone minutes, TRIMP) plus the
// stretches of heart rate that actually counted, so a screen can explain a low or surprising score.
// It computes nothing of its own: the gate, durations, TRIMP and log map are the scorer's own functions.

/// One unbroken run of heart rate that counted towards Effort.
public struct EffortStretch: Equatable, Sendable {
    public let startTs: Int
    public let endTs: Int
    /// Credited minutes (each reading is credited at most `StrainScorer.maxSampleGapMin`).
    public let minutes: Double
    public let peakBpm: Int

    public init(startTs: Int, endTs: Int, minutes: Double, peakBpm: Int) {
        self.startTs = startTs; self.endTs = endTs; self.minutes = minutes; self.peakBpm = peakBpm
    }
}

public struct EffortBreakdown: Equatable, Sendable {
    public let sampleCount: Int
    /// First and last reading in the window, nil when there are none.
    public let firstTs: Int?
    public let lastTs: Int?
    /// Wall-clock span of the readings, seconds.
    public let spanSeconds: Int
    /// True when `StrainScorer.strain` would have scored this window rather than refusing it.
    public let enoughData: Bool
    public let hrMax: Double
    public let restingHR: Double
    public let reserve: Double
    public let method: StrainScorer.Method
    /// Share of the reserve above which a reading counts: 0.5 for Edwards, the sedentary floor for Banister.
    public let thresholdFraction: Double
    public let thresholdBpm: Double
    /// nil when the window was refused (not enough data, or HRmax <= resting HR).
    public let trimp: Double?
    public let effort: Double?
    /// Minutes in each Edwards zone, `[0]` below zone 1, `[1...5]` zones 1 to 5. nil when refused.
    public let zoneMinutes: [Double]?
    /// Credited minutes at or above `thresholdBpm`.
    public let countedMinutes: Double
    /// Counted runs in time order.
    public let stretches: [EffortStretch]

    /// The longest counted stretches first, ties broken by the earlier start.
    public func topStretches(_ limit: Int) -> [EffortStretch] {
        let ranked = stretches.sorted { ($0.minutes, -$0.startTs) > ($1.minutes, -$1.startTs) }
        return Array(ranked.prefix(max(0, limit)))
    }
}

extension StrainScorer {

    /// Explain an Effort score: the same inputs `strain` takes, the intermediate quantities it computes,
    /// and the stretches that counted. `hr` must be time-ordered, as it is for `strain`.
    public static func breakdown(_ hr: [HRSample],
                                 maxHR: Double? = nil,
                                 restingHR: Double = defaultRestingHR,
                                 method: Method = .edwards,
                                 sex: String = "male") -> EffortBreakdown {
        let effMax = maxHR ?? Double(defaultMaxHR())
        let reserve = effMax - restingHR
        let fraction = method == .edwards ? 0.5 : banisterSedentaryHRR
        let enough = hasEnoughData(hr)
        let tss = hr.map { $0.ts }
        let first = tss.min()
        let last = tss.max()
        var span = 0
        if let first, let last { span = last - first }

        func refused() -> EffortBreakdown {
            EffortBreakdown(sampleCount: hr.count, firstTs: first, lastTs: last, spanSeconds: span,
                            enoughData: enough, hrMax: effMax, restingHR: restingHR, reserve: reserve,
                            method: method, thresholdFraction: fraction,
                            thresholdBpm: restingHR + fraction * reserve, trimp: nil, effort: nil,
                            zoneMinutes: nil, countedMinutes: 0, stretches: [])
        }
        guard enough, effMax > restingHR else { return refused() }

        let durations = sampleDurationsMinutes(hr)
        let trimp = trimpFor(hr, restingHR: restingHR, hrReserve: reserve, durations: durations,
                             method: method, sex: sex)
        let effort = trimpToStrain(trimp, denominator: logMapDenominator(method: method, sex: sex))
        let zones = zoneMinutes(hr, restingHR: restingHR, hrReserve: reserve, durations: durations)

        // The same per-sample test the TRIMP sums use: Edwards pays from zone 1 up, Banister pays when
        // the rate beats the sedentary floor, which is exactly when %HRR exceeds that floor.
        func counted(_ bpm: Int) -> Bool {
            switch method {
            case .edwards:
                return zoneWeight(Double(bpm), restingHR: restingHR, hrReserve: reserve) >= 1
            case .banister:
                return pctHRR(Double(bpm), restingHR: restingHR, hrReserve: reserve) / 100.0
                    > banisterSedentaryHRR
            }
        }

        var stretches: [EffortStretch] = []
        var start = 0, lastTsInRun = 0, peak = 0
        var minutes = 0.0
        var inRun = false
        func close() {
            guard inRun else { return }
            stretches.append(EffortStretch(startTs: start, endTs: lastTsInRun, minutes: minutes, peakBpm: peak))
            inRun = false
        }
        for i in hr.indices {
            guard counted(hr[i].bpm) else { close(); continue }
            // A dropout longer than one credited sample ends the run: it is not continuous effort.
            if inRun, i > 0, Double(hr[i].ts - hr[i - 1].ts) / 60.0 > maxSampleGapMin { close() }
            if !inRun {
                inRun = true; start = hr[i].ts; minutes = 0; peak = hr[i].bpm
            }
            minutes += durations[i]
            peak = max(peak, hr[i].bpm)
            lastTsInRun = hr[i].ts + Int((durations[i] * 60.0).rounded())
        }
        close()

        return EffortBreakdown(sampleCount: hr.count, firstTs: first, lastTs: last, spanSeconds: span,
                               enoughData: true, hrMax: effMax, restingHR: restingHR, reserve: reserve,
                               method: method, thresholdFraction: fraction,
                               thresholdBpm: restingHR + fraction * reserve, trimp: trimp, effort: effort,
                               zoneMinutes: zones, countedMinutes: stretches.reduce(0) { $0 + $1.minutes },
                               stretches: stretches)
    }
}
