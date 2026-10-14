import XCTest
@testable import StrandDesign

final class LookStageTypicalTests: XCTestCase {
    private func night(_ asleep: Double = 400, deep: Double = 80, rem: Double = 90, light: Double = 230,
                       eff: Double = 0.9) -> LookNight {
        LookNight(asleepMin: asleep, deepMin: deep, remMin: rem, lightMin: light, efficiency: eff)
    }

    func testStageRangesNeedFiveNights() {
        XCTAssertNil(LookStageTypical.ranges(Array(repeating: night(), count: 4)))
    }

    func testSteadyNightsGiveANarrowDeepRangeAroundTheShare() {
        let r = LookStageTypical.ranges(Array(repeating: night(), count: 6))
        XCTAssertEqual(r?.deep.lowerBound ?? 0, 80 / (400 / 0.9), accuracy: 1e-9)
    }

    func testAwakeShareIsWhatEfficiencyLeavesOver() {
        let r = LookStageTypical.ranges(Array(repeating: night(eff: 0.9), count: 6))
        XCTAssertEqual(r?.awake.lowerBound ?? 0, 0.1, accuracy: 1e-9)
    }

    func testNightsWithImpossibleEfficiencyAreIgnored() {
        let nights = Array(repeating: night(), count: 4) + [night(eff: 0), night(eff: 1.4)]
        XCTAssertNil(LookStageTypical.ranges(nights))
    }

    func testVaryingNightsWidenTheRange() {
        let nights = (0..<6).map { night(deep: $0.isMultiple(of: 2) ? 60 : 100) }
        let r = LookStageTypical.ranges(nights)
        XCTAssertGreaterThan((r?.deep.upperBound ?? 0) - (r?.deep.lowerBound ?? 0), 0.05)
    }
}
