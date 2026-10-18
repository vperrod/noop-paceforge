import XCTest
@testable import Strand

final class MetricCatalogStepsTests: XCTestCase {
    func testTodayStepsUsesStrapSeriesForAStrapCount() {
        let metric = MetricCatalog.todayStepsMetric(source: .noopComputed, hasStrapCount: true)

        XCTAssertEqual(metric?.key, "steps")
        XCTAssertEqual(metric?.source, "my-whoop")
    }

    func testTodayStepsUsesWhoopFourEstimateWhenThereIsNoStrapCount() {
        let metric = MetricCatalog.todayStepsMetric(source: .noopComputed, hasStrapCount: false)

        XCTAssertEqual(metric?.key, "steps_est")
        XCTAssertEqual(metric?.source, "my-whoop")
    }

    func testTodayStepsWithNothingToShowOpensTheEstimate() {
        XCTAssertEqual(MetricCatalog.todayStepsMetric(source: nil)?.key, "steps_est")
    }

    /// #377 parity: when Apple Health supplied the day's count, Today taps through to the imported series.
    func testTodayStepsTapsThroughToAppleHealthWhenAppleSuppliedTheCount() {
        let metric = MetricCatalog.todayStepsMetric(source: .appleHealth, hasStrapCount: true)

        XCTAssertEqual(metric?.key, "steps")
        XCTAssertEqual(metric?.source, "apple-health")
    }

    /// A day whose count came from the Garmin mirror opens the Garmin series, not the (empty) strap one.
    func testTodayStepsTapsThroughToGarminWhenGarminSuppliedTheCount() {
        let metric = MetricCatalog.todayStepsMetric(source: .paceforgeGarmin, hasStrapCount: true)

        XCTAssertEqual(metric?.id, "paceforge-garmin:steps")
    }

    func testAppleHealthStepsRemainsAnIndependentCatalogMetric() {
        let metric = MetricCatalog.metric(key: "steps", source: "apple-health")

        XCTAssertEqual(metric?.id, "apple-health:steps")
    }

    /// Both measured WHOOP steps and the WHOOP 4.0 estimate must be resolvable by EXACT source, so the
    /// Today card/tile can route to them (via `.metricSourced` / `todayStepsMetric`) without depending on
    /// catalog declaration order.
    func testWhoopStepsAreResolvableBySource() {
        XCTAssertEqual(MetricCatalog.metric(key: "steps", source: "my-whoop")?.id, "my-whoop:steps")
        XCTAssertEqual(MetricCatalog.metric(key: "steps_est", source: "my-whoop")?.id, "my-whoop:steps_est")
    }

    /// Regression guard: the bare-key `first { $0.key == "steps" }` resolvers that are NOT source-aware
    /// (LabBookView's correlation descriptors, CompareView's default/legacy picks, the TabRoute `.metric`
    /// fallback) must keep resolving Apple Health, exactly as before the measured-WHOOP entry was added.
    /// The measured entry is declared AFTER apple-health precisely so it never captures these lookups —
    /// the Today surface reaches it explicitly instead. If a future edit reorders the catalog, this fails
    /// loudly rather than silently emptying those screens for an Apple-Health-steps user.
    func testBareKeyStepsResolutionStaysAppleHealth() {
        XCTAssertEqual(MetricCatalog.all.first(where: { $0.key == "steps" })?.source, "apple-health")
    }
}
