import XCTest
@testable import Strand

/// The expert reports: the history rows, the stage order, the claim tags split off a paragraph and the dated or stale note.
/// Every word is made up.
final class PaceForgeReportsTests: XCTestCase {

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private let weekly = """
    {"kind": "week", "key": "2030-W11", "label": "Week 11", "date": "2030-03-17", "generated_at": "2030-03-17T19:02:11+00:00",
     "stale": false, "stage_titles": {"headline": "Headline", "review": "Week review", "goals": "Goals for the week"},
     "head_coach": {"text_source": "mixed",
       "goals": {"text": "Synthetic goals.", "text_source": "fallback-rules"},
       "headline": {"text": "Synthetic headline.", "text_source": "free-model"},
       "review": {"text": "Synthetic review.", "text_source": "free-model"}},
     "experts": {"running": {"text": "Synthetic running.", "text_source": "free-model"},
                 "sleep": {"text": "Synthetic sleep.", "text_source": "free-model"},
                 "zeta": {"text": "Synthetic extra.", "text_source": "no-model"}},
     "proposals": [{"id": 7, "title": "Synthetic move", "description": "Synthetic detail."}, {"description": "no title"}],
     "not_checked": ["Synthetic gap one", "Synthetic gap two"]}
    """

    func testStagesAreOrderedByKindWithTheHeadlineFirst() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekly), kind: .weekly))

        XCTAssertEqual(report.stages.map(\.id), ["headline", "review", "goals"])
    }

    func testStageTitlesComeFromTheDocument() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekly), kind: .weekly))

        XCTAssertEqual(report.stages.map(\.title), ["Headline", "Week review", "Goals for the week"])
    }

    func testDailyDocumentWithoutTitlesUsesTheDefaultStageNames() throws {
        let doc = json("""
        {"kind": "daily", "key": "2030-03-13", "date": "2030-03-13", "head_coach": {"text_source": "free-model",
         "decisions": {"text": "Synthetic d."}, "readiness": {"text": "Synthetic r."}, "preparedness": {"text": "Synthetic p."}}}
        """)

        let report = try XCTUnwrap(PFReportParse.report(doc, kind: .daily))

        XCTAssertEqual(report.stages.map(\.title), ["Readiness", "Preparedness", "Decisions"])
    }

    func testExpertsKeepTheDomainOrderAndUnknownOnesFollow() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekly), kind: .weekly))

        XCTAssertEqual(report.experts.map(\.id), ["sleep", "running", "zeta"])
    }

    func testProposalWithoutATitleIsLeftOut() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekly), kind: .weekly))

        XCTAssertEqual(report.proposals.map(\.title), ["Synthetic move"])
    }

    func testReportWithNoStageTextIsNotAReport() {
        let doc = json(#"{"kind": "daily", "head_coach": {"text_source": "free-model", "readiness": {"text": "  "}}}"#)

        XCTAssertNil(PFReportParse.report(doc, kind: .daily))
    }

    func testHistoryRowsKeepTheServersOrderAndSkipRowsWithoutAKey() {
        let index = json("""
        {"daily": [{"key": "2030-03-13", "label": "Wed 13 Mar", "stale": true, "headline": "Synthetic"}, {"label": "no key"},
                   {"key": "2030-03-12"}], "weekly": [], "monthly": []}
        """)

        let rows = PFReportParse.rows(index, kind: .daily)

        XCTAssertEqual(rows.map(\.key), ["2030-03-13", "2030-03-12"])
    }

    func testHistoryRowLabelFallsBackToTheKey() {
        let index = json(#"{"daily": [{"key": "2030-03-12"}]}"#)

        XCTAssertEqual(PFReportParse.rows(index, kind: .daily).first?.label, "2030-03-12")
    }

    func testMissingIndexKindGivesNoRows() {
        XCTAssertEqual(PFReportParse.rows(json("{}"), kind: .monthly), [])
    }

    func testClaimTagIsSplitOffAsASmallLabel() {
        XCTAssertEqual(PFReportText.splitTags("Sleep ran short [health:C16, PARTIAL].").tags, ["health C16 \u{00B7} partial"])
    }

    func testTextKeepsItsPunctuationAfterTheTagIsTakenOut() {
        XCTAssertEqual(PFReportText.splitTags("Sleep ran short [health:C16, PARTIAL].").text, "Sleep ran short.")
    }

    func testTwoTagsOnOneLineKeepTheirOrder() {
        let tags = PFReportText.splitTags("A [sleep:K02, VERIFIED] and B [running:R4, INFERENCE]").tags

        XCTAssertEqual(tags, ["sleep K02 \u{00B7} verified", "running R4 \u{00B7} inference"])
    }

    func testBracketWithoutAStatusWordIsKept() {
        XCTAssertEqual(PFReportText.splitTags("Plan [see note] stays").text, "Plan [see note] stays")
    }

    func testBoldLabelSurvivesBlockSplitting() {
        let blocks = PFReportText.blocks("**Autonomic** HRV sat at his usual [health:C1, VERIFIED]")

        XCTAssertEqual(blocks.first?.text, "**Autonomic** HRV sat at his usual")
    }

    func testBulletsGetADotAndDividerRowsAreDropped() {
        let blocks = PFReportText.blocks("- first\n|---|---|\n* second\n\n\u{2022} third")

        XCTAssertEqual(blocks.map(\.text), ["\u{2022} first", "\u{2022} second", "\u{2022} third"])
    }

    func testHeadingBecomesABoldHeadingBlock() {
        let blocks = PFReportText.blocks("## Next steps")

        XCTAssertEqual(blocks.first, PFReportBlock(id: 0, text: "**Next steps**", tags: [], isHeading: true))
    }

    func testDailyReadingFromAnEarlierDayIsLabelledNotToday() throws {
        let doc = json(#"{"kind": "daily", "key": "2030-03-12", "date": "2030-03-12", "stale": false, "head_coach": {"readiness": {"text": "Synthetic."}}}"#)
        let report = try XCTUnwrap(PFReportParse.report(doc, kind: .daily))

        XCTAssertEqual(PFReportFreshness.note(report, today: "2030-03-13"),
                       "This is the reading from \(PFFormat.dayTitle("2030-03-12")), not today's. Today's has not been written yet.")
    }

    func testDailyReadingFromTodayHasNoNote() throws {
        let doc = json(#"{"kind": "daily", "key": "2030-03-13", "date": "2030-03-13", "stale": false, "head_coach": {"readiness": {"text": "Synthetic."}}}"#)
        let report = try XCTUnwrap(PFReportParse.report(doc, kind: .daily))

        XCTAssertNil(PFReportFreshness.note(report, today: "2030-03-13"))
    }

    func testStaleDailyReadingSaysTodaysRunFailed() throws {
        let doc = json(#"{"kind": "daily", "key": "2030-03-12", "date": "2030-03-12", "stale": true, "head_coach": {"readiness": {"text": "Synthetic."}}}"#)
        let report = try XCTUnwrap(PFReportParse.report(doc, kind: .daily))

        XCTAssertEqual(PFReportFreshness.note(report, today: "2030-03-13"),
                       "Today's reading did not run, so this is the one from \(PFFormat.dayTitle("2030-03-12")).")
    }

    func testFreshWeeklyReportHasNoNote() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekly), kind: .weekly))

        XCTAssertNil(PFReportFreshness.note(report, today: "2030-03-20"))
    }

    func testStaleWeeklyReportSaysWhenItWasWritten() throws {
        let doc = weekly.replacingOccurrences(of: "\"stale\": false", with: "\"stale\": true")
        let report = try XCTUnwrap(PFReportParse.report(json(doc), kind: .weekly))

        XCTAssertEqual(PFReportFreshness.note(report, today: "2030-03-20"),
                       "The last run failed, so this is the report written \(PFFormat.dayTitle("2030-03-17")).")
    }

    // MARK: Week tables, glossary, sources

    private let weekWithTables = """
    {"kind": "week", "key": "2030-W11", "label": "Week 11", "date": "2030-03-17", "stale": false,
     "head_coach": {"text_source": "free-model",
       "headline": {"text": "Synthetic headline.", "text_source": "free-model"},
       "detail": {"text": "Synthetic week.", "text_source": "free-model"}},
     "sessions": [
       {"date": "2030-03-11", "weekday": "Mon", "type": "Run", "name": "Synthetic easy run", "minutes": 45, "km": 8.24, "pace": "5:27",
        "avg_hr": 142, "max_hr": 160, "hard": false, "plan": {"status": "done"}},
       {"date": "2030-03-13", "weekday": "Wed", "type": "Strength", "name": "Synthetic lift", "minutes": 60, "km": null, "pace": null,
        "avg_hr": null, "hard": true, "plan": {"status": "unplanned"}},
       {"weekday": "Fri", "type": "Run", "minutes": 30, "plan": {"status": "partial"}},
       {"weekday": "Sat", "name": "Synthetic long run", "plan": {"status": "partial"}}],
     "week_table": [{"date": "2030-03-11", "weekday": "Mon", "sessions": ["Synthetic easy run"], "minutes": 45, "sleep_h": 7.4, "hrv": 62, "resting_hr": 48},
                    {"date": "2030-03-12", "weekday": "Tue", "sessions": [], "minutes": 0, "sleep_h": null, "hrv": null, "resting_hr": null}],
     "week_totals": {"totals": {"sessions": 2, "minutes": 105, "run_km": 8.2},
       "totals_by_type": {"strength": {"label": "Strength", "sessions": 1, "minutes": 60, "km": null},
                          "run": {"label": "Run", "sessions": 1, "minutes": 45, "km": 8.2}},
       "hard_vs_easy": {"hard_sessions": 1, "easy_sessions": 1, "hard_minutes": 60, "easy_minutes": 45},
       "load_vs_previous_week": {"minutes_change_pct": 12.5}},
     "glossary": [{"key": "hrv", "term": "HRV", "text": "Synthetic HRV meaning."}, {"term": "no text"}],
     "sources": [{"id": "health:C09", "status": "PARTIAL", "words": "Partly supported", "claim": "Synthetic claim."},
                 {"id": "sleep:K02", "words": "Confirmed"}, {"id": "run:R4", "words": "Our estimate"}, {"claim": "Id-less claim"}]}
    """

    func testWeeklyStageOrderPutsTheSessionByDetailAfterTheHeadline() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.stages.map(\.id), ["headline", "detail"])
    }

    func testDetailStageHasADefaultTitle() throws {
        let doc = weekWithTables.replacingOccurrences(of: "\"label\": \"Week 11\",", with: "\"label\": \"Week 11\", \"stage_titles\": {},")
        let report = try XCTUnwrap(PFReportParse.report(json(doc), kind: .weekly))

        XCTAssertEqual(report.stages.last?.title, "The week, session by session")
    }

    func testSessionsKeepTheServersOrderAndSkipRowsWithoutAName() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.sessions.map(\.name), ["Synthetic easy run", "Synthetic lift", "Synthetic long run"])
    }

    func testSessionLineReadsTypeMinutesKmPaceHeartRateAndPlan() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(PFReportWeekText.sessionLine(report.sessions[0]), "Run \u{00B7} 45 min \u{00B7} 8.2 km \u{00B7} 5:27 /km \u{00B7} avg HR 142 \u{00B7} done")
    }

    func testSessionLineLeavesOutWhatTheRowDoesNotCarry() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(PFReportWeekText.sessionLine(report.sessions[1]), "Strength \u{00B7} 60 min \u{00B7} added")
    }

    func testHardFlagIsKept() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.sessions.map(\.isHard), [false, true, false])
    }

    func testPartialPlanStatusReadsPartlyDone() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.sessions.last?.plan, "partly done")
    }

    func testTotalsByTypeAreOrderedLongestFirst() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.totals?.byType.map(\.label), ["Strength", "Run"])
    }

    func testHardAgainstEasyLine() throws {
        let totals = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly)?.totals)

        XCTAssertEqual(PFReportWeekText.hardEasyLine(totals), "Hard: 1 session (60 min). Easy: 1 session (45 min).")
    }

    func testHardAgainstEasyLineNeedsAllFourFigures() {
        XCTAssertNil(PFReportWeekText.hardEasyLine(PFReportWeekTotals(hardSessions: 1, hardMinutes: 60)))
    }

    func testTrainingTimeChangeLine() throws {
        let totals = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly)?.totals)

        XCTAssertEqual(PFReportWeekText.changeLine(totals), "Training time up 12.5 % on the week before.")
    }

    func testWholeWeekTotalLine() throws {
        let totals = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly)?.totals)

        XCTAssertEqual(PFReportWeekText.totalLine(totals), "2 sessions \u{00B7} 105 min \u{00B7} 8.2 km run")
    }

    func testRestDayAndNightLines() throws {
        let days = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly)?.days)

        XCTAssertEqual([PFReportWeekText.dayLine(days[1]), PFReportWeekText.nightLine(days[0]) ?? "", PFReportWeekText.nightLine(days[1]) ?? "none"],
                       ["rest", "sleep 7.4 h \u{00B7} HRV 62 \u{00B7} resting HR 48", "none"])
    }

    func testOlderReportWithoutTablesStillLoads() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekly), kind: .weekly))

        XCTAssertFalse(report.hasWeekNumbers || report.totals != nil || !report.glossary.isEmpty || !report.sources.isEmpty)
    }

    func testGlossaryListSkipsATermWithoutText() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.glossary, [PFReportGlossaryEntry(term: "HRV", text: "Synthetic HRV meaning.")])
    }

    func testGlossaryObjectFormIsReadSortedByTerm() {
        let entries = PFReportParse.glossary(json(#"{"glossary": {"Taper": "Synthetic taper.", "HRV": "Synthetic hrv."}}"#))

        XCTAssertEqual(entries.map(\.term), ["HRV", "Taper"])
    }

    func testSourceLevelsFollowTheServersWords() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.sources.map(\.level), [.partial, .confirmed, .estimate, .estimate])
    }

    func testSourceWithoutAnIdUsesItsClaimAsTheId() throws {
        let report = try XCTUnwrap(PFReportParse.report(json(weekWithTables), kind: .weekly))

        XCTAssertEqual(report.sources.last?.id, "Id-less claim")
    }

    func testSourcesObjectFormIsRead() {
        let sources = PFReportParse.sources(json(#"{"sources": {"health:C09": "Partly supported"}}"#))

        XCTAssertEqual(sources, [PFReportSource(id: "health:C09", level: .partial, claim: nil)])
    }

    func testTagLabelWithPartialIsPartlySupported() {
        XCTAssertEqual(PFReportText.sureLevel(ofTag: "health C09 \u{00B7} partial"), .partial)
    }

    func testTagLabelWithInferenceIsAnEstimate() {
        XCTAssertEqual(PFReportText.sureLevel(ofTag: "running R4 \u{00B7} inference"), .estimate)
    }

    func testTagLabelWithVerifiedIsConfirmed() {
        XCTAssertEqual(PFReportText.sureLevel(ofTag: "sleep K02 \u{00B7} verified"), .confirmed)
    }

    func testEstimateWinsOverPartialOnOneTag() {
        XCTAssertEqual(PFReportText.sureLevel(ofTag: "x C1 \u{00B7} partial \u{00B7} speculative"), .estimate)
    }

    // MARK: Daily freshness

    private func daily(date: String = "2030-03-13", stale: Bool = false, extra: String = "") throws -> PFReport {
        let doc = json("""
        {"kind": "daily", "key": "\(date)", "date": "\(date)", "stale": \(stale), \(extra)
         "head_coach": {"readiness": {"text": "Synthetic."}}}
        """)
        return try XCTUnwrap(PFReportParse.report(doc, kind: .daily))
    }

    private func moment(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    func testReadingWrittenTodayIsFresh() throws {
        let status = PFReportFreshness.status(try daily(), runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z"))

        XCTAssertEqual(status.headline, "Fresh: written today, after the morning Garmin data arrived")
    }

    func testReadingFromAnEarlierDayIsOlderThanToday() throws {
        let status = PFReportFreshness.status(try daily(date: "2030-03-12"), runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z"))

        XCTAssertEqual(status.headline, "Older than today: this is \(PFFormat.dayTitle("2030-03-12"))'s reading")
    }

    func testFailedRunShowsTheDayItFellBackTo() throws {
        let status = PFReportFreshness.status(try daily(date: "2030-03-12", stale: true), runs: [], today: "2030-03-13",
                                              now: try moment("2030-03-13T09:30:00Z"))

        XCTAssertEqual(status.headline, "Failed: the last run did not work, showing \(PFFormat.dayTitle("2030-03-12"))'s reading")
    }

    func testStaleWinsOverTodaysDate() throws {
        let status = PFReportFreshness.status(try daily(stale: true), runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z"))

        XCTAssertEqual(status.state, .failed)
    }

    func testWrittenLineNamesTheScheduledRunAndHowLongAgo() throws {
        let report = try daily(extra: #""generated_at": "2030-03-13T06:30:00Z", "run_kind": "06:30","#)
        let written = PFReportFreshness.status(report, runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z")).written

        XCTAssertTrue(written?.hasSuffix(" (3 h ago), by the 06:30 scheduled run") == true)
    }

    func testWrittenLineSaysManualRun() throws {
        let report = try daily(extra: #""generated_at": "2030-03-13T06:30:00Z", "run_kind": "manual","#)
        let written = PFReportFreshness.status(report, runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z")).written

        XCTAssertTrue(written?.hasSuffix(", by a manual run") == true)
    }

    func testGarminSyncLineGivesMinutesUnderNinety() throws {
        let report = try daily(extra: #""data_as_of": "2030-03-13T08:45:00Z","#)
        let synced = PFReportFreshness.status(report, runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z")).dataSynced

        XCTAssertTrue(synced?.hasPrefix("Garmin data synced ") == true && synced?.hasSuffix(" (45 min ago)") == true)
    }

    func testOldStampGivesDays() throws {
        let report = try daily(extra: #""generated_at": "2030-03-10T06:30:00Z","#)
        let written = PFReportFreshness.status(report, runs: [], today: "2030-03-13", now: try moment("2030-03-13T06:30:00Z")).written

        XCTAssertTrue(written?.hasSuffix(" (3 days ago)") == true)
    }

    func testStampInTheFutureHasNoAgo() throws {
        let report = try daily(extra: #""generated_at": "2030-03-13T10:30:00Z","#)
        let written = PFReportFreshness.status(report, runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z")).written

        XCTAssertTrue(written?.contains("ago") == false)
    }

    func testUnreadableStampLeavesTheWrittenLineOut() throws {
        let report = try daily(extra: #""generated_at": "yesterday-ish","#)

        XCTAssertNil(PFReportFreshness.status(report, runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z")).written)
    }

    func testNoStampsLeavesBothLinesOut() throws {
        let status = PFReportFreshness.status(try daily(), runs: [], today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z"))

        XCTAssertNil(status.written ?? status.dataSynced)
    }

    func testRunsParseKeepsOnlyRunsWithAResult() {
        let doc = json(#"{"2030-03-13": [{"at": "2030-03-13T06:30:00Z", "run_kind": "06:30", "result": "ok"}, {"result": "failed", "why": "no model answered"}, {"at": "x"}]}"#)

        XCTAssertEqual(PFReportParse.runs(doc)["2030-03-13"]?.map(\.result), ["ok", "failed"])
    }

    func testRunLineWithoutATimeStartsWithTheKind() {
        let run = PFReportRun(at: nil, runKind: "11:00", result: "failed", why: "no model answered")

        XCTAssertEqual(PFReportFreshness.runLine(run), "11:00: failed (no model answered)")
    }

    func testRunLineWithNoTimeAndNoKindIsTheResult() {
        XCTAssertEqual(PFReportFreshness.runLine(PFReportRun(at: nil, runKind: nil, result: "skipped", why: nil)), "skipped")
    }

    func testRunsTitleCountsTheDaysRuns() throws {
        let runs = [PFReportRun(at: nil, runKind: "06:30", result: "ok", why: nil), PFReportRun(at: nil, runKind: "08:30", result: "skipped", why: nil)]
        let status = PFReportFreshness.status(try daily(), runs: runs, today: "2030-03-13", now: try moment("2030-03-13T09:30:00Z"))

        XCTAssertEqual(status.runsTitle, "Runs today (2)")
    }

    func testDailyDocumentCarriesTheRunKindAndTheSyncStamp() throws {
        let report = try daily(extra: #""run_kind": "08:30", "data_as_of": "2030-03-13T08:00:00Z","#)

        XCTAssertEqual([report.runKind, report.dataAsOf], ["08:30", "2030-03-13T08:00:00Z"])
    }
}
