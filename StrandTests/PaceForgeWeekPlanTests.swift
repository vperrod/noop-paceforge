import XCTest
@testable import Strand

final class PaceForgeWeekPlanTests: XCTestCase {
    // Synthetic values only: this repository is public.
    private let pending = Data("""
    [
      {"id": "p-late", "title": "Late change", "description": "Short line", "why": "Because **rest** matters.", "day": "2026-11-12",
       "changes": [{"session_id": "s1", "field": "session", "to": null}]},
      {"id": "p-nodate", "title": "No day", "description": "Only a description", "changes": []},
      {"id": "p-early", "title": "Early change", "description": "D", "why": "  ", "day": "2026-11-10",
       "changes": [{"session_id": "s2", "field": "notes", "to": "Do 4 x 4"}, {"session_id": "s2", "field": "name", "to": "Easy run"},
                   {"session_id": "s3", "field": "duration_min", "to": 45}, {"session_id": "s3", "field": "intensity", "to": null}]},
      {"title": "No id", "description": "dropped"}
    ]
    """.utf8)

    private var proposals: [PFPendingProposal] { PFWeekPlan.proposals(pending) }

    func testProposalsSortByDayWithUndatedLast() {
        XCTAssertEqual(proposals.map(\.id), ["p-early", "p-late", "p-nodate"])
    }

    func testProposalWithoutAnIdIsDropped() {
        XCTAssertEqual(proposals.count, 3)
    }

    func testWhyIsKeptWhenPresent() {
        XCTAssertEqual(proposals[1].explanation, "Because **rest** matters.")
    }

    func testMissingWhyFallsBackToTheDescription() {
        XCTAssertEqual(proposals[2].explanation, "Only a description")
    }

    func testBlankWhyFallsBackToTheDescription() {
        XCTAssertEqual(proposals[0].explanation, "D")
    }

    func testMissingDayHasNoLabel() {
        XCTAssertNil(proposals[2].dayLabel)
    }

    func testDayLabelNamesTheWeekday() {
        XCTAssertEqual(proposals[0].dayLabel, "Tue 10 Nov")
    }

    func testRemovingASessionReadsAsRemovingItFromTheCalendar() {
        XCTAssertEqual(proposals[1].changes[0].plainWords, "Remove this session from the calendar")
    }

    func testNotesChangeReadsAsPuttingThePrescriptionInTheNotes() {
        XCTAssertEqual(proposals[0].changes[0].plainWords, "Put this prescription in the session notes")
    }

    func testNameChangeNamesTheNewName() {
        XCTAssertEqual(proposals[0].changes[1].plainWords, "Rename the session to: Easy run")
    }

    func testOtherFieldReadsInWordsWithItsValue() {
        XCTAssertEqual(proposals[0].changes[2].plainWords, "Set the session's duration min to 45")
    }

    func testOtherFieldWithNullClearsIt() {
        XCTAssertEqual(proposals[0].changes[3].plainWords, "Clear the session's intensity")
    }

    func testAskPromptNamesTheProposal() {
        XCTAssertEqual(proposals[0].askPrompt,
                       "About your proposal \"Early change\": why do you want this change, and what happens if I keep the session as it is?")
    }

    func testGarbagePendingChangesParseToEmpty() {
        XCTAssertEqual(PFWeekPlan.proposals(Data("{}".utf8)), [])
    }

    // MARK: weekly.json

    private let weeklyJSON = Data("""
    {"headline": "A steady week", "generated_at": "2026-11-09T06:00:00Z", "content_md": "## Numbers\\n\\n| a | b |\\n|---|---|\\n| 1 | 2 |",
     "plan_md": "x", "source_context": {"period": {"start": "2026-11-02", "end": "2026-11-08"}}}
    """.utf8)

    func testWeeklyReadsTheHeadline() {
        XCTAssertEqual(PFWeekPlan.weekly(weeklyJSON)?.headline, "A steady week")
    }

    func testWeeklyReadsThePeriodAsALabel() {
        XCTAssertEqual(PFWeekPlan.weekly(weeklyJSON)?.periodLabel, "2\u{2013}8 Nov")
    }

    func testWeeklyKeepsTheWholeReportText() {
        XCTAssertTrue(PFWeekPlan.weekly(weeklyJSON)?.contentMD.hasPrefix("## Numbers") == true)
    }

    func testWeeklyWithoutPeriodHasNoLabel() {
        XCTAssertNil(PFWeekPlan.weekly(Data(#"{"headline": "H"}"#.utf8))?.periodLabel)
    }

    func testEmptyWeeklyIsNil() {
        XCTAssertNil(PFWeekPlan.weekly(Data("{}".utf8)))
    }

    // MARK: events and race plans

    private let events = Data("""
    [{"date": "2026-11-07", "name": "Past"}, {"date": "2026-11-09", "name": "Today"}, {"date": "2026-11-23", "name": "Edge"},
     {"date": "2026-11-24", "name": "Too far"}, {"name": "No date"}]
    """.utf8)

    func testUpcomingEventsKeepTodayThroughFourteenDays() {
        XCTAssertEqual(PFWeekPlan.upcomingEvents(events, today: "2026-11-09").map(\.name), ["Today", "Edge"])
    }

    func testUpcomingEventsOfAnUnreadableFileAreEmpty() {
        XCTAssertEqual(PFWeekPlan.upcomingEvents(Data("{}".utf8), today: "2026-11-09"), [])
    }

    func testFirstSectionStopsBeforeTheSecondHeading() {
        let plan = "# Title\n\n## Start\nGo easy.\n\n## Fuel\nEat."
        XCTAssertEqual(PFWeekPlan.firstSection(plan).text, "# Title\n\n## Start\nGo easy.")
    }

    func testFirstSectionOfAMultiSectionPlanHasMore() {
        XCTAssertTrue(PFWeekPlan.firstSection("## A\nx\n## B\ny").hasMore)
    }

    func testFirstSectionOfASingleSectionPlanHasNoMore() {
        XCTAssertFalse(PFWeekPlan.firstSection("# T\n## A\nx").hasMore)
    }

    func testTextBeforeTheFirstHeadingIsTheFirstSection() {
        XCTAssertEqual(PFWeekPlan.firstSection("Intro line.\n\n## A\nx").text, "Intro line.")
    }

    // MARK: markdown blocks and Today

    func testBlocksSplitATableFromTheTextAroundIt() {
        let blocks = PFWeekPlan.blocks("Before\n\n| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n\nAfter")
        XCTAssertEqual(blocks, [.text("Before\n"), .table("| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |", columns: 3), .text("\nAfter")])
    }

    func testALoneBarLineStaysText() {
        XCTAssertEqual(PFWeekPlan.blocks("| just one line"), [.text("| just one line")])
    }

    func testSplitSeparatesProposalsFromTheOtherItems() {
        let items = [PFNeedsItem(id: "proposal:a", kind: .proposal, title: "A"), PFNeedsItem(id: "rpe:1", kind: .rpe, title: "R")]
        XCTAssertEqual(PFWeekPlan.split(items).others.map(\.id), ["rpe:1"])
    }

    func testTodayLineCountsThings() {
        XCTAssertEqual(PFWeekPlan.todayLine(3), "Your coach wants to change 3 things in your plan")
    }

    func testTodayLineUsesTheSingularForOne() {
        XCTAssertEqual(PFWeekPlan.todayLine(1), "Your coach wants to change 1 thing in your plan")
    }
}
