import XCTest
@testable import Strand

/// today-call.json (the document the unified Today's six cards read), the card order, the week strip, the Reports index kinds, the Race
/// rows, the Coach read and the changed days, and how stale data and failed refreshes read. All values are made up.
final class PaceForgeTodayCallTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private let raceDay = """
    {"version": 1, "date": "2030-03-16", "generated_at": "2030-03-16T07:00:00+00:00",
     "call": {"verdict": "Race day: go as planned.", "reason": "Both devices read well.", "source": "daily-intel"},
     "today": {"kind": "race", "title": "HYROX Testville", "detail": "goal 1:10:00", "session_id": null, "race_date": "2030-03-16"},
     "next_race": {"name": "HYROX Testville", "date": "2030-03-16", "days_out": 0, "goal_time": "1:10:00"},
     "readiness": {"garmin": {"score": 81, "band": "green", "label": "Ready"}, "strap": {"score": 74, "band": "green"},
                   "own": {"score": 77, "band": "green"}, "agreement": "agree", "sleep": {"minutes": 452, "need_minutes": 480}},
     "needs_you": 2,
     "week": [
       {"date": "2030-03-11", "dow": "Mon", "items": [{"kind": "session", "title": "Easy run", "status": "done", "session_id": "s1"}]},
       {"date": "2030-03-12", "dow": "Tue", "items": []},
       {"date": "2030-03-16", "dow": "Sat", "items": [{"kind": "race", "title": "HYROX Testville", "status": "planned", "session_id": null}]}]}
    """

    private let sessionDay = """
    {"version": 1, "date": "2030-03-13", "generated_at": "2030-03-13T07:00:00+00:00",
     "call": {"verdict": "Train as planned.", "reason": "Recovery is steady.", "source": "daily-intel"},
     "today": {"kind": "session", "title": "Tempo run", "detail": "8 km", "session_id": "s42", "race_date": null},
     "next_race": null,
     "readiness": {"garmin": {"score": 66, "band": "amber", "label": null}, "strap": {"score": null, "band": null},
                   "own": {"score": null, "band": null}, "agreement": "unknown", "sleep": {"minutes": null, "need_minutes": null}},
     "needs_you": 0, "week": []}
    """

    // MARK: Parsing

    func testRaceDayNamesTheRaceAsToday() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual([call.today.kind, call.today.title, call.today.raceDate], ["race", "HYROX Testville", "2030-03-16"])
    }

    func testRaceDayKeepsTheNextRaceWithItsCountdownAndGoal() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual(call.nextRace, PFTodayCall.Race(name: "HYROX Testville", date: "2030-03-16", daysOut: 0, goalTime: "1:10:00"))
    }

    func testRaceDayReadsBothDevicesAndTheirAgreement() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual([call.readiness.garmin.score, call.readiness.strap.score], [81, 74])
        XCTAssertEqual(call.readiness.agreement, "agree")
    }

    func testRaceDayReadsTheSleepAgainstItsNeed() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual([call.readiness.sleepMinutes, call.readiness.sleepNeedMinutes], [452, 480])
    }

    func testRaceDayReadsTheVerdictAndReason() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual([call.call?.verdict, call.call?.reason], ["Race day: go as planned.", "Both devices read well."])
    }

    func testRaceDayKeepsTheWeekInItsOrderWithEmptyDays() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual(call.week.map { $0.dow }, ["Mon", "Tue", "Sat"])
    }

    func testSessionDayNamesTheSessionById() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(sessionDay)))
        XCTAssertEqual([call.today.kind, call.today.sessionID], ["session", "s42"])
    }

    func testSessionDayWithNoRaceHasNoNextRace() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(sessionDay)))
        XCTAssertNil(call.nextRace)
    }

    func testAMissingDeviceScoreReadsAsNil() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(sessionDay)))
        XCTAssertNil(call.readiness.strap.score)
    }

    func testAMissingDocumentIsNil() {
        XCTAssertNil(PFTodayCallParse.document(PFJ(nil)))
    }

    func testADocumentOfTheWrongShapeIsNil() {
        XCTAssertNil(PFTodayCallParse.document(json("[1, 2]")))
    }

    func testAnEmptyDocumentHasNothingToDrawSoItIsNil() {
        XCTAssertNil(PFTodayCallParse.document(json("{}")))
    }

    func testAnUnknownAgreementReadsAsUnknown() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(#"{"call": {"verdict": "Rest.", "reason": ""}}"#)))
        XCTAssertEqual(call.readiness.agreement, "unknown")
    }

    private func readiness(_ garmin: String, own: String = "{}") throws -> PFTodayCall.Readiness {
        let text = #"{"call": {"verdict": "Go.", "reason": ""}, "readiness": {"garmin": "# + garmin + #", "own": "# + own + #"}}"#
        return try XCTUnwrap(PFTodayCallParse.document(json(text))).readiness
    }

    func testGarminFactorsRecoveryTimeAndHRVRangeAreParsed() throws {
        let r = try readiness(#"{"score": 70, "factors": ["Sleep good", "HRV balanced"], "recovery_time_h": 14, "hrv_range_ms": {"low": 31, "high": 44, "last_night": 36}}"#)
        XCTAssertEqual([r.garminFactors, [r.garminRecoveryHours.map { String($0) } ?? ""], [String(r.garminHRV?.low ?? 0), String(r.garminHRV?.lastNight ?? 0)]],
                       [["Sleep good", "HRV balanced"], ["14.0"], ["31.0", "36.0"]])
    }

    func testOwnShowIsParsedAndDefaultsToFalse() throws {
        XCTAssertEqual([try readiness("{}", own: #"{"show": true}"#).ownShow, try readiness("{}").ownShow], [true, false])
    }

    func testMissingGarminKeysRenderNoLines() throws {
        XCTAssertEqual(try readiness(#"{"score": 70}"#).garminLines, [])
    }

    func testWrongTypesBecomeNothing() throws {
        let r = try readiness(#"{"factors": "Sleep good", "recovery_time_h": "14", "hrv_range_ms": {"low": "31", "high": 44}}"#)
        XCTAssertEqual(r.garminLines, [])
    }

    func testNonStringFactorsAreDroppedAndTheLineKeepsThree() throws {
        let r = try readiness(#"{"factors": ["A", 5, "B", "C", "D"]}"#)
        XCTAssertEqual(r.factorsLine, "A \u{00B7} B \u{00B7} C")
    }

    func testRecoveryTimeAndHRVRangeLinesRead() throws {
        let r = try readiness(#"{"recovery_time_h": 13.6, "hrv_range_ms": {"low": 31, "high": 44, "last_night": 36}}"#)
        XCTAssertEqual(r.garminLines, ["Recovery time 14 h", "HRV normal 31\u{2013}44 ms, last night 36"])
    }

    func testHRVRangeWithoutLastNightOmitsIt() throws {
        XCTAssertEqual(try readiness(#"{"hrv_range_ms": {"low": 31, "high": 44}}"#).hrvLine, "HRV normal 31\u{2013}44 ms")
    }

    func testTheDocumentIsFetchedWithTheOtherDocuments() {
        XCTAssertTrue(PFDocs.all.contains { $0.path == PFDocs.todayCall })
    }

    func testTheBuilderFetchesTheDocumentThroughItsLeaf() {
        XCTAssertEqual(PFLeaf.todayCall.docs, ["data/today-call.json"])
    }

    func testTheDocumentDoesNotReloadTheWidgetSummary() {
        XCTAssertFalse(PFDocs.summaryInputs.contains(PFDocs.todayCall))
    }

    // MARK: The six cards

    func testTheFixedOrderIsTheCallNeedsYouTodayHowYouAreFeelThenTheWeek() {
        XCTAssertEqual(PFTodayCard.allCases.map { $0.identifier },
                       ["pf-today-card-the-call", "pf-today-card-needs-you", "pf-today-card-today", "pf-today-card-how-you-are",
                        "pf-today-card-feel", "pf-today-card-this-week"])
    }

    func testAFullDocumentDrawsAllSixInOrder() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual(PFTodayCard.present(call: call, needsYou: 2, hasFeel: true), PFTodayCard.allCases)
    }

    func testNeedsYouIsLeftOutWhenNothingIsOpen() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertFalse(PFTodayCard.present(call: call, needsYou: 0, hasFeel: true).contains(.needsYou))
    }

    func testFeelIsLeftOutWhenTheServerServesNoSummary() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertFalse(PFTodayCard.present(call: call, needsYou: 1, hasFeel: false).contains(.feel))
    }

    func testASessionDayWithNoWeekAndOneDeviceDrawsTheCallTheDayAndHowYouAre() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(sessionDay)))
        XCTAssertEqual(PFTodayCard.present(call: call, needsYou: 0, hasFeel: false), [.theCall, .today, .howYouAre])
    }

    func testEveryCardHasItsOwnIdentifier() {
        XCTAssertEqual(Set(PFTodayCard.allCases.map { $0.identifier }).count, PFTodayCard.allCases.count)
    }

    // MARK: The week strip

    func testARaceDayShowsTheFinishFlag() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual(PFWeekGlyph.glyph(for: call.week[2]), "\u{1F3C1}")
    }

    func testADoneDayShowsAFilledDot() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual(PFWeekGlyph.glyph(for: call.week[0]), "\u{25CF}")
    }

    func testARestDayShowsADash() throws {
        let call = try XCTUnwrap(PFTodayCallParse.document(json(raceDay)))
        XCTAssertEqual(PFWeekGlyph.glyph(for: call.week[1]), "\u{2013}")
    }

    func testAPlannedDayShowsAnEmptyDot() {
        let day = PFTodayCall.WeekDay(date: "2030-03-14", dow: "Thu",
                                      items: [PFTodayCall.WeekItem(kind: "session", title: "Tempo", status: "planned", sessionID: "s2")])
        XCTAssertEqual(PFWeekGlyph.glyph(for: day), "\u{25CB}")
    }

    func testADayWithOneDoneAndOnePlannedSessionIsNotDone() {
        let day = PFTodayCall.WeekDay(date: "2030-03-14", dow: "Thu", items: [
            PFTodayCall.WeekItem(kind: "session", title: "Run", status: "done", sessionID: "s2"),
            PFTodayCall.WeekItem(kind: "session", title: "Lift", status: "planned", sessionID: "s3")])
        XCTAssertEqual(PFWeekGlyph.glyph(for: day), "\u{25CB}")
    }

    // MARK: Reports index

    func testTheReportsIndexHasFourKinds() {
        XCTAssertEqual(PFReportIndexKind.allCases.map { $0.title }, ["Day", "Week", "Month", "Race"])
    }

    func testTheFirstThreeKindsAreTheExpertReports() {
        XCTAssertEqual(PFReportIndexKind.allCases.compactMap { $0.reportKind }, [.daily, .weekly, .monthly])
    }

    func testRaceIsNotAnExpertReport() {
        XCTAssertNil(PFReportIndexKind.race.reportKind)
    }

    // MARK: Race reports

    private let races = [
        PFNextRace(name: "HYROX Old", date: "2030-01-12", daysOut: -60, goalTime: "1:12:00"),
        PFNextRace(name: "10K Fun Run", date: "2030-02-02", daysOut: -40, goalTime: nil),
        PFNextRace(name: "HYROX Testville", date: "2030-03-16", daysOut: 3, goalTime: "1:10:00"),
    ]
    private let activities = ["a1": PFActivity(id: "a1", startTime: "2030-01-12T09:00:00", durationS: 4300),
                              "a2": PFActivity(id: "a2", startTime: "2030-01-12T07:00:00", durationS: 900)]
    private let analyses = ["a1": PFAnalysisRow(id: "a1", headline: "A steady race.")]

    func testARaceWithAPackOrAnAnalysisIsListedNewestFirst() {
        let rows = PFRaceReports.rows(races: races, activities: activities, analyses: analyses, packDates: ["2030-03-16"])
        XCTAssertEqual(rows.map { $0.name }, ["HYROX Testville", "HYROX Old"])
    }

    func testARaceWithNeitherIsLeftOut() {
        let rows = PFRaceReports.rows(races: races, activities: activities, analyses: analyses, packDates: ["2030-03-16"])
        XCTAssertFalse(rows.contains { $0.name == "10K Fun Run" })
    }

    func testTheDebriefIsTheLongestAnalysedActivityOfTheRaceDay() {
        let rows = PFRaceReports.rows(races: races, activities: activities, analyses: analyses, packDates: [])
        XCTAssertEqual(rows.first?.analysisActivityID, "a1")
    }

    func testARowSaysWhatItHas() {
        let rows = PFRaceReports.rows(races: races, activities: activities, analyses: analyses, packDates: ["2030-01-12", "2030-03-16"])
        XCTAssertEqual(rows.map { PFRaceReports.summary($0) }, ["Race pack", "Pack and debrief"])
    }

    func testNoRacesGiveNoRows() {
        XCTAssertTrue(PFRaceReports.rows(races: [], activities: [:], analyses: [:], packDates: ["2030-03-16"]).isEmpty)
    }

    // MARK: The Coach read and the changed days

    func testTheReadKeepsTheFirstThreeSentences() {
        let text = ["Sleep was short. HRV is down. Keep it easy. Tomorrow is a rest day."]
        XCTAssertEqual(PFCoachRead.summary(paragraphs: text, sentences: 3), "Sleep was short. HRV is down. Keep it easy.")
    }

    func testTheReadDoesNotEndASentenceInsideANumber() {
        XCTAssertEqual(PFCoachRead.summary(paragraphs: ["You slept 7.5 hours. Good."], sentences: 1), "You slept 7.5 hours.")
    }

    func testTheReadRunsOnIntoTheNextParagraph() {
        XCTAssertEqual(PFCoachRead.summary(paragraphs: ["One.", "Two. Three. Four."], sentences: 3), "One. Two. Three.")
    }

    func testNoParagraphsGiveAnEmptyRead() {
        XCTAssertEqual(PFCoachRead.summary(paragraphs: [], sentences: 3), "")
    }

    private func week(_ days: [(String, [PFWorkout])]) -> [PFWeek] {
        [PFWeek(key: "2030-W11", start: "2030-03-11", end: "2030-03-17",
                days: days.map { PFDay(date: $0.0, dow: "Day", workouts: $0.1) })]
    }

    func testAMovedSessionChangesBothDays() {
        let run = PFWorkout(id: "w1", date: "2030-03-14", status: "planned", name: "Long run")
        let before = week([("2030-03-14", [run]), ("2030-03-16", [])])
        let after = week([("2030-03-14", []), ("2030-03-16", [PFWorkout(id: "w1", date: "2030-03-16", status: "planned", name: "Long run")])])
        XCTAssertEqual(PFPlanDiff.changedDays(before: before, after: after), ["2030-03-14", "2030-03-16"])
    }

    func testAnUnchangedPlanChangesNoDay() {
        let run = PFWorkout(id: "w1", date: "2030-03-14", status: "planned", name: "Long run")
        XCTAssertTrue(PFPlanDiff.changedDays(before: week([("2030-03-14", [run])]), after: week([("2030-03-14", [run])])).isEmpty)
    }

    func testAResizedSessionChangesItsDay() {
        let short = PFWorkout(id: "w1", date: "2030-03-14", status: "planned", name: "Long run", durationMin: 60)
        let long = PFWorkout(id: "w1", date: "2030-03-14", status: "planned", name: "Long run", durationMin: 90)
        XCTAssertEqual(PFPlanDiff.changedDays(before: week([("2030-03-14", [short])]), after: week([("2030-03-14", [long])])), ["2030-03-14"])
    }

    // MARK: Stale data and failed refreshes

    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func iso(_ secondsAgo: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(-secondsAgo))
    }

    func testTheStaleLineSaysWhenTheCopyWasSaved() {
        let line = PFSavedCopy.staleLine(names: ["the body scale"], generatedAt: iso(3 * 3600), now: now)
        XCTAssertEqual(line, "Couldn't refresh the body scale. Showing the copy saved 3 h ago.")
    }

    func testTheStaleLineNamesThreeDocumentsAndCountsTheRest() {
        let line = PFSavedCopy.staleLine(names: ["a", "b", "c", "d", "e"], generatedAt: iso(120), now: now)
        XCTAssertEqual(line, "Couldn't refresh a, b, c and 2 more. Showing the copy saved 2 min ago.")
    }

    func testASavedCopyWithNoKnownTimeStillSaysItIsSaved() {
        XCTAssertEqual(PFSavedCopy.savedCopy(generatedAt: nil, now: now), "Showing the last saved copy.")
    }

    func testAgeReadsInMinutesHoursAndDays() {
        XCTAssertEqual([30, 300, 7200, 172_800].map { PFSavedCopy.age($0) }, ["just now", "5 min ago", "2 h ago", "2 days ago"])
    }

    func testTheAutomaticRetriesComeAfterTenSecondsThirtySecondsAndTwoMinutes() {
        XCTAssertEqual((1...3).compactMap { PFRetrySchedule.delay(afterFailures: $0) }, [10, 30, 120])
    }

    func testTheFourthFailureInARowDoesNotRetryByItself() {
        XCTAssertNil(PFRetrySchedule.delay(afterFailures: 4))
    }

    func testNoConnectionReadsAsUnreachable() {
        XCTAssertTrue(PFReachability.isUnreachable(.notConnectedToInternet))
    }

    func testABadReplyIsNotUnreachable() {
        XCTAssertFalse(PFReachability.isUnreachable(.badServerResponse))
    }

    func testTheBannerTellsUnreachableFromAnsweredWithAnError() {
        XCTAssertEqual([PFOfflineNote.banner(unreachable: true, status: nil), PFOfflineNote.banner(unreachable: false, status: 503)],
                       ["Can't reach PaceForge. Showing the data last saved on this iPhone.",
                        "PaceForge answered with an error (HTTP 503). Showing the data last saved on this iPhone."])
    }

    func testAJobThatMeetsABadReplyIsNotOffline() {
        XCTAssertEqual(PFJobError.transport(URLError(.badServerResponse)), .unreadable)
    }
}
