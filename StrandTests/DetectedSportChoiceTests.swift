import XCTest
import StrandDesign
@testable import Strand

/// The types a My Day suggestion can be saved as. Each stored name must be the workout catalogue's own, or the
/// saved row would lose its icon and dedupe differently from a hand-entered one.
final class DetectedSportChoiceTests: XCTestCase {

    func testEveryChoiceIsAnExactCatalogueSport() {
        let unknown = DetectedSportChoice.allCases.filter { KnownWorkoutType.exact(matching: $0.sportName) == nil }
        XCTAssertEqual(unknown.map(\.rawValue), [])
    }

    func testTheMenuOffersTheNineTypes() {
        XCTAssertEqual(DetectedSportChoice.allCases.map(\.rawValue),
                       ["walk", "run", "cycle", "strength", "hiit", "yoga", "hike", "swim", "other"])
    }

    func testWalkIsSavedAsWalking() {
        XCTAssertEqual(DetectedSportChoice.walk.sportName, "Walking")
    }

    func testTheAutoSaveSettingIsOnWhenNeverSet() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DetectedSportChoiceTests.never"))
        defaults.removePersistentDomain(forName: "DetectedSportChoiceTests.never")
        XCTAssertTrue(MyDayWalkPrefs.isAutoSaveEnabled(defaults))
    }

    func testTheAutoSaveSettingStaysOffWhenSwitchedOff() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DetectedSportChoiceTests.off"))
        defaults.removePersistentDomain(forName: "DetectedSportChoiceTests.off")
        defaults.set(false, forKey: MyDayWalkPrefs.autoSaveKey)
        XCTAssertFalse(MyDayWalkPrefs.isAutoSaveEnabled(defaults))
    }
}
