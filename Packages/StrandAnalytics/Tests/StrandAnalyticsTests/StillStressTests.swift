import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class StillStressTests: XCTestCase {
    private let day = 86_400
    private let hour = 3_600
    /// Local midnight of the fixture day (UTC).
    private var midnight: Int { 100 * day }

    private func hr(_ fromHour: Double, _ toHour: Double, bpm: Int) -> [HRSample] {
        let start = midnight + Int(fromHour * Double(hour))
        let end = midnight + Int(toHour * Double(hour))
        return (start..<end).map { HRSample(ts: $0, bpm: bpm) }
    }

    private func still(_ fromHour: Double, _ toHour: Double) -> [GravitySample] {
        let start = midnight + Int(fromHour * Double(hour))
        let end = midnight + Int(toHour * Double(hour))
        return (start..<end).map { GravitySample(ts: $0, x: 0, y: 0, z: 1) }
    }

    /// Strong back-and-forth motion every second: the intensity between records is 0.6, three times the walk floor.
    private func moving(_ fromHour: Double, _ toHour: Double) -> [GravitySample] {
        let start = midnight + Int(fromHour * Double(hour))
        let end = midnight + Int(toHour * Double(hour))
        return (start..<end).map { GravitySample(ts: $0, x: $0 % 2 == 0 ? 0.3 : -0.3, y: 0, z: 1) }
    }

    /// 09:00-10:00 at 60 bpm, 10:00-11:00 at 70, 11:00-12:00 at 80, all still.
    private var threeStillHours: (hr: [HRSample], gravity: [GravitySample]) {
        (hr(9, 10, bpm: 60) + hr(10, 11, bpm: 70) + hr(11, 12, bpm: 80), still(9, 12))
    }

    func testThreeStillHoursGiveOneHundredEightyStillMinutes() {
        let input = threeStillHours
        let result = StillStress.analyze(hr: input.hr, gravity: input.gravity)
        XCTAssertEqual(result?.stillMinutes, 180)
        XCTAssertEqual(result?.calmHR ?? 0, 60, accuracy: 0.0001)
    }

    func testWithoutEarlierDaysThereAreNoRestorativeMinutes() {
        let input = threeStillHours
        let result = StillStress.analyze(hr: input.hr, gravity: input.gravity, recentCalmHR: [60, 60, 60, 60])
        XCTAssertNil(result?.restorativeMinutes)
        XCTAssertNil(result?.referenceHR)
    }

    func testRestorativeMinutesAreTheStillMinutesAtOrBelowThePersonalCalmLevel() {
        let input = threeStillHours
        let result = StillStress.analyze(hr: input.hr, gravity: input.gravity, recentCalmHR: [66, 66, 66, 66, 66])
        XCTAssertEqual(result?.referenceHR, 66)
        XCTAssertEqual(result?.restorativeMinutes, 60)
    }

    func testTheHourlyCurveScoresAgainstTheDaysOwnCalmQuarterWhenThereIsNoHistory() {
        let input = threeStillHours
        let result = StillStress.analyze(hr: input.hr, gravity: input.gravity)
        let nine = result?.hourly.first { $0.hour == 9 }?.level
        let ten = result?.hourly.first { $0.hour == 10 }?.level
        XCTAssertEqual(nine ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(ten ?? 0, 2.3184, accuracy: 0.01)
    }

    func testHoursWithoutStillWindowsHaveNoPoint() {
        let input = threeStillHours
        let result = StillStress.analyze(hr: input.hr, gravity: input.gravity)
        XCTAssertEqual(result?.hourly.count, 16)
        XCTAssertNil(result?.hourly.first { $0.hour == 14 }?.level)
    }

    func testAnAmbulatoryHourIsLeftOut() {
        let heartRate = hr(9, 10, bpm: 60) + hr(10, 11, bpm: 70) + hr(11, 12, bpm: 80)
        let result = StillStress.analyze(hr: heartRate, gravity: still(9, 10) + moving(10, 11) + still(11, 12))
        XCTAssertEqual(result?.stillMinutes, 120)
    }

    func testAWorkoutAndTheThirtyMinutesAfterItAreLeftOut() {
        let input = threeStillHours
        let workout = StillStress.Interval(start: midnight + 9 * hour, end: midnight + 10 * hour)
        let result = StillStress.analyze(hr: input.hr, gravity: input.gravity, workouts: [workout])
        // 10:30 to 12:00 remains: 18 windows of five minutes.
        XCTAssertEqual(result?.stillMinutes, 90)
    }

    func testStillnessAtNightIsNotCounted() {
        let result = StillStress.analyze(hr: hr(2, 4, bpm: 52), gravity: still(2, 4))
        XCTAssertNil(result)
    }

    func testLessThanHalfAnHourOfStillnessGivesNoRead() {
        let result = StillStress.analyze(hr: hr(9, 9.33, bpm: 62), gravity: still(9, 9.33))
        XCTAssertNil(result)
    }

    func testWithoutMotionNothingCanBeCalledStill() {
        XCTAssertNil(StillStress.analyze(hr: hr(9, 12, bpm: 62), gravity: []))
    }

    func testAClockOffsetMovesTheWakingHoursButNotTheMinutes() {
        let input = threeStillHours
        // The same samples read on a clock one hour ahead: 10:00 to 13:00 local, still waking time.
        let result = StillStress.analyze(hr: input.hr, gravity: input.gravity, tzOffsetSeconds: hour)
        XCTAssertEqual(result?.stillMinutes, 180)
        XCTAssertNotNil(result?.hourly.first { $0.hour == 12 }?.level)
    }

    // MARK: Calm history

    func testRecordingACalmLevelKeepsTheNewestTwentyNineDays() {
        let history = (1...29).reduce(into: [String: Double]()) { $0[String(format: "2026-01-%02d", $1)] = Double($1) }
        let updated = StillStress.recordingCalm(history, day: "2026-02-01", calmHR: 70)
        XCTAssertEqual(updated.count, 29)
        XCTAssertNil(updated["2026-01-01"])
        XCTAssertEqual(updated["2026-02-01"], 70)
    }

    func testRecentCalmIsEarlierDaysOnlyOldestFirst() {
        let history = ["2026-03-01": 64.0, "2026-03-02": 63.0, "2026-03-03": 62.0, "2026-03-04": 99.0]
        XCTAssertEqual(StillStress.recentCalm(history, before: "2026-03-03"), [64, 63])
    }
}
