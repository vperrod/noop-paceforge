import XCTest
import WhoopStore
@testable import Strand

/// The pure helpers behind My Day's loader: reading PaceForge's activity id off a mirrored row, keying
/// workouts, and splitting a wake day's sleep blocks into the night and naps.
@MainActor
final class DayTimelineLoaderTests: XCTestCase {

    private func row(source: String, notes: String?) -> WorkoutRow {
        WorkoutRow(startTs: 1_000, endTs: 2_000, sport: "Running", source: source, durationS: 1_000,
                   energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil,
                   notes: notes, steps: nil)
    }

    private func block(_ start: Date, hours: Double) -> CachedSleepSession {
        let s = Int(start.timeIntervalSince1970)
        return CachedSleepSession(startTs: s, endTs: s + Int(hours * 3600), efficiency: nil, restingHr: nil,
                                  avgHrv: nil, stagesJSON: nil)
    }

    func testPaceForgeActivityIdIsReadFromAMirroredRowsNotes() {
        XCTAssertEqual(DayTimelineLoader.paceForgeActivityId(row(source: "paceforge", notes: "PaceForge #9000000001: Easy run")),
                       "9000000001")
    }

    func testOnlyAPaceForgeRowCarriesAnActivityId() {
        XCTAssertNil(DayTimelineLoader.paceForgeActivityId(row(source: "manual", notes: "PaceForge #9000000001: Easy run")))
    }

    func testWorkoutKeyDistinguishesTheSameWindowFromTwoSources() {
        XCTAssertNotEqual(DayTimelineLoader.workoutKey(row(source: "paceforge", notes: nil)),
                          DayTimelineLoader.workoutKey(row(source: "apple-health", notes: nil)))
    }

    func testABlockOutsideTheWakeDaysMainNightIsANap() {
        let cal = Calendar.current
        let bed = cal.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 23))!
        let nap = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 14))!
        let night = block(bed, hours: 8)
        let afternoon = block(nap, hours: 0.6)
        XCTAssertEqual(DayTimelineLoader.napStarts([night, afternoon], habitual: nil, calendar: cal), [afternoon.startTs])
    }

    // 02:00 on 11 Jun is still the logical day of 10 Jun (rollover 04:00).
    private var smallHours: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 2))!
    }

    func testTheWidgetsNowInTheSmallHoursIsLogicallyToday() {
        let cal = Calendar.current
        let now = smallHours
        XCTAssertTrue(DayTimelineLoader.isLogicalToday(day: now, dayStart: cal.startOfDay(for: now), now: now, calendar: cal))
    }

    func testMyDaysMidnightOfTheLogicalDayIsToday() {
        let cal = Calendar.current
        let midnight = cal.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        XCTAssertTrue(DayTimelineLoader.isLogicalToday(day: midnight, dayStart: midnight, now: smallHours, calendar: cal))
    }

    func testYesterdaysMidnightIsNotToday() {
        let cal = Calendar.current
        let midnight = cal.date(from: DateComponents(year: 2026, month: 6, day: 9))!
        XCTAssertFalse(DayTimelineLoader.isLogicalToday(day: midnight, dayStart: midnight, now: smallHours, calendar: cal))
    }
}
