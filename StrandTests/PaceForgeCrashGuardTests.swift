import XCTest
@testable import Strand

/// The PaceForge tab crashed on a real iPhone (build 465) while every simulator test passed on made-up documents.
/// These tests hold the two things that differ in real life. First, numbers that the made-up documents never held:
/// a division by zero, an infinity or a value far out of range, each of which traps Swift's `Int(Double)`. Second,
/// the live documents' shapes (nulls, empty lists, a range whose low edge is above its high edge, a series with one
/// point), kept in `LiveShapes/PaceForgeRealShapes.json` with every value replaced. All values here are made up.
final class PaceForgeCrashGuardTests: XCTestCase {

    // MARK: Safe.int

    func testSafeIntReadsNaNAsZero() {
        XCTAssertEqual(Safe.int(.nan), 0)
    }

    func testSafeIntClampsInfinity() {
        XCTAssertEqual(Safe.int(.infinity), Int(Safe.limit))
    }

    func testSafeIntClampsNegativeInfinity() {
        XCTAssertEqual(Safe.int(-.infinity), -Int(Safe.limit))
    }

    func testSafeIntClampsAHugeFiniteValue() {
        XCTAssertEqual(Safe.int(1e300), Int(Safe.limit))
    }

    func testSafeIntRoundsHalfAwayFromZero() {
        XCTAssertEqual(Safe.int(2.5), 3)
    }

    func testSafeIntRoundsNegativeHalfAwayFromZero() {
        XCTAssertEqual(Safe.int(-2.5), -3)
    }

    func testSafeIntTruncatesTowardZeroOnRequest() {
        XCTAssertEqual(Safe.int(2.9, .towardZero), 2)
    }

    func testSafeIntRoundsUpOnRequest() {
        XCTAssertEqual(Safe.int(2.1, .up), 3)
    }

    func testSafeIntKeepsNegativeZeroAtZero() {
        XCTAssertEqual(Safe.int(-0.0), 0)
    }

    // MARK: Formats that took Int(value.rounded())

    func testPaceOfNaNReadsAsZero() {
        XCTAssertEqual(PFFormat.pace(.nan), "0:00")
    }

    func testPaceOfInfinityDoesNotTrap() {
        XCTAssertFalse(PFFormat.pace(.infinity).isEmpty)
    }

    func testClockOfNaNReadsAsZero() {
        XCTAssertEqual(PFFormat.clock(.nan), "0:00")
    }

    func testTrimmedOfInfinityDoesNotTrap() {
        XCTAssertFalse(PFFormat.trimmed(.infinity).isEmpty)
    }

    func testNumberTrimmedOfInfinityDoesNotTrap() {
        XCTAssertFalse(PFNumber.trimmed(.infinity).isEmpty)
    }

    func testSimClockOfNaNReadsAsZero() {
        XCTAssertEqual(PFSimFormat.clock(.nan), "0:00")
    }

    func testSimSignedOfInfinityDoesNotTrap() {
        XCTAssertFalse(PFSimFormat.signed(.infinity).isEmpty)
    }

    func testRideClockOfNaNReadsAsZero() {
        XCTAssertEqual(PFRideFormat.clock(.nan), "0:00")
    }

    func testRideMinutesOfNaNReadsAsZero() {
        XCTAssertEqual(PFRideFormat.minutes(.nan), "0 min")
    }

    func testRideSignedPercentOfNaNReadsAsZero() {
        XCTAssertEqual(PFRideFormat.signedPercent(.nan), "0 %")
    }

    func testImpactPercentOfNaNReadsAsZero() {
        XCTAssertEqual(PFImpactFormat.pctText(.nan), "0 %")
    }

    func testBodyAgeRangeWithNaNEdgeDoesNotTrap() {
        XCTAssertFalse(PFHealthspanFormat.rangeText(low: .nan, high: 38).isEmpty)
    }

    func testAgeVerdictWithInfiniteEdgeDoesNotTrap() {
        XCTAssertFalse(PFHealthspanFormat.ageVerdict(PFYearsRange(low: -.infinity, high: -3, mid: nil)).text.isEmpty)
    }

    func testDriverBarWithInfiniteYearsStaysWithinTenSegments() {
        XCTAssertLessThanOrEqual(PFDriverBar.make(years6m: .infinity, years30d: .nan, scale: 1).filled, PFDriverBar.segments)
    }

    func testSleepClockOfNaNReadsAsTheEveningStart() {
        XCTAssertEqual(PFSleepClock.clock(sinceEvening: .nan), "18:00")
    }

    func testSleepClockOfMinutesOfDayInfinityDoesNotTrap() {
        XCTAssertEqual(PFSleepClock.clock(minutesOfDay: .nan), "00:00")
    }

    func testCallScoreOfNaNRoundsToZero() {
        XCTAssertEqual(PFCallScore(score: .nan).rounded, 0)
    }

    func testEffortRangeWithNaNEdgeDoesNotTrap() {
        XCTAssertFalse(PFEffortTarget(low: .nan, high: .infinity).rangeText.isEmpty)
    }

    func testEffortArcWithNaNEdgeIsNotDrawn() {
        XCTAssertNil(PFEffortTarget(low: .nan, high: .nan).arc)
    }

    func testRideZoneRangeWithHugeEdgesDoesNotTrap() {
        let zone = PFRideZone(zone: 2, name: nil, low: 1e300, high: .infinity, secs: 0, pct: nil)
        XCTAssertNotNil(zone.rangeText)
    }

    // The heat chip took Int(feels_c) of whatever the file held; a temperature far out of range trapped it.
    func testHeatChipWithAnAbsurdTemperatureDoesNotTrap() throws {
        let heat = try XCTUnwrap(PFWave3Parse.heat(PFJ(["temp_c": 1e300, "feels_c": -1e300, "level": "hot"])))
        XCTAssertFalse(heat.chipText.isEmpty)
    }

    func testHeatChipWithAnIntegerBeyondDoubleRangeDoesNotTrap() throws {
        let heat = try XCTUnwrap(PFWave3Parse.heat(PFJ(["temp_c": NSNumber(value: Int64.max)])))
        XCTAssertFalse(heat.chipText.isEmpty)
    }

    // MARK: Real shapes

    private func fixture(file: StaticString = #filePath) throws -> [String: Any] {
        let fallback = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            .appendingPathComponent("LiveShapes/PaceForgeRealShapes.json")
        let url = ProcessInfo.processInfo.environment["PF_REAL_SHAPES_FILE"].map { URL(fileURLWithPath: $0) } ?? fallback
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(root["docs"] as? [String: Any])
    }

    private func doc(_ path: String) throws -> PFJ { PFJ(try XCTUnwrap(try fixture()[path])) }

    private func rawBundle() throws -> PFRawBundle {
        var raw = PFRawBundle()
        raw.state = try doc("api/state")
        raw.fitness = try doc("data/fitness.json")
        raw.activities = try doc("data/activities.json")
        raw.body = try doc("data/body.json")
        raw.standing = try doc("data/standing.json")
        raw.insightsV2 = try doc("data/insights-v2.json")
        raw.dailyIntel = try doc("data/daily-intel.json")
        raw.healthspan = try doc("data/healthspan.json")
        raw.journalImpact = try doc("data/journal-impact.json")
        raw.highlights = try doc("data/highlights.json")
        raw.monthlyReport = try doc("data/monthly-report.json")
        raw.myPlan = try doc("data/my-plan.json")
        raw.dismissed = try doc("data/dismissed.json")
        raw.todayLayout = try doc("data/today-layout.json")
        return raw
    }

    func testRealShapedDocumentsBuildASnapshot() throws {
        XCTAssertNotNil(PFBuilder.snapshot(from: try rawBundle(), today: "2030-03-13"))
    }

    func testRealShapedDocumentsBuildASnapshotOnAnotherDay() throws {
        XCTAssertNotNil(PFBuilder.snapshot(from: try rawBundle(), today: "2030-03-20"))
    }

    func testRealShapedDailyIntelHasTodaysCall() throws {
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: try rawBundle(), today: "2030-03-13"))
        XCTAssertNotNil(snapshot.dailyIntel?.call)
    }

    func testRealShapedMyPlanIsReady() throws {
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: try rawBundle(), today: "2030-03-13"))
        XCTAssertNotNil(snapshot.intelDocs.myPlan.value)
    }

    func testRealShapedHealthspanIsReady() throws {
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: try rawBundle(), today: "2030-03-13"))
        XCTAssertNotNil(snapshot.intelDocs.healthspan.value)
    }

    func testRealShapedActivitiesAreKept() throws {
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: try rawBundle(), today: "2030-03-13"))
        XCTAssertFalse(snapshot.activities.isEmpty)
    }

    func testRealShapedVitalWithLowEdgeAboveHighEdgeHasNoBand() throws {
        let snapshot = try XCTUnwrap(PFBuilder.snapshot(from: try rawBundle(), today: "2030-03-13"))
        let vitals = try XCTUnwrap(snapshot.dailyIntel?.health?.vitals)
        XCTAssertTrue(vitals.contains { $0.available && $0.band == nil })
    }

    // The pace ruler draws a tick every 0.1x, so a reversed or enormous served range must fall back to -1x to 3x.
    private func healthspan(paceRange: Any) throws -> PFHealthspan {
        let healthspanDoc = try XCTUnwrap(try fixture()["data/healthspan.json"] as? [String: Any])
        let items = try XCTUnwrap(healthspanDoc["items"] as? [String: Any])
        let item = try XCTUnwrap(items["healthspan"] as? [String: Any])
        var metric = try XCTUnwrap(item["metric"] as? [String: Any])
        var pace = try XCTUnwrap(metric["pace"] as? [String: Any])
        pace["range"] = paceRange
        metric["pace"] = pace
        return try XCTUnwrap(PFIntelDocsParse.healthspan(PFJ(metric)))
    }

    func testPaceRangeServedBackwardsFallsBackToTheUsualRuler() throws {
        XCTAssertEqual(try healthspan(paceRange: [3.0, -1.0]).pace?.rangeLow, -1)
    }

    func testPaceRangeServedEnormousFallsBackToTheUsualRuler() throws {
        XCTAssertEqual(try healthspan(paceRange: [0.0, 1e9]).pace?.rangeHigh, 3)
    }

    func testPaceRangeServedAsOneNumberFallsBackToTheUsualRuler() throws {
        XCTAssertEqual(try healthspan(paceRange: [2.0]).pace?.rangeHigh, 3)
    }

    func testPaceRangeServedSensiblyIsKept() throws {
        XCTAssertEqual(try healthspan(paceRange: [-2.0, 4.0]).pace?.rangeHigh, 4)
    }
}
