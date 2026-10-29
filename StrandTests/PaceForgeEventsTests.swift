import XCTest
@testable import Strand

/// Events and HYROX simulations logged from the app: the list `save-events` replaces, and the inputs of `hyrox-sim-add` (field names as
/// the job contract has them). All values are made up.
final class PaceForgeEventsTests: XCTestCase {
    private let file = #"""
    [{"date": "2030-06-01", "name": "City Half", "type": "Half Marathon", "goal_time": "1:45:00", "priority": "A", "partner": null},
     {"date": "2030-04-20", "name": "Hyrox Open", "type": "HYROX", "goal_time": "", "format": "doubles", "partner": {"name": "Sam"}}]
    """#

    private var list: [[String: Any]] { PFEvents.parse(Data(file.utf8)) ?? [] }

    // MARK: Reading

    func testTheFileIsReadAsAList() {
        XCTAssertEqual(list.count, 2)
    }

    func testTheRowsAreSoonestFirst() {
        XCTAssertEqual(PFEvents.rows(list).map { $0.name }, ["Hyrox Open", "City Half"])
    }

    func testARowCarriesItsType() {
        XCTAssertEqual(PFEvents.rows(list).first?.type, "HYROX")
    }

    func testAFileThatIsNotAListIsNotRead() {
        XCTAssertNil(PFEvents.parse(Data(#"{"events": []}"#.utf8)))
    }

    func testNoFileIsNotRead() {
        XCTAssertNil(PFEvents.parse(nil))
    }

    // MARK: Adding

    func testAddingKeepsEveryOtherEventUntouched() {
        let updated = (try? PFEvents.adding(name: "10K", date: "2030-05-05", type: "10K", location: "", to: list).get()) ?? []
        XCTAssertEqual(updated.count, 3)
    }

    func testAddingKeepsTheOtherKeysOfAnExistingRow() {
        let updated = (try? PFEvents.adding(name: "10K", date: "2030-05-05", type: "10K", location: "", to: list).get()) ?? []
        XCTAssertEqual(updated.first(where: { ($0["date"] as? String) == "2030-06-01" })?["priority"] as? String, "A")
    }

    func testANewEventHasTheOriginalShape() {
        let updated = (try? PFEvents.adding(name: " 10K ", date: "2030-05-05", type: "10K", location: "", to: []).get()) ?? []
        let expected: [String: Any] = ["date": "2030-05-05", "name": "10K", "type": "10K", "goal_time": ""]
        XCTAssertEqual((updated.first ?? [:]) as NSDictionary, expected as NSDictionary)
    }

    func testAPlaceIsAddedWhenGiven() {
        let updated = (try? PFEvents.adding(name: "10K", date: "2030-05-05", type: "10K", location: " Dublin ", to: []).get()) ?? []
        XCTAssertEqual(updated.first?["location"] as? String, "Dublin")
    }

    func testAnEmptyNameIsRefused() {
        XCTAssertEqual(PFEvents.adding(name: "  ", date: "2030-05-05", type: "", location: "", to: []).problem, .nameMissing)
    }

    func testANameOverTwoHundredCharactersIsRefused() {
        let long = String(repeating: "a", count: 201)
        XCTAssertEqual(PFEvents.adding(name: long, date: "2030-05-05", type: "", location: "", to: []).problem, .nameTooLong)
    }

    func testADateThatIsNotADayIsRefused() {
        XCTAssertEqual(PFEvents.adding(name: "10K", date: "5 May", type: "", location: "", to: []).problem, .badDate)
    }

    func testADayWithAnEventAlreadyIsRefused() {
        XCTAssertEqual(PFEvents.adding(name: "10K", date: "2030-06-01", type: "", location: "", to: list).problem, .dateTaken)
    }

    func testAHundredAndFirstEventIsRefused() {
        let full = (0..<100).map { ["date": String(format: "2031-01-%02d-%d", $0 % 28 + 1, $0), "name": "E\($0)"] as [String: Any] }
        XCTAssertEqual(PFEvents.adding(name: "10K", date: "2030-05-05", type: "", location: "", to: full).problem, .tooMany)
    }

    // MARK: Cancelling and sending

    func testCancellingRemovesOnlyThatDay() {
        XCTAssertEqual(PFEvents.rows(PFEvents.removing(date: "2030-06-01", name: "City Half", from: list)).map { $0.name }, ["Hyrox Open"])
    }

    func testCancellingKeepsTheOthersKeys() {
        let kept = PFEvents.removing(date: "2030-06-01", name: "City Half", from: list)
        XCTAssertEqual((kept.first?["partner"] as? [String: Any])?["name"] as? String, "Sam")
    }

    func testCancellingKeepsAnotherEventOnTheSameDay() {
        let both = list + [["date": "2030-06-01", "name": "Park 5K"]]
        XCTAssertEqual(PFEvents.rows(PFEvents.removing(date: "2030-06-01", name: "City Half", from: both)).map { $0.name }, ["Hyrox Open", "Park 5K"])
    }

    func testCancellingRemovesOnlyTheFirstOfTwoIdenticalRows() {
        let twice: [[String: Any]] = [["date": "2030-06-01", "name": "City Half"], ["date": "2030-06-01", "name": "City Half"]]
        XCTAssertEqual(PFEvents.removing(date: "2030-06-01", name: "City Half", from: twice).count, 1)
    }

    func testCancellingAnEventThatIsGoneChangesNothing() {
        XCTAssertEqual(PFEvents.removing(date: "2030-06-01", name: "Other", from: list).count, 2)
    }

    func testTwoEventsOnOneDayHaveDifferentRowIds() {
        let both: [[String: Any]] = [["date": "2030-06-01", "name": "A"], ["date": "2030-06-01", "name": "B"]]
        XCTAssertEqual(Set(PFEvents.rows(both).map { $0.id }).count, 2)
    }

    func testTwoIdenticalRowsHaveDifferentRowIds() {
        let twice: [[String: Any]] = [["date": "2030-06-01", "name": "A"], ["date": "2030-06-01", "name": "A"]]
        XCTAssertEqual(Set(PFEvents.rows(twice).map { $0.id }).count, 2)
    }

    func testAChangeIsAppliedToTheFreshListItIsGiven() {
        let fresh: [[String: Any]] = [["date": "2030-07-01", "name": "New one"]]
        let updated = (try? PFEvents.applying(.add(name: "10K", date: "2030-05-05", type: "10K", location: ""), to: fresh).get()) ?? []
        XCTAssertEqual(PFEvents.rows(updated).map { $0.name }, ["10K", "New one"])
    }

    func testACancelIsAppliedToTheFreshList() {
        let updated = (try? PFEvents.applying(.cancel(date: "2030-06-01", name: "City Half"), to: list).get()) ?? []
        XCTAssertEqual(updated.count, 1)
    }

    func testAnAddOnADayTakenOnTheFreshListIsRefused() {
        XCTAssertEqual(PFEvents.applying(.add(name: "10K", date: "2030-06-01", type: "", location: ""), to: list).problem, .dateTaken)
    }

    func testAnUnreadableListHasAPlainMessage() {
        XCTAssertEqual(PFEventProblem.unreadable.message, "PaceForge's events could not be read, so nothing was changed.")
    }

    func testAListStillOverTheCapAfterACancelIsNotSent() {
        let over = (0..<102).map { ["date": "2031-02-\($0)", "name": "E\($0)"] as [String: Any] }
        XCTAssertNil(PFEvents.inputs(PFEvents.removing(date: "2031-02-0", name: "E0", from: over)))
    }

    func testTheInputsCarryTheWholeListSoonestFirst() {
        let sent = PFEvents.inputs(list)?["data"] as? [[String: Any]]
        XCTAssertEqual(sent?.compactMap { $0["date"] as? String }, ["2030-04-20", "2030-06-01"])
    }

    func testAListOverAHundredIsNotSent() {
        XCTAssertNil(PFEvents.inputs(Array(repeating: ["date": "2030-01-01", "name": "E"], count: 101)))
    }

    func testTheJobsAreNamedAsInTheContract() {
        XCTAssertEqual([PFJobName.saveEvents, .hyroxSimAdd].map { $0.rawValue }, ["save-events", "hyrox-sim-add"])
    }

    // MARK: HYROX simulation

    func testTimesSeparatedBySpacesAreSplit() {
        XCTAssertEqual(PFHyroxSimInput.times("4:05 4:10  4:12"), ["4:05", "4:10", "4:12"])
    }

    func testTimesSeparatedByCommasAreSplit() {
        XCTAssertEqual(PFHyroxSimInput.times("4:05, 4:10"), ["4:05", "4:10"])
    }

    func testAnEmptyPlaceBetweenCommasSkipsASplit() {
        XCTAssertEqual(PFHyroxSimInput.times("4:05,,4:12"), ["4:05", "", "4:12"])
    }

    func testAnEmptyBoxHasNoTimes() {
        XCTAssertEqual(PFHyroxSimInput.times("  "), [])
    }

    func testASimulationCarriesTheDayTheRunsTheStationsAndTheRoxzone() {
        let inputs = PFJobInputs.hyroxSim(date: "2030-03-13", runs: "4:05 4:10", stations: "3:50, 4:20", roxzone: " 6:30 ")
        let expected: [String: Any] = ["date": "2030-03-13", "runs": ["4:05", "4:10"], "stations": ["3:50", "4:20"], "roxzone": "6:30"]
        XCTAssertEqual((inputs ?? [:]) as NSDictionary, expected as NSDictionary)
    }

    func testRunsAloneAreEnough() {
        let inputs = PFJobInputs.hyroxSim(date: "2030-03-13", runs: "4:05", stations: "", roxzone: "")
        XCTAssertNil(inputs?["stations"])
    }

    func testNoTimeAtAllIsNotSent() {
        XCTAssertNil(PFJobInputs.hyroxSim(date: "2030-03-13", runs: "", stations: " ", roxzone: "6:30"))
    }

    func testOnlySkippedSplitsAreNotSent() {
        XCTAssertNil(PFJobInputs.hyroxSim(date: "2030-03-13", runs: ",,", stations: "", roxzone: ""))
    }

    func testNineRunTimesAreNotSent() {
        XCTAssertNil(PFJobInputs.hyroxSim(date: "2030-03-13", runs: "1:00 1:00 1:00 1:00 1:00 1:00 1:00 1:00 1:00", stations: "", roxzone: ""))
    }
}

private extension Result {
    /// The error of a failed result; nil when it succeeded.
    var problem: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
