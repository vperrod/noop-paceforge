import XCTest
@testable import Strand

/// Niggles: reading `niggles.json` and the inputs of `niggle-add` / `niggle-resolve` (field names as the job contract has them).
/// All values are made up.
final class PaceForgeNigglesTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    private let file = #"""
    [{"id": "a1b2c3d4", "date": "2030-03-12", "site": "knee", "side": "left", "severity": 3, "movements": ["lunges"], "note": "", "resolved": null},
     {"id": "e5f6a7b8", "date": "2030-03-10", "site": "calf", "side": "", "severity": 2, "movements": [], "note": "", "resolved": "2030-03-11"},
     {"id": "0a0b0c0d", "date": "2030-03-13", "site": "hip", "side": "", "severity": 1, "movements": [], "note": "", "resolved": null}]
    """#

    func testEveryRowIsRead() {
        XCTAssertEqual(PFNiggles.list(data(file)).count, 3)
    }

    func testAResolvedRowIsNotOpen() {
        XCTAssertEqual(PFNiggles.list(data(file)).filter { !$0.isOpen }.map { $0.site }, ["calf"])
    }

    func testTheOpenOnesAreNewestFirst() {
        XCTAssertEqual(PFNiggles.open(PFNiggles.list(data(file))).map { $0.site }, ["hip", "knee"])
    }

    func testARowCarriesItsSeverity() {
        XCTAssertEqual(PFNiggles.list(data(file)).first?.severity, 3)
    }

    func testAWrappedListReadsTheSame() {
        XCTAssertEqual(PFNiggles.list(data(#"{"niggles": [{"id": "a1b2c3d4", "site": "knee", "resolved": null}]}"#)).count, 1)
    }

    func testARowWithoutAnIdIsSkipped() {
        XCTAssertEqual(PFNiggles.list(data(#"[{"site": "knee"}]"#)).count, 0)
    }

    func testNoFileIsNoNiggles() {
        XCTAssertEqual(PFNiggles.list(nil), [])
    }

    func testLoggingSendsTheAreaAndTheSeverity() {
        let inputs = PFJobInputs.niggleAdd(site: .achilles, severity: 4)
        let expected: [String: Any] = ["site": "achilles", "severity": 4]
        XCTAssertEqual((inputs ?? [:]) as NSDictionary, expected as NSDictionary)
    }

    func testASeverityOfZeroIsNotSent() {
        XCTAssertNil(PFJobInputs.niggleAdd(site: .knee, severity: 0))
    }

    func testASeverityOfSixIsNotSent() {
        XCTAssertNil(PFJobInputs.niggleAdd(site: .knee, severity: 6))
    }

    func testTheAreasAreTheContractsEight() {
        XCTAssertEqual(PFNiggleSite.allCases.map { $0.rawValue },
                       ["knee", "calf", "achilles", "hamstring", "hip", "back", "shoulder", "other"])
    }

    func testResolvingSendsTheId() {
        let expected: [String: Any] = ["id": "a1b2c3d4"]
        XCTAssertEqual((PFJobInputs.niggleResolve(id: "a1b2c3d4") ?? [:]) as NSDictionary, expected as NSDictionary)
    }

    func testAnIdThatIsNotEightHexDigitsIsNotSent() {
        XCTAssertNil(PFJobInputs.niggleResolve(id: "a1b2c3"))
    }

    func testAnIdWithAnUppercaseLetterIsNotSent() {
        XCTAssertNil(PFJobInputs.niggleResolve(id: "A1B2C3D4"))
    }

    func testTheNiggleJobsAreNamedAsInTheContract() {
        XCTAssertEqual([PFJobName.niggleAdd, .niggleResolve].map { $0.rawValue }, ["niggle-add", "niggle-resolve"])
    }
}
