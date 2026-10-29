import XCTest
@testable import Strand

/// Editing a planned session: which sessions the edits apply to and the inputs of `calendar-edit`, `session-state` and `session-drop`
/// (field names as the job contract has them). All values are made up.
final class PaceForgePlanEditTests: XCTestCase {
    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    // MARK: Which sessions

    func testAPlannedSessionCanBeEdited() {
        XCTAssertTrue(PFPlanEdit.applies(status: "planned", sessionID: "s1"))
    }

    func testAMissedSessionCanBeEdited() {
        XCTAssertTrue(PFPlanEdit.applies(status: "missed", sessionID: "s1"))
    }

    func testAnOptionalSessionCanBeEdited() {
        XCTAssertTrue(PFPlanEdit.applies(status: "optional", sessionID: "s1"))
    }

    func testADoneSessionCannotBeEdited() {
        XCTAssertFalse(PFPlanEdit.applies(status: "done", sessionID: "s1"))
    }

    func testARowWithoutASessionIdCannotBeEdited() {
        XCTAssertFalse(PFPlanEdit.applies(status: "planned", sessionID: nil))
    }

    // MARK: Session ids

    func testASessionIdWithTheServersCharactersIsKept() {
        XCTAssertEqual(PFJobInputs.sessionID("wk-12_Tue.run:1"), "wk-12_Tue.run:1")
    }

    func testASessionIdWithASlashIsRefused() {
        XCTAssertNil(PFJobInputs.sessionID("../plan"))
    }

    func testASessionIdOfMoreThanEightyCharactersIsRefused() {
        XCTAssertNil(PFJobInputs.sessionID(String(repeating: "a", count: 81)))
    }

    func testAnEmptySessionIdIsRefused() {
        XCTAssertNil(PFJobInputs.sessionID(""))
    }

    // MARK: Inputs

    func testMovingSendsTheSessionTheActionAndTheDay() {
        assertSame(PFJobInputs.calendarMove(sessionID: "s1", to: "2030-03-16"),
                   ["session_id": "s1", "action": "reschedule", "new_date": "2030-03-16"])
    }

    func testMovingToSomethingThatIsNotADayIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarMove(sessionID: "s1", to: "16 March"))
    }

    func testSkippingSendsOnlyTheSessionAndTheDeleteAction() {
        assertSame(PFJobInputs.calendarDelete(sessionID: "s1"), ["session_id": "s1", "action": "delete"])
    }

    func testAcceptingSendsTheActiveState() {
        assertSame(PFJobInputs.sessionAccept(sessionID: "s1"), ["session_id": "s1", "state": "active"])
    }

    func testDroppingSendsOnlyTheSession() {
        assertSame(PFJobInputs.sessionDrop(sessionID: "s1"), ["session_id": "s1"])
    }

    func testNoSessionIdSendsNothing() {
        XCTAssertNil(PFJobInputs.sessionDrop(sessionID: nil))
    }

    func testTheJobsAreNamedAsInTheContract() {
        XCTAssertEqual([PFJobName.calendarEdit, .sessionState, .sessionDrop].map { $0.rawValue },
                       ["calendar-edit", "session-state", "session-drop"])
    }
}
