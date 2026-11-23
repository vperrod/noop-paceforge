import XCTest
@testable import Strand

/// The redesigned Plan screens (build 543): the week document's new optional fields (and the old document without them), the words of a
/// session row, its badges and its VoiceOver sentence, the needs-you strip, the week notes, the overlap sheet, the skip confirmation, the Coach's
/// workout questions (pages, typed answers, payload), the asked-against-did table and the notes thread. Every name and number is made up.
final class PFPlanScreens543Tests: XCTestCase {
    // MARK: Helpers

    private func doc(_ text: String) throws -> PFPlanWeekDoc {
        try PFPlan529Decoder.make().decode(PFPlanWeekDoc.self, from: Data(text.utf8))
    }

    private func item(_ text: String) throws -> PFPlanWeekDoc.Item {
        try PFPlan529Decoder.make().decode(PFPlanWeekDoc.Item.self, from: Data(text.utf8))
    }

    private func ask(_ text: String) throws -> PFWorkoutAsk543 {
        try XCTUnwrap(PFWorkoutAsk543.parse(PFJ(data: Data(text.utf8))))
    }

    private let coachRun = """
    {"kind": "session", "session_id": "s-1", "title": "Run test", "minutes": 54, "status": "planned", "coach_assigned": true, "mandatory": true,
     "pieces": [{"n": 1, "label": "2 km warm-up"}, {"n": 2, "label": "5 km"}, {"n": 3, "label": "2 km cooldown"}]}
    """

    private let planWithNewFields = """
    {"week": "2030-W11", "state": "current",
     "days": [{"date": "2030-03-11", "dow": "Mon", "items": [
       {"kind": "session", "session_id": "s-1", "title": "Run test", "status": "planned",
        "pieces": [{"n": 1, "label": "Warm-up 2 km", "text": "Easy", "effort": "easy", "band": "Heart rate under Z2", "unknown": false}],
        "state_label": "To do", "source_label": "From your coach", "required_this_week": true,
        "overlap": {"with": ["Cardio Class"], "reason": "Two sessions on one day"}, "needs_you": true}]}],
     "needs_you": {"count": 2, "items": [{"kind": "question", "title": "Answer the Coach", "session_id": "s-1", "activity_id": "9"}]},
     "notes": {"coach_week": {"last_sync": "2030-03-11T08:00:00+00:00", "count": 6, "error": null}, "changes": {"count": 0},
               "hours": {"planned_h": 5.5, "estimated": true}, "rhythm": "Sunday at seven", "deleted": {"count": 1}}}
    """

    private let planWithoutNewFields = """
    {"week": "2030-W10", "state": "current",
     "days": [{"date": "2030-03-04", "dow": "Mon", "items": [{"kind": "session", "session_id": "s-9", "title": "Easy run", "status": "planned"}]}]}
    """

    /// A Monday with a finished-or-not set of sessions for the notes and the report.
    private let weekOfFive = """
    {"week": "2030-W11", "state": "finished", "days": [
      {"date": "2030-03-11", "dow": "Mon", "items": [
        {"kind": "session", "session_id": "a", "title": "Run test", "status": "done", "coach_assigned": true},
        {"kind": "session", "session_id": "b", "title": "35 min easy run", "status": "planned"}]},
      {"date": "2030-03-12", "dow": "Tue", "items": [
        {"kind": "session", "session_id": "c", "title": "Strength A", "status": "planned", "coach_assigned": true},
        {"kind": "rest", "title": "Rest"}]},
      {"date": "2030-03-13", "dow": "Wed", "items": [
        {"kind": "session", "session_id": "d", "title": "Wod A", "status": "done", "coach_assigned": true}]}]}
    """

    private let overlapDay = """
    {"date": "2030-03-12", "dow": "Tue", "items": [
      {"kind": "session", "session_id": "s1", "title": "Strength A", "status": "planned", "coach_assigned": true, "mandatory": true,
       "overlap": {"with": ["Cardio Class"], "reason": "Two hard days"}},
      {"kind": "session", "session_id": "s2", "title": "Cardio Class", "status": "planned",
       "overlap": {"with": ["Strength A"], "reason": "Two hard days"}}]}
    """

    // MARK: The week document

    func testAWeekWithTheNewFieldsKeepsThePieces() throws {
        XCTAssertEqual(try doc(planWithNewFields).days?.first?.items?.first?.pieces?.first?.label, "Warm-up 2 km")
    }

    func testAWeekWithTheNewFieldsKeepsTheStateWord() throws {
        XCTAssertEqual(try doc(planWithNewFields).days?.first?.items?.first?.stateLabel, "To do")
    }

    func testAWeekWithTheNewFieldsKeepsWhoItComesFrom() throws {
        XCTAssertEqual(try doc(planWithNewFields).days?.first?.items?.first?.sourceLabel, "From your coach")
    }

    func testAWeekWithTheNewFieldsKeepsRequiredThisWeek() throws {
        XCTAssertEqual(try doc(planWithNewFields).days?.first?.items?.first?.requiredThisWeek, true)
    }

    func testAWeekWithTheNewFieldsKeepsTheOverlapNames() throws {
        XCTAssertEqual(try doc(planWithNewFields).days?.first?.items?.first?.overlap?.with, ["Cardio Class"])
    }

    func testAWeekWithTheNewFieldsKeepsTheWaitingFlag() throws {
        XCTAssertEqual(try doc(planWithNewFields).days?.first?.items?.first?.needsYou, true)
    }

    func testAWeekWithTheNewFieldsKeepsTheNeedsYouActivity() throws {
        XCTAssertEqual(try doc(planWithNewFields).needsYou?.items?.first?.activityId, "9")
    }

    func testAWeekWithTheNewFieldsKeepsTheNotesHours() throws {
        XCTAssertEqual(try doc(planWithNewFields).notes?.hours?.plannedH, 5.5)
    }

    func testAWeekWithTheNewFieldsKeepsTheNotesCoachWeekCount() throws {
        XCTAssertEqual(try doc(planWithNewFields).notes?.coachWeek?.count, 6)
    }

    func testAWeekWithTheNewFieldsKeepsTheDeletedCount() throws {
        XCTAssertEqual(try doc(planWithNewFields).notes?.deleted?.count, 1)
    }

    func testTodaysWeekWithoutTheNewFieldsStillDecodes() throws {
        XCTAssertEqual(try doc(planWithoutNewFields).days?.first?.items?.first?.title, "Easy run")
    }

    func testTodaysWeekHasNoPieces() throws {
        XCTAssertNil(try doc(planWithoutNewFields).days?.first?.items?.first?.pieces)
    }

    func testTodaysWeekHasNoNeedsYouBlock() throws {
        XCTAssertNil(try doc(planWithoutNewFields).needsYou)
    }

    func testTodaysWeekHasNoNotes() throws {
        XCTAssertNil(try doc(planWithoutNewFields).notes)
    }

    // MARK: Row words

    func testACoachSessionSaysItComesFromTheCoach() throws {
        XCTAssertEqual(PFPlanRow543.source(try item(coachRun)), "From your coach")
    }

    func testAnUnmarkedSessionIsMine() throws {
        XCTAssertEqual(PFPlanRow543.source(try item(#"{"kind": "session", "title": "Easy run"}"#)), "Mine")
    }

    func testASessionWithAClassPillIsAClass() throws {
        XCTAssertEqual(PFPlanRow543.source(try item(#"{"kind": "session", "title": "Cardio Class", "pills": ["Class"]}"#)), "Class")
    }

    func testAProposedSessionIsADraft() throws {
        XCTAssertEqual(PFPlanRow543.source(try item(#"{"kind": "session", "title": "Easy run", "proposed": true}"#)), "Draft")
    }

    func testTheServersSourceLabelWins() throws {
        XCTAssertEqual(PFPlanRow543.source(try item(#"{"kind": "session", "coach_assigned": true, "source_label": "Class"}"#)), "Class")
    }

    func testARestDayHasNoSource() throws {
        XCTAssertNil(PFPlanRow543.source(try item(#"{"kind": "rest", "title": "Rest"}"#)))
    }

    func testAPlannedSessionIsToDo() throws {
        XCTAssertEqual(PFPlanRow543.stateWord(try item(coachRun)), "To do")
    }

    func testADoneSessionIsDone() throws {
        XCTAssertEqual(PFPlanRow543.stateWord(try item(#"{"kind": "session", "status": "done"}"#)), "Done")
    }

    func testAMissedSessionIsMissed() throws {
        XCTAssertEqual(PFPlanRow543.stateWord(try item(#"{"kind": "session", "status": "missed"}"#)), "Missed")
    }

    func testASkippedCoachSessionIsSkipped() throws {
        XCTAssertEqual(PFPlanRow543.stateWord(try item(#"{"kind": "session", "status": "planned", "skipped_mandatory": true}"#)), "Skipped")
    }

    func testTheServersStateLabelWins() throws {
        XCTAssertEqual(PFPlanRow543.stateWord(try item(#"{"kind": "session", "status": "done", "state_label": "Reassessing"}"#)), "Reassessing")
    }

    func testACoachRowCarriesThreeBadgesInOrder() throws {
        XCTAssertEqual(PFPlanRow543.badges(try item(coachRun)).map { $0.text }, ["From your coach", "Required this week", "To do"])
    }

    func testTheCoachBadgeHasTheCoachTone() throws {
        XCTAssertEqual(PFPlanRow543.badges(try item(coachRun)).first?.tone, .coach)
    }

    func testASkippedCoachSessionIsNoLongerRequired() throws {
        let skipped = try item(#"{"kind": "session", "status": "planned", "coach_assigned": true, "mandatory": true, "skipped_mandatory": true}"#)
        XCTAssertEqual(PFPlanRow543.badges(skipped).map { $0.text }, ["From your coach", "Skipped"])
    }

    func testAWaitingSessionSaysItNeedsAnAnswer() throws {
        let waiting = try item(#"{"kind": "session", "status": "done", "needs_you": true}"#)
        XCTAssertEqual(PFPlanRow543.badges(waiting).last?.text, "Needs your answer")
    }

    func testAnOverlapNamesTheOtherSession() throws {
        let overlapping = try item(#"{"kind": "session", "overlap": {"with": ["Strength A"]}}"#)
        XCTAssertEqual(PFPlanRow543.badges(overlapping).last?.text, "Overlaps Strength A")
    }

    func testAnOverlapWithSeveralSessionsJustSaysOverlaps() throws {
        let overlapping = try item(#"{"kind": "session", "overlap": {"with": ["A", "B"]}}"#)
        XCTAssertEqual(PFPlanRow543.badges(overlapping).last?.text, "Overlaps")
    }

    func testARestDayHasNoBadges() throws {
        XCTAssertEqual(PFPlanRow543.badges(try item(#"{"kind": "rest"}"#)), [])
    }

    func testASessionWithThreePiecesSumsThemUpByTheirLabels() throws {
        XCTAssertEqual(PFPlanRow543.summary(try item(coachRun)), "2 km warm-up, 5 km, 2 km cooldown")
    }

    func testASessionWithManyPiecesSaysHowManyAndWhichComesFirst() throws {
        let many = try item(#"{"kind": "session", "pieces": [{"label": "Deadlift 5 x 5"}, {"label": "B"}, {"label": "C"}, {"label": "D"}]}"#)
        XCTAssertEqual(PFPlanRow543.summary(many), "4 pieces, Deadlift 5 x 5 first")
    }

    func testASessionWithoutPiecesSaysItsLengthAndEffort() throws {
        XCTAssertEqual(PFPlanRow543.summary(try item(#"{"kind": "session", "minutes": 35, "effort_label": "Easy"}"#)), "35 min \u{00B7} Easy")
    }

    func testADoneSessionSaysWhatWasDone() throws {
        let done = try item(#"{"kind": "session", "status": "done", "minutes": 54, "done": {"line": "5.0 km in 25:10"}}"#)
        XCTAssertEqual(PFPlanRow543.summary(done), "5.0 km in 25:10")
    }

    func testARowReadsAloudAsOneSentence() throws {
        XCTAssertEqual(PFPlanRow543.sentence(try item(coachRun), dow: "Mon"),
                       "Monday, run test, from your coach, required this week, to do")
    }

    func testARowSentenceEndsWithItsOverlapAndItsWaitingQuestion() throws {
        let busy = try item(#"{"kind": "session", "title": "Cardio Class", "status": "planned", "needs_you": true, "overlap": {"with": ["Strength A"]}}"#)
        XCTAssertEqual(PFPlanRow543.sentence(busy, dow: "Tue"),
                       "Tuesday, cardio class, mine, to do, needs your answer, overlaps strength a")
    }

    func testAWeekdayIsWrittenOut() {
        XCTAssertEqual(PFPlanRow543.dayName("Thu"), "Thursday")
    }

    // MARK: The strip above Monday

    func testAWaitingWorkoutAndAnOverlapAreTwoEntries() throws {
        let busy = try doc("""
        {"days": [{"date": "2030-03-11", "dow": "Mon", "items": [
          {"kind": "session", "session_id": "a", "title": "Run test", "activity_id": "9", "needs_you": true, "overlap": {"with": ["Easy run"]}},
          {"kind": "session", "session_id": "b", "title": "Easy run", "overlap": {"with": ["Run test"]}}]}]}
        """)
        XCTAssertEqual(PFNeedsStrip543.entries(busy).map { $0.kind }, [.question, .overlap])
    }

    func testTheStripReadsTwoThingsNeedYou() {
        XCTAssertEqual(PFNeedsStrip543.headline(count: 2), "2 things need you")
    }

    func testTheStripReadsOneThingNeedsYou() {
        XCTAssertEqual(PFNeedsStrip543.headline(count: 1), "1 thing needs you")
    }

    func testTheStripListsEachKindOnce() throws {
        let entries = [PFNeedsEntry543(id: "1", kind: .question, title: "Answer the Coach", sessionID: nil, activityID: "9"),
                       PFNeedsEntry543(id: "2", kind: .question, title: "Answer the Coach", sessionID: nil, activityID: "10"),
                       PFNeedsEntry543(id: "3", kind: .overlap, title: "Review overlaps", sessionID: "s", activityID: nil)]
        XCTAssertEqual(PFNeedsStrip543.actionsLine(entries), "Answer the Coach \u{00B7} Review overlaps")
    }

    func testTheServersNeedsYouItemsAreUsedWhenItSendsThem() throws {
        let served = try doc(#"{"needs_you": {"count": 2, "items": [{"kind": "question", "activity_id": "9"}, {"kind": "overlap", "session_id": "s"}]}}"#)
        XCTAssertEqual(PFNeedsStrip543.entries(served).map { $0.kind }, [.question, .overlap])
    }

    func testAServedEntryWithoutATitleGetsTheKindsWords() throws {
        let served = try doc(#"{"needs_you": {"count": 1, "items": [{"kind": "question", "activity_id": "9"}]}}"#)
        XCTAssertEqual(PFNeedsStrip543.entries(served).first?.title, "Answer the Coach")
    }

    func testAChangeWaitingIsAnEntry() throws {
        let waiting = try doc(#"{"changes": [{"id": "c1", "title": "Shorter long run"}]}"#)
        XCTAssertEqual(PFNeedsStrip543.entries(waiting).map { $0.title }, ["Review changes"])
    }

    func testTheServersCountCanBeHigherThanWhatThePhoneCanList() throws {
        XCTAssertEqual(PFNeedsStrip543.count(try doc(#"{"needs_you": {"count": 3}}"#)), 3)
    }

    func testAKeptOverlapIsNotListedAgain() throws {
        let busy = try doc("""
        {"days": [{"date": "2030-03-11", "items": [
          {"kind": "session", "session_id": "a", "title": "Run test", "overlap": {"with": ["Easy run"]}}]}]}
        """)
        XCTAssertEqual(PFNeedsStrip543.entries(busy, keptOverlap: { _ in true }), [])
    }

    func testAKeptOverlapIsNotListedWhenTheServerSendsItsItems() throws {
        let served = try doc("""
        {"needs_you": {"count": 1, "items": [{"kind": "overlap", "session_id": "a"}]},
         "days": [{"date": "2030-03-11", "items": [
          {"kind": "session", "session_id": "a", "title": "Run test", "overlap": {"with": ["Easy run"]}}]}]}
        """)
        XCTAssertEqual(PFNeedsStrip543.entries(served, keptOverlap: { _ in true }), [])
        XCTAssertEqual(PFNeedsStrip543.count(served, keptOverlap: { _ in true }), 0)
    }

    func testTheKeepBothAnswerKeyIsThePerSessionIdempotencyKey() {
        XCTAssertEqual(PFOverlap543.keepKey(sessionID: "s 9/x"), "keep-s_9_x")
    }

    func testTheLiveQuestionsReplaceTheDocumentsOwn() {
        let fromDoc = [PFNeedsEntry543(id: "q", kind: .question, title: "Answer the Coach", sessionID: nil, activityID: nil),
                       PFNeedsEntry543(id: "o", kind: .overlap, title: "Review overlaps", sessionID: "s", activityID: nil)]
        XCTAssertEqual(PFNeedsStrip543.merged(fromDoc, liveQuestionActivityIDs: ["7", "8"]).map { $0.id }, ["live-7", "live-8", "o"])
    }

    func testWithoutLiveQuestionsTheDocumentsQuestionsStay() {
        let fromDoc = [PFNeedsEntry543(id: "o", kind: .overlap, title: "Review overlaps", sessionID: "s", activityID: nil),
                       PFNeedsEntry543(id: "q", kind: .question, title: "Answer the Coach", sessionID: nil, activityID: nil)]
        XCTAssertEqual(PFNeedsStrip543.merged(fromDoc, liveQuestionActivityIDs: []).map { $0.id }, ["q", "o"])
    }

    // MARK: Week notes

    func testTheProgressLineCountsEverySessionAndTheCoachs() throws {
        XCTAssertEqual(PFWeekNotes543.progressLine(try doc(weekOfFive)), "2 of 4 done \u{00B7} coach sessions 2 of 3")
    }

    func testAWeekWithoutSessionsHasNoProgressLine() throws {
        XCTAssertNil(PFWeekNotes543.progressLine(try doc(#"{"days": [{"date": "2030-03-11", "items": [{"kind": "rest"}]}]}"#)))
    }

    func testHoursAreWrittenInHoursAndMinutes() {
        XCTAssertEqual(PFWeekNotes543.hoursText(5.5), "5 h 30")
    }

    func testWholeHoursHaveNoMinutes() {
        XCTAssertEqual(PFWeekNotes543.hoursText(2), "2 h")
    }

    func testUnderAnHourIsInMinutes() {
        XCTAssertEqual(PFWeekNotes543.hoursText(0.75), "45 min")
    }

    func testEstimatedHoursSayTheCoachGaveNoDurations() {
        XCTAssertEqual(PFWeekNotes543.hoursLine(PFPlanWeekDoc.NotesHours(plannedH: 5.5, estimated: true), fallback: nil),
                       "Estimated, your coach gave no durations")
    }

    func testPlannedHoursAreSaidAsPlanned() {
        XCTAssertEqual(PFWeekNotes543.hoursLine(PFPlanWeekDoc.NotesHours(plannedH: 5.5, estimated: false), fallback: nil), "Planned 5 h 30")
    }

    func testNoChangesSaysNone() {
        XCTAssertEqual(PFWeekNotes543.changesLine(count: nil), "None")
    }

    func testChangesWaitingAreCounted() {
        XCTAssertEqual(PFWeekNotes543.changesLine(count: 2), "2 waiting for you")
    }

    func testNothingDeletedSaysSo() {
        XCTAssertEqual(PFWeekNotes543.deletedLine(count: 0), "Nothing in the last 30 days")
    }

    func testTheRhythmFallsBackToTheSundaySchedule() {
        XCTAssertEqual(PFWeekNotes543.rhythmLine(nil), PFWeekNotes543.rhythmDefault)
    }

    func testTheServersRhythmWins() throws {
        XCTAssertEqual(PFWeekNotes543.rhythmLine(try doc(planWithNewFields).notes), "Sunday at seven")
    }

    func testTheCoachWeekLineSaysWhenItWasReadAndHowMany() throws {
        let read = try XCTUnwrap(ISO8601DateFormatter().date(from: "2030-03-11T08:00:00+00:00"))
        let week = PFPlanWeekDoc.CoachWeek(lastSync: "2030-03-11T08:00:00+00:00", count: 6, error: nil)
        XCTAssertEqual(PFWeekNotes543.coachWeekLine(week, now: read.addingTimeInterval(3 * 3600)), "Read from TrueCoach 3 h ago \u{00B7} 6 sessions")
    }

    func testTheCoachWeekLineGivesTheReasonWhenTheReadFailed() {
        let week = PFPlanWeekDoc.CoachWeek(lastSync: nil, count: nil, error: "Login expired")
        XCTAssertEqual(PFWeekNotes543.coachWeekLine(week), "Could not read your coach's week: Login expired")
    }

    // MARK: The overlap sheet

    func testTheOverlapSheetFindsBothSessionsOfTheDay() throws {
        let day = try JSONDecoder.pf543().decode(PFPlanWeekDoc.Day.self, from: Data(overlapDay.utf8))
        let other = try XCTUnwrap(day.items?.last)
        XCTAssertEqual(PFOverlap543.sessions(on: day, with: other).compactMap { $0.sessionId }, ["s1", "s2"])
    }

    func testTheOverlapSheetNamesTheCoachsSessionAndTheClass() throws {
        let day = try JSONDecoder.pf543().decode(PFPlanWeekDoc.Day.self, from: Data(overlapDay.utf8))
        let pair = PFOverlap543.sessions(on: day, with: try XCTUnwrap(day.items?.last))
        let parts = PFOverlap543.split(pair)
        XCTAssertEqual(PFOverlap543.intro(coach: parts.coach, other: parts.other),
                       "Two sessions on one day. Your coach's Strength A is required this week. The Cardio Class is yours.")
    }

    func testOnlyTheClassCanBeMovedOrSkippedFromTheOverlapSheet() throws {
        let day = try JSONDecoder.pf543().decode(PFPlanWeekDoc.Day.self, from: Data(overlapDay.utf8))
        let pair = PFOverlap543.sessions(on: day, with: try XCTUnwrap(day.items?.last))
        XCTAssertEqual(PFOverlap543.changeable(pair)?.sessionId, "s2")
    }

    func testTwoCoachSessionsOfferNothingToMoveOrSkip() throws {
        let both = [try item(#"{"kind": "session", "session_id": "x", "title": "A", "coach_assigned": true}"#),
                    try item(#"{"kind": "session", "session_id": "y", "title": "B", "coach_assigned": true}"#)]
        XCTAssertNil(PFOverlap543.changeable(both))
    }

    func testKeepingBothIsRememberedForThatPairOnThatDay() {
        let overlap = PFPlanWeekDoc.Overlap(with: ["Strength A"], reason: nil)
        XCTAssertEqual(PFOverlap543.keptKey(date: "2030-03-12", title: "Cardio Class", overlap: overlap),
                       "noop.plan.overlapKept.2030-03-12|Cardio Class|Strength A")
    }

    func testTheOverlapChoicesHaveTheDrawingsWords() {
        XCTAssertEqual([PFOverlap543.keepBoth, PFOverlap543.moveClass, PFOverlap543.skipClass],
                       ["Keep both", "Move the class to another day", "Skip the class"])
    }

    // MARK: Confirm wording

    func testSkippingACoachSessionAsksInTheDrawingsWords() {
        XCTAssertEqual(PFSkipCoachConfirm543.message(sessionTitle: "Strength A"),
                       "Strength A is required this week. If you skip it, it is recorded as missed and shows in the week analysis. You can undo this.")
    }

    func testTheSkipQuestionIsTheDrawingsTitle() {
        XCTAssertEqual(PFSkipCoachConfirm543.title, "Skip your coach's session?")
    }

    func testTheSkipButtonsAreTheDrawingsWords() {
        XCTAssertEqual([PFSkipCoachConfirm543.confirmTitle, PFSkipCoachConfirm543.keepTitle], ["Skip it, record as missed", "Keep it"])
    }

    func testTheSkipQuestionWithoutATitleStillReads() {
        XCTAssertTrue(PFSkipCoachConfirm543.message(sessionTitle: nil).hasPrefix("This session is required this week."))
    }

    func testAConfirmedSkipIsSentWithTheServersFlag() {
        let inputs = PFJobInputs.confirmed(PFJobInputs.calendarDelete(sessionID: "s-1"), .skipMandatory)
        XCTAssertEqual(inputs?["confirm_skip_mandatory"] as? Bool, true)
    }

    // MARK: The three dots

    func testAPlannedSessionOffersEveryChange() {
        XCTAssertEqual(PFSessionMenu543.items(status: "planned", isOptional: false, isDone: false),
                       [.move, .skip, .swap, .optional, .easier, .details, .judged, .askCoach])
    }

    func testAnOptionalDraftOffersAcceptAndDrop() {
        XCTAssertEqual(PFSessionMenu543.items(status: "optional", isOptional: true, isDone: false),
                       [.move, .skip, .swap, .accept, .drop, .easier, .details, .judged, .askCoach])
    }

    func testADoneSessionOffersHowItWasJudgedAndTheCoach() {
        XCTAssertEqual(PFSessionMenu543.items(status: "done", isOptional: false, isDone: true), [.judged, .askCoach])
    }

    // MARK: Text sizes

    func testASmallSizeIsReadAsFifteen() {
        XCTAssertEqual(PFPlanTextStyle543.style(forSize: 10.5), .subheadline)
    }

    func testSixteenScalesWithTheCalloutStyle() {
        XCTAssertEqual(PFPlanTextStyle543.style(forSize: 16), .callout)
    }

    func testSeventeenScalesWithTheBodyStyle() {
        XCTAssertEqual(PFPlanTextStyle543.style(forSize: 17), .body)
    }

    func testTwentyTwoScalesWithTheSecondTitleStyle() {
        XCTAssertEqual(PFPlanTextStyle543.style(forSize: 22), .title2)
    }

    // MARK: Session words

    func testTheWhatToDoHeaderSaysTheLengthAndThatItIsEstimated() throws {
        let estimated = try item(#"{"minutes": 54, "description": "A. Run\nDuration is estimated — your coach gave none."}"#)
        XCTAssertEqual(PFSessionText543.whatToDoHeader(estimated), "What to do \u{00B7} about 54 min, estimated")
    }

    func testTheWhatToDoHeaderSaysOnlyTheLengthWhenItIsKnown() throws {
        XCTAssertEqual(PFSessionText543.whatToDoHeader(try item(#"{"minutes": 54, "description": "A. Run"}"#)), "What to do \u{00B7} about 54 min")
    }

    func testTheWhatToDoHeaderWithoutMinutesIsJustTheWords() throws {
        XCTAssertEqual(PFSessionText543.whatToDoHeader(try item(#"{"description": "A. Run"}"#)), "What to do")
    }

    func testAnEffortIsWrittenAsAWord() {
        XCTAssertEqual(PFSessionText543.effortWord("all_out"), "All out")
    }

    func testAWorkoutWithPiecesDoesNotRepeatItsText() throws {
        XCTAssertNil(PFSessionText543.fallbackText(try item(#"{"description": "A. Run", "pieces": [{"label": "Run"}]}"#)))
    }

    func testAWorkoutWithoutPiecesShowsItsTextOnce() throws {
        XCTAssertEqual(PFSessionText543.fallbackText(try item(#"{"description": "A. Run"}"#)), "A. Run")
    }

    // MARK: The finished week

    func testTheFinishedWeeksSessionsListTheCoachsFirst() throws {
        XCTAssertEqual(PFReportSessions543.rows(try doc(weekOfFive)).map { $0.title }, ["Run test", "Strength A", "Wod A", "35 min easy run"])
    }

    func testASessionStillToDoInAFinishedWeekWasNotDone() throws {
        XCTAssertEqual(PFReportSessions543.rows(try doc(weekOfFive)).map { $0.state }, ["Done", "Not done", "Done", "Not done"])
    }

    func testAReportRowReadsAsASentence() throws {
        XCTAssertEqual(PFReportSessions543.rows(try doc(weekOfFive)).first?.sentence, "run test, from your coach, done")
    }

    // MARK: Workout questions

    private let questions = """
    {"activity_id": "2511", "name": "Run test", "date": "2030-03-11", "round": 0, "questions": [
      {"key": "session.exact", "modality": "session", "name": "exact", "type": "choice", "choices": ["yes exactly", "mostly", "no"],
       "text": "Did you do it exactly as written?", "why": "w", "prefill": null, "confirm": false},
      {"key": "segments.confirm", "modality": "segments", "group": "segments.confirm", "name": "confirm", "type": "choice",
       "choices": ["yes", "adjust"], "text": "I think your 5 km ran from 10:00 to 35:00 - right?", "proposed": {"start_s": 600, "end_s": 2100}},
      {"key": "segments.piece_start_s", "modality": "segments", "group": "segments.confirm", "name": "piece_start_s", "type": "number",
       "unit": "s from the start", "min": 0, "max": 36000, "text": "When did it start?", "show_if": {"segments.confirm": "adjust"}},
      {"key": "segments.piece_end_s", "modality": "segments", "group": "segments.confirm", "name": "piece_end_s", "type": "number",
       "unit": "s from the start", "min": 0, "max": 36000, "text": "When did it end?", "show_if": {"segments.confirm": "adjust"}},
      {"key": "skierg.pace_500m_s", "modality": "skierg", "name": "pace_500m_s", "type": "number", "unit": "s per 500 m",
       "min": 60, "max": 400, "text": "Pace per 500 m?"},
      {"key": "skierg.meters_per_rep", "modality": "skierg", "name": "meters_per_rep", "type": "number", "unit": "m",
       "min": 50, "max": 5000, "text": "Metres per interval?", "implied_by_exact": true},
      {"key": "piece.all_out", "modality": "piece", "name": "all_out", "type": "choice",
       "choices": ["yes, all out", "held back", "paced it"], "text": "Did you go all out?"}]}
    """

    private func flow() throws -> PFQuestionFlow543 { PFQuestionFlow543(ask: try ask(questions)) }

    func testAnAskKeepsAllItsQuestions() throws {
        XCTAssertEqual(try ask(questions).questions.count, 7)
    }

    func testAnAskWithoutQuestionsIsNotAnAsk() {
        XCTAssertNil(PFWorkoutAsk543.parse(PFJ(data: Data(#"{"activity_id": "1", "questions": []}"#.utf8))))
    }

    func testAnAskKeepsTheProposedCut() throws {
        XCTAssertEqual(try ask(questions).questions[1].proposedEndS, 2100)
    }

    func testAnAskKeepsWhenAQuestionIsShown() throws {
        XCTAssertEqual(try ask(questions).questions[2].showIf, ["segments.confirm": "adjust"])
    }

    func testTheFlowStartsWithFivePages() throws {
        XCTAssertEqual(try flow().pages.count, 5)
    }

    func testTheFirstPageIsTheExactnessQuestion() throws {
        XCTAssertEqual(try flow().currentPage?.style, .exact)
    }

    func testThePositionReadsOneOfFive() throws {
        XCTAssertEqual(try flow().positionLine, "1 of 5")
    }

    func testYesExactlyHidesTheQuestionsItSettles() throws {
        var started = try flow()
        started.choose("session.exact", "yes exactly")
        XCTAssertEqual(started.positionLine, "1 of 4")
    }

    func testMostlyKeepsAllTheQuestions() throws {
        var started = try flow()
        started.choose("session.exact", "mostly")
        XCTAssertEqual(started.positionLine, "1 of 5")
    }

    func testAdjustingTheCutShowsTheTwoTimes() throws {
        var started = try flow()
        started.choose("segments.confirm", "adjust")
        XCTAssertEqual(started.pages[1].questions.count, 3)
    }

    func testTheCutPageIsTheSegmentsPage() throws {
        XCTAssertEqual(try flow().pages[1].style, .segments)
    }

    func testNextMovesToTheNextPage() throws {
        var started = try flow()
        started.next()
        XCTAssertEqual(started.positionLine, "2 of 5")
    }

    func testBackReturnsToThePageBefore() throws {
        var started = try flow()
        started.next()
        started.back()
        XCTAssertEqual(started.positionLine, "1 of 5")
    }

    func testTheFirstQuestionMustBeAnsweredToGoOn() throws {
        let started = try flow()
        XCTAssertEqual(started.blocker(started.pages[0]), "Choose one to go on.")
    }

    func testAnsweringTheFirstQuestionLetsYouGoOn() throws {
        var started = try flow()
        started.choose("session.exact", "mostly")
        XCTAssertNil(started.blocker(started.pages[0]))
    }

    func testAdjustingNeedsBothTimes() throws {
        var started = try flow()
        started.choose("segments.confirm", "adjust")
        XCTAssertEqual(started.blocker(started.pages[1]), "To adjust, give when the piece started and ended (start before end).")
    }

    func testAdjustingWithBothTimesLetsYouGoOn() throws {
        var started = try flow()
        started.choose("segments.confirm", "adjust")
        started.setText("segments.piece_start_s", "10:00")
        started.setText("segments.piece_end_s", "2100")
        XCTAssertNil(started.blocker(started.pages[1]))
    }

    func testAPaceCanBeTypedAsMinutesAndSeconds() throws {
        var started = try flow()
        started.setText("skierg.pace_500m_s", "2:05")
        XCTAssertEqual(started.numberValue(started.ask.questions[4]), 125)
    }

    func testATimeFromTheStartCanBeTypedAsMinutesAndSeconds() throws {
        var started = try flow()
        started.setText("segments.piece_start_s", "10:00")
        XCTAssertEqual(started.numberValue(started.ask.questions[2]), 600)
    }

    func testANumberOutsideTheServersRangeIsExplained() throws {
        var started = try flow()
        started.setText("skierg.pace_500m_s", "5")
        XCTAssertEqual(started.problem(started.ask.questions[4]), "Give a number from 60 to 400 (s per 500 m).")
    }

    func testTextThatIsNoNumberIsExplained() throws {
        var started = try flow()
        started.setText("skierg.pace_500m_s", "fast")
        XCTAssertEqual(started.problem(started.ask.questions[4]), "Type a number.")
    }

    func testATypedProblemStopsTheNextButton() throws {
        var started = try flow()
        started.setText("skierg.pace_500m_s", "5")
        XCTAssertEqual(started.blocker(started.pages[2]), "Give a number from 60 to 400 (s per 500 m).")
    }

    func testTheAnswersCarryAChoiceAsItsWords() throws {
        var started = try flow()
        started.choose("session.exact", "mostly")
        XCTAssertEqual(started.answers()["session.exact"] as? String, "mostly")
    }

    func testTheAnswersCarryATypedPaceInSeconds() throws {
        var started = try flow()
        started.setText("skierg.pace_500m_s", "2:05")
        XCTAssertEqual(started.answers()["skierg.pace_500m_s"] as? Double, 125)
    }

    func testIDontKnowIsNull() throws {
        var started = try flow()
        started.markUnknown("skierg.pace_500m_s")
        XCTAssertTrue(started.answers()["skierg.pace_500m_s"] is NSNull)
    }

    func testAnUnansweredQuestionIsLeftOut() throws {
        var started = try flow()
        started.choose("session.exact", "mostly")
        XCTAssertNil(started.answers()["piece.all_out"])
    }

    func testAQuestionHiddenByYesExactlyIsLeftOut() throws {
        var started = try flow()
        started.setText("skierg.meters_per_rep", "300")
        started.choose("session.exact", "yes exactly")
        XCTAssertNil(started.answers()["skierg.meters_per_rep"])
    }

    func testTheLastSimilarWorkoutsAnswerIsShownForConfirmation() throws {
        let withPrefill = try ask("""
        {"activity_id": "1", "questions": [{"key": "skierg.pace_500m_s", "type": "number", "unit": "s per 500 m", "min": 60, "max": 400,
          "text": "Pace?", "prefill": 125, "confirm": true}]}
        """)
        XCTAssertEqual(PFQuestionFlow543(ask: withPrefill).typed["skierg.pace_500m_s"], "125")
    }

    func testNothingAnsweredIsTheFinalSkip() throws {
        let plain = try ask(#"{"activity_id": "1", "questions": [{"key": "piece.all_out", "type": "choice", "choices": ["a"], "text": "Q?"}]}"#)
        XCTAssertEqual(PFQuestionFlow543(ask: plain).finalAnswer.body["kind"] as? String, "workout_answer_skip")
    }

    func testAnswersAreSentAsAWorkoutAnswer() throws {
        var started = try flow()
        started.choose("session.exact", "mostly")
        XCTAssertEqual(started.finalAnswer.body["kind"] as? String, "workout_answer")
    }

    func testTheAnswerNamesTheActivity() throws {
        var started = try flow()
        started.choose("session.exact", "mostly")
        XCTAssertEqual(started.finalAnswer.body["activity_id"] as? String, "2511")
    }

    func testTheSkipBodyHasOnlyTheKindAndTheActivity() {
        XCTAssertEqual(Set(PFNeedsAnswer.workoutSkip(activityID: "2511").body.keys), ["kind", "activity_id"])
    }

    func testTheSameAnswersHaveTheSameSignature() {
        let a = PFNeedsAnswer.workoutAnswers(activityID: "1", answers: ["k": 5.0, "j": NSNull()])
        XCTAssertEqual(a.signature(for: "i"), PFNeedsAnswer.workoutAnswers(activityID: "1", answers: ["j": NSNull(), "k": 5.0]).signature(for: "i"))
    }

    func testTheChoiceWordsReadWell() {
        XCTAssertEqual([PFQuestionFlow543.choiceTitle("yes exactly"), PFQuestionFlow543.choiceTitle("mostly")], ["Yes, exactly", "Mostly"])
    }

    func testAWorkoutQuestionsItemOfTheNeedsYouListIsRead() throws {
        let list = PFJ(data: Data("""
        {"items": [{"id": "workout_questions:2511", "kind": "workout_questions", "title": "Questions about Run test",
                    "metric": \(questions), "ref": {"kind": "workout_questions", "activity_id": "2511"}}]}
        """.utf8))
        XCTAssertEqual(PFNeedsParse.items(list).first?.workout?.questions.count, 7)
    }

    func testAWorkoutQuestionsItemWithoutQuestionsIsLeftOut() {
        let list = PFJ(data: Data(#"{"items": [{"id": "workout_questions:1", "kind": "workout_questions", "metric": {"activity_id": "1", "questions": []}}]}"#.utf8))
        XCTAssertEqual(PFNeedsParse.items(list), [])
    }

    func testTheWorkoutQuestionsListOfTheServerIsRead() {
        let body = Data(("{\"items\": [" + questions + "]}").utf8)
        XCTAssertEqual(PFWorkoutAsk543.list(body).first?.activityID, "2511")
    }

    // MARK: Where the pieces ran

    func testTheBarSharesTheRecordingIntoWarmUpPieceAndCooldown() throws {
        let shares = try XCTUnwrap(PFPieceTimeline543.shares(startS: 600, endS: 2100, totalS: 2700))
        XCTAssertEqual(shares.piece, 1500.0 / 2700.0, accuracy: 0.0001)
    }

    func testWithoutTheRecordingsLengthTheCooldownIsAsLongAsTheWarmUp() throws {
        let shares = try XCTUnwrap(PFPieceTimeline543.shares(startS: 600, endS: 2100, totalS: nil))
        XCTAssertEqual(shares.after, 600.0 / 2700.0, accuracy: 0.0001)
    }

    func testAPieceThatEndsBeforeItStartsHasNoBar() {
        XCTAssertNil(PFPieceTimeline543.shares(startS: 2100, endS: 600, totalS: 2700))
    }

    func testTheBarsTimesAreWrittenAsClockTimes() {
        XCTAssertEqual([PFPieceTimeline543.clock(600), PFPieceTimeline543.clock(3725)], ["10:00", "1:02:05"])
    }

    // MARK: Asked against did

    private let execution = """
    {"activity_id": "2511", "available": true, "what_happened": "You ran it as asked.", "limits": ["Strength sets are not judged."],
     "blocks": [
       {"index": 0, "text": "Warm-up 2 km", "expected": {"hr": {"band": [0, 140], "source": "zones"}},
        "actual": {"avg_hr": 132, "peak_hr": 139}, "verdict": "on", "why": "Inside the band."},
       {"index": 1, "text": "Test 5 km", "actual": {"avg_hr": 170}, "verdict": "not_judged"}]}
    """

    func testTheExecutionTableHasARowPerPiece() throws {
        XCTAssertEqual(PFSessionExecution543.parse(Data(execution.utf8))?.rows.count, 2)
    }

    func testAPieceIsAskedWithItsBand() throws {
        XCTAssertEqual(PFSessionExecution543.parse(Data(execution.utf8))?.rows.first?.asked, "Warm-up 2 km \u{00B7} heart rate under 140 bpm")
    }

    func testAPieceShowsWhatTheRecordingHas() throws {
        XCTAssertEqual(PFSessionExecution543.parse(Data(execution.utf8))?.rows.first?.did, "average heart rate 132, peak 139")
    }

    func testTheVerdictIsAWord() throws {
        XCTAssertEqual(PFSessionExecution543.parse(Data(execution.utf8))?.rows.map { $0.verdict }, ["On target", "Not judged"])
    }

    func testTheExecutionKeepsItsLimitsAndItsAccount() throws {
        let parsed = try XCTUnwrap(PFSessionExecution543.parse(Data(execution.utf8)))
        XCTAssertEqual([parsed.limits.first, parsed.whatHappened], ["Strength sets are not judged.", "You ran it as asked."])
    }

    func testAnUnavailableExecutionSaysWhy() throws {
        let parsed = PFSessionExecution543.parse(Data(#"{"available": false, "reason": "No described session."}"#.utf8))
        XCTAssertEqual([parsed?.isAvailable, parsed?.reason == "No described session."], [false, true])
    }

    func testAnEmptyAnswerIsNoExecution() {
        XCTAssertNil(PFSessionExecution543.parse(Data("{}".utf8)))
    }

    // MARK: Notes thread

    private let threadBody = """
    {"status": "reassessing", "pending_questions": 2,
     "versions": [{"n": 1, "text": "v1"}, {"n": 2, "what_changed": "the first km is judged against the hill"}],
     "messages": [{"at": "2030-03-11T20:20:00+00:00", "from": "athlete", "text": "The first km was on a hill."}, {"from": "coach", "text": "Noted."}]}
    """

    func testTheThreadSaysItIsReassessing() {
        XCTAssertEqual(PFSessionThread543.parse(Data(threadBody.utf8))?.isReassessing, true)
    }

    func testTheNewestVersionIsTheLatest() {
        XCTAssertEqual(PFSessionThread543.parse(Data(threadBody.utf8))?.latestVersion?.number, 2)
    }

    func testAVersionSaysWhatChanged() throws {
        let latest = try XCTUnwrap(PFSessionThread543.parse(Data(threadBody.utf8))?.latestVersion)
        XCTAssertEqual(PFSessionThread543.versionLine(latest), "Version 2 \u{00B7} what changed: the first km is judged against the hill")
    }

    func testAVersionWithoutAnythingElseIsJustItsNumber() throws {
        XCTAssertEqual(PFSessionThread543.versionLine(PFSessionThread543.Version(number: 1, at: nil, whatChanged: nil, text: nil)), "Version 1")
    }

    func testTheThreadKeepsBothSidesOfTheConversation() {
        XCTAssertEqual(PFSessionThread543.parse(Data(threadBody.utf8))?.messages.map { PFSessionThread543.speaker($0.from) }, ["You", "Coach"])
    }

    func testTheThreadCountsTheQuestionsStillWaiting() {
        XCTAssertEqual(PFSessionThread543.parse(Data(threadBody.utf8))?.pendingQuestions, 2)
    }

    func testAnEmptyAnswerIsNoThread() {
        XCTAssertNil(PFSessionThread543.parse(Data("{}".utf8)))
    }
}

private extension JSONDecoder {
    static func pf543() -> JSONDecoder { PFPlan529Decoder.make() }
}
