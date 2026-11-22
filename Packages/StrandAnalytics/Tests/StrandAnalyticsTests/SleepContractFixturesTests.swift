import XCTest
@testable import StrandAnalytics

/// The synthetic cases of PaceForge's sleep contract (docs/sleep-contract-2026-11-22.md, "Main night versus nap" and "Sleep-debt contract") run
/// against the native code that contract says it mirrors: the main-night classification (`PhysiologicalSteps.classifyForCycle`, grouping by
/// `SleepStageTotals.bridgedNightGroups`) and the nap credit and ledger (`SleepPlanner`, `SleepDebt`). The cases are synthetic: they pin the rule,
/// they do not validate its accuracy on real sleep. The phone sees in-bed spans, not stage evidence, so the server's "unclassified" verdicts
/// (sitting, no stage data, a short night, an evening doze) are naps here, as the contract says ("native calls these naps").
final class SleepContractFixturesTests: XCTestCase {
    private typealias Block = PhysiologicalSteps.SleepBlock
    /// 2026-01-02 00:00:00 UTC: fixtures read as local clock times with an offset of 0.
    private let t0 = 1_767_312_000

    private func at(_ hours: Double, day: Int = 0) -> Int { t0 + day * 86_400 + Int(hours * 3_600) }

    private func block(_ start: Double, _ end: Double, startDay: Int = 0, endDay: Int = 0) -> Block {
        Block(onset: at(start, day: startDay), end: at(end, day: endDay))
    }

    private func kinds(_ blocks: [Block]) -> [PhysiologicalSteps.SleepKind] {
        PhysiologicalSteps.classifyForCycle(blocks, offsetSec: 0, habitualMidsleepSec: nil).map { $0.kind }
    }

    // MARK: Main night versus nap

    func testAFullNightIsTheMainNight() {
        XCTAssertEqual(kinds([block(-1, 7)]), [.mainSleep])
    }

    func testANightSplitByAFortyFiveMinuteWakeIsOneMainNight() {
        XCTAssertEqual(kinds([block(-1, 3), block(3.75, 7)]), [.mainSleep, .mainSleep])
    }

    func testAWakeJustOverNinetyMinutesLeavesTheSecondPartANap() {
        XCTAssertEqual(kinds([block(-1, 3), block(4.6, 7)]), [.mainSleep, .nap])
    }

    func testAShortAfternoonNapIsANap() {
        XCTAssertEqual(kinds([block(-1, 7), block(14, 14.5)]), [.mainSleep, .nap])
    }

    func testALongAfternoonNapIsStillANapBecauseItStartsInTheDaytime() {
        XCTAssertEqual(kinds([block(-1, 7), block(14, 17.5)]), [.mainSleep, .nap])
    }

    func testATwoHourOvernightSleepIsNotAMainNight() {
        XCTAssertEqual(kinds([block(1, 3)]), [.nap])
    }

    func testAFourHourSleepThatStartsMidMorningIsAMainNightNotANap() {
        XCTAssertEqual(kinds([block(9.5, 13.5)]), [.mainSleep])
    }

    func testAnEveningSessionOutsideTheNightIsNotAMainNight() {
        XCTAssertEqual(kinds([block(19.5, 20)]), [.nap])
    }

    func testTheShorterOfTwoOvernightCandidatesOnOneWakeDayIsNotMain() {
        let eveningDoze = block(21, 0.5, endDay: 1)
        let afterMidnight = block(2.25, 8, startDay: 1, endDay: 1)
        XCTAssertEqual(kinds([eveningDoze, afterMidnight]), [.nap, .mainSleep])
    }

    // MARK: Nap credit and the sleep-debt ledger

    func testTonightsNapLineIsCappedAtSixtyMinutes() {
        XCTAssertEqual(SleepPlanner.napCreditMin(napMin: 195), 60)
    }

    func testAPastDaysNapsAreNotCappedInTheLedger() {
        // Contract section 2: naps are uncapped in the ledger, as in native `creditedSleepMin`. Whether the cap should reach the ledger is an
        // open decision (section "Unreconciled" 2); server and native would change together.
        XCTAssertEqual(SleepDebt.creditedSleepMin(mainSleepMin: 420, napSleepMin: 195), 615)
    }

    func testAMainNightPlusAFortyFiveMinuteNapCreditsFourHundredSixtyFive() {
        XCTAssertEqual(SleepDebt.creditedSleepMin(mainSleepMin: 420, napSleepMin: 45), 465)
    }

    func testADayWithoutAUsableMainNightStaysMissingWhateverTheNaps() {
        XCTAssertNil(SleepDebt.creditedSleepMin(mainSleepMin: nil, napSleepMin: 90))
    }

    func testRepaymentIsAQuarterOfTheDebt() {
        XCTAssertEqual(SleepPlanner.debtRepaymentMin(debtMin: 100), 25)
    }

    func testRepaymentIsAtMostSixtyMinutesANight() {
        XCTAssertEqual(SleepPlanner.debtRepaymentMin(debtMin: 400), 60)
    }

    func testTheSignedBreakdownAddsUpToTonightsNeed() {
        let parts = SleepPlanner.breakdown(baselineMin: 480, yesterdayEffort: nil, typicalEffort: nil, debtMin: 100, napMin: 195)
        XCTAssertEqual([parts.baselineMin, parts.effortExtraMin, parts.debtRepaymentMin, -parts.napCreditMin, parts.tonightMin], [480, 0, 25, -60, 445])
    }
}
