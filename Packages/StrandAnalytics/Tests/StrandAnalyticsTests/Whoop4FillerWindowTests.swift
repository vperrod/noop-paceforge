import XCTest
import WhoopProtocol
@testable import StrandAnalytics

/// A WHOOP 4.0 sends 500 / 333 ms filler intervals; a 5-minute window holding one is left out of the nightly HRV.
final class Whoop4FillerWindowTests: XCTestCase {

    /// One 5-minute window of alternating 1000 / 1040 ms beats (RMSSD 40 ms), or 1000 / 1080 ms (80 ms).
    private func window(_ index: Int, swing: Int, channel: RRSourceChannel?, extra: Int? = nil) -> [RRInterval] {
        var beats = (0..<60).map { RRInterval(ts: index * 300 + $0 * 4, rrMs: 1000 + ($0 % 2) * swing,
                                              srcChannel: channel) }
        if let extra { beats.append(RRInterval(ts: index * 300 + 241, rrMs: extra, srcChannel: channel)) }
        return beats.sorted { $0.ts < $1.ts }
    }

    private func nightHrv(_ rr: [RRInterval], windows: Int) -> Double? {
        SleepStager.sessionAvgHRV(start: 0, end: windows * 300, rr: rr)
    }

    func testHistoryWindowWith500IsLeftOutOfTheNight() {
        let rr = window(0, swing: 40, channel: .whoop4Historical)
            + window(1, swing: 80, channel: .whoop4Historical, extra: 500)
        XCTAssertEqual(nightHrv(rr, windows: 2) ?? -1, 40, accuracy: 0.001)
    }

    func testRealtimeWindowWith333IsLeftOutOfTheNight() {
        let rr = window(0, swing: 40, channel: .whoop4Realtime)
            + window(1, swing: 80, channel: .whoop4Realtime, extra: 333)
        XCTAssertEqual(nightHrv(rr, windows: 2) ?? -1, 40, accuracy: 0.001)
    }

    func testStandardBleWindowWithRescaledFillerIsLeftOut() {
        let rr = window(0, swing: 40, channel: .whoop4Standard)
            + window(1, swing: 80, channel: .whoop4Standard, extra: 477)
            + window(2, swing: 80, channel: .whoop4Standard, extra: 317)
        XCTAssertEqual(nightHrv(rr, windows: 3) ?? -1, 40, accuracy: 0.001)
    }

    func testNeighbouringIntervalValuesDoNotExcludeAWindow() {
        let rr = window(0, swing: 40, channel: .whoop4Historical, extra: 499)
        XCTAssertNotNil(nightHrv(rr, windows: 1))
    }

    func testNightWithNoCleanWindowHasNoHrv() {
        let rr = window(0, swing: 40, channel: .whoop4Historical, extra: 500)
            + window(1, swing: 40, channel: .whoop4Historical, extra: 333)
        XCTAssertNil(nightHrv(rr, windows: 2))
    }

    func testWhoop5ChannelKeepsAWindowHolding500() {
        let rr = window(0, swing: 40, channel: .whoop5Historical, extra: 500)
        XCTAssertNotNil(nightHrv(rr, windows: 1))
    }
}
