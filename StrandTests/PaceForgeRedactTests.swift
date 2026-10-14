import XCTest
@testable import Strand

/// Hide numbers applied to sentences: the same two switches as the figures, so a brief that says "Recovery 74"
/// reads "Recovery Hidden" while the Charge/Effort/Sleep switch is on. The examples are made-up sentences in the
/// shapes the server writes.
final class PaceForgeRedactTests: XCTestCase {
    private func scores(_ text: String) -> String { PFRedact.text(text, scores: true, body: false) }
    private func body(_ text: String) -> String { PFRedact.text(text, scores: false, body: true) }

    func testThePlaceholderIsTheSameWordAsTheFigures() {
        XCTAssertEqual(PFRedact.placeholder, HideScoresPrefs.placeholder)
    }

    func testAScoreNextToItsLabelIsHidden() {
        XCTAssertEqual(scores("Recovery 74 (green), strain 12.3 of 21."), "Recovery Hidden (green), strain Hidden.")
    }

    func testAScoreAfterIsAndAPercentSignIsHidden() {
        XCTAssertEqual(scores("Your recovery is 74%."), "Your recovery is Hidden.")
    }

    func testAScoreInBoldMarkdownIsHidden() {
        XCTAssertEqual(scores("**Recovery:** 74"), "**Recovery:** Hidden")
    }

    func testAStrainTargetRangeIsHidden() {
        XCTAssertEqual(scores("Strain target 10-13 today."), "Strain target Hidden today.")
    }

    func testAScoreBeforeItsLabelIsHidden() {
        XCTAssertEqual(scores("A 74% recovery morning."), "A Hidden recovery morning.")
    }

    func testASleepScoreIsHidden() {
        XCTAssertEqual(scores("Sleep score 84, readiness 61 \u{00B7} low."), "Sleep score Hidden, readiness Hidden \u{00B7} low.")
    }

    func testAScoreOfIsHidden() {
        XCTAssertEqual(scores("The score of 82 held."), "The score of Hidden held.")
    }

    func testARideRowsTrainingStressIsHidden() {
        XCTAssertEqual(scores("60 min \u{00B7} avg 160 W \u{00B7} TSS 62 \u{00B7} avg HR 148 bpm"),
                       "60 min \u{00B7} avg 160 W \u{00B7} TSS Hidden \u{00B7} avg HR 148 bpm")
    }

    func testAnRpeIsHidden() {
        XCTAssertEqual(scores("RPE 7 of 10 for the long ride."), "RPE Hidden for the long ride.")
    }

    func testSleepDurationIsNotAScore() {
        XCTAssertEqual(scores("Sleep 7h20 against 8h00 needed."), "Sleep 7h20 against 8h00 needed.")
    }

    func testSleepInHoursIsNotAScore() {
        XCTAssertEqual(scores("Sleep 7 hours last night."), "Sleep 7 hours last night.")
    }

    func testAnEffortInMinutesIsNotAScore() {
        XCTAssertEqual(scores("Effort 20 min at threshold."), "Effort 20 min at threshold.")
    }

    func testARecoveryRunIsNotAScore() {
        XCTAssertEqual(scores("Recovery run 5 km easy."), "Recovery run 5 km easy.")
    }

    func testScoresStayWhenOnlyTheBodySwitchIsOn() {
        XCTAssertEqual(body("Recovery 74 (green)."), "Recovery 74 (green).")
    }

    func testAWeightInKilogramsIsHidden() {
        XCTAssertEqual(body("Weight 82.4 kg, down 0.4 kg this week."), "Weight Hidden, down Hidden this week.")
    }

    func testAWeeklyChangeWithItsSignIsHidden() {
        XCTAssertEqual(body("Trend -0.4 kg/week."), "Trend Hidden.")
    }

    func testABodyFatPercentAfterItsLabelIsHidden() {
        XCTAssertEqual(body("Body fat 18.2%."), "Body fat Hidden.")
    }

    func testABodyFatPercentBeforeItsLabelIsHidden() {
        XCTAssertEqual(body("Down to 18.2% body fat."), "Down to Hidden body fat.")
    }

    func testBmiAndLeanMassAreHidden() {
        XCTAssertEqual(body("BMI 24.1, lean mass 63.5 kg."), "BMI Hidden, lean mass Hidden.")
    }

    func testAWaistWithoutAKilogramUnitIsHidden() {
        XCTAssertEqual(body("Waist 92.5 cm."), "Waist Hidden cm.")
    }

    func testPoundsAreHiddenToo() {
        XCTAssertEqual(body("Weighed 180 lb."), "Weighed Hidden.")
    }

    func testGramsOfFatAreNotBodyFat() {
        XCTAssertEqual(body("Fat 20 g at breakfast."), "Fat 20 g at breakfast.")
    }

    func testBodyFiguresStayWhenOnlyTheScoresSwitchIsOn() {
        XCTAssertEqual(scores("Weight 82.4 kg."), "Weight 82.4 kg.")
    }

    func testBothSwitchesHideBoth() {
        XCTAssertEqual(PFRedact.text("Recovery 74 at 82.4 kg.", scores: true, body: true), "Recovery Hidden at Hidden.")
    }

    func testBothSwitchesOffChangeNothing() {
        XCTAssertEqual(PFRedact.text("Recovery 74 at 82.4 kg.", scores: false, body: false), "Recovery 74 at 82.4 kg.")
    }

    func testHidingTwiceGivesTheSameText() {
        let once = PFRedact.text("Recovery 74, weight 82.4 kg, 18% body fat.", scores: true, body: true)
        XCTAssertEqual(PFRedact.text(once, scores: true, body: true), once)
    }

    func testEmptyTextStaysEmpty() {
        XCTAssertEqual(PFRedact.text("", scores: true, body: true), "")
    }

    func testTextWithNoFiguresIsUntouched() {
        XCTAssertEqual(scores("A green morning, so the intervals are on."), "A green morning, so the intervals are on.")
    }

    func testBodyCompositionMetricsOfTheScorecardFollowTheBodySwitch() {
        XCTAssertEqual(["body_fat", "ffmi", "waist_cm", "whtr", "bmi"].map(PFRedact.kind(forStandingMetric:)),
                       [.body, .body, .body, .body, .body])
    }

    func testSleepMetricsOfTheScorecardFollowTheScoresSwitch() {
        XCTAssertEqual(["sleep_duration", "sleep_consistency"].map(PFRedact.kind(forStandingMetric:)), [.scores, .scores])
    }

    func testOtherScorecardMetricsAreNeverHidden() {
        XCTAssertNil(PFRedact.kind(forStandingMetric: "vo2max"))
    }
}
