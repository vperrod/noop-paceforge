import XCTest
@testable import Strand

/// The outcome review of accepted proposals and the contextual guides: how each document reads, which proposals belong to a reviewed week,
/// and where each guide step's control is on the iPhone. Every value is made up.
final class PaceForgeOutcomeGuidesTests: XCTestCase {
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    // MARK: Outcome review

    private let outcomes = """
    {"days": 7, "accepted": [
      {"id": "ab12", "title": "Ease Tuesday", "accepted_at": "2030-03-05T09:00:00+00:00", "changes": ["Tue 2030-03-12 Easy run shortened as you accepted"],
       "result": {"state": "recorded", "next_day": {"date": "2030-03-06", "recovery": 71, "resting_hr": 50, "hrv_last_night": 64, "sleep_duration_seconds": 27000},
                  "state_when_answered": {"resting_hr": 52}},
       "feedback": [{"ts": "2030-03-06T07:00:00Z", "verdict": "up", "reason": "Felt right", "source": "app"}]},
      {"id": "cd34", "title": "Move long run", "accepted_at": "2030-03-07T18:30:00+00:00", "changes": [],
       "result": {"state": "pending", "next_day": null, "state_when_answered": null}, "feedback": []},
      {"id": "ef56", "title": "Add a rest day", "accepted_at": "2030-03-10T08:00:00+00:00", "changes": [],
       "result": {"state": "none", "next_day": null, "state_when_answered": null}, "feedback": []}]}
    """

    func testEachAcceptedProposalIsRead() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes)).map(\.id), ["ab12", "cd34", "ef56"])
    }

    func testARecordedMorningListsEachReadingUnderItsOwnName() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes)).first?.nextReadings.map(\.label),
                       ["Charge (NOOP)", "Resting heart rate (Garmin)", "HRV last night (Garmin)", "Sleep (Garmin)"])
    }

    func testReadingsAreNeverCombined() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes)).first?.nextReadings.map(\.text), ["71%", "50 bpm", "64 ms", "7:30 h"])
    }

    func testTheValueWhenAnsweredIsKeptApart() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes)).first?.answeredReadings.map(\.text), ["52 bpm"])
    }

    func testTheThumbsAndItsReasonAreKept() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes)).first?.ratings, [PFOutcomeRow.Rating(verdict: "up", reason: "Felt right")])
    }

    func testAPendingMorningSaysItIsNotFiledYet() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes))[1].stateLine, "The next morning has not been filed yet.")
    }

    func testAProposalWithNoNextMorningSaysNothingIsTiedToIt() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes))[2].stateLine, "No next-morning reading is tied to this change.")
    }

    func testARecordedMorningNamesItsDay() {
        XCTAssertEqual(PFOutcomeReview.parse(json(outcomes)).first?.nextDay, "2030-03-06")
    }

    func testOnlyTheProposalsAcceptedInTheWeekBelongToIt() {
        let rows = PFOutcomeReview.parse(json(outcomes))
        XCTAssertEqual(PFOutcomeReview.rows(rows, from: "2030-03-04", to: "2030-03-10").map(\.id), ["ab12", "cd34", "ef56"])
    }

    func testAProposalAcceptedAfterTheWeekIsLeftOut() {
        let rows = PFOutcomeReview.parse(json(outcomes))
        XCTAssertEqual(PFOutcomeReview.rows(rows, from: "2030-03-04", to: "2030-03-06").map(\.id), ["ab12"])
    }

    func testTheRequestReachesBackToTheWeeksFirstDay() {
        XCTAssertEqual(PFOutcomeReview.days(weekStart: "2030-03-04", today: "2030-03-13"), 10)
    }

    func testTheRequestIsAtLeastAWeek() {
        XCTAssertEqual(PFOutcomeReview.days(weekStart: "2030-03-11", today: "2030-03-13"), 7)
    }

    func testTheRequestIsAtMostThirtyDays() {
        XCTAssertEqual(PFOutcomeReview.days(weekStart: "2030-02-01", today: "2030-03-13"), 30)
    }

    func testAWeekOlderThanTheLogHasNothingToAsk() {
        XCTAssertFalse(PFOutcomeReview.isInLog(weekStart: "2030-02-01", today: "2030-03-13"))
    }

    func testARecentWeekIsStillInTheLog() {
        XCTAssertTrue(PFOutcomeReview.isInLog(weekStart: "2030-03-04", today: "2030-03-13"))
    }

    func testAnEmptyReviewReadsAsNoRows() {
        XCTAssertEqual(PFOutcomeReview.parse(json("{\"days\": 7, \"accepted\": []}")), [])
    }

    // MARK: Guides

    private let guides = """
    {"version": 1, "guides": [
     {"id": "fix-sleep", "title": "Check or question a night of sleep", "summary": "Recorded sleep is never rewritten.", "steps": [
       {"text": "Open Sleep.", "web": "#/health/sleep"},
       {"text": "Under Tonight.", "web": "#/health/sleep", "anchor": "part-planner"},
       {"text": "Tell the Coach.", "web": "#/coach", "job": "coach"}]},
     {"id": "edit-plan", "title": "Change your plan", "summary": "Edit one session.", "steps": [
       {"text": "Open Plan, Week.", "web": "#/plan/week"},
       {"text": "Reschedule it.", "job": "calendar-edit"},
       {"text": "Swap it.", "job": "session-swap"},
       {"text": "Set the hours.", "job": "plan-hours"},
       {"text": "Move a race.", "web": "#/plan/events", "job": "event-update"}]},
     {"id": "correct-workout", "title": "Correct a workout", "summary": "Fix a record.", "steps": [
       {"text": "Open Activities.", "web": "#/train/activities"},
       {"text": "Set how hard it felt.", "job": "save-rpe"}]},
     {"id": "find-reports", "title": "Find your reports", "summary": "Reports.", "steps": [
       {"text": "Open Reports.", "web": "#/plan/reports"},
       {"text": "The weekly review.", "web": "#/health/weekly"},
       {"text": "The index.", "route": "/data/reports/list.json"}]},
     {"id": "import-csv", "title": "Import a CSV", "summary": "Preview first.", "steps": [
       {"text": "Preview.", "job": "strength-import-preview"},
       {"text": "Confirm.", "job": "strength-import"},
       {"text": "History.", "route": "/strength-history"},
       {"text": "Lab results.", "native": "Lab Book > markers CSV"},
       {"text": "The Lab Book page.", "web": "#/health/labbook"},
       {"text": "Something the app does not have.", "web": "#/admin/nothing"}]}]}
    """

    private func targets(_ id: String) -> [PFGuideTarget?] {
        (PFGuides.parse(json(guides)).first { $0.id == id }?.steps ?? []).map { PFGuideTarget.resolve($0) }
    }

    func testEveryGuideIsRead() {
        XCTAssertEqual(PFGuides.parse(json(guides)).map(\.id), ["fix-sleep", "edit-plan", "correct-workout", "find-reports", "import-csv"])
    }

    func testStepsKeepTheirOrderAndTheirAnchor() {
        let step = PFGuides.parse(json(guides)).first?.steps[1]
        XCTAssertEqual([step?.index, step?.anchor == "part-planner" ? 1 : 0], [1, 1])
    }

    func testSleepStepsGoToHealthSleepAndTheCoach() {
        XCTAssertEqual(targets("fix-sleep"), [.healthSleep, .healthSleep, .coach])
    }

    func testPlanStepsGoToTheWeekTheSettingsAndTheSeason() {
        XCTAssertEqual(targets("edit-plan"), [.planWeek, .planWeek, .planWeek, .planSettings, .planSeason])
    }

    func testWorkoutStepsGoToTheWorkoutsList() {
        XCTAssertEqual(targets("correct-workout"), [.trainWorkouts, .trainWorkouts])
    }

    func testReportStepsGoToThePlanReports() {
        XCTAssertEqual(targets("find-reports"), [.planReports, .planReports, .planReports])
    }

    func testImportStepsGoToTheStrengthChipAndTheLabBook() {
        XCTAssertEqual(targets("import-csv"), [.trainStrength, .trainStrength, .trainStrength, .labBook, .labBook, nil])
    }

    func testAStepThatNamesNothingTheAppHasGetsNoButton() {
        XCTAssertNil(PFGuideTarget.resolve(PFGuide.Step(index: 0, text: "Just read this.")))
    }

    func testAGuideWithoutATitleIsLeftOut() {
        XCTAssertEqual(PFGuides.parse(json("{\"guides\": [{\"id\": \"x\", \"steps\": []}]}")), [])
    }
}
