import XCTest
import Foundation
@testable import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// Effort v2 (`StrainScorer.Method.allDay`): the day's Effort counts all-day movement, not only time above 50 % of
/// heart-rate reserve. The cases come from `EffortV2Data/effort_v2_cases.json`, the same synthetic file the PaceForge
/// server's `tests/test_effort_v2.py` runs, so the two implementations are held to one set of numbers.
final class StrainScorerAllDayTests: XCTestCase {

    private let resting = 55.0
    private let maxHR = 180.0
    private var reserve: Double { maxHR - resting }

    private struct Case {
        let name: String
        let hr: [HRSample]
        let sleep: [(start: Int, end: Int)]
        let classic: Double?
        let allDay: Double?
        let trimp: Double
    }

    private func samples(_ segments: [[String: Any]]) -> [HRSample] {
        var out: [HRSample] = []
        for s in segments {
            let t0 = s["t0"] as! Int, t1 = s["t1"] as! Int, step = s["step"] as! Int, bpm = s["bpm"] as! Int
            var t = t0
            while t < t1 { out.append(HRSample(ts: t, bpm: bpm)); t += step }
        }
        return out.sorted { $0.ts < $1.ts }
    }

    private func loadCases() throws -> [Case] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("EffortV2Data/effort_v2_cases.json")
        let doc = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return (doc["cases"] as! [[String: Any]]).map { c in
            let sleep = (c["sleep"] as! [[Int]]).map { (start: $0[0], end: $0[1]) }
            return Case(name: c["name"] as! String, hr: samples(c["segments"] as! [[String: Any]]), sleep: sleep,
                        classic: c["classic"] as? Double, allDay: c["all_day"] as? Double,
                        trimp: c["trimp_all_day"] as! Double)
        }
    }

    private func bpm(_ x: Double) -> Double { resting + x * reserve }

    // MARK: - Shared fixtures (Swift <-> Python parity)

    func testEveryFixtureCaseGivesThePythonClassicEffort() throws {
        for c in try loadCases() {
            let got = StrainScorer.strain(c.hr, maxHR: maxHR, restingHR: resting, method: .edwards)
            if let want = c.classic {
                XCTAssertEqual(got ?? -1, want, accuracy: 0.011, c.name)
            } else {
                XCTAssertNil(got, c.name)
            }
        }
    }

    func testEveryFixtureCaseGivesThePythonAllDayEffort() throws {
        for c in try loadCases() {
            let got = StrainScorer.strain(c.hr, maxHR: maxHR, restingHR: resting, method: .allDay,
                                          sleepWindows: c.sleep)
            if let want = c.allDay {
                XCTAssertEqual(got ?? -1, want, accuracy: 0.011, c.name)
            } else {
                XCTAssertNil(got, c.name)
            }
        }
    }

    func testEveryFixtureCaseGivesThePythonAllDayTrimp() throws {
        for c in try loadCases() {
            let durations = StrainScorer.sampleDurationsMinutes(c.hr)
            let got = StrainScorer.allDayTRIMP(c.hr, restingHR: resting, hrReserve: reserve,
                                               durations: durations, sleepWindows: c.sleep)
            XCTAssertEqual(got, c.trimp, accuracy: 1e-4, c.name)
        }
    }

    // MARK: - The weight function

    func testNothingCountsAtOrBelowTheFloor() {
        for x in [0.0, 0.05, 0.25] {
            XCTAssertEqual(StrainScorer.allDaySampleWeight(bpm(x), restingHR: resting, hrReserve: reserve), 0.0, "x=\(x)")
        }
    }

    func testBetweenTheFloorAndZoneOneTheWeightIsLinearInReserve() {
        let w = StrainScorer.allDaySampleWeight(bpm(0.35), restingHR: resting, hrReserve: reserve)
        XCTAssertEqual(w, StrainScorer.allDayLowWeight * (0.35 - StrainScorer.allDayFloorHRR), accuracy: 1e-12)
    }

    func testFromHalfReserveTheEdwardsZoneWeightIsUnchanged() {
        let got = [0.5, 0.6, 0.7, 0.8, 0.9].map {
            StrainScorer.allDaySampleWeight(bpm($0), restingHR: resting, hrReserve: reserve)
        }
        XCTAssertEqual(got, [1, 2, 3, 4, 5])
    }

    func testJustUnderZoneOneThePayIsLessThanZoneOne() {
        XCTAssertLessThan(StrainScorer.allDaySampleWeight(bpm(0.499), restingHR: resting, hrReserve: reserve), 1.0)
    }

    // MARK: - Days

    private func block(_ t0: Int, _ t1: Int, step: Int, bpm: Int) -> [HRSample] {
        stride(from: t0, to: t1, by: step).map { HRSample(ts: $0, bpm: bpm) }
    }

    func testADeskDayStaysAtZero() {
        let hr = block(0, 8 * 3600, step: 30, bpm: 52) + block(8 * 3600, 24 * 3600, step: 5, bpm: Int(bpm(0.24).rounded()))
        XCTAssertEqual(StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .allDay,
                                           sleepWindows: [(start: 0, end: 8 * 3600)]), 0.0)
    }

    func testAWalkingDayScoresWhereClassicScoredNothing() {
        let hr = block(0, 10 * 3600, step: 5, bpm: 68) + block(10 * 3600, 10 * 3600 + 9480, step: 5, bpm: 98)
        let classic = StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .edwards)
        let allDay = StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .allDay)
        XCTAssertEqual(classic, 0.0)
        XCTAssertGreaterThan(allDay ?? 0, 20)
        XCTAssertLessThan(allDay ?? 100, 45)
    }

    func testAHardSessionDayKeepsItsClassicNumberWhenTheRestOfTheDayIsQuiet() {
        let hr = block(0, 10 * 3600, step: 5, bpm: 70) + block(10 * 3600, 10 * 3600 + 2700, step: 1, bpm: Int(bpm(0.75).rounded()))
        XCTAssertEqual(StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .allDay),
                       StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .edwards))
    }

    func testSleepWindowsAreLeftOutAndTheCacheKnowsTheDifference() {
        let hr = block(0, 6 * 3600, step: 5, bpm: Int(bpm(0.40).rounded())) + block(6 * 3600, 12 * 3600, step: 5, bpm: 70)
        let awake = StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .allDay)
        let asleep = StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .allDay,
                                         sleepWindows: [(start: 0, end: 6 * 3600)])
        XCTAssertGreaterThan(awake ?? 0, 0)
        XCTAssertEqual(asleep, 0.0)
    }

    func testAStrapOffGapCreditsTwoMinutesForTheReadingBeforeIt() {
        let hr = [HRSample(ts: 0, bpm: Int(bpm(0.5).rounded())), HRSample(ts: 3 * 3600, bpm: Int(bpm(0.5).rounded()))]
        let got = StrainScorer.allDayTRIMP(hr, restingHR: resting, hrReserve: reserve,
                                           durations: StrainScorer.sampleDurationsMinutes(hr), sleepWindows: [])
        XCTAssertEqual(got, 1.0 * (StrainScorer.maxSampleGapMin + StrainScorer.maxSampleGapMin), accuracy: 1e-9)
    }

    func testTooFewReadingsStillScoreNothing() {
        let hr = block(0, 570, step: 30, bpm: 110)
        XCTAssertNil(StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .allDay))
    }

    // MARK: - Plumbing

    func testAllDayUsesTheClassicDenominator() {
        XCTAssertEqual(StrainScorer.logMapDenominator(method: .allDay, sex: "male"), StrainScorer.strainDenominator)
    }

    func testAWorkoutKeepsItsClassicRecipeUnderAllDay() {
        XCTAssertEqual([StrainScorer.Method.allDay.workoutRecipe, .edwards.workoutRecipe, .banister.workoutRecipe],
                       [.edwards, .edwards, .banister])
    }

    func testTheVersionKeyAndNumbersAreTheOnesTheServerReads() {
        XCTAssertEqual("\(StrainScorer.effortVersionKey)=\(StrainScorer.classicEffortVersion)/\(StrainScorer.allDayEffortVersion)",
                       "effort_version=1/2")
    }

    func testBreakdownCountsTheSameReadingsTheScorePays() {
        let hr = block(0, 3600, step: 5, bpm: Int(bpm(0.35).rounded()))
        let b = StrainScorer.breakdown(hr, maxHR: maxHR, restingHR: resting, method: .allDay)
        XCTAssertEqual(b.effort, StrainScorer.strain(hr, maxHR: maxHR, restingHR: resting, method: .allDay))
        XCTAssertEqual(b.countedMinutes, 60.0, accuracy: 1e-6)
    }
}
