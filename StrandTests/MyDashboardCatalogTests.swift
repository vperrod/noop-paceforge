import XCTest
@testable import Strand

/// Every metric My Dashboard offers must exist in the metric catalog, or its row would silently never draw.
final class MyDashboardCatalogTests: XCTestCase {
    private func descriptor(_ id: String) -> MetricDescriptor? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return MetricCatalog.metric(key: parts[1], source: parts[0])
    }

    func testEveryAddableMetricIsInTheCatalog() {
        let missing = MyDashboardPrefs.addableIDs.filter { descriptor($0) == nil }
        XCTAssertEqual(missing, [])
    }
}
