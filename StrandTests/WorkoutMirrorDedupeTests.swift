import XCTest
import WhoopStore
@testable import Strand

/// A PaceForge (Garmin mirror) workout is canonical: it dedupes against any overlapping strap, Apple Health or
/// detected row whatever the sport, using PaceForge's own rule (overlap of at least half the shorter session AND
/// starts within ten minutes). Without it a strap "Workout" beside a mirrored "indoor_cardio" listed twice.
final class WorkoutMirrorDedupeTests: XCTestCase {

    private func row(start: Int, minutes: Int, sport: String, source: String, avgHr: Int? = nil) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + minutes * 60, sport: sport, source: source,
                   durationS: Double(minutes * 60), energyKcal: nil, avgHr: avgHr, maxHr: nil,
                   strain: nil, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
    }

    private let t0 = 1_760_000_000

    // MARK: - Sport mismatch

    func testStrapWorkoutDedupesAgainstMirrorDespiteSportMismatch() {
        let garmin = row(start: t0, minutes: 45, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0 + 60, minutes: 44, sport: "Workout", source: "my-whoop", avgHr: 140)
        XCTAssertEqual(WorkoutSource.dedupCrossSource([strap, garmin]).map(\.source), ["paceforge"])
    }

    func testKeptRowIsTheGarminRecordNotTheRicherStrapRow() {
        let garmin = row(start: t0, minutes: 45, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0, minutes: 45, sport: "Workout", source: "my-whoop", avgHr: 140)
        XCTAssertEqual(WorkoutSource.dedupCrossSource([garmin, strap]).first?.sport, "indoor_cardio")
    }

    func testAppleHealthTwinWithADifferentSportDedupesAgainstMirror() {
        let garmin = row(start: t0, minutes: 30, sport: "running", source: "paceforge")
        let apple = row(start: t0 + 120, minutes: 30, sport: "Outdoor Run", source: "apple-health")
        XCTAssertEqual(WorkoutSource.dedupCrossSource([apple, garmin]).count, 1)
    }

    // MARK: - Overlap boundary (workout_match.py: share of the shorter >= 0.5)

    func testExactlyHalfOverlapWithinTheStartToleranceDedupes() {
        let garmin = row(start: t0, minutes: 20, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0 + 10 * 60, minutes: 20, sport: "Workout", source: "my-whoop")
        XCTAssertTrue(WorkoutSource.isMirrorDuplicate(strap, of: garmin))
    }

    func testHalfOverlapWithStartsMoreThanTenMinutesApartStaysSeparate() {
        let garmin = row(start: t0, minutes: 60, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0 + 30 * 60, minutes: 60, sport: "Workout", source: "my-whoop")
        XCTAssertFalse(WorkoutSource.isMirrorDuplicate(strap, of: garmin))
    }

    func testJustUnderHalfOverlapStaysSeparate() {
        let garmin = row(start: t0, minutes: 20, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0 + 10 * 60 + 1, minutes: 20, sport: "Workout", source: "my-whoop")
        XCTAssertFalse(WorkoutSource.isMirrorDuplicate(strap, of: garmin))
    }

    func testTouchingSessionsStaySeparate() {
        let garmin = row(start: t0, minutes: 30, sport: "running", source: "paceforge")
        let strap = row(start: t0 + 30 * 60, minutes: 30, sport: "Workout", source: "my-whoop")
        XCTAssertFalse(WorkoutSource.isMirrorDuplicate(strap, of: garmin))
    }

    func testNoOverlapKeepsBothRows() {
        let garmin = row(start: t0, minutes: 30, sport: "running", source: "paceforge")
        let strap = row(start: t0 + 6 * 3600, minutes: 30, sport: "Workout", source: "my-whoop")
        XCTAssertEqual(WorkoutSource.dedupCrossSource([garmin, strap]).count, 2)
    }

    func testShortStrapRowInsideALongGarminSessionStartingLateStaysSeparate() {
        // Fully inside the Garmin session, but it starts 20 minutes in: a different bout, not the same one.
        let garmin = row(start: t0, minutes: 90, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0 + 20 * 60, minutes: 20, sport: "Workout", source: "my-whoop")
        XCTAssertFalse(WorkoutSource.isMirrorDuplicate(strap, of: garmin))
    }

    // MARK: - What is not dropped

    func testTwoMirrorRowsAreNeverDedupedAgainstEachOther() {
        let a = row(start: t0, minutes: 30, sport: "running", source: "paceforge")
        let b = row(start: t0 + 60, minutes: 30, sport: "cycling", source: "paceforge")
        XCTAssertEqual(WorkoutSource.dedupCrossSource([a, b]).count, 2)
    }

    func testImportedLiftingSessionIsNotDropped() {
        let garmin = row(start: t0, minutes: 45, sport: "strength_training", source: "paceforge")
        let lifting = row(start: t0, minutes: 45, sport: "Upper body", source: "lifting")
        XCTAssertEqual(WorkoutSource.dedupCrossSource([garmin, lifting]).count, 2)
    }

    func testListWithoutAMirrorRowIsUnchanged() {
        let strap = row(start: t0, minutes: 30, sport: "Workout", source: "my-whoop")
        let apple = row(start: t0 + 6 * 3600, minutes: 30, sport: "Walking", source: "apple-health")
        XCTAssertEqual(WorkoutSource.dedupCrossSource([strap, apple]), [strap, apple])
    }

    // MARK: - The trace twin agrees with the plain path

    func testTraceKeepsTheSameRowsAsThePlainPath() {
        let garmin = row(start: t0, minutes: 45, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0 + 60, minutes: 44, sport: "Workout", source: "my-whoop")
        let rows = [strap, garmin]
        XCTAssertEqual(WorkoutSource.dedupCrossSourceTrace(rows).kept, WorkoutSource.dedupCrossSource(rows))
    }

    func testTraceNamesTheDroppedStrapRow() {
        let garmin = row(start: t0, minutes: 45, sport: "indoor_cardio", source: "paceforge")
        let strap = row(start: t0 + 60, minutes: 44, sport: "Workout", source: "my-whoop")
        XCTAssertEqual(WorkoutSource.dedupCrossSourceTrace([strap, garmin]).trace.count, 1)
    }
}
