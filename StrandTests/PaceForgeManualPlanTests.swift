import XCTest
@testable import Strand

/// Editing a planned session, adding one, and logging a workout by hand: each form's rules and the inputs it sends (field names as the job
/// contract and the server's validators have them). All values are made up.
final class PaceForgeManualPlanTests: XCTestCase {
    private let today = "2030-03-13"

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private func logDraft(_ change: (inout PFManualWorkoutDraft) -> Void = { _ in }) -> PFManualWorkoutDraft {
        var draft = PFManualWorkoutDraft(date: "2030-03-12")
        draft.minutesText = "45"
        change(&draft)
        return draft
    }

    private let saved = PFManualWorkout(id: "manual:abc123", date: "2030-03-12", startTime: "07:30", sport: "Run", minutes: 45, km: 8.5,
                                        avgHR: 150, maxHR: 170, rpe: 6, notes: "Felt fine", planSessionID: nil)

    // MARK: calendar-edit, edit

    func testEditSendsOnlyTheFieldsGiven() {
        assertSame(PFJobInputs.calendarEdit(sessionID: "s1", minutes: 50, targetRPE: 6),
                   ["session_id": "s1", "action": "edit", "minutes": 50, "target_rpe": 6])
    }

    func testEditWithNothingToChangeIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarEdit(sessionID: "s1"))
    }

    func testEditWithMinutesBelowFiveIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarEdit(sessionID: "s1", minutes: 4))
    }

    func testEditWithMinutesAboveSixHundredIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarEdit(sessionID: "s1", minutes: 601))
    }

    func testEditWithEffortAboveTenIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarEdit(sessionID: "s1", targetRPE: 11))
    }

    func testEditWithADateThatIsNotADayIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarEdit(sessionID: "s1", newDate: "16 March"))
    }

    func testEditCarriesATemplateKey() {
        assertSame(PFJobInputs.calendarEdit(sessionID: "s1", template: "bike_sweet_spot"),
                   ["session_id": "s1", "action": "edit", "template": "bike_sweet_spot"])
    }

    func testEditWithATemplateThatIsNotAKeyIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarEdit(sessionID: "s1", template: "a b/c"))
    }

    func testEditWithoutASessionIdIsNotSent() {
        XCTAssertNil(PFJobInputs.calendarEdit(sessionID: nil, minutes: 50))
    }

    // MARK: Session edit form

    func testAnUntouchedEditFormHasNothingToSend() {
        XCTAssertNil(PFSessionEditDraft(date: "2030-03-15", minutes: 45, rpe: 5).inputs(sessionID: "s1", today: today))
    }

    func testAnUntouchedEditFormSaysNothingChanged() {
        XCTAssertEqual(PFSessionEditDraft(date: "2030-03-15", minutes: 45, rpe: 5).problem(today: today), "Nothing has changed.")
    }

    func testChangingTheMinutesSendsOnlyTheMinutes() {
        var draft = PFSessionEditDraft(date: "2030-03-15", minutes: 45, rpe: 5)
        draft.minutesText = "60"
        assertSame(draft.inputs(sessionID: "s1", today: today), ["session_id": "s1", "action": "edit", "minutes": 60])
    }

    func testChangingTheDayAndTheEffortSendsBoth() {
        var draft = PFSessionEditDraft(date: "2030-03-15", minutes: 45, rpe: 5)
        draft.date = "2030-03-17"
        draft.rpeText = "7"
        assertSame(draft.inputs(sessionID: "s1", today: today),
                   ["session_id": "s1", "action": "edit", "new_date": "2030-03-17", "target_rpe": 7])
    }

    func testABlankMinutesFieldLeavesTheMinutesAlone() {
        var draft = PFSessionEditDraft(date: "2030-03-15", minutes: 45, rpe: 5)
        draft.minutesText = " "
        draft.rpeText = "6"
        assertSame(draft.inputs(sessionID: "s1", today: today), ["session_id": "s1", "action": "edit", "target_rpe": 6])
    }

    func testMinutesThatAreNotANumberAreRefusedWithAReason() {
        var draft = PFSessionEditDraft(date: "2030-03-15", minutes: 45, rpe: 5)
        draft.minutesText = "abc"
        XCTAssertEqual(draft.problem(today: today), "Minutes must be a whole number from 5 to 600.")
    }

    func testADayMoreThanFourHundredDaysAwayIsRefused() {
        var draft = PFSessionEditDraft(date: "2030-03-15", minutes: 45, rpe: 5)
        draft.date = "2031-06-01"
        XCTAssertEqual(draft.problem(today: today), "That day is more than 400 days away.")
    }

    func testASessionWithNoMinutesOnThePlanCanBeGivenSome() {
        var draft = PFSessionEditDraft(date: "2030-03-15", minutes: nil, rpe: nil)
        draft.minutesText = "30"
        assertSame(draft.inputs(sessionID: "s1", today: today), ["session_id": "s1", "action": "edit", "minutes": 30])
    }

    // MARK: add-session

    func testAddingASessionSendsTheDaySportAndMinutes() {
        assertSame(PFAddSessionDraft(date: "2030-03-16").inputs(today: today),
                   ["date": "2030-03-16", "sport": "Run", "minutes": 45])
    }

    func testAddingASessionSendsItsNameWhenGiven() {
        var draft = PFAddSessionDraft(date: "2030-03-16")
        draft.name = "  Tempo on the canal "
        XCTAssertEqual(draft.inputs(today: today)?["name"] as? String, "Tempo on the canal")
    }

    func testAddingASessionRepeatedSendsTheWeeks() {
        var draft = PFAddSessionDraft(date: "2030-03-16")
        draft.repeatWeeks = 4
        XCTAssertEqual(draft.inputs(today: today)?["repeat_weeks"] as? Int, 4)
    }

    func testAddingASessionOnceSendsNoRepeat() {
        XCTAssertNil(PFAddSessionDraft(date: "2030-03-16").inputs(today: today)?["repeat_weeks"])
    }

    func testAddingASessionWithoutASportIsRefused() {
        var draft = PFAddSessionDraft(date: "2030-03-16")
        draft.sport = "  "
        XCTAssertEqual(draft.problem(today: today), "Say what sport it is.")
    }

    func testAddingASessionOfFourMinutesIsRefused() {
        var draft = PFAddSessionDraft(date: "2030-03-16")
        draft.minutesText = "4"
        XCTAssertEqual(draft.problem(today: today), "Minutes must be a whole number from 5 to 480.")
    }

    func testAddingASessionRepeatedFiftyThreeWeeksIsRefused() {
        var draft = PFAddSessionDraft(date: "2030-03-16")
        draft.repeatWeeks = 53
        XCTAssertEqual(draft.problem(today: today), "Repeat for 1 to 52 weeks.")
    }

    func testAddingASessionWithAMissingDayIsNotSent() {
        XCTAssertNil(PFAddSessionDraft(date: "").inputs(today: today))
    }

    // MARK: manual-workout

    func testLoggingAWorkoutSendsOnlyTheRequiredFieldsWhenTheRestIsBlank() {
        assertSame(logDraft().inputs(today: today), ["date": "2030-03-12", "sport": "Run", "minutes": 45])
    }

    func testLoggingAWorkoutSendsEveryFieldTyped() {
        let draft = logDraft {
            $0.startTime = "07:30"
            $0.kmText = "8,5"
            $0.avgHRText = "150"
            $0.maxHRText = "170"
            $0.rpeText = "6"
            $0.notes = " Felt fine "
            $0.planSessionID = "s1"
        }
        assertSame(draft.inputs(today: today),
                   ["date": "2030-03-12", "sport": "Run", "minutes": 45, "start_time": "07:30", "km": 8.5, "avg_hr": 150, "max_hr": 170,
                    "rpe": 6, "notes": "Felt fine", "plan_session_id": "s1"])
    }

    func testAWorkoutInTheFutureIsRefused() {
        XCTAssertEqual(logDraft { $0.date = "2030-03-14" }.problem(today: today), "A workout you did cannot be in the future.")
    }

    func testAWorkoutOfTodayIsAccepted() {
        XCTAssertNil(logDraft { $0.date = "2030-03-13" }.problem(today: today))
    }

    func testAWorkoutWithoutMinutesIsRefused() {
        XCTAssertEqual(logDraft { $0.minutesText = "" }.problem(today: today), "Minutes must be a whole number from 1 to 600.")
    }

    func testAStartTimeThatIsNotAClockTimeIsRefused() {
        XCTAssertEqual(logDraft { $0.startTime = "25:00" }.problem(today: today), "Start time must look like 07:30.")
    }

    func testADistanceOfZeroIsRefused() {
        XCTAssertEqual(logDraft { $0.kmText = "0" }.problem(today: today), "Distance must be more than 0 and up to 500 km.")
    }

    func testAMaxHeartRateBelowTheAverageIsRefused() {
        XCTAssertEqual(logDraft { $0.avgHRText = "160"; $0.maxHRText = "150" }.problem(today: today),
                       "Max heart rate cannot be below the average.")
    }

    func testAHeartRateBelowThirtyIsRefused() {
        XCTAssertEqual(logDraft { $0.avgHRText = "20" }.problem(today: today), "Average heart rate must be 30 to 230.")
    }

    func testEffortOfElevenIsRefused() {
        XCTAssertEqual(logDraft { $0.rpeText = "11" }.problem(today: today), "Effort must be a whole number from 1 to 10.")
    }

    func testNotesOfMoreThanFiveHundredCharactersAreRefused() {
        XCTAssertEqual(logDraft { $0.notes = String(repeating: "a", count: 501) }.problem(today: today), "Notes are too long (500 characters at most).")
    }

    func testALinkThatIsNotASessionIdIsRefused() {
        XCTAssertEqual(logDraft { $0.planSessionID = "../plan" }.problem(today: today), "That planned session cannot be linked.")
    }

    func testAFormWithAProblemSendsNothing() {
        XCTAssertNil(logDraft { $0.minutesText = "0" }.inputs(today: today))
    }

    // MARK: manual-workout-edit and -delete

    func testEditingAWorkoutWithoutChangesSendsNothing() {
        XCTAssertNil(PFManualWorkoutDraft(editing: saved).editInputs(from: saved, today: today))
    }

    func testEditingAWorkoutSendsTheIdAndWhatChanged() {
        var draft = PFManualWorkoutDraft(editing: saved)
        draft.minutesText = "50"
        assertSame(draft.editInputs(from: saved, today: today), ["id": "manual:abc123", "minutes": 50])
    }

    func testClearingAnOptionalFieldSendsNull() {
        var draft = PFManualWorkoutDraft(editing: saved)
        draft.notes = ""
        XCTAssertTrue(draft.editInputs(from: saved, today: today)?["notes"] is NSNull)
    }

    func testEditingToSomethingInvalidSendsNothing() {
        var draft = PFManualWorkoutDraft(editing: saved)
        draft.rpeText = "12"
        XCTAssertNil(draft.editInputs(from: saved, today: today))
    }

    func testRemovingAWorkoutSendsOnlyItsId() {
        assertSame(PFJobInputs.manualWorkoutDelete(id: "manual:abc123"), ["id": "manual:abc123"])
    }

    func testRemovingAWorkoutWithoutAnIdSendsNothing() {
        XCTAssertNil(PFJobInputs.manualWorkoutDelete(id: nil))
    }

    func testAnEditWithNoChangesIsNotBuilt() {
        XCTAssertNil(PFJobInputs.manualWorkoutEdit(id: "manual:abc123", changes: [:]))
    }

    // MARK: The list of logged workouts

    private func list(_ json: String) -> [PFManualWorkout] { PFManualWorkouts.parse(json.data(using: .utf8)) }

    func testAListGivenAsAnArrayIsRead() {
        let rows = list(#"[{"id":"manual:a","date":"2030-03-12","sport":"Run","minutes":45,"km":8.5,"avg_hr":150,"rpe":6,"start_time":"07:30"}]"#)
        XCTAssertEqual(rows, [PFManualWorkout(id: "manual:a", date: "2030-03-12", startTime: "07:30", sport: "Run", minutes: 45, km: 8.5,
                                              avgHR: 150, maxHR: nil, rpe: 6, notes: nil, planSessionID: nil)])
    }

    func testAListGivenInsideAnObjectIsRead() {
        XCTAssertEqual(list(#"{"workouts":[{"id":"manual:a","date":"2030-03-12","sport":"Run","minutes":45}]}"#).count, 1)
    }

    func testADeletedWorkoutIsLeftOut() {
        XCTAssertEqual(list(#"[{"id":"manual:a","date":"2030-03-12","sport":"Run","minutes":45,"deleted":true}]"#).count, 0)
    }

    func testARowWithoutMinutesIsLeftOut() {
        XCTAssertEqual(list(#"[{"id":"manual:a","date":"2030-03-12","sport":"Run"}]"#).count, 0)
    }

    func testTheNewestWorkoutComesFirst() {
        let rows = list(#"[{"id":"manual:a","date":"2030-03-10","sport":"Run","minutes":30},{"id":"manual:b","date":"2030-03-12","sport":"Bike","minutes":60}]"#)
        XCTAssertEqual(rows.map { $0.id }, ["manual:b", "manual:a"])
    }

    func testNothingServedReadsAsAnEmptyList() {
        XCTAssertEqual(PFManualWorkouts.parse(nil).count, 0)
    }

    // MARK: Draft retention

    func testAFormTheServerDidNotTakeIsKeptWhole() {
        let draft = logDraft { $0.notes = "typed" }
        XCTAssertEqual(PFDraftKeeping.afterSend(draft, tookIt: false), draft)
    }

    func testAFormTheServerTookIsCleared() {
        XCTAssertNil(PFDraftKeeping.afterSend(logDraft(), tookIt: true))
    }

    func testAKeptFormReadsBackTheSame() {
        let draft = logDraft { $0.kmText = "8,5"; $0.planSessionID = "s1" }
        XCTAssertEqual(PFDraftKeeping.decode(PFDraftKeeping.encode(draft)), draft)
    }

    func testNothingKeptReadsAsNoForm() {
        XCTAssertNil(PFDraftKeeping.decode(nil))
    }

    // MARK: Job names

    func testTheJobsAreNamedAsOnTheServer() {
        XCTAssertEqual([PFJobName.addSession, .manualWorkout, .manualWorkoutEdit, .manualWorkoutDelete].map { $0.rawValue },
                       ["add-session", "manual-workout", "manual-workout-edit", "manual-workout-delete"])
    }

    func testAWorkoutLoggedByHandIsNeverSentAgainBehindTheUsersBack() {
        XCTAssertEqual([PFJobName.addSession, .manualWorkout, .manualWorkoutEdit, .manualWorkoutDelete].map { $0.isQueueable },
                       [false, false, false, false])
    }
}

/// "Also send to Coach": the phone's own Add Workout sheet filled into the one manual-workout payload. Made-up values, UTC so the day and clock are fixed.
final class PaceForgeSendToCoachTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let start = Date(timeIntervalSince1970: 1_899_532_800)

    private func draft(sport: String = "Running", minutes: Double = 45, km: Double? = nil, avgHR: Int? = nil) -> PFManualWorkoutDraft? {
        PFManualWorkoutDraft(savedOnPhone: sport, start: start, end: start.addingTimeInterval(minutes * 60), distanceKm: km, avgHR: avgHR, timeZone: utc)
    }

    func testPhoneSportRunningIsRun() {
        XCTAssertEqual(PFManualPlan.coachSport(forPhoneSport: "Running"), "Run")
    }

    func testPhoneSportCyclingIsBike() {
        XCTAssertEqual(PFManualPlan.coachSport(forPhoneSport: "Cycling"), "Bike")
    }

    func testPhoneSportWeightliftingIsStrength() {
        XCTAssertEqual(PFManualPlan.coachSport(forPhoneSport: "Weightlifting"), "Strength")
    }

    func testPhoneSportPadelIsNotSent() {
        XCTAssertNil(PFManualPlan.coachSport(forPhoneSport: "Padel"))
    }

    func testDraftReadsTheDayAndClockOfTheStart() {
        XCTAssertEqual(draft()?.date, "2030-03-12")
        XCTAssertEqual(draft()?.startTime, "08:00")
    }

    func testDraftTurnsStartAndEndIntoMinutes() {
        XCTAssertEqual(draft(minutes: 45)?.minutesText, "45")
    }

    func testDraftUnderOneMinuteIsSkipped() {
        XCTAssertNil(draft(minutes: 0.4))
    }

    func testDraftOverSixHundredMinutesIsSkipped() {
        XCTAssertNil(draft(minutes: 601))
    }

    func testDraftWithAnUnknownSportIsSkipped() {
        XCTAssertNil(draft(sport: "Padel"))
    }

    func testPayloadCarriesSportMinutesDistanceAndHeartRate() {
        let inputs = draft(km: 8.456, avgHR: 150)?.inputs(today: "2030-03-13")
        XCTAssertEqual(inputs as NSDictionary?, ["date": "2030-03-12", "sport": "Run", "minutes": 45, "start_time": "08:00", "km": 8.46, "avg_hr": 150] as NSDictionary)
    }

    func testZeroDistanceIsLeftOutNotRefused() {
        XCTAssertNil(draft(km: 0)?.inputs(today: "2030-03-13")?["km"])
    }

    func testHeartRateOutsideTheServersRangeIsLeftOutNotRefused() {
        XCTAssertNil(draft(avgHR: 25)?.inputs(today: "2030-03-13")?["avg_hr"])
    }
}
