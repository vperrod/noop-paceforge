import XCTest
@testable import Strand

/// The contributor rows on a PaceForge ring's page: Garmin's factors and PaceForge's own drivers stay under their own names.
final class PaceForgeRingRowsTests: XCTestCase {
    private let facts = PFRingFacts(
        garminReadiness: 62, garminLevel: "moderate",
        garminFactors: [PFRingFacts.Factor(name: "last night's sleep", value: "good", status: "ok")],
        garminRecoveryTimeH: 14.0, paceforgeDrivers: ["HRV above your usual"],
        garminSleepFactor: 80, garminSleepFactorStatus: "good",
        lastNightNeedText: "7 h 40", tonightNeedText: "8 h", tonightBedtime: "22:15")

    func testRecoveryRowsNameGarminAndPaceForgeSeparately() {
        XCTAssertEqual(PFRingRows.recovery(facts).map(\.source), ["Garmin", "Garmin", "Garmin", "PaceForge"])
    }

    func testRecoveryRowsCapitaliseGarminsFactorName() {
        XCTAssertEqual(PFRingRows.recovery(facts)[1].label, "Last night's sleep")
    }

    func testRecoveryTimeDropsTheTrailingZero() {
        XCTAssertEqual(PFRingRows.recovery(facts)[2].value, "14 h")
    }

    func testSleepRowsPutGarminsFactorFirst() {
        XCTAssertEqual(PFRingRows.sleep(facts).first?.source, "Garmin")
    }

    func testSleepNeedRowsAreLabelledPaceForge() {
        XCTAssertEqual(PFRingRows.sleep(facts).dropFirst().map(\.source), ["PaceForge", "PaceForge", "PaceForge"])
    }

    func testNoFactsGiveNoRows() {
        XCTAssertEqual(PFRingRows.recovery(PFRingFacts()), [])
    }
}
