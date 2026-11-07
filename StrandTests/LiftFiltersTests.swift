import XCTest
@testable import Strand
#if canImport(WhoopStore)
import WhoopStore
#endif

/// Lift exercise filters: an exercise is matched by the region of its primary muscle and by its equipment tag,
/// and equipment tags are kept by exercise name. All values are made up.
final class LiftFiltersTests: XCTestCase {

    private struct Item { var name: String; var primary: LiftMuscle? }

    private let items = [Item(name: "Bench press", primary: .chest), Item(name: "Row", primary: .lats),
                         Item(name: "Squat", primary: .quads), Item(name: "Plank", primary: .abs),
                         Item(name: "Mystery", primary: nil)]

    private func names(_ filter: LiftExerciseFilter, tags: [String: LiftEquipment] = [:]) -> [String] {
        filter.apply(items, primary: { $0.primary }, name: { $0.name },
                     equipmentOf: { tags[LiftEquipmentStore.normalized($0)] }).map(\.name)
    }

    // MARK: Muscle group

    func testNoFilterKeepsEverything() {
        XCTAssertEqual(names(LiftExerciseFilter()).count, 5)
    }

    func testPushKeepsTheChestExercise() {
        XCTAssertEqual(names(LiftExerciseFilter(region: .push)), ["Bench press"])
    }

    func testPullKeepsTheLatsExercise() {
        XCTAssertEqual(names(LiftExerciseFilter(region: .pull)), ["Row"])
    }

    func testLegsKeepsTheQuadExercise() {
        XCTAssertEqual(names(LiftExerciseFilter(region: .legs)), ["Squat"])
    }

    func testTrunkKeepsTheAbsExercise() {
        XCTAssertEqual(names(LiftExerciseFilter(region: .trunk)), ["Plank"])
    }

    func testAnUnclassifiedExerciseIsLeftOutOfAMuscleFilter() {
        XCTAssertFalse(names(LiftExerciseFilter(region: .push)).contains("Mystery"))
    }

    func testAnUnclassifiedExerciseStaysWithoutAFilter() {
        XCTAssertTrue(names(LiftExerciseFilter()).contains("Mystery"))
    }

    // MARK: Equipment

    func testEquipmentKeepsTheTaggedExercises() {
        let tags: [String: LiftEquipment] = ["bench press": .barbell, "squat": .barbell, "row": .cable]
        XCTAssertEqual(names(LiftExerciseFilter(equipment: .barbell), tags: tags), ["Bench press", "Squat"])
    }

    func testAnUntaggedExerciseIsLeftOutOfAnEquipmentFilter() {
        XCTAssertEqual(names(LiftExerciseFilter(equipment: .machine), tags: ["row": .cable]), [])
    }

    func testBothFiltersMustMatch() {
        let tags: [String: LiftEquipment] = ["bench press": .barbell, "squat": .barbell]
        XCTAssertEqual(names(LiftExerciseFilter(region: .legs, equipment: .barbell), tags: tags), ["Squat"])
    }

    func testEquipmentMatchesWithoutCaseOrSpace() {
        let tags: [String: LiftEquipment] = [LiftEquipmentStore.normalized("  BENCH press "): .barbell]
        XCTAssertEqual(names(LiftExerciseFilter(equipment: .barbell), tags: tags), ["Bench press"])
    }

    func testAFilterIsActiveOnlyWhenSomethingIsPicked() {
        XCTAssertEqual([LiftExerciseFilter().isActive, LiftExerciseFilter(region: .pull).isActive,
                        LiftExerciseFilter(equipment: .band).isActive], [false, true, true])
    }

    func testFilterOrderIsKept() {
        let tags: [String: LiftEquipment] = ["row": .cable, "bench press": .cable]
        XCTAssertEqual(names(LiftExerciseFilter(equipment: .cable), tags: tags), ["Bench press", "Row"])
    }

    func testEveryRegionHasAFilterName() {
        XCTAssertEqual(LiftMuscle.Region.allCases.map(\.filterName), ["Push", "Pull", "Legs", "Trunk"])
    }

    func testEquipmentHasEightKinds() {
        XCTAssertEqual(LiftEquipment.allCases.count, 8)
    }

    // MARK: Storage

    func testATagSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "lift-equipment-test")!
        defaults.removePersistentDomain(forName: "lift-equipment-test")
        LiftEquipmentStore.set(.dumbbell, for: "Incline press", defaults: defaults)
        XCTAssertEqual(LiftEquipmentStore.equipment(for: " incline PRESS ", defaults: defaults), .dumbbell)
    }

    func testClearingATagRemovesIt() {
        let defaults = UserDefaults(suiteName: "lift-equipment-clear")!
        defaults.removePersistentDomain(forName: "lift-equipment-clear")
        LiftEquipmentStore.set(.band, for: "Pull apart", defaults: defaults)
        LiftEquipmentStore.set(nil, for: "Pull apart", defaults: defaults)
        XCTAssertNil(LiftEquipmentStore.equipment(for: "Pull apart", defaults: defaults))
    }

    func testTaggingOneExerciseKeepsTheOthers() {
        let defaults = UserDefaults(suiteName: "lift-equipment-two")!
        defaults.removePersistentDomain(forName: "lift-equipment-two")
        LiftEquipmentStore.set(.barbell, for: "Squat", defaults: defaults)
        LiftEquipmentStore.set(.cable, for: "Row", defaults: defaults)
        XCTAssertEqual(LiftEquipmentStore.equipment(for: "Squat", defaults: defaults), .barbell)
    }

    func testABlankNameIsNotTagged() {
        let defaults = UserDefaults(suiteName: "lift-equipment-blank")!
        defaults.removePersistentDomain(forName: "lift-equipment-blank")
        LiftEquipmentStore.set(.barbell, for: "   ", defaults: defaults)
        XCTAssertTrue(LiftEquipmentStore.all(defaults).isEmpty)
    }
}
