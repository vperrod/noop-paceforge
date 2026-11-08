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

    // MARK: report sections (build 513)

    private let designedJSON = Data("""
    {"headline": "H", "content_md": "x", "limiters": ["Fatigue", "  ", "Sleep"], "charts": ["pmc", "../bad", "progression"], "charts_at": "2026-11-08T18:30:47Z",
     "summary": {"sessions": 14, "hours": 7.6, "run_km": 12.3, "avg_recovery": 48, "red_nights": 3, "green_nights": 2, "avg_sleep_h": 6.8, "hrv_first": 52.7, "hrv_last": 47.4},
     "sections": [
       {"id": "summary", "title": "This week in short", "intro": "Key numbers.", "md": "", "open": true, "kind": "summary"},
       {"id": "plan", "title": "Next week", "intro": "", "md": "Intro\\n\\n### Monday 2026-11-09 - Openers\\nEasy.\\n### Tuesday 2026-11-10 - Rest\\nRest.", "open": true, "kind": "plan"},
       {"id": "x", "title": "Odd", "md": "m", "kind": "table-of-everything"},
       {"id": "nokind", "title": "Charts", "open": false, "kind": "charts"},
       {"title": "No id"}
     ]}
    """.utf8)

    private var designed: PFWeekReport? { PFWeekPlan.weekly(designedJSON) }

    func testSectionsKeepTheServerOrderAndDropRowsWithoutAnId() {
        XCTAssertEqual(designed?.sections.map(\.id), ["summary", "plan", "x", "nokind"])
    }

    func testSectionKindsDecode() {
        XCTAssertEqual(designed?.sections.map(\.kind), [.summary, .plan, .md, .charts])
    }

    func testUnknownKindReadsAsMarkdown() {
        XCTAssertEqual(designed?.sections[2].kind, .md)
    }

    func testSectionOpenFlagAndIntroDecode() {
        XCTAssertEqual([designed?.sections[0].open, designed?.sections[3].open], [true, false])
    }

    func testReportWithoutSectionsHasNone() {
        XCTAssertEqual(PFWeekPlan.weekly(weeklyJSON)?.sections, [])
    }

    func testLimitersDropBlankEntries() {
        XCTAssertEqual(designed?.limiters, ["Fatigue", "Sleep"])
    }

    func testChartNamesThatCouldEscapeThePathAreDropped() {
        XCTAssertEqual(designed?.charts, ["pmc", "progression"])
    }

    func testChartPathIsUnderApiCharts() {
        XCTAssertEqual(PFWeekPlan.chartPath("pmc"), "api/charts/pmc.png")
    }

    func testChartCaptions() {
        XCTAssertEqual(["pmc", "progression"].map(PFWeekPlan.chartCaption), ["Fitness, fatigue and form", "Eight-week progression"])
    }

    func testSummaryTilesInOrderWithTheirValues() {
        let tiles = PFWeekPlan.summaryTiles(designed!.summary!)
        XCTAssertEqual(tiles.map { "\($0.label)=\($0.value)" },
                       ["Sessions=14", "Training time=7.6 h", "Running=12.3 km", "Avg strap recovery=48%", "Red nights=3", "Avg sleep=6.8 h"])
    }

    func testRedNightsTileNotesTheGreenNights() {
        XCTAssertEqual(PFWeekPlan.summaryTiles(designed!.summary!)[4].note, "2 green")
    }

    func testSleepTileNotesTheHrvChange() {
        XCTAssertEqual(PFWeekPlan.summaryTiles(designed!.summary!)[5].note, "HRV 52.7 \u{2192} 47.4 ms")
    }

    func testSummaryTilesSkipMissingValues() {
        XCTAssertEqual(PFWeekPlan.summaryTiles(PFWeekSummary(sessions: 3, hours: nil, runKm: 0, avgRecovery: nil)).map(\.label), ["Sessions", "Running"])
    }

    func testSleepTileWithoutHrvHasNoNote() {
        XCTAssertNil(PFWeekPlan.summaryTiles(PFWeekSummary(avgSleepH: 7)).first?.note)
    }

    func testEmptySummaryObjectIsNoSummary() {
        XCTAssertNil(PFWeekPlan.weekly(Data(#"{"headline": "H", "summary": {}}"#.utf8))?.summary)
    }

    // MARK: one thing not to do

    func testOneThingNotToDoStopsAtTheNextHeading() {
        let md = "### Headline\nA\n\n### One thing to NOT do\nDo not chase volume.\nRest.\n\n### Next\nB"
        XCTAssertEqual(PFWeekPlan.oneThingNotToDo(md), "Do not chase volume.\nRest.")
    }

    func testOneThingNotToDoAtTheEndOfTheText() {
        XCTAssertEqual(PFWeekPlan.oneThingNotToDo("### One thing to NOT do\nStop.\n"), "Stop.")
    }

    func testOneThingNotToDoKeepsADeeperHeadingInside() {
        XCTAssertEqual(PFWeekPlan.oneThingNotToDo("### One thing to NOT do\n#### Why\nTired."), "#### Why\nTired.")
    }

    func testNoOneThingNotToDoIsNil() {
        XCTAssertNil(PFWeekPlan.oneThingNotToDo("### Headline\nA"))
    }

    func testEmptyOneThingNotToDoIsNil() {
        XCTAssertNil(PFWeekPlan.oneThingNotToDo("### One thing to NOT do\n\n### Next\nB"))
    }

    // MARK: plan days

    private let planMD = "Intro line.\n\n### Monday 2026-11-09 - Openers\n- Easy.\n\n### Tuesday 10-11-2026 - Rest\nRest.\n### Wed 11 - Race\nGo.\n### Thursday - Walk\nWalk."

    func testPlanSplitsIntoDaysWithTheirTitles() {
        XCTAssertEqual(PFWeekPlan.planDays(planMD).days.map(\.title),
                       ["Monday 2026-11-09 - Openers", "Tuesday 10-11-2026 - Rest", "Wed 11 - Race", "Thursday - Walk"])
    }

    func testPlanDayBodyIsTheTextUnderItsHeading() {
        XCTAssertEqual(PFWeekPlan.planDays(planMD).days[0].body, "- Easy.")
    }

    func testPlanKeepsTheTextBeforeTheFirstDayAsPreamble() {
        XCTAssertEqual(PFWeekPlan.planDays(planMD).preamble, "Intro line.")
    }

    func testPlanThatStartsWithADayHasNoPreamble() {
        XCTAssertEqual(PFWeekPlan.planDays("### A\nx").preamble, "")
    }

    private func proposal(_ id: String, day: String?) -> PFPendingProposal {
        PFPendingProposal(id: id, title: id, description: "", why: nil, day: day, changes: [])
    }

    private var plannedDays: [PFPlanDay] { PFWeekPlan.planDays(planMD).days }

    func testProposalMatchesTheDayByIsoDate() {
        XCTAssertEqual(PFWeekPlan.assign([proposal("a", day: "2026-11-09")], to: plannedDays).byDay[0].map(\.id), ["a"])
    }

    func testProposalMatchesTheDayByDayMonthYear() {
        XCTAssertEqual(PFWeekPlan.assign([proposal("a", day: "2026-11-10")], to: plannedDays).byDay[1].map(\.id), ["a"])
    }

    func testProposalMatchesTheDayByShortWeekdayAndDate() {
        XCTAssertEqual(PFWeekPlan.assign([proposal("a", day: "2026-11-11")], to: plannedDays).byDay[2].map(\.id), ["a"])
    }

    func testProposalMatchesTheDayByFullWeekdayName() {
        XCTAssertEqual(PFWeekPlan.assign([proposal("a", day: "2026-11-12")], to: plannedDays).byDay[3].map(\.id), ["a"])
    }

    func testProposalWithoutADayIsUnmatched() {
        XCTAssertEqual(PFWeekPlan.assign([proposal("a", day: nil)], to: plannedDays).unmatched.map(\.id), ["a"])
    }

    func testProposalForADayThePlanDoesNotHaveIsUnmatched() {
        XCTAssertEqual(PFWeekPlan.assign([proposal("a", day: "2026-11-14")], to: plannedDays).unmatched.map(\.id), ["a"])
    }

    func testProposalWithAMalformedDayIsUnmatched() {
        XCTAssertEqual(PFWeekPlan.assign([proposal("a", day: "soon")], to: plannedDays).unmatched.map(\.id), ["a"])
    }

    func testAssignKeepsOneListPerDay() {
        XCTAssertEqual(PFWeekPlan.assign([], to: plannedDays).byDay.count, 4)
    }
}
