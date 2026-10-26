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
}
