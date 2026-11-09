import XCTest
@testable import Strand

/// Starting and ending easy mode: the inputs of `easy-mode` (field names as the job contract has them) and how a filed proposal is
/// found again in Needs you. All values are made up.
final class PaceForgeEasyModeJobsTests: XCTestCase {
    func testTheLevelsAreTheContractsOneToThree() {
        XCTAssertEqual(PFEasyLevel.allCases.map { $0.rawValue }, [1, 2, 3])
    }

    func testStartingSendsTheLevelAndTheDays() {
        let expected: [String: Any] = ["level": 2, "days": 5]
        XCTAssertEqual((PFJobInputs.easyMode(level: .reduce, days: 5) ?? [:]) as NSDictionary, expected as NSDictionary)
    }

    func testRestishIsLevelThree() {
        XCTAssertEqual(PFJobInputs.easyMode(level: .restish, days: 7)?["level"] as? Int, 3)
    }

    func testTwoDaysIsNotOffered() {
        XCTAssertNil(PFJobInputs.easyMode(level: .light, days: 2))
    }

    func testFifteenDaysIsNotOffered() {
        XCTAssertNil(PFJobInputs.easyMode(level: .light, days: 15))
    }

    func testTheEdgesOfTheRangeAreOffered() {
        XCTAssertEqual([3, 14].compactMap { PFJobInputs.easyMode(level: .light, days: $0)?["days"] as? Int }, [3, 14])
    }

    func testTheDefaultsAreReduceForFiveDays() {
        XCTAssertEqual([PFEasyModeJobs.defaultLevel.rawValue, PFEasyModeJobs.defaultDays], [2, 5])
    }

    func testAFiledLineIsTheServersNote() {
        let result = PFJ(data: Data(#"{"proposal": "ab12", "note": "Days set to 3, the shortest."}"#.utf8))
        XCTAssertEqual(PFEasyModeJobs.filedLine(result), "Days set to 3, the shortest.")
    }

    func testAFiledLineWithoutANoteSaysWhatHappensNext() {
        let result = PFJ(data: Data(#"{"proposal": "ab12"}"#.utf8))
        XCTAssertEqual(PFEasyModeJobs.filedLine(result), "Proposed. Accept it to start.")
    }

    func testTheProposalItemIsFoundByItsProposalId() {
        var item = PFNeedsItem(id: "proposal:ab12", kind: .proposal, title: "Easy mode")
        item.proposalID = "ab12"
        XCTAssertEqual(PFEasyModeJobs.item(forProposal: "ab12", in: [item])?.id, "proposal:ab12")
    }

    func testAnotherProposalIsNotTheOne() {
        var item = PFNeedsItem(id: "proposal:cd34", kind: .proposal, title: "Other")
        item.proposalID = "cd34"
        XCTAssertNil(PFEasyModeJobs.item(forProposal: "ab12", in: [item]))
    }

    func testTheEasyModeJobsAreNamedAsInTheContract() {
        XCTAssertEqual([PFJobName.easyMode, .easyModeEnd].map { $0.rawValue }, ["easy-mode", "easy-mode-end"])
    }
}
