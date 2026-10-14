import XCTest
@testable import Strand

/// The staged journal: which writes SAVE JOURNAL makes, the chip's tri-state, the 7-day strip and the stepper.
final class JournalFlowLogicTests: XCTestCase {

    private func writes(saved: [String: Bool] = [:], staged: [String: Bool] = [:],
                        savedN: [String: Double] = [:], stagedN: [String: Double] = [:]) -> [JournalWrite] {
        JournalFlowLogic.writes(savedAnswers: saved, stagedAnswers: staged, savedNumbers: savedN, stagedNumbers: stagedN)
    }

    func testNothingChangedMeansNothingToWrite() {
        XCTAssertEqual(writes(saved: ["a": true], staged: ["a": true], savedN: ["n": 2], stagedN: ["n": 2]), [])
    }

    func testANewAnswerIsSaved() {
        XCTAssertEqual(writes(staged: ["a": false]), [.saveAnswer(question: "a", yes: false)])
    }

    func testAFlippedAnswerIsSaved() {
        XCTAssertEqual(writes(saved: ["a": true], staged: ["a": false]), [.saveAnswer(question: "a", yes: false)])
    }

    func testAnAnswerTakenBackIsCleared() {
        XCTAssertEqual(writes(saved: ["a": true]), [.clearAnswer(question: "a")])
    }

    func testANewNumberIsSaved() {
        XCTAssertEqual(writes(stagedN: ["n": 3]), [.saveNumber(question: "n", value: 3)])
    }

    func testAChangedNumberIsSaved() {
        XCTAssertEqual(writes(savedN: ["n": 3], stagedN: ["n": 4]), [.saveNumber(question: "n", value: 4)])
    }

    func testANumberTakenBackIsCleared() {
        XCTAssertEqual(writes(savedN: ["n": 3]), [.clearNumber(question: "n")])
    }

    func testAnswersComeBeforeNumbersEachInQuestionOrder() {
        let out = writes(staged: ["b": true, "a": true], stagedN: ["n": 1])
        XCTAssertEqual(out, [.saveAnswer(question: "a", yes: true), .saveAnswer(question: "b", yes: true), .saveNumber(question: "n", value: 1)])
    }

    func testTappingTheChosenChipClearsIt() {
        XCTAssertEqual(JournalFlowLogic.toggled(["a": true], question: "a", to: true), [:])
    }

    func testTappingTheOtherChipFlipsIt() {
        XCTAssertEqual(JournalFlowLogic.toggled(["a": true], question: "a", to: false), ["a": false])
    }

    func testTappingAnUnansweredQuestionAnswersIt() {
        XCTAssertEqual(JournalFlowLogic.toggled([:], question: "a", to: true), ["a": true])
    }

    private func strip(selected: Int = 0, logged: Set<String> = []) -> [JournalFlowLogic.StripDay] {
        JournalFlowLogic.strip(selectedOffset: selected, logged: logged,
                               keyFor: { "d\($0)" }, partsFor: { (weekday: "W\($0)", day: 20 - $0) })
    }

    func testStripHasSevenDaysOldestFirst() {
        XCTAssertEqual(strip().map(\.offset), [6, 5, 4, 3, 2, 1, 0])
    }

    func testStripMarksTheLoggedDays() {
        XCTAssertEqual(strip(logged: ["d0", "d3"]).filter(\.isLogged).map(\.offset), [3, 0])
    }

    func testStripMarksTheSelectedDay() {
        XCTAssertEqual(strip(selected: 2).filter(\.isSelected).map(\.offset), [2])
    }

    func testStripHasNoSelectionWhenTomorrowIsOpen() {
        XCTAssertEqual(strip(selected: -1).filter(\.isSelected).count, 0)
    }

    func testStripCarriesTheDayOfTheMonth() {
        XCTAssertEqual(strip().last?.dayOfMonth, 20)
    }

    func testStepperTitles() {
        XCTAssertEqual([-1, 0, 1, 3].map { JournalFlowLogic.title(forOffset: $0) }, ["TOMORROW", "TODAY", "YESTERDAY", "3 DAYS AGO"])
    }

    func testStepperStopsAtTomorrow() {
        XCTAssertEqual(JournalFlowLogic.stepped(-1, by: -1), -1)
    }

    func testStepperStopsSixDaysBack() {
        XCTAssertEqual(JournalFlowLogic.stepped(6, by: 1), 6)
    }

    func testStepperMovesOneDayBack() {
        XCTAssertEqual(JournalFlowLogic.stepped(0, by: 1), 1)
    }

    func testQuestionForToday() {
        XCTAssertEqual(JournalFlowLogic.question(forOffset: 0, dateText: "April 15"), "What's happening today, April 15?")
    }

    func testQuestionForTomorrowLooksAhead() {
        XCTAssertEqual(JournalFlowLogic.question(forOffset: -1, dateText: "April 16"), "What's happening tomorrow, April 16?")
    }

    func testQuestionForYesterday() {
        XCTAssertEqual(JournalFlowLogic.question(forOffset: 1, dateText: "April 14"), "What happened yesterday, April 14?")
    }

    func testQuestionForAnOlderDay() {
        XCTAssertEqual(JournalFlowLogic.question(forOffset: 4, dateText: "Saturday, April 11"), "What happened on Saturday, April 11?")
    }
}
