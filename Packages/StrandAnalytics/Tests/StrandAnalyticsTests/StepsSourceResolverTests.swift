import XCTest
@testable import StrandAnalytics

/// The steps order (phone or band that counts, then the Garmin mirror, then any strap estimate), the
/// labels printed beside a count, and the two small rules the Garmin fix leans on: the day-cycle pass never
/// replaces a count with nothing, and a missing Apple count is explained instead of silent.
final class StepsSourceResolverTests: XCTestCase {

    // MARK: - Arbitration order

    func testAppleHealthBeatsGarminWhenBothReport() {
        let r = StepsSourceResolver.resolve([
            StepsReading(source: .paceforgeGarmin, value: 9100),
            StepsReading(source: .appleHealth, value: 8800),
        ])
        XCTAssertEqual(r?.source, .appleHealth)
    }

    func testGarminBeatsStrapEstimate() {
        let r = StepsSourceResolver.resolve([
            StepsReading(source: .noopComputed, value: 7000),
            StepsReading(source: .paceforgeGarmin, value: 9100),
        ])
        XCTAssertEqual(r?.value, 9100)
    }

    func testGarminIsShownWhenAppleHealthHasStopped() {
        // Apple Health rows end on 2026-10-08, so for later days only Garmin and the strap report.
        let r = StepsSourceResolver.resolve([
            StepsReading(source: .noopComputed, value: 6400),
            StepsReading(source: .paceforgeGarmin, value: 10240),
        ])
        XCTAssertEqual(r?.label, "Garmin")
    }

    func testStrapEstimateIsShownWhenItIsTheOnlySource() {
        let r = StepsSourceResolver.resolve([StepsReading(source: .noopComputed, value: 6400)])
        XCTAssertEqual(r?.label, "strap estimate")
    }

    func testNoSourcesResolveToNothing() {
        XCTAssertNil(StepsSourceResolver.resolve([]))
    }

    func testAppleHealthLabel() {
        let r = StepsSourceResolver.resolve([StepsReading(source: .appleHealth, value: 5000)])
        XCTAssertEqual(r?.label, "Apple Health")
    }

    func testPositiveGarminBeatsAppleZero() {
        // A phone that was left at home reports 0 steps; it must not hide the watch's real count.
        let r = StepsSourceResolver.resolve([
            StepsReading(source: .appleHealth, value: 0),
            StepsReading(source: .paceforgeGarmin, value: 9100),
        ])
        XCTAssertEqual(r?.source, .paceforgeGarmin)
    }

    func testAllZeroResolvesToZeroFromBestRankedSource() {
        let r = StepsSourceResolver.resolve([
            StepsReading(source: .noopComputed, value: 0),
            StepsReading(source: .paceforgeGarmin, value: 0),
        ])
        XCTAssertEqual(r?.source, .paceforgeGarmin)
    }

    func testNaNReadingIsIgnored() {
        let r = StepsSourceResolver.resolve([
            StepsReading(source: .appleHealth, value: .nan),
            StepsReading(source: .noopComputed, value: 3000),
        ])
        XCTAssertEqual(r?.source, .noopComputed)
    }

    func testMergedCacheCountRanksBehindEveryRealSource() {
        let r = StepsSourceResolver.resolve([
            StepsReading(source: .localCache, value: 4000),
            StepsReading(source: .noopComputed, value: 3900),
        ])
        XCTAssertEqual(r?.source, .noopComputed)
    }

    func testMergedCacheCountIsShownWhenNothingElseReports() {
        let r = StepsSourceResolver.resolve([StepsReading(source: .localCache, value: 4000)])
        XCTAssertEqual(r?.label, "Cached")
    }

    func testGarminOutranksStrapInThePolicyTable() {
        XCTAssertEqual(MetricArbitrationPolicy.tier(metric: .steps, source: .paceforgeGarmin), 1)
    }

    func testGarminSitsBehindPhoneInThePolicyTable() {
        XCTAssertGreaterThan(MetricArbitrationPolicy.tier(metric: .steps, source: .paceforgeGarmin),
                             MetricArbitrationPolicy.tier(metric: .steps, source: .appleHealth))
    }

    func testGarminStoredIdMapsToTheGarminSource() {
        XCTAssertEqual(StepsSourceResolver.source(forStoredId: "paceforge-garmin"), .paceforgeGarmin)
    }

    func testStrapStoredIdMapsToAStrapSource() {
        XCTAssertEqual(StepsSourceResolver.source(forStoredId: "my-whoop-noop"), .noopComputed)
    }

    // MARK: - Series source

    func testSeriesSourceIsTheOneReachingTheLatestDay() {
        let picked = StepsSourceResolver.preferredSeriesSource(latestDayBySource: [
            .appleHealth: "2026-10-08", .paceforgeGarmin: "2026-10-18", .noopComputed: "2026-10-18",
        ])
        XCTAssertEqual(picked, .paceforgeGarmin)
    }

    func testSeriesSourceTieGoesToApple() {
        let picked = StepsSourceResolver.preferredSeriesSource(latestDayBySource: [
            .appleHealth: "2026-10-18", .paceforgeGarmin: "2026-10-18",
        ])
        XCTAssertEqual(picked, .appleHealth)
    }

    func testSeriesSourceIsNilWithoutAnySource() {
        XCTAssertNil(StepsSourceResolver.preferredSeriesSource(latestDayBySource: [:]))
    }

    // MARK: - Day-cycle merge (a missing cycle count never erases a stored count)

    func testCycleWithoutACountKeepsTheExistingSteps() {
        XCTAssertEqual(StepsSourceResolver.cycleSteps(established: true, cycle: nil, existing: 4200), 4200)
    }

    func testCycleCountReplacesTheExistingSteps() {
        XCTAssertEqual(StepsSourceResolver.cycleSteps(established: true, cycle: 5100, existing: 4200), 5100)
    }

    func testCycleBeforeEstablishmentKeepsTheExistingSteps() {
        XCTAssertEqual(StepsSourceResolver.cycleSteps(established: false, cycle: 5100, existing: 4200), 4200)
    }

    func testCycleWithNothingAnywhereStaysNil() {
        XCTAssertNil(StepsSourceResolver.cycleSteps(established: true, cycle: nil, existing: nil))
    }

    // MARK: - Missing Apple steps are explained

    func testNoticeNamesGarminWhenAppleStepsAreUnavailable() {
        let garmin = ResolvedSteps(value: 9000, source: .paceforgeGarmin, label: "Garmin")
        XCTAssertEqual(StepsSourceResolver.unavailableNotice(appleUnavailable: true, resolved: garmin),
                       "Steps from Apple Health unavailable — showing Garmin")
    }

    func testNoticeIsSilentWhenAppleStepsAreAvailable() {
        let garmin = ResolvedSteps(value: 9000, source: .paceforgeGarmin, label: "Garmin")
        XCTAssertNil(StepsSourceResolver.unavailableNotice(appleUnavailable: false, resolved: garmin))
    }

    func testNoticeStandsAloneWhenNothingIsShown() {
        XCTAssertEqual(StepsSourceResolver.unavailableNotice(appleUnavailable: true, resolved: nil),
                       "Steps from Apple Health unavailable")
    }

    func testNoticeIsSilentWhenTheShownCountIsApples() {
        let apple = ResolvedSteps(value: 9000, source: .appleHealth, label: "Apple Health")
        XCTAssertNil(StepsSourceResolver.unavailableNotice(appleUnavailable: true, resolved: apple))
    }
}
