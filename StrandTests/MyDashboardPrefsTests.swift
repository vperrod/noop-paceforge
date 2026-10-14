import XCTest
@testable import Strand

/// My Dashboard's saved list: what a fresh install shows, the stored string, adding, removing and moving rows.
final class MyDashboardPrefsTests: XCTestCase {

    func testFreshInstallShowsTheDefaultList() {
        XCTAssertEqual(MyDashboardPrefs.decode(MyDashboardPrefs.defaultCSV), MyDashboardPrefs.defaultIDs)
    }

    func testStoredStringRoundTrips() {
        let ids = ["my-whoop:hrv", "apple-health:weight", "my-whoop:steps"]
        XCTAssertEqual(MyDashboardPrefs.decode(MyDashboardPrefs.encode(ids)), ids)
    }

    func testEmptyStringIsAnEmptyListNotTheDefault() {
        XCTAssertEqual(MyDashboardPrefs.decode(""), [])
    }

    func testBlankAndRepeatedIdsAreDropped() {
        XCTAssertEqual(MyDashboardPrefs.decode("my-whoop:hrv, ,my-whoop:hrv,my-whoop:rhr,"), ["my-whoop:hrv", "my-whoop:rhr"])
    }

    func testAddingAppendsToTheEnd() {
        XCTAssertEqual(MyDashboardPrefs.adding("my-whoop:steps", to: ["my-whoop:hrv"]), ["my-whoop:hrv", "my-whoop:steps"])
    }

    func testAddingAMetricAlreadyChosenChangesNothing() {
        XCTAssertEqual(MyDashboardPrefs.adding("my-whoop:hrv", to: ["my-whoop:hrv"]), ["my-whoop:hrv"])
    }

    func testRemovingDropsOnlyThatMetric() {
        XCTAssertEqual(MyDashboardPrefs.removing("my-whoop:hrv", from: ["my-whoop:hrv", "my-whoop:rhr"]), ["my-whoop:rhr"])
    }

    func testMovingARowDownKeepsTheOthersInOrder() {
        XCTAssertEqual(MyDashboardPrefs.moving(["a", "b", "c"], from: 0, to: 2), ["b", "c", "a"])
    }

    func testMovingARowUp() {
        XCTAssertEqual(MyDashboardPrefs.moving(["a", "b", "c"], from: 2, to: 0), ["c", "a", "b"])
    }

    func testMovingWithABadIndexChangesNothing() {
        XCTAssertEqual(MyDashboardPrefs.moving(["a", "b"], from: 0, to: 5), ["a", "b"])
    }

    func testAvailableLeavesOutWhatIsAlreadyChosen() {
        XCTAssertFalse(MyDashboardPrefs.available(excluding: ["my-whoop:hrv"]).contains("my-whoop:hrv"))
    }

    func testAvailableOffersTheRestInTheirListOrder() {
        let chosen = MyDashboardPrefs.addableIDs.filter { $0 != "my-whoop:steps" }
        XCTAssertEqual(MyDashboardPrefs.available(excluding: chosen), ["my-whoop:steps"])
    }

    func testTheDefaultListIsOfferedInTheAddList() {
        XCTAssertTrue(Set(MyDashboardPrefs.defaultIDs).isSubset(of: Set(MyDashboardPrefs.addableIDs)))
    }

    func testTheAddListHasNoRepeats() {
        XCTAssertEqual(Set(MyDashboardPrefs.addableIDs).count, MyDashboardPrefs.addableIDs.count)
    }

    func testChosenListSurvivesAUserDefaultsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MyDashboardPrefsTests"))
        defer { defaults.removePersistentDomain(forName: "MyDashboardPrefsTests") }
        defaults.set(MyDashboardPrefs.encode(["my-whoop:steps", "my-whoop:hrv"]), forKey: MyDashboardPrefs.storageKey)
        XCTAssertEqual(MyDashboardPrefs.decode(defaults.string(forKey: MyDashboardPrefs.storageKey) ?? ""), ["my-whoop:steps", "my-whoop:hrv"])
    }
}
