import XCTest
@testable import Strand

/// The Coach's sourced charts and the athlete's experiments: the inputs of `query-chart` and `experiment`, the rows a chart answers (a day with
/// no reading is a gap, never a value), the group means, and an experiment's review with the server's caveat carried word for word.
/// Every value is made up.
final class PaceForgeSourcedChartsTests: XCTestCase {
    private let today = "2030-03-13"

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    // MARK: query-chart inputs

    func testChartInputsAreTheClosedSpec() {
        assertSame(PFJobInputs.queryChart(metric: "hrv", days: 28), ["metric": "hrv", "days": 28])
    }

    func testChartInputsCarryTheSplitQuestion() {
        assertSame(PFJobInputs.queryChart(metric: "hrv", days: 28, split: " Alcohol? "), ["metric": "hrv", "days": 28, "split": "Alcohol?"])
    }

    func testChartWithAnUnknownMetricIsNotSent() {
        XCTAssertNil(PFJobInputs.queryChart(metric: "steps", days: 28))
    }

    func testChartOfSixDaysIsNotSent() {
        XCTAssertNil(PFJobInputs.queryChart(metric: "hrv", days: 6))
    }

    func testChartOfOneHundredEightyOneDaysIsNotSent() {
        XCTAssertNil(PFJobInputs.queryChart(metric: "hrv", days: 181))
    }

    func testChartOfOneHundredEightyDaysIsSent() {
        XCTAssertNotNil(PFJobInputs.queryChart(metric: "hrv", days: 180))
    }

    func testChartWithABlankSplitIsNotSent() {
        XCTAssertNil(PFJobInputs.queryChart(metric: "hrv", days: 28, split: "   "))
    }

    func testEveryMetricTheContractNamesIsOffered() {
        XCTAssertEqual(Set(PFChartMetric.allCases.map(\.rawValue)),
                       ["hrv", "resting_hr", "resp", "skin_temp", "spo2", "sleep_hours", "noop_recovery", "pf_recovery", "pf_sleep_score"])
    }

    // MARK: The turn's chart

    func testACoachTurnsChartBlockReadsAsASpecAndAScope() {
        let ref = PFChartRef.parse(json("{\"id\": \"0123456789abcdef\", \"scope\": \"chart:0123456789abcdef\", \"spec\": {\"metric\": \"hrv\", \"days\": 30, \"split\": null}}"))
        XCTAssertEqual(ref, PFChartRef(id: "0123456789abcdef", scope: "chart:0123456789abcdef", spec: PFChartSpec(metric: "hrv", days: 30, split: nil)))
    }

    func testACoachTurnsChartSpecBecomesTheJobInputs() {
        assertSame(PFChartSpec(metric: "resting_hr", days: 14, split: "Late meal?").inputs,
                   ["metric": "resting_hr", "days": 14, "split": "Late meal?"])
    }

    func testAChartBlockWithoutAScopeIsNotUsable() {
        XCTAssertNil(PFChartRef.parse(json("{\"id\": \"0123456789abcdef\", \"spec\": {\"metric\": \"hrv\", \"days\": 30}}")))
    }

    // MARK: The rows

    private let plain = """
    {"id": "0123456789abcdef", "scope": "chart:0123456789abcdef", "spec": {"metric": "hrv", "days": 7, "split": null},
     "metric": {"id": "hrv", "label": "HRV", "unit": "ms", "source": "Garmin"},
     "window": {"start": "2030-03-07", "end": "2030-03-13", "days": 7},
     "rows": [{"date": "2030-03-07", "value": 61.0, "source": "Garmin"}, {"date": "2030-03-08", "value": 58.5, "source": "Garmin"},
              {"date": "2030-03-10", "value": 64.0, "source": "Garmin"}],
     "n": 3, "missing_days": ["2030-03-09", "2030-03-11", "2030-03-12", "2030-03-13"],
     "note": "Rows are the stored readings.", "split": null}
    """

    func testRowsKeepTheirSource() {
        XCTAssertEqual(PFChartResult.parse(json(plain))?.rows.map(\.source), ["Garmin", "Garmin", "Garmin"])
    }

    func testADayWithNoReadingBreaksTheLine() {
        XCTAssertEqual(PFChartResult.parse(json(plain))?.points.map(\.segment), [0, 0, 1])
    }

    func testMissingDaysStayMissingAndAreNotRows() {
        XCTAssertEqual(PFChartResult.parse(json(plain))?.rows.map(\.date), ["2030-03-07", "2030-03-08", "2030-03-10"])
    }

    func testCoverageNamesTheDaysWithAReadingAndTheSource() {
        XCTAssertEqual(PFChartResult.parse(json(plain))?.coverageLine, "3 of 7 days have a reading from Garmin.")
    }

    func testMissingLineSaysTheGapsAreNotFilled() {
        XCTAssertTrue(PFChartResult.parse(json(plain))?.missingLine?.hasSuffix("These days are left as gaps, not filled in.") ?? false)
    }

    func testAChartWithEveryDayReadHasNoMissingLine() {
        let full = plain.replacingOccurrences(of: "\"missing_days\": [\"2030-03-09\", \"2030-03-11\", \"2030-03-12\", \"2030-03-13\"]", with: "\"missing_days\": []")
        XCTAssertNil(PFChartResult.parse(json(full))?.missingLine)
    }

    func testValuesShowTheirUnit() {
        XCTAssertEqual(PFChartResult.parse(json(plain))?.valueText(61), "61 ms")
    }

    func testPercentValuesHaveNoSpaceBeforeTheSign() {
        let percent = plain.replacingOccurrences(of: "\"unit\": \"ms\"", with: "\"unit\": \"%\"")
        XCTAssertEqual(PFChartResult.parse(json(percent))?.valueText(71), "71%")
    }

    func testAnUnreadableValueIsLeftOutNotZeroed() {
        let broken = plain.replacingOccurrences(of: "\"value\": 58.5", with: "\"value\": null")
        XCTAssertEqual(PFChartResult.parse(json(broken))?.rows.count, 2)
    }

    // MARK: Split

    private let split = """
    {"id": "0123456789abcdef", "scope": "chart:0123456789abcdef", "spec": {"metric": "hrv", "days": 14, "split": "Alcohol?"},
     "metric": {"id": "hrv", "label": "HRV", "unit": "ms", "source": "NOOP"},
     "window": {"start": "2030-02-28", "end": "2030-03-13", "days": 14},
     "rows": [{"date": "2030-03-01", "value": 60.0, "source": "NOOP", "group": "yes"}, {"date": "2030-03-02", "value": 66.0, "source": "NOOP", "group": "no"},
              {"date": "2030-03-03", "value": 62.0, "source": "NOOP", "group": null}],
     "n": 3, "missing_days": [], "note": "n",
     "split": {"question": "Alcohol?", "lag_days": 1, "source": "NOOP journal", "min_each": 5, "unanswered_days": 1,
               "groups": {"yes": {"n": 6, "mean": 59.4}, "no": {"n": 3, "mean": null}}}}
    """

    func testASplitColoursEachRowByItsGroup() {
        XCTAssertEqual(PFChartResult.parse(json(split))?.points.map { $0.group ?? "none" }, ["yes", "no", "none"])
    }

    func testAGroupWithEnoughDaysShowsItsMeanAndCount() {
        XCTAssertEqual(PFChartResult.parse(json(split))?.groupLine("yes"), "Yes days: 6, average 59.4 ms.")
    }

    func testAGroupBelowTheMinimumShowsNoMean() {
        XCTAssertEqual(PFChartResult.parse(json(split))?.groupLine("no"), "No days: 3, under 5 days so no average is shown.")
    }

    func testASplitIsDescribedAsTwoGroupsOfDaysNotAFinding() {
        XCTAssertTrue(PFChartResult.parse(json(split))?.splitLine?.contains("It is not a finding.") ?? false)
    }

    func testAChartWithoutASplitHasNoGroupLines() {
        XCTAssertNil(PFChartResult.parse(json(plain))?.groupLine("yes"))
    }

    // MARK: Experiments

    func testDefineSendsTheQuestionOutcomeAndWindow() {
        let inputs = PFJobInputs.experimentDefine(title: " Evening caffeine ", question: "Caffeine after 3pm?", outcome: "hrv",
                                                  start: "2030-03-13", end: "2030-03-26", today: today)
        assertSame(inputs, ["action": "define", "title": "Evening caffeine", "question": "Caffeine after 3pm?", "outcome": "hrv",
                            "start": "2030-03-13", "end": "2030-03-26"])
    }

    func testAWindowOfSixDaysIsNotSent() {
        XCTAssertNil(PFJobInputs.experimentDefine(title: "T", question: "Q?", outcome: "hrv", start: "2030-03-13", end: "2030-03-18", today: today))
    }

    func testAWindowOfSevenDaysIsSent() {
        XCTAssertNotNil(PFJobInputs.experimentDefine(title: "T", question: "Q?", outcome: "hrv", start: "2030-03-13", end: "2030-03-19", today: today))
    }

    func testAWindowOfNinetyOneDaysIsNotSent() {
        XCTAssertNil(PFJobInputs.experimentDefine(title: "T", question: "Q?", outcome: "hrv", start: "2030-03-13", end: "2030-06-11", today: today))
    }

    func testAWindowStartingTooFarBackIsNotSent() {
        XCTAssertNil(PFJobInputs.experimentDefine(title: "T", question: "Q?", outcome: "hrv", start: "2029-08-01", end: "2029-08-14", today: today))
    }

    func testAWindowEndingTooFarAheadIsNotSent() {
        XCTAssertNil(PFJobInputs.experimentDefine(title: "T", question: "Q?", outcome: "hrv", start: "2030-05-20", end: "2030-06-02", today: today))
    }

    func testAnUnknownOutcomeIsNotSent() {
        XCTAssertNil(PFJobInputs.experimentDefine(title: "T", question: "Q?", outcome: "mood", start: "2030-03-13", end: "2030-03-26", today: today))
    }

    func testAnExperimentWithoutAHabitSaysWhatIsMissing() {
        XCTAssertEqual(PFExperimentRules.problem(title: "T", question: nil, outcome: "hrv", start: "2030-03-13", end: "2030-03-26", today: today),
                       "Choose the habit it is about.")
    }

    func testReviewAndRetireNeedAnIDOfSixteenHexDigits() {
        XCTAssertEqual([PFJobInputs.experimentAction("review", id: "0123456789abcdef") != nil,
                        PFJobInputs.experimentAction("retire", id: "XYZ") != nil], [true, false])
    }

    func testTheListIsReadNewestFirst() {
        let data = Data("""
        {"experiments": [{"id": "0123456789abcdef", "title": "Older", "question": "Q?", "outcome": "hrv", "start": "2030-01-01", "end": "2030-01-14", "status": "running"},
                         {"id": "fedcba9876543210", "title": "Newer", "question": "Q?", "outcome": "hrv", "start": "2030-03-01", "end": "2030-03-14", "status": "running"}]}
        """.utf8)
        XCTAssertEqual(PFExperiment.parseList(data).map(\.title), ["Newer", "Older"])
    }

    // MARK: Review

    private let caveat = "Other things differ on those days (training, sleep, stress, the season). It is one person with no control group, and with several habits and outcomes to look at, some will line up by chance. A lead to test, not a result."

    private func review(status: String, effect: String, nYes: Int = 12, nNo: Int = 9) -> String {
        """
        {"id": "0123456789abcdef", "scope": "experiment:0123456789abcdef", "title": "Evening caffeine", "question": "Caffeine after 3pm?",
         "outcome": {"id": "hrv", "label": "HRV", "unit": "ms", "source": "Garmin"},
         "window": {"start": "2030-03-01", "end": "2030-03-28", "evaluated_through": "2030-03-13"}, "lag_days": 1,
         "n_yes": \(nYes), "n_no": \(nNo), "min_each": 5, "answered_without_reading": 2, "status": "\(status)",
         "statement": "A statement from the server.", "effect": \(effect), "caveat": "\(caveat)"}
        """
    }

    func testTheCaveatIsCarriedWordForWord() {
        XCTAssertEqual(PFExperimentReview.parse(json(review(status: "not_enough_data", effect: "null")))?.caveat, caveat)
    }

    func testBelowTheMinimumNoNumberIsShown() {
        let parsed = PFExperimentReview.parse(json(review(status: "not_enough_data", effect: "null", nYes: 3, nNo: 2)))
        XCTAssertEqual(parsed?.effectLines(valueText: { "\($0)" }), [])
    }

    func testAnEarlyReviewShowsTheNumbersToInspect() {
        let effect = "{\"mean_yes\": 55.0, \"mean_no\": 62.0, \"diff\": -7.0, \"pct\": -11.3, \"t\": -2.1, \"effect_size\": -0.8, \"confidence\": \"low\"}"
        let parsed = PFExperimentReview.parse(json(review(status: "too_early", effect: effect)))
        XCTAssertEqual(parsed?.effectLines(valueText: { "\(PFFormat.trimmed($0)) ms" }).first,
                       "Next-morning average after a yes: 55 ms. After a no: 62 ms.")
    }

    func testTheStatusReadsInPlainWords() {
        XCTAssertEqual(PFExperimentReview.parse(json(review(status: "too_early", effect: "null")))?.statusTitle, "Too early to act on")
    }

    func testTheServersStatementIsKeptAsItIs() {
        XCTAssertEqual(PFExperimentReview.parse(json(review(status: "no_clear_difference", effect: "null")))?.statement, "A statement from the server.")
    }

    func testDaysWithAnAnswerButNoReadingAreSaid() {
        XCTAssertEqual(PFExperimentReview.parse(json(review(status: "no_clear_difference", effect: "null")))?.gapLine,
                       "2 answered days had no reading the next morning and are left out.")
    }

    func testAReviewWithoutACaveatIsNotUsable() {
        let text = review(status: "too_early", effect: "null").replacingOccurrences(of: "\"caveat\": \"\(caveat)\"", with: "\"caveat\": \"\"")
        XCTAssertNil(PFExperimentReview.parse(json(text)))
    }

    func testTheScopeIsTheThreadKeyOfTheExperiment() {
        XCTAssertEqual(PFExperimentReview.parse(json(review(status: "too_early", effect: "null")))?.scope, "experiment:0123456789abcdef")
    }
}
